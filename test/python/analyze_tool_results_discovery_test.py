#!/usr/bin/env python3
"""Regression test for the shared log-discovery helper.

Four `tool/analyze_*.py` scripts had their own copy of a one/two-level glob, so
`CAVERNO_SESSION_LOG_DIR=build/integration_test_reports` found the reporter
`flutter_test.jsonl` files and zero session logs — the canary tree nests them at
`<run>/session_logs/<surface>/*.jsonl`.
"""

import importlib.util
import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "analyze_tool_results",
    ROOT / "tool" / "analyze_tool_results.py",
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Could not load analyze_tool_results")
air = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(air)


class LogDiscoveryTest(unittest.TestCase):
    def test_finds_canary_depth_and_corpus_depth_alike(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            canary = root / "coding_todo_app_mvp_live_canary_1" / "session_logs" / "coding"
            canary.mkdir(parents=True)
            (canary / "deep.jsonl").write_text("{}\n")
            (root / "chat").mkdir()
            (root / "chat" / "corpus.jsonl").write_text("{}\n")
            (root / "flat.jsonl").write_text("{}\n")
            (root / "ignored.txt").write_text("x")

            found = {p.name for p in air.iter_log_paths(root)}

        self.assertEqual(found, {"deep.jsonl", "corpus.jsonl", "flat.jsonl"})

    def test_yields_sorted_and_deduplicated(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "b").mkdir()
            (root / "b" / "z.jsonl").write_text("{}\n")
            (root / "a.jsonl").write_text("{}\n")

            found = air.iter_log_paths(root)

        self.assertEqual([p.name for p in found], ["a.jsonl", "z.jsonl"])
        self.assertEqual(len(found), len(set(found)))


if __name__ == "__main__":
    unittest.main()
