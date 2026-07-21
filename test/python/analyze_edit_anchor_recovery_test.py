#!/usr/bin/env python3
"""Regression tests for ``tool/analyze_edit_anchor_recovery.py``."""

import importlib.util
import json
import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "analyze_edit_anchor_recovery",
    ROOT / "tool" / "analyze_edit_anchor_recovery.py",
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Could not load recovery analyzer")
analyzer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(analyzer)


def _section(tool, arguments, result):
    lines = [f"[Tool: {tool}]"]
    if arguments is not None:
        lines.append(f"Arguments: {json.dumps(arguments)}")
    lines.extend(["Result:", json.dumps(result)])
    return "\n".join(lines)


def _record(*messages):
    return {"request": {"messages": list(messages)}}


class EditAnchorRecoveryTest(unittest.TestCase):
    def test_tracks_next_attempt_reads_splits_and_streaks(self):
        failed_small = {
            "error": analyzer.ANCHOR_ERROR,
            "current_content": "actual\n",
        }
        failed_large = {"error": analyzer.ANCHOR_ERROR}
        messages = [
            {
                "id": "1",
                "content": _section(
                    "edit_file",
                    {"path": "lib/a.dart", "old_text": "guess", "new_text": "new"},
                    failed_small,
                ),
            },
            {
                "id": "2",
                "content": _section(
                    "read_file",
                    {"path": "/work/lib/a.dart"},
                    {"content": "actual\n"},
                ),
            },
            {
                "id": "3",
                "content": _section(
                    "edit_file",
                    {
                        "path": "/work/lib/a.dart",
                        "old_text": "wrong",
                        "new_text": "new",
                    },
                    failed_small,
                ),
            },
            {
                "id": "4",
                "content": _section(
                    "edit_file",
                    {
                        "path": "lib/a.dart",
                        "old_text": "actual",
                        "new_text": "new",
                    },
                    {"path": "lib/a.dart"},
                ),
            },
            {
                "id": "5",
                "content": _section(
                    "edit_file",
                    {"path": "lib/b.dart", "old_text": "guess", "new_text": "new"},
                    failed_large,
                ),
            },
            {
                "id": "6",
                "content": _section(
                    "write_file",
                    {"path": "lib/b.dart", "content": "new"},
                    {"path": "lib/b.dart"},
                ),
            },
            {
                "id": "7",
                "content": _section(
                    "edit_file",
                    {"path": "lib/c.dart", "old_text": "guess", "new_text": "new"},
                    failed_small,
                ),
            },
        ]

        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "session.jsonl"
            with path.open("w") as handle:
                handle.write(json.dumps(_record(messages[0])) + "\n")
                handle.write(json.dumps(_record(*messages)) + "\n")
            result = analyzer.collect([path])

        self.assertEqual(result["counters"]["message slots"], 8)
        self.assertEqual(result["counters"]["distinct messages"], 7)
        self.assertEqual(result["counters"]["anchor failures"], 4)
        self.assertEqual(result["outcomes"]["failed_again"], 1)
        self.assertEqual(result["outcomes"]["recovered_next"], 1)
        self.assertEqual(result["outcomes"]["switched_to_write"], 1)
        self.assertEqual(result["outcomes"]["abandoned"], 1)
        self.assertEqual(
            result["split_outcomes"][
                ("switched_to_write", "without current_content")
            ],
            1,
        )
        self.assertEqual(result["reads_by_outcome"][("failed_again", "read")], 1)
        self.assertEqual(
            result["split_reads"][("failed_again", "with current_content", "read")],
            1,
        )
        self.assertEqual(result["streaks"][2], 1)
        self.assertEqual(result["streaks"][1], 2)
        self.assertEqual(result["counters"]["verbatim-present canary"], 0)

    def test_counts_missing_arguments_instead_of_silently_skipping(self):
        content = _section("edit_file", None, {"error": analyzer.ANCHOR_ERROR})
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "session.jsonl"
            path.write_text(
                json.dumps(_record({"id": "1", "content": content})) + "\n"
            )
            result = analyzer.collect([path])

        self.assertEqual(result["counters"]["anchor failures"], 1)
        self.assertEqual(result["outcomes"]["unclassified path"], 1)
        self.assertEqual(result["counters"]["edit_file: missing Arguments line"], 1)
        self.assertEqual(result["counters"]["edit_file: missing path"], 1)


if __name__ == "__main__":
    unittest.main()
