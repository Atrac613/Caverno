#!/usr/bin/env python3
"""Summarize a `flutter test --file-reporter json:...` log for LLM consumption.

The default Flutter reporters echo one progress line per test plus every
`print` / `Logger` line emitted by *passing* tests. On this repository that is
~3.4 MB of stdout for a fully green run, which an agent must either read or
have truncated. Almost none of it carries information when the run succeeds.

This summarizer reads the machine-readable JSON log instead and prints:

* a one-line verdict plus counts when everything passed;
* only the failing tests -- name, suite location, error, filtered stack, and
  the console output captured *for that test* -- when something failed.

Exit code mirrors the run: 0 when the JSON log reports success, 1 otherwise.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any

# Stack frames from these packages describe the test harness, not the code
# under test, so they are noise in a failure report.
_NOISY_FRAME_MARKERS = (
    "package:test_api",
    "package:test_core",
    "package:matcher",
    "package:stack_trace",
    "package:flutter_test/src/binding.dart",
    "dart:async",
    "dart:isolate",
)


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Summarize a Flutter test JSON reporter log.",
    )
    parser.add_argument("log", help="Path to the JSON reporter log.")
    parser.add_argument(
        "--root",
        default=os.getcwd(),
        help="Repository root used to shorten absolute paths.",
    )
    parser.add_argument(
        "--max-failures",
        type=int,
        default=10,
        help="Maximum number of failing tests to describe. Default: 10.",
    )
    parser.add_argument(
        "--max-error-lines",
        type=int,
        default=25,
        help="Maximum error lines per failure. Default: 25.",
    )
    parser.add_argument(
        "--max-stack-lines",
        type=int,
        default=8,
        help="Maximum stack frames per failure. Default: 8.",
    )
    parser.add_argument(
        "--max-print-lines",
        type=int,
        default=20,
        help="Maximum captured console lines per failure. Default: 20.",
    )
    parser.add_argument(
        "--slowest",
        type=int,
        default=0,
        help="Also list the N slowest tests on success. Default: 0 (off).",
    )
    return parser.parse_args(argv)


class _Run:
    def __init__(self) -> None:
        self.suites: dict[Any, str] = {}
        self.tests: dict[Any, dict[str, Any]] = {}
        self.errors: dict[Any, list[dict[str, str]]] = {}
        self.prints: dict[Any, list[str]] = {}
        self.suite_count = 0
        self.success: bool | None = None
        self.load_errors: list[dict[str, str]] = []

    def ingest(self, event: dict[str, Any]) -> None:
        kind = event.get("type")
        if kind == "suite":
            suite = event.get("suite", {})
            self.suites[suite.get("id")] = suite.get("path") or "<unknown>"
        elif kind == "allSuites":
            self.suite_count = event.get("count", 0)
        elif kind == "testStart":
            test = event.get("test", {})
            self.tests[test.get("id")] = {
                "name": test.get("name", "<unnamed>"),
                "suiteID": test.get("suiteID"),
                "line": test.get("root_line") or test.get("line"),
                "start": event.get("time", 0),
                "result": None,
                "hidden": False,
                "skipped": False,
            }
        elif kind == "testDone":
            record = self.tests.get(event.get("testID"))
            if record is None:
                return
            record["result"] = event.get("result")
            record["hidden"] = bool(event.get("hidden"))
            record["skipped"] = bool(event.get("skipped"))
            record["duration"] = event.get("time", 0) - record["start"]
        elif kind == "print":
            self.prints.setdefault(event.get("testID"), []).append(
                event.get("message", "")
            )
        elif kind == "error":
            entry = {
                "error": event.get("error", ""),
                "stackTrace": event.get("stackTrace", ""),
            }
            test_id = event.get("testID")
            if test_id in self.tests:
                self.errors.setdefault(test_id, []).append(entry)
            else:
                self.load_errors.append(entry)
        elif kind == "done":
            self.success = bool(event.get("success"))


def _load(path: str) -> _Run:
    run = _Run()
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                run.ingest(json.loads(line))
            except json.JSONDecodeError:
                continue
    return run


def _relative(path: str, root: str) -> str:
    try:
        return os.path.relpath(path, root)
    except ValueError:
        return path


def _clip(lines: list[str], limit: int) -> list[str]:
    if len(lines) <= limit:
        return lines
    dropped = len(lines) - limit
    return lines[:limit] + [f"    ... {dropped} more line(s) omitted"]


def _filter_stack(stack: str, limit: int) -> list[str]:
    frames = [frame.rstrip() for frame in stack.splitlines() if frame.strip()]
    project = [
        frame
        for frame in frames
        if not any(marker in frame for marker in _NOISY_FRAME_MARKERS)
    ]
    return _clip(project or frames, limit)


def main(argv: list[str]) -> int:
    args = _parse_args(argv)
    if not os.path.exists(args.log):
        print(f"FAIL: test JSON log not found at {args.log}", file=sys.stderr)
        return 1

    run = _load(args.log)

    # A test is only interesting when it failed. `hidden` marks the synthetic
    # tearDown/setUpAll entries the reporter emits for bookkeeping.
    failed = [
        (test_id, record)
        for test_id, record in run.tests.items()
        if record.get("result") not in (None, "success")
        or test_id in run.errors
    ]
    completed = [r for r in run.tests.values() if not r["hidden"]]
    skipped = sum(1 for r in completed if r["skipped"])
    passed = sum(
        1 for r in completed if r["result"] == "success" and not r["skipped"]
    )

    if run.load_errors:
        print(f"FAIL: {len(run.load_errors)} suite(s) failed to load")
        for entry in run.load_errors[: args.max_failures]:
            message = entry["error"].replace(args.root + os.sep, "")
            for line in _clip(message.splitlines(), args.max_error_lines):
                print(f"  {line}")
        return 1

    if not failed and run.success:
        summary = (
            f"PASS {passed} tests in {run.suite_count or len(run.suites)} suites"
        )
        if skipped:
            summary += f" ({skipped} skipped)"
        print(summary)
        if args.slowest > 0:
            slow = sorted(
                (r for r in completed if r.get("duration") is not None),
                key=lambda r: r["duration"],
                reverse=True,
            )[: args.slowest]
            print("Slowest tests:")
            for record in slow:
                suite = _relative(run.suites.get(record["suiteID"], "?"), args.root)
                print(f"  {record['duration'] / 1000:6.1f}s {suite}: {record['name']}")
        return 0

    if not failed and run.success is None:
        # No `done` event: the run was killed (timeout, Ctrl-C, crashed host)
        # rather than failing. Saying "FAIL 0 of N" would hide that.
        unfinished = [
            record for record in run.tests.values() if record["result"] is None
        ]
        print(
            f"INCOMPLETE: the run ended without a result. "
            f"{passed} passed, {len(unfinished)} test(s) never finished."
        )
        for record in unfinished[:5]:
            suite = _relative(run.suites.get(record["suiteID"], "?"), args.root)
            name = record["name"].replace(args.root + os.sep, "")
            print(f"  in flight: {suite}: {name}")
        return 1

    print(f"FAIL {len(failed)} of {passed + len(failed)} tests")
    for test_id, record in failed[: args.max_failures]:
        suite = _relative(run.suites.get(record["suiteID"], "?"), args.root)
        location = f"{suite}:{record['line']}" if record["line"] else suite
        print(f"\n--- {location}")
        print(f"    {record['name'].replace(args.root + os.sep, '')}")
        for entry in run.errors.get(test_id, []):
            message = entry["error"].replace(args.root + os.sep, "")
            for line in _clip(message.splitlines(), args.max_error_lines):
                print(f"  {line}")
            for frame in _filter_stack(entry["stackTrace"], args.max_stack_lines):
                print(f"    {frame}")
        captured = run.prints.get(test_id, [])
        if captured:
            print("  captured output:")
            for line in _clip(captured, args.max_print_lines):
                print(f"    {line}")
    if len(failed) > args.max_failures:
        print(
            f"\n... {len(failed) - args.max_failures} more failing test(s); "
            f"rerun with --max-failures to see them"
        )
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
