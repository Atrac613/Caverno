#!/usr/bin/env python3
"""Measure recovery after failed ``edit_file`` anchors in session logs.

This is the sequential companion to ``analyze_edit_anchors.py``. It follows
each ``old_text was not found`` result to the next mutation of the same file
and reports whether the next edit recovered, failed again, was abandoned, or
was replaced by ``write_file``. It also counts same-file reads between the
failure and that next action, plus consecutive anchor-failure streak lengths.

The analysis corrects for the two traps documented in
``docs/reread_loop_mechanism_2026-07-21.md``:

1. History replay is removed by de-duplicating messages by stable id within
   each session log.
2. Payload contamination is avoided by JSON-parsing tool results and reading
   the error field rather than substring-matching rendered file content.

Unparseable payloads, missing argument lines, and missing paths are counted as
instrument-quality failures instead of being silently skipped. A failed edit
whose ``old_text`` is nevertheless present verbatim in ``current_content`` is
an asserted-empty canary bucket for parser regressions.

Usage:  python3 tool/analyze_edit_anchor_recovery.py

Honors CAVERNO_SESSION_LOG_DIR / CAVERNO_HOME. Pure stdlib and read-only.
"""

from __future__ import annotations

import argparse
import collections
import importlib.util
import json
import os
import pathlib
import re
import sys


TOOL_DIR = pathlib.Path(__file__).resolve().parent
_SPEC = importlib.util.spec_from_file_location(
    "analyze_tool_results", TOOL_DIR / "analyze_tool_results.py"
)
if _SPEC is None or _SPEC.loader is None:
    raise RuntimeError("Could not load analyze_tool_results.py")
air = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(air)

ARGUMENTS_LINE = re.compile(r"^Arguments:\s*(.+)$", re.MULTILINE)
ANCHOR_ERROR = "old_text was not found in the target file"
TRACKED_TOOLS = frozenset({"edit_file", "read_file", "write_file"})


def _path_key(value: object) -> str | None:
    """Normalize absolute and relative spellings to a stable file suffix."""
    if not isinstance(value, str) or not value.strip():
        return None
    normalized = os.path.normpath(value.strip())
    parent = os.path.basename(os.path.dirname(normalized))
    base = os.path.basename(normalized)
    return f"{parent}/{base}" if parent else base


def _decode_arguments(header: str, quality: collections.Counter) -> dict | None:
    match = ARGUMENTS_LINE.search(header)
    if match is None:
        quality["missing Arguments line"] += 1
        return None
    try:
        decoded = json.loads(match.group(1))
    except ValueError:
        quality["unparseable Arguments JSON"] += 1
        return None
    if not isinstance(decoded, dict):
        quality["Arguments JSON is not an object"] += 1
        return None
    return decoded


def _decode_payload(payload: str, quality: collections.Counter) -> dict | None:
    try:
        decoded = json.loads(payload)
    except ValueError:
        quality["unparseable result payload"] += 1
        return None
    if not isinstance(decoded, dict):
        quality["result payload is not an object"] += 1
        return None
    return decoded


def _is_success(payload: dict | None) -> bool | None:
    if payload is None:
        return None
    if (
        payload.get("error") not in (None, "")
        or payload.get("ok") is False
        or payload.get("already_applied") is True
    ):
        return False
    code = str(payload.get("code") or "").strip().lower()
    if code and code not in {"ok", "success"}:
        return False
    return True


