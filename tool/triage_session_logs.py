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
  - oversized_turn   : assistant turns with very large content
  - tool_error       : tool results carrying an error payload (capped; noisy)

Each signal is weighted into a score; sessions are printed worst-first.

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

# Score weights. Tuned so that a single truncation or transport error is
# noticeable while noisy-but-normal tool errors barely register.
WEIGHT_FR_LENGTH = 3.0
WEIGHT_TRANSPORT = 2.5
WEIGHT_TOOL_LOOP = 2.0  # per repeat beyond the first two identical calls
WEIGHT_OVERSIZED = 1.0
WEIGHT_TOOL_ERROR = 0.25

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
    title = ""
    for entry in entries:
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

    loop_excess = max(0, max_run - (TOOL_LOOP_MIN_RUN - 1)) if max_run else 0
    score = (
        fr_length * WEIGHT_FR_LENGTH
        + transport * WEIGHT_TRANSPORT
        + loop_excess * WEIGHT_TOOL_LOOP
        + oversized * WEIGHT_OVERSIZED
        + tool_errors * WEIGHT_TOOL_ERROR
    )
    return {
        "path": path,
        "title": title,
        "entries": len(entries),
        "fr_length": fr_length,
        "transport": transport,
        "max_tool_run": max_run,
        "oversized": oversized,
        "tool_errors": tool_errors,
        "mtime": os.path.getmtime(path),
        "score": round(score, 2),
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

    rows.sort(key=lambda r: (r["score"], r["mtime"]), reverse=True)
    rows = rows[: args.top]

    print(f"== Session log triage ({root}) ==")
    print(
        f"{'score':>6}  {'len':>3} {'txp':>3} {'loop':>4} {'big':>3} {'err':>3}  "
        f"{'n':>3}  session"
    )
    for r in rows:
        ident = r["path"] if args.full else os.path.basename(r["path"])
        title = f"  {r['title']}" if r["title"] else ""
        print(
            f"{r['score']:>6}  {r['fr_length']:>3} {r['transport']:>3} "
            f"{r['max_tool_run']:>4} {r['oversized']:>3} {r['tool_errors']:>3}  "
            f"{r['entries']:>3}  {ident}{title}"
        )
    if not rows:
        print("(no sessions matched)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
