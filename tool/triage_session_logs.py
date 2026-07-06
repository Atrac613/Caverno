#!/usr/bin/env python3
"""Rank Caverno LLM session logs by how anomalous they look.

Each ``~/.caverno/session_logs/**/<id>.jsonl`` file records one chat/coding
session as a series of LLM request/response entries (schema
``caverno_llm_session_log_entry``). This tool scores every session by signals
that historically pointed at real harness problems, so you can deep-dive the
worst offenders instead of opening logs at random.

Signals (per session):
  - fr_length        : responses cut off by the token limit (finishReason=length)
  - transport_error  : entries with a transport error / no finishReason
  - tool_loop        : longest run of identical consecutive tool-call signatures
  - reread           : byte-identical repeat read_file requests (same file AND
                       same paging window) across the turn — non-consecutive, so
                       `tool_loop` misses them. Distinct offset/limit windows of
                       one file are legitimate paging and don't count. read_file
                       is repeatable by design, so the first two repeats are free.
  - oversized_turn   : assistant turns with very large content
  - tool_error       : tool results carrying an error payload (capped; noisy)

Each signal is weighted into a score; sessions are printed worst-first.

The ``build`` column shows the git commit the binary was built from (schema v2+;
a ``*`` suffix means the build had uncommitted changes, ``—`` means the log
predates build provenance or the binary was not built via tool/safe-flutter).

Locations match the app: honors CAVERNO_SESSION_LOG_DIR, else
CAVERNO_HOME (default ~/.caverno) + /session_logs.

Pure python3, no Flutter/Dart/Caverno runtime, so any coding agent with shell
access can run it.

Usage:
  tool/triage_session_logs.py [--top N] [--since-days D] [--min-score S]
                              [--dir PATH] [--full]
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import time
from collections import Counter

# Score weights. Tuned so that a single truncation or transport error is
# noticeable while noisy-but-normal tool errors barely register.
WEIGHT_FR_LENGTH = 3.0
WEIGHT_TRANSPORT = 2.5
WEIGHT_TOOL_LOOP = 2.0  # per repeat beyond the first two identical calls
# Redundant file re-reads: the dominant *silent* inefficiency in real logs
# (~53% of read_file sessions have >=1; worst seen: one file read 34x). Unlike
# tool_loop these are non-consecutive, so they otherwise score zero. read_file
# is repeatable by design ([[caverno-read-file-repeatable-by-design]]), so only
# re-reads beyond REREAD_FREE per session are penalised, and lightly.
WEIGHT_REREAD = 0.4  # per redundant read beyond the free allowance
REREAD_FREE = 2      # redundant reads tolerated before scoring kicks in
WEIGHT_OVERSIZED = 1.0
WEIGHT_TOOL_ERROR = 0.25
# LL31 turn-exit instrument: a turn that ended with no visible answer ("the
# agent just stops") is a strong anomaly signal; abnormal-but-answered exits
# (tool_failure_abort, max_iterations, length_truncated) get a lighter weight.
WEIGHT_NO_ANSWER = 2.5
WEIGHT_ABNORMAL_EXIT = 0.5

# turn_exit reasons that are abnormal (everything except a healthy text answer).
_ABNORMAL_EXIT_REASONS = frozenset({
    "tool_failure_abort",
    "max_iterations",
    "guardrail_block",
    "user_confirmation_block",
    "streaming_cancelled",
    "length_truncated",
    "empty_response",
    "partial_fragment",
    "unknown",
})

OVERSIZED_CONTENT_CHARS = 8000
TOOL_LOOP_MIN_RUN = 3  # a run shorter than this is normal exploration

_ERROR_MARKERS = ('"error"', "is required", "old_text was not found", "not found")


def _session_dir() -> str:
    override = os.environ.get("CAVERNO_SESSION_LOG_DIR")
    if override:
        return override
    home = os.environ.get("CAVERNO_HOME", os.path.expanduser("~/.caverno"))
    return os.path.join(home, "session_logs")


def _iter_log_files(root: str):
    yield from glob.glob(os.path.join(root, "*", "*.jsonl"))
    yield from glob.glob(os.path.join(root, "*.jsonl"))


def _tool_names(response: dict) -> tuple:
    calls = response.get("toolCalls") or []
    names = []
    for call in calls:
        if not isinstance(call, dict):
            continue
        name = call.get("name") or call.get("function", {}).get("name")
        if name:
            names.append(name)
    return tuple(sorted(names))


def _read_paths(response: dict):
    """Yield read_file keys ``(<parent>/<basename>, offset, limit, max_chars)``.

    The path part normalizes to ``<parent>/<basename>`` so the same file counts
    as one target whether the model addressed it by a relative or an absolute
    path (the two formats resolve to the same file but are distinct strings — a
    real driver of the re-read loop). The paging window (offset/limit/max_chars)
    is part of the key on purpose: distinct windows of a large file are
    legitimate paging, NOT redundant, so only byte-identical repeat requests
    collapse to the same key. (Keying on the path alone mislabels paging as
    thrash — e.g. session 495ad863 paged chat_notifier.dart 6x with distinct
    windows and would otherwise score as the worst offender.) Collisions between
    same-named files in different subtrees are accepted as noise.
    """
    for call in response.get("toolCalls") or []:
        if not isinstance(call, dict):
            continue
        name = call.get("name") or call.get("function", {}).get("name")
        if name != "read_file":
            continue
        args = call.get("arguments")
        if args is None:
            args = call.get("function", {}).get("arguments")
        if isinstance(args, str):
            try:
                args = json.loads(args)
            except ValueError:
                continue
        if not isinstance(args, dict):
            continue
        path = (args.get("path") or "").strip().rstrip("/")
        if not path:
            continue
        parent = os.path.basename(os.path.dirname(path))
        base = os.path.basename(path)
        norm = f"{parent}/{base}" if parent else base
        yield (norm, args.get("offset"), args.get("limit"), args.get("max_chars"))


def _is_transport_error(entry: dict, response: dict) -> bool:
    if entry.get("error") or response.get("errorMessage"):
        return True
    # A missing finishReason with no content and no tool calls is an aborted
    # request (e.g. the stream never produced a terminal chunk).
    return (
        response.get("finishReason") in (None, "")
        and not (response.get("content") or "")
        and not (response.get("toolCalls") or [])
    )


def _count_error_markers(entry: dict) -> int:
    count = 0
    for message in entry.get("request", {}).get("messages", []):
        content = message.get("content")
        if isinstance(content, str) and any(m in content for m in _ERROR_MARKERS):
            count += 1
    return count


def analyze(path: str) -> dict | None:
    try:
        entries = [json.loads(line) for line in open(path) if line.strip()]
    except (OSError, ValueError):
        return None
    if not entries:
        return None

    fr_length = 0
    transport = 0
    oversized = 0
    tool_errors = 0
    max_run = 0
    run = 0
    prev_sig = None
    read_counts: Counter = Counter()
    title = ""
    # Build provenance (schema v2+); v1 logs have no `build` block.
    build = next((e["build"] for e in entries if e.get("build")), {})
    commit = build.get("commit") or "—"
    dirty = bool(build.get("dirty"))
    no_answer = 0
    exit_reasons: Counter = Counter()
    transforms: Counter = Counter()
    for entry in entries:
        # LL31 turn-exit markers are separate, response-less entries.
        if entry.get("operation") == "turn_exit":
            turn_exit = entry.get("turnExit", {})
            reason = turn_exit.get("reason") or "unknown"
            exit_reasons[reason] += 1
            if turn_exit.get("noVisibleAnswer"):
                no_answer += 1
            # Post-LLM transforms applied to the on-screen message (guard
            # notices, etc.) — a direct record of guard firings, no longer
            # inferred from leaked notice prose.
            for t in turn_exit.get("transforms") or []:
                transforms[t] += 1
            continue
        response = entry.get("response", {})
        title = title or entry.get("context", {}).get("sessionTitle", "")
        if response.get("finishReason") == "length":
            fr_length += 1
        if _is_transport_error(entry, response):
            transport += 1
        if len(response.get("content") or "") > OVERSIZED_CONTENT_CHARS:
            oversized += 1
        tool_errors += _count_error_markers(entry)

        sig = _tool_names(response)
        if sig and sig == prev_sig:
            run += 1
            max_run = max(max_run, run + 1)
        else:
            run = 0
        if sig:
            prev_sig = sig

        read_counts.update(_read_paths(response))

    loop_excess = max(0, max_run - (TOOL_LOOP_MIN_RUN - 1)) if max_run else 0
    # Redundant reads = byte-identical repeat read_file requests (same file +
    # same paging window) beyond the first, across the whole session. Distinct
    # windows of one file are legitimate paging and do NOT count (see
    # _read_paths). `reread_max` is the worst single byte-identical repeat.
    reread_total = sum(read_counts.values()) - len(read_counts)
    reread_max = max(read_counts.values(), default=0)
    reread_excess = max(0, reread_total - REREAD_FREE)
    abnormal_exits = sum(
        c for r, c in exit_reasons.items() if r in _ABNORMAL_EXIT_REASONS
    )
    score = (
        fr_length * WEIGHT_FR_LENGTH
        + transport * WEIGHT_TRANSPORT
        + loop_excess * WEIGHT_TOOL_LOOP
        + reread_excess * WEIGHT_REREAD
        + oversized * WEIGHT_OVERSIZED
        + tool_errors * WEIGHT_TOOL_ERROR
        + no_answer * WEIGHT_NO_ANSWER
        + abnormal_exits * WEIGHT_ABNORMAL_EXIT
    )
    return {
        "path": path,
        "title": title,
        "entries": len(entries),
        "fr_length": fr_length,
        "transport": transport,
        "max_tool_run": max_run,
        "reread_total": reread_total,
        "reread_max": reread_max,
        "oversized": oversized,
        "tool_errors": tool_errors,
        "no_answer": no_answer,
        "exit_reasons": dict(exit_reasons),
        "transforms": dict(transforms),
        "mtime": os.path.getmtime(path),
        "score": round(score, 2),
        "commit": commit,
        "dirty": dirty,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--top", type=int, default=10, help="rows to print")
    parser.add_argument(
        "--since-days",
        type=float,
        default=None,
        help="only sessions modified within the last N days",
    )
    parser.add_argument(
        "--min-score", type=float, default=0.0, help="hide sessions below this score"
    )
    parser.add_argument("--dir", default=None, help="session_logs dir override")
    parser.add_argument(
        "--full", action="store_true", help="print absolute paths, not basenames"
    )
    args = parser.parse_args()

    root = args.dir or _session_dir()
    if not os.path.isdir(root):
        print(f"session log dir not found: {root}")
        return 1

    cutoff = time.time() - args.since_days * 86400 if args.since_days else None
    rows = []
    for path in _iter_log_files(root):
        if cutoff and os.path.getmtime(path) < cutoff:
            continue
        row = analyze(path)
        if row and row["score"] >= args.min_score:
            rows.append(row)

    # Aggregate the LL31 exit-reason distribution across every scanned session
    # (not just the printed top-N) — this is the evidence that gates LL29 vs
    # LL30: it shows whether complex turns actually stop on tool_failure_abort,
    # max_iterations, an empty answer, or normal text_response.
    exit_totals: Counter = Counter()
    transform_totals: Counter = Counter()
    for r in rows:
        exit_totals.update(r.get("exit_reasons") or {})
        transform_totals.update(r.get("transforms") or {})

    # Worst byte-identical repeat-read offenders (reread_max), across all
    # scanned sessions — spotlights thrash that ranking-by-total can bury.
    reread_offenders = sorted(
        (r for r in rows if r.get("reread_max", 0) >= 3),
        key=lambda r: r["reread_max"],
        reverse=True,
    )
    reread_sessions = sum(1 for r in rows if r.get("reread_total", 0) >= 1)

    rows.sort(key=lambda r: (r["score"], r["mtime"]), reverse=True)
    rows = rows[: args.top]

    print(f"== Session log triage ({root}) ==")
    print(
        f"{'score':>6}  {'len':>3} {'txp':>3} {'loop':>4} {'rerd':>4} {'big':>3} "
        f"{'err':>3} {'stop':>4}  {'n':>3}  {'build':>9}  session"
    )
    for r in rows:
        ident = r["path"] if args.full else os.path.basename(r["path"])
        title = f"  {r['title']}" if r["title"] else ""
        # `*` marks a build made with uncommitted changes (commit is not exact).
        build = r["commit"] + ("*" if r["dirty"] else "")
        print(
            f"{r['score']:>6}  {r['fr_length']:>3} {r['transport']:>3} "
            f"{r['max_tool_run']:>4} {r['reread_total']:>4} {r['oversized']:>3} "
            f"{r['tool_errors']:>3} {r['no_answer']:>4}  {r['entries']:>3}  "
            f"{build:>9}  {ident}{title}"
        )
    if not rows:
        print("(no sessions matched)")

    if exit_totals:
        total = sum(exit_totals.values())
        print(f"\n== Turn-exit reasons (LL31, {total} turns across all scanned) ==")
        for reason, count in exit_totals.most_common():
            mark = " *" if reason in _ABNORMAL_EXIT_REASONS else ""
            print(f"  {count:>5} ({count / total:>5.1%})  {reason}{mark}")

    if reread_offenders:
        print(
            f"\n== Redundant file re-reads (worst byte-identical repeat; "
            f"{reread_sessions} sessions with any re-read) =="
        )
        for r in reread_offenders[:10]:
            ident = r["path"] if args.full else os.path.basename(r["path"])
            title = f"  {r['title']}" if r["title"] else ""
            print(
                f"  {r['reread_max']:>3}x identical, {r['reread_total']:>3} "
                f"redundant total  {ident}{title}"
            )

    if transform_totals:
        print("\n== Post-LLM transforms applied to on-screen messages ==")
        for name, count in transform_totals.most_common():
            print(f"  {count:>5}  {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
