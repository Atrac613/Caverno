#!/usr/bin/env python3
"""Regression tests for ``tool/summarize_flutter_test_json.py``.

The summarizer exists so a green `flutter test` run costs an agent one line
instead of the ~3.4 MB the default reporter emits. These tests pin the two
properties that make it safe to rely on: passing tests contribute nothing to
the output, and a failing test keeps its error, its own captured console
output, and a stack trace with the harness frames removed.
"""

import importlib.util
import io
import json
import pathlib
import tempfile
import unittest
from contextlib import redirect_stdout


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "summarize_flutter_test_json",
    ROOT / "tool" / "summarize_flutter_test_json.py",
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Could not load summarizer tool")
summarize = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(summarize)


def _events(*events: dict) -> list[dict]:
    return list(events)


def _suite(suite_id: int, path: str) -> dict:
    return {"type": "suite", "suite": {"id": suite_id, "path": path}}


def _start(test_id: int, name: str, suite_id: int, line: int, time: int) -> dict:
    return {
        "type": "testStart",
        "time": time,
        "test": {
            "id": test_id,
            "name": name,
            "suiteID": suite_id,
            "root_line": line,
        },
    }


def _done(test_id: int, result: str, time: int, hidden: bool = False) -> dict:
    return {
        "type": "testDone",
        "testID": test_id,
        "result": result,
        "hidden": hidden,
        "skipped": False,
        "time": time,
    }


class SummarizeFlutterTestJsonTest(unittest.TestCase):
    def _run(self, events: list[dict], *args: str) -> tuple[int, str]:
        with tempfile.TemporaryDirectory() as directory:
            log = pathlib.Path(directory) / "flutter_test.json"
            log.write_text(
                "\n".join(json.dumps(event) for event in events) + "\n",
                encoding="utf-8",
            )
            buffer = io.StringIO()
            with redirect_stdout(buffer):
                status = summarize.main([str(log), "--root", "/repo", *args])
            return status, buffer.getvalue()

    def test_green_run_collapses_to_a_single_line(self) -> None:
        status, output = self._run(
            _events(
                _suite(0, "/repo/test/a_test.dart"),
                {"type": "allSuites", "count": 1},
                _start(1, "keeps quiet", 0, 4, 0),
                {
                    "type": "print",
                    "testID": 1,
                    "messageType": "print",
                    "message": "[Tool] noisy passing chatter",
                },
                _done(1, "success", 120),
                {"type": "done", "success": True},
            )
        )
        self.assertEqual(status, 0)
        self.assertEqual(output.strip(), "PASS 1 tests in 1 suites")
        self.assertNotIn("noisy passing chatter", output)

    def test_failure_keeps_error_own_output_and_project_frames(self) -> None:
        status, output = self._run(
            _events(
                _suite(0, "/repo/test/a_test.dart"),
                {"type": "allSuites", "count": 1},
                _start(1, "passes", 0, 4, 0),
                {"type": "print", "testID": 1, "message": "passing chatter"},
                _done(1, "success", 10),
                _start(2, "fails", 0, 11, 10),
                {"type": "print", "testID": 2, "message": "failing context"},
                {
                    "type": "error",
                    "testID": 2,
                    "error": "Expected: <5>\n  Actual: <4>",
                    "stackTrace": (
                        "package:test_api/src/expect.dart 1:1  expect\n"
                        "/repo/test/a_test.dart 12:5             main.<fn>\n"
                    ),
                    "isFailure": True,
                },
                _done(2, "failure", 20),
                {"type": "done", "success": False},
            )
        )
        self.assertEqual(status, 1)
        self.assertIn("FAIL 1 of 2 tests", output)
        self.assertIn("test/a_test.dart:11", output)
        self.assertIn("Actual: <4>", output)
        self.assertIn("failing context", output)
        self.assertNotIn("passing chatter", output)
        self.assertNotIn("package:test_api", output)

    def test_failure_list_is_capped(self) -> None:
        events = [_suite(0, "/repo/test/a_test.dart"), {"type": "allSuites", "count": 1}]
        for index in range(1, 6):
            events.append(_start(index, f"fails {index}", 0, index, index))
            events.append(
                {
                    "type": "error",
                    "testID": index,
                    "error": f"boom {index}",
                    "stackTrace": "/repo/test/a_test.dart 1:1  main.<fn>\n",
                    "isFailure": True,
                }
            )
            events.append(_done(index, "failure", index + 1))
        events.append({"type": "done", "success": False})

        status, output = self._run(events, "--max-failures", "2")
        self.assertEqual(status, 1)
        self.assertIn("boom 1", output)
        self.assertNotIn("boom 3", output)
        self.assertIn("3 more failing test(s)", output)

    def test_interrupted_run_is_not_reported_as_a_failure(self) -> None:
        status, output = self._run(
            _events(
                _suite(0, "/repo/test/a_test.dart"),
                {"type": "allSuites", "count": 1},
                _start(1, "finished", 0, 4, 0),
                _done(1, "success", 10),
                _start(2, "still running", 0, 11, 10),
                # No testDone for 2 and no `done` event: the run was killed.
            )
        )
        self.assertEqual(status, 1)
        self.assertIn("INCOMPLETE", output)
        self.assertIn("1 test(s) never finished", output)
        self.assertIn("in flight: test/a_test.dart: still running", output)
        self.assertNotIn("FAIL 0", output)

    def test_suite_load_error_is_reported_without_absolute_paths(self) -> None:
        status, output = self._run(
            _events(
                _suite(0, "/repo/test/a_test.dart"),
                {"type": "allSuites", "count": 1},
                {
                    "type": "error",
                    "testID": 99,
                    "error": 'Failed to load "/repo/test/a_test.dart": Compilation failed',
                    "stackTrace": "",
                },
                {"type": "done", "success": False},
            )
        )
        self.assertEqual(status, 1)
        self.assertIn("suite(s) failed to load", output)
        self.assertIn('Failed to load "test/a_test.dart"', output)
        self.assertNotIn("/repo/test", output)


if __name__ == "__main__":
    unittest.main()
