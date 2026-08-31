#!/usr/bin/env python3
"""Measure how often the model corrects itself, and whether it could have.

Why this exists
---------------
Frontier agents appear to "notice their own mistakes" mid-turn. The mechanism is
mostly not introspection -- it is that their harness keeps every tool result of
the turn resident in context, so a claim and the evidence contradicting it are
visible at the same time. Caverno's tool loop deliberately does not: a follow-up
request carries only the *current* batch's results (`StickyToolResultPolicy`
re-sends nothing else), with earlier steps reduced to the label-only
`ToolLoopContextDigest`.

So "why doesn't the local model self-correct?" splits into two questions that
have to be measured separately:

1. **Could it?** -- evidence residency: what fraction of the turn's tool results
   were still in front of the model when it produced its final answer.
2. **Did it?** -- reversal rate: how often a response reverses course, split by
   whether the incoming batch carried an error.

The split in (2) is the point. A reversal right after a failing exit code is the
harness correcting the model; the interesting number is a reversal after a
*clean* batch, which is the model correcting itself. Only the second is the
behaviour worth trying to reproduce locally.

Method notes
------------
- The trigger classification (`clean` vs `errored`) is read from **typed**
  outcome fields -- `outcome.exit_code`, `ok`, `error` -- never from prose. This
  follows the house rule that a heuristic may trigger but may not judge: the
  lexical patterns here only *detect a candidate*, and the tool is an
  instrument, not a gate. Validate them by eye with `--examples`.
- Only records with `schemaName == caverno_llm_session_log_entry` are read.
  `build/integration_test_reports` also holds `flutter test` machine output --
  257k lines of it -- which silently inflated earlier published figures
  (docs/session_log_corpus_contamination_2026-08-05.md).
- Responses are read from `response`, one per entry, so the conversation replay
  that forces `analyze_tool_results.py` to de-duplicate by message id does not
  apply here.

Usage
-----
    python3 tool/analyze_self_correction.py
    python3 tool/analyze_self_correction.py --dir ~/.caverno/session_logs
    python3 tool/analyze_self_correction.py --dir build/integration_test_reports
    python3 tool/analyze_self_correction.py --examples 12
    python3 tool/analyze_self_correction.py --by-model --since-days 30

Honors CAVERNO_SESSION_LOG_DIR / CAVERNO_HOME like triage_session_logs.py.
Pure stdlib; no Flutter or Dart needed.
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import json
import os
import pathlib
import random
import re
import statistics
import sys

SCHEMA_NAME = "caverno_llm_session_log_entry"

# Operations that open a turn (tools attached, no results yet) and those that
# continue one (results attached). Everything else -- memory extraction,
# pro-reasoning stages, goal shadows -- is a secondary call and is not a step of
# the user's turn.
OPENING_OPS = frozenset(
    {"streamChatCompletionWithTools", "createChatCompletionWithTools"}
)
FOLLOWUP_OPS = frozenset(
    {"createChatCompletionWithToolResults", "streamChatCompletionWithToolResults"}
)

THINK_BLOCK = re.compile(r"<think>(.*?)(?:</think>|\Z)", re.DOTALL | re.IGNORECASE)

# Explicit admission that something already said or done was wrong.
STRONG_PATTERNS = [
    r"\bi (?:was|am) wrong\b",
    r"\bi(?:'ve| have)? made a mistake\b",
    r"\bmy mistake\b",
    r"\bthat(?:'s| is| was) (?:incorrect|wrong|not right)\b",
    r"\bi (?:incorrectly|mistakenly|wrongly|erroneously)\b",
    r"\blet me correct\b",
    r"\bcorrection:",
    r"\bscratch that\b",
    r"\boops\b",
    r"間違(?:い|え|っ)",
    r"訂正",
    r"誤(?:り|って)",
]

# Course reversal without an explicit admission. Noisier by construction --
# reported separately and never merged into the strong count.
WEAK_PATTERNS = [
    r"\bwait[,.—!]",
    r"\bbut wait\b",
    r"\bhold on\b",
    r"\bactually,",
    r"\bon second thought\b",
    r"\bhmm+,?\s*(?:no|wait)\b",
    r"\blet me re-?(?:check|read|verify|examine)\b",
    r"やはり",
    r"いや、",
]

STRONG_RE = re.compile("|".join(STRONG_PATTERNS), re.IGNORECASE)
WEAK_RE = re.compile("|".join(WEAK_PATTERNS), re.IGNORECASE)


def log_dir() -> pathlib.Path:
    if os.environ.get("CAVERNO_SESSION_LOG_DIR"):
        return pathlib.Path(os.environ["CAVERNO_SESSION_LOG_DIR"]).expanduser()
    home = os.environ.get("CAVERNO_HOME") or "~/.caverno"
    return pathlib.Path(home).expanduser() / "session_logs"


def iter_log_paths(root: pathlib.Path) -> list[pathlib.Path]:
    """Every `.jsonl` under `root`, at any depth, sorted and deduplicated."""
    return sorted(set(root.glob("**/*.jsonl")))


def iter_entries(path: pathlib.Path):
    """Yield only genuine session-log entries, in file order."""
    with path.open(errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except ValueError:
                continue
            if not isinstance(record, dict):
                continue
            if record.get("schemaName") != SCHEMA_NAME:
                continue
            yield record


def result_is_error(entry: dict) -> bool:
    """Whether one `request.toolResults[]` element reports a failure.

    Typed first: `outcome.exit_code` is the field LL34 exists to provide. The
    payload's own `ok` / `error` keys are the fallback for tools that report
    structurally but have no exit code. Nothing here matches prose.
    """
    outcome = entry.get("outcome")
    if isinstance(outcome, dict):
        code = outcome.get("exit_code")
        if isinstance(code, int) and code != 0:
            return True
        for nested in outcome.values():
            if isinstance(nested, dict) and nested.get("ok") is False:
                return True
    payload = entry.get("result")
    if isinstance(payload, str):
        try:
            payload = json.loads(payload)
        except ValueError:
            payload = None
    if isinstance(payload, dict):
        if payload.get("ok") is False:
            return True
        error = payload.get("error")
        if isinstance(error, str) and error.strip():
            return True
        code = payload.get("exit_code")
        if isinstance(code, int) and code != 0:
            return True
    return False


INSPECTION_TOOLS = frozenset(
    {"read_file", "list_directory", "search_files", "grep_files", "repo_map"}
)

# File mutations. Absent from both digest sets, so a turn's own edits are the
# one class of action that leaves no trace in the follow-up request at all.
MUTATION_TOOLS = frozenset(
    {"edit_file", "write_file", "create_file", "delete_file", "apply_patch",
     "move_file"}
)

# Tools whose run counts as having checked something after a mutation. Matches
# the capability classifier's view that a static re-run is a verification
# ([[caverno-two-notions-of-verified]]).
VERIFICATION_TOOLS = frozenset(
    {"local_execute_command", "git_execute_command", "dart_analyze_feedback",
     "dart_test_verification_evidence", "run_tests"}
)

# The sentence ToolLoopContextDigest renders over every prior inspection. Two
# wordings exist and the distinction is load-bearing: the original told the
# model outright not to re-read, and session 9a44b9c8 showed the cost (it needed
# content it had been told it already had). The current wording only warns
# against reflex repeats. Nearly the whole corpus predates the change, so the
# re-inspection numbers below are measured under the *harsher* instruction --
# check `build.commit` before generalising ([[caverno-session-log-build-provenance]]).
DIGEST_DISCOURAGE_STRICT = "do not re-read these"
DIGEST_DISCOURAGE_SOFT = "Do not repeat one by reflex"


def call_signature(entry: dict) -> tuple[str, str]:
    """Stable (tool, arguments) identity shared by issued calls and results.

    `reason` is stripped: the tool loop deliberately keeps it out of the
    failure-dedup key because a reworded reason is the same call
    ([[caverno-reason-arg-dedup-split]]).
    """
    name = entry.get("name") or ""
    arguments = entry.get("arguments")
    if isinstance(arguments, str):
        try:
            arguments = json.loads(arguments)
        except ValueError:
            arguments = {"_raw": arguments}
    if not isinstance(arguments, dict):
        arguments = {}
    stable = {k: v for k, v in sorted(arguments.items()) if k != "reason"}
    return name, json.dumps(stable, sort_keys=True, ensure_ascii=False)


def split_think(content: str) -> tuple[str, str]:
    """Return (reasoning text, visible text) for one response body."""
    thinks = THINK_BLOCK.findall(content)
    visible = THINK_BLOCK.sub(" ", content)
    return "\n".join(thinks), visible


class Turn:
    """One user-facing turn: an opening request and its follow-up steps."""

    __slots__ = ("steps", "model", "mode", "session")

    def __init__(self, model: str, mode: str, session: str):
        self.steps: list[dict] = []
        self.model = model
        self.mode = mode
        self.session = session

    @property
    def results_total(self) -> int:
        return sum(step["results"] for step in self.steps)

    @property
    def results_resident_at_final(self) -> int:
        return self.steps[-1]["results"] if self.steps else 0


def collect_turns(paths, cutoff):
    turns: list[Turn] = []
    grounded_files = 0
    for path in paths:
        if cutoff is not None:
            try:
                if dt.datetime.fromtimestamp(path.stat().st_mtime) < cutoff:
                    continue
            except OSError:
                continue
        current: Turn | None = None
        grounded = False
        for record in iter_entries(path):
            operation = record.get("operation")
            if operation == "turn_exit":
                current = None
                continue
            request = record.get("request")
            if request is None:
                continue
            if operation not in OPENING_OPS and operation not in FOLLOWUP_OPS:
                continue
            grounded = True
            context = record.get("context") or {}
            if operation in OPENING_OPS or current is None:
                current = Turn(
                    model=request.get("model") or "",
                    mode=context.get("workspaceMode") or "",
                    session=(context.get("sessionId") or path.stem)[:8],
                )
                turns.append(current)
                if operation in OPENING_OPS:
                    # The opening request carries no results, so it is not a
                    # step: nothing could have been contradicted yet.
                    continue
            tool_results = request.get("toolResults") or []
            response = record.get("response") or {}
            content = response.get("content") or ""
            reasoning, visible = split_think(content)
            digest = request.get("assistantContent") or ""
            issued = [call_signature(c) for c in (response.get("toolCalls") or [])]
            current.steps.append(
                {
                    "results": len(tool_results),
                    "errored": any(result_is_error(r) for r in tool_results),
                    "gathered": [call_signature(r) for r in tool_results],
                    "names": [r.get("name") or "" for r in tool_results],
                    "issued": issued,
                    "digest_strict": DIGEST_DISCOURAGE_STRICT in digest,
                    "digest_soft": DIGEST_DISCOURAGE_SOFT in digest,
                    "digest_unchanged": "unchanged —" in digest,
                    "strong_think": bool(STRONG_RE.search(reasoning)),
                    "strong_visible": bool(STRONG_RE.search(visible)),
                    "weak_think": bool(WEAK_RE.search(reasoning)),
                    "weak_visible": bool(WEAK_RE.search(visible)),
                    "content": content,
                    "session": current.session,
                    "model": current.model,
                }
            )
        if grounded:
            grounded_files += 1
    return turns, grounded_files


def percent(part: int, whole: int) -> str:
    return f"{100.0 * part / whole:5.1f}%" if whole else "    --"


def report(turns, grounded_files, total_files, args) -> None:
    steps = [step for turn in turns for step in turn.steps]
    if not steps:
        print("No tool-loop steps found.", file=sys.stderr)
        return

    clean = [s for s in steps if not s["errored"]]
    errored = [s for s in steps if s["errored"]]

    def counts(bucket):
        strong = sum(1 for s in bucket if s["strong_think"] or s["strong_visible"])
        weak = sum(1 for s in bucket if s["weak_think"] or s["weak_visible"])
        return strong, weak

    print(f"Logs: {grounded_files} grounded of {total_files} scanned")
    print(f"Turns: {len(turns)}   tool-loop steps: {len(steps)}")
    print()

    print("== Evidence residency (could the model have noticed?) ==")
    multi = [t for t in turns if len(t.steps) >= 2]
    ratios = []
    for turn in multi:
        total = turn.results_total
        if total:
            ratios.append(turn.results_resident_at_final / total)
    print(f"  turns with >=2 tool-loop steps      : {len(multi)}")
    if ratios:
        print(
            "  tool results resident at last step : "
            f"median {statistics.median(ratios):.0%}, "
            f"mean {statistics.fmean(ratios):.0%}"
        )
        fully = sum(1 for r in ratios if r >= 0.999)
        print(
            "  turns where nothing was dropped    : "
            f"{fully}/{len(ratios)} ({percent(fully, len(ratios))})"
        )
    dropped = sum(t.results_total - t.results_resident_at_final for t in turns)
    print(f"  tool results dropped before answer : {dropped}")
    print()

    print("== Reversal rate by what arrived in the batch ==")
    header = f"  {'bucket':<10}{'steps':>8}{'strong':>10}{'rate':>9}{'weak':>10}{'rate':>9}"
    print(header)
    for name, bucket in (("clean", clean), ("errored", errored), ("all", steps)):
        strong, weak = counts(bucket)
        print(
            f"  {name:<10}{len(bucket):>8}{strong:>10}{percent(strong, len(bucket)):>9}"
            f"{weak:>10}{percent(weak, len(bucket)):>9}"
        )
    print()
    print("  strong = explicit admission that something was wrong")
    print("  weak   = course reversal without an admission (noisier; validate)")
    print("  self-initiated = the `clean` row: nothing had just failed")
    print()

    print("== Where the reversal appears ==")
    for label, key in (
        ("reasoning only", "think"),
        ("visible answer", "visible"),
    ):
        strong = sum(1 for s in steps if s[f"strong_{key}"])
        weak = sum(1 for s in steps if s[f"weak_{key}"])
        print(f"  {label:<16} strong {strong:>5}   weak {weak:>5}")
    print()

    print("== Mutation blindness (what the digest cannot say at all) ==")
    mutating = 0
    blind_after = []
    unverified = 0
    mutation_calls = 0
    for turn in turns:
        last = -1
        for index, step in enumerate(turn.steps):
            hits = sum(1 for n in step["names"] if n in MUTATION_TOOLS)
            mutation_calls += hits
            if hits:
                last = index
        if last < 0:
            continue
        mutating += 1
        blind_after.append(len(turn.steps) - 1 - last)
        after = [n for s2 in turn.steps[last + 1 :] for n in s2["names"]]
        if not any(n in VERIFICATION_TOOLS for n in after):
            unverified += 1
    print(f"  turns that mutated a file        : {mutating}/{len(turns)}"
          f" ({percent(mutating, len(turns))})   calls: {mutation_calls}")
    if blind_after:
        print(
            "  steps continued after last edit  : "
            f"median {statistics.median(blind_after):.0f}, "
            f"mean {statistics.fmean(blind_after):.1f}, max {max(blind_after)}"
        )
    print(
        "  mutating turns with no verification after the last edit: "
        f"{unverified}/{mutating} ({percent(unverified, mutating)})"
    )
    print()

    print("== Follow-through: what a self-monitoring step does next ==")
    # Walk each turn so "already gathered" is turn-scoped, matching the digest.
    marked_calls = marked_repeats = marked_steps = 0
    plain_calls = plain_repeats = plain_steps = 0
    marked_under_digest = 0
    for turn in turns:
        seen: set[tuple[str, str]] = set()
        for step in turn.steps:
            marked = (
                step["strong_think"]
                or step["strong_visible"]
                or step["weak_think"]
                or step["weak_visible"]
            )
            issued = [c for c in step["issued"] if c[0] in INSPECTION_TOOLS]
            repeats = sum(1 for c in issued if c in seen)
            if marked:
                marked_steps += 1
                marked_calls += len(issued)
                marked_repeats += repeats
                if step["digest_strict"] or step["digest_soft"]:
                    marked_under_digest += 1
            else:
                plain_steps += 1
                plain_calls += len(issued)
                plain_repeats += repeats
            seen.update(step["gathered"])

    print(f"  {'step kind':<26}{'steps':>7}{'inspect calls':>15}{'re-inspections':>16}{'share':>8}")
    for name, steps_n, calls, repeats in (
        ("self-monitoring", marked_steps, marked_calls, marked_repeats),
        ("everything else", plain_steps, plain_calls, plain_repeats),
    ):
        print(
            f"  {name:<26}{steps_n:>7}{calls:>15}{repeats:>16}"
            f"{percent(repeats, calls):>8}"
        )
    print(
        "  self-monitoring steps arriving under a digest that discourages "
        f"re-reading: {marked_under_digest}/{marked_steps} "
        f"({percent(marked_under_digest, marked_steps)})"
    )
    strict = sum(1 for t in turns for s2 in t.steps if s2["digest_strict"])
    soft = sum(1 for t in turns for s2 in t.steps if s2["digest_soft"])
    print(
        f"  digest wording across all steps: strict {strict}, soft {soft} "
        "(strict is the pre-softening text; see the module note)"
    )
    print()

    if args.by_model:
        print("== By model ==")
        by_model = collections.defaultdict(list)
        for step in steps:
            by_model[step["model"] or "(unknown)"].append(step)
        print(f"  {'model':<34}{'steps':>7}{'clean':>7}{'strong/clean':>14}")
        for model, bucket in sorted(
            by_model.items(), key=lambda kv: -len(kv[1])
        )[: args.top]:
            bclean = [s for s in bucket if not s["errored"]]
            strong = sum(
                1 for s in bclean if s["strong_think"] or s["strong_visible"]
            )
            print(
                f"  {model[:33]:<34}{len(bucket):>7}{len(bclean):>7}"
                f"{percent(strong, len(bclean)):>14}"
            )
        print()

    if args.examples:
        pool = [
            s
            for s in clean
            if s["strong_think"] or s["strong_visible"] or s["weak_think"]
            or s["weak_visible"]
        ]
        random.seed(args.seed)
        random.shuffle(pool)
        print(f"== Sampled self-initiated candidates ({min(args.examples, len(pool))}"
              f" of {len(pool)}) — read these before trusting the rates ==")
        for step in pool[: args.examples]:
            kind = "STRONG" if (step["strong_think"] or step["strong_visible"]) else "weak"
            match = (STRONG_RE if kind == "STRONG" else WEAK_RE).search(step["content"])
            start = max(0, (match.start() if match else 0) - 140)
            snippet = step["content"][start : start + 320].replace("\n", " ")
            print(f"  [{kind}] {step['session']} {step['model'][:24]}")
            print(f"    …{snippet}…")
        print()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument(
        "--dir",
        action="append",
        default=None,
        help="log root to scan (repeatable); defaults to the app's log dir",
    )
    parser.add_argument("--since-days", type=int, default=None)
    parser.add_argument("--examples", type=int, default=0)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--by-model", action="store_true")
    parser.add_argument("--top", type=int, default=10)
    args = parser.parse_args()

    roots = (
        [pathlib.Path(d).expanduser() for d in args.dir] if args.dir else [log_dir()]
    )
    paths: list[pathlib.Path] = []
    for root in roots:
        if not root.is_dir():
            print(f"No such log directory: {root}", file=sys.stderr)
            return 1
        paths.extend(iter_log_paths(root))
    if not paths:
        print(f"No session logs under {', '.join(str(r) for r in roots)}", file=sys.stderr)
        return 1

    cutoff = (
        dt.datetime.now() - dt.timedelta(days=args.since_days)
        if args.since_days is not None
        else None
    )
    turns, grounded = collect_turns(paths, cutoff)
    print(f"Roots: {', '.join(str(r) for r in roots)}")
    report(turns, grounded, len(paths), args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
