#!/usr/bin/env python3
"""Count distinct tool results and payload facts across Caverno session logs.

Why this exists
---------------
The obvious way to ask "how often does X happen?" is to grep the session logs.
Two things make that wrong, and both produced published-then-withdrawn numbers
(see docs/reread_loop_mechanism_2026-07-21.md):

1. **Replay.** Every log record carries the whole conversation, so a message
   from turn 1 appears again in every later record. One session measured here
   holds 415 message slots for 23 distinct messages -- an 18x inflation, and
   not a uniform one, since early turns are replayed more than late ones.

2. **Payload contamination.** Tool payloads embed file content: the `old_text`
   not-found error inlines the file being edited. Grepping for `not found`
   counted 64 lines of a TODO app printing "item not found" as if they were
   tool errors.

This tool avoids both. Messages are de-duplicated by their stable id, so each
is counted once in the session where it first appears, and payloads are JSON
parsed so a fact is read from its field rather than matched as a substring.

Usage
-----
    python3 tool/analyze_tool_results.py                 # summary
    python3 tool/analyze_tool_results.py --tool edit_file
    python3 tool/analyze_tool_results.py --since-days 30
    python3 tool/analyze_tool_results.py --sessions      # per-session table

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
import re
import sys

TOOL_SECTION = re.compile(r"\[Tool: ([a-z0-9_]+)\]")
RESULT_MARKER = "\nResult:\n"


def log_dir() -> pathlib.Path:
    if os.environ.get("CAVERNO_SESSION_LOG_DIR"):
        return pathlib.Path(os.environ["CAVERNO_SESSION_LOG_DIR"]).expanduser()
    home = os.environ.get("CAVERNO_HOME") or "~/.caverno"
    return pathlib.Path(home).expanduser() / "session_logs"


def iter_records(path: pathlib.Path):
    with path.open(errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except ValueError:
                continue


def split_tool_sections(content: str):
    """Yield (tool_name, payload) for each rendered tool result in a message.

    Mirrors ToolResultPromptBuilder.formatToolResults: sections start with
    `[Tool: <name>]` and the payload follows a `Result:` line. The payload is
    returned raw; callers decide whether to parse it.
    """
    marks = list(TOOL_SECTION.finditer(content))
    for index, match in enumerate(marks):
        end = marks[index + 1].start() if index + 1 < len(marks) else len(content)
        section = content[match.end() : end]
        cut = section.find(RESULT_MARKER)
        payload = section[cut + len(RESULT_MARKER) :] if cut >= 0 else ""
        yield match.group(1), payload.strip()


def payload_facts(payload: str) -> dict:
    """Read facts from a tool payload by parsing it, never by substring match.

    An unparseable payload yields nothing rather than a guess -- the same rule
    the ToolOutcome contract follows.
    """
    try:
        decoded = json.loads(payload)
    except ValueError:
        return {}
    if not isinstance(decoded, dict):
        return {}
    facts = {}
    error = decoded.get("error")
    if isinstance(error, str) and error.strip():
        facts["error"] = error.strip()
    for key in ("exit_code", "changed", "created", "already_applied"):
        if key in decoded:
            facts[key] = decoded[key]
    return facts


def collect(paths, since_days: int | None):
    cutoff = None
    if since_days is not None:
        cutoff = dt.datetime.now() - dt.timedelta(days=since_days)

    renders = collections.Counter()          # distinct tool results per tool
    sessions_with = collections.Counter()    # sessions containing each tool
    errors = collections.Counter()           # (tool, normalized error) pairs
    facts = collections.Counter()            # notable payload facts
    per_session = []
    replay_slots = replay_distinct = 0

    for path in paths:
        if cutoff is not None:
            try:
                if dt.datetime.fromtimestamp(path.stat().st_mtime) < cutoff:
                    continue
            except OSError:
                continue

        seen_ids: set[str] = set()
        local = collections.Counter()
        local_errors = collections.Counter()
        for record in iter_records(path):
            messages = (record.get("request") or {}).get("messages") or []
            for message in messages:
                replay_slots += 1
                key = message.get("id")
                if key is None or key in seen_ids:
                    continue
                seen_ids.add(key)
                replay_distinct += 1
                content = message.get("content")
                if not isinstance(content, str) or "[Tool: " not in content:
                    continue
                for tool, payload in split_tool_sections(content):
                    local[tool] += 1
                    found = payload_facts(payload)
                    if "error" in found:
                        # Collapse the variable tail so distinct failures group.
                        head = found["error"].split(":")[0][:60]
                        local_errors[(tool, head)] += 1
                    for name in ("changed", "exit_code", "already_applied"):
                        if name in found:
                            facts[f"{tool}.{name}={found[name]}"] += 1

        if not local:
            continue
        renders.update(local)
        errors.update(local_errors)
        for tool in local:
            sessions_with[tool] += 1
        per_session.append((path.name[:8], sum(local.values()), local, local_errors))

    return renders, sessions_with, errors, facts, per_session, replay_slots, replay_distinct


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--since-days", type=int, default=None)
    parser.add_argument("--tool", default=None, help="restrict output to one tool")
    parser.add_argument("--sessions", action="store_true", help="per-session table")
    parser.add_argument("--top", type=int, default=20)
    args = parser.parse_args()

    root = log_dir()
    if not root.is_dir():
        print(f"No session log directory at {root}", file=sys.stderr)
        return 1
    paths = sorted(root.glob("*/*.jsonl")) + sorted(root.glob("*.jsonl"))
    if not paths:
        print(f"No session logs under {root}", file=sys.stderr)
        return 1

    (renders, sessions_with, errors, facts, per_session, slots, distinct) = collect(
        paths, args.since_days
    )

    total = sum(renders.values())
    print(f"== Distinct tool results ({root}) ==")
    print(f"{len(paths)} session logs, {total} tool results, {len(renders)} tools invoked")
    inflation = slots / distinct if distinct else 1.0
    print(
        f"history replay: {slots} message slots -> {distinct} distinct "
        f"({inflation:.1f}x); grep-based counts would inflate by roughly this"
    )

    print(f"\n{'tool':30}{'results':>9}{'share':>8}{'sessions':>10}")
    items = renders.most_common()
    if args.tool:
        items = [(t, c) for t, c in items if t == args.tool]
    for tool, count in items[: args.top]:
        share = 100 * count / total if total else 0
        print(f"{tool:30}{count:9}{share:7.1f}%{sessions_with[tool]:10}")

    if errors:
        print(f"\n== Tool errors (parsed from the payload's error field) ==")
        for (tool, head), count in errors.most_common(args.top):
            if args.tool and tool != args.tool:
                continue
            print(f"{count:5}  {tool:24} {head}")

    if facts:
        print(f"\n== Payload facts (LL34 outcome fields) ==")
        for name, count in facts.most_common(args.top):
            if args.tool and not name.startswith(args.tool + "."):
                continue
            print(f"{count:5}  {name}")

    if args.sessions:
        print(f"\n== Per session ==")
        for name, count, local, local_errors in sorted(
            per_session, key=lambda row: -row[1]
        )[: args.top]:
            top = ", ".join(f"{t}x{c}" for t, c in local.most_common(4))
            errs = sum(local_errors.values())
            print(f"{name}  {count:4} results  errors={errs:3}  {top}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