def _message_events(content: str, quality: collections.Counter):
    """Yield parsed tracked-tool events while reusing the shared splitter."""
    marks = list(air.TOOL_SECTION.finditer(content))
    split = list(air.split_tool_sections(content))
    if len(marks) != len(split):
        quality["tool-section parser disagreement"] += 1
        return

    for index, ((tool, payload_text), mark) in enumerate(zip(split, marks)):
        if tool not in TRACKED_TOOLS:
            continue
        end = marks[index + 1].start() if index + 1 < len(marks) else len(content)
        section = content[mark.end() : end]
        cut = section.find(air.RESULT_MARKER)
        if cut < 0:
            quality[f"{tool}: missing Result marker"] += 1
            header = section
        else:
            header = section[:cut]

        local_quality = collections.Counter()
        arguments = _decode_arguments(header, local_quality)
        payload = _decode_payload(payload_text, local_quality)
        for name, count in local_quality.items():
            quality[f"{tool}: {name}"] += count

        path = arguments.get("path") if arguments is not None else None
        key = _path_key(path)
        if key is None:
            quality[f"{tool}: missing path"] += 1
        yield {
            "tool": tool,
            "arguments": arguments,
            "payload": payload,
            "path_key": key,
            "success": _is_success(payload),
            "anchor_failure": (
                tool == "edit_file"
                and payload is not None
                and payload.get("error") == ANCHOR_ERROR
            ),
        }


def _session_events(path: pathlib.Path, counters: collections.Counter):
    seen_ids: set[str] = set()
    events = []
    for record in air.iter_records(path):
        for message in (record.get("request") or {}).get("messages") or []:
            counters["message slots"] += 1
            message_id = message.get("id")
            if message_id is None:
                counters["messages without id"] += 1
                continue
            if message_id in seen_ids:
                continue
            seen_ids.add(message_id)
            counters["distinct messages"] += 1
            content = message.get("content")
            if not isinstance(content, str) or "[Tool: " not in content:
                continue
            events.extend(_message_events(content, counters))
    return events


def collect(paths):
    counters = collections.Counter()
    outcomes = collections.Counter()
    split_outcomes = collections.Counter()
    reads_by_outcome = collections.Counter()
    split_reads = collections.Counter()
    streaks = collections.Counter()
    failures = 0
    canary = 0

    for path in paths:
        events = _session_events(path, counters)
        failures_by_path = collections.defaultdict(list)

        for index, event in enumerate(events):
            if not event["anchor_failure"]:
                continue
            failures += 1
            arguments = event["arguments"] or {}
            payload = event["payload"] or {}
            current_content = payload.get("current_content")
            split = (
                "with current_content"
                if isinstance(current_content, str)
                else "without current_content"
            )
            old_text = arguments.get("old_text")
            if (
                isinstance(current_content, str)
                and isinstance(old_text, str)
                and old_text
                and old_text in current_content
            ):
                canary += 1

            key = event["path_key"]
            if key is None:
                outcomes["unclassified path"] += 1
                split_outcomes[("unclassified path", split)] += 1
                continue
            failures_by_path[key].append(index)

            read_between = False
            outcome = "abandoned"
            for later in events[index + 1 :]:
                if later["path_key"] != key:
                    continue
                if later["tool"] == "read_file":
                    read_between = True
                    continue
                if later["tool"] == "write_file":
                    outcome = "switched_to_write"
                    break
                if later["tool"] == "edit_file":
                    if later["success"] is True:
                        outcome = "recovered_next"
                    elif later["success"] is False:
                        outcome = "failed_again"
                    else:
                        outcome = "unclassifiable_next_edit"
                    break

            outcomes[outcome] += 1
            split_outcomes[(outcome, split)] += 1
            if read_between:
                reads_by_outcome[(outcome, "read")] += 1
                split_reads[(outcome, split, "read")] += 1
            else:
                reads_by_outcome[(outcome, "no read")] += 1
                split_reads[(outcome, split, "no read")] += 1

        for key, failure_indexes in failures_by_path.items():
            failure_set = set(failure_indexes)
            run = 0
            for index, event in enumerate(events):
                if event["path_key"] != key or event["tool"] != "edit_file":
                    continue
                if index in failure_set:
                    run += 1
                elif run:
                    streaks[run] += 1
                    run = 0
            if run:
                streaks[run] += 1

    counters["session logs"] = len(paths)
    counters["anchor failures"] = failures
    counters["verbatim-present canary"] = canary
    return {
        "counters": counters,
        "outcomes": outcomes,
        "split_outcomes": split_outcomes,
        "reads_by_outcome": reads_by_outcome,
        "split_reads": split_reads,
        "streaks": streaks,
    }


def _print_report(result) -> None:
    counters = result["counters"]
    outcomes = result["outcomes"]
    split_outcomes = result["split_outcomes"]
    reads = result["reads_by_outcome"]
    split_reads = result["split_reads"]
    total = counters["anchor failures"]
    slots = counters["message slots"]
    distinct = counters["distinct messages"]
    inflation = slots / distinct if distinct else 1.0

    print("== Edit-anchor recovery ==")
    print(f"{counters['session logs']} session logs, {total} anchor failures")
    print(
        f"history replay: {slots} message slots -> {distinct} distinct "
        f"({inflation:.1f}x)"
    )
    print(
        "verbatim-present canary: "
        f"{counters['verbatim-present canary']} (must remain zero)"
    )

    print("\n== Next same-file action ==")
    print(
        f"{'outcome':26}{'total':>7}{'with content':>15}"
        f"{'without':>10}{'read seen':>11}"
    )
    order = [
        "recovered_next",
        "failed_again",
        "switched_to_write",
        "abandoned",
        "unclassifiable_next_edit",
        "unclassified path",
    ]
    for outcome in order:
        count = outcomes[outcome]
        if not count and outcome not in order[:4]:
            continue
        with_content = split_outcomes[(outcome, "with current_content")]
        without = split_outcomes[(outcome, "without current_content")]
        read_count = reads[(outcome, "read")]
        print(
            f"{outcome:26}{count:7}{with_content:15}"
            f"{without:10}{read_count:11}"
        )

    print("\n== Same-file read before the next edit ==")
    print(
        f"{'failure payload':26}{'next edits':>11}"
        f"{'read before':>13}{'recovered after read':>22}"
    )
    for split in ("with current_content", "without current_content"):
        next_edits = sum(
            split_outcomes[(outcome, split)]
            for outcome in ("recovered_next", "failed_again")
        )
        read_before = sum(
            split_reads[(outcome, split, "read")]
            for outcome in ("recovered_next", "failed_again")
        )
        recovered_after_read = split_reads[("recovered_next", split, "read")]
        print(
            f"{split:26}{next_edits:11}{read_before:13}"
            f"{recovered_after_read:22}"
        )

    print("\n== Consecutive anchor-failure streaks ==")
    print(f"{'length':>8}{'runs':>8}{'failures':>11}")
    for length, runs in sorted(result["streaks"].items()):
        print(f"{length:8}{runs:8}{length * runs:11}")

    quality = [(name, count) for name, count in counters.items() if ": " in name]
    print("\n== Instrument quality ==")
    if quality:
        for name, count in sorted(quality):
            print(f"{count:5}  {name}")
    else:
        print("    0  parse or argument issues")
    if counters["messages without id"]:
        print(f"{counters['messages without id']:5}  messages without id")
    if total < 20:
        print("\nWARNING: fewer than 20 classifiable failures; treat as indicative.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--dir", type=pathlib.Path, default=None)
    args = parser.parse_args()

    root = args.dir.expanduser() if args.dir else air.log_dir()
    if not root.is_dir():
        print(f"No session log directory at {root}", file=sys.stderr)
        return 1
    paths = sorted(root.glob("*/*.jsonl")) + sorted(root.glob("*.jsonl"))
    if not paths:
        print(f"No session logs under {root}", file=sys.stderr)
        return 1

    result = collect(paths)
    _print_report(result)
    if result["counters"]["verbatim-present canary"]:
        print(
            "Parser canary failed: old_text was present in current_content",
            file=sys.stderr,
        )
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
