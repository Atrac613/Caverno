#!/usr/bin/env python3
"""Regression tests for tool/check_fix_firings.py (run with system python3):

    python3 test/python/check_fix_firings_test.py

Flutter is not required. Covers the part that is easy to get wrong and
expensive when wrong: keeping the real-session corpus apart from the live
canary corpus. Merging them lets a fixture pass for usage; omitting the
canaries reports a path as unobserved after a canary has just proved it, which
is how ANA2's closed evidence gap kept reading as open.

Build provenance is taken from real commits in this repository so the ancestry
qualification runs for real rather than being stubbed out.
"""
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

REPO_ROOT = os.path.abspath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
)
TOOL_PATH = os.path.join(REPO_ROOT, "tool", "check_fix_firings.py")


def _load_tool():
    spec = importlib.util.spec_from_file_location("check_fix_firings", TOOL_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _head_commit():
    return subprocess.run(
        ["git", "-C", REPO_ROOT, "rev-parse", "--short", "HEAD"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


class CheckFixFiringsCorpusTest(unittest.TestCase):
    """The three verdicts, each driven by which corpus carries the hit."""

    @classmethod
    def setUpClass(cls):
        cls.tool = _load_tool()
        cls.head = _head_commit()
        # Any registered signature will do; this test is about corpus
        # separation, not about a particular change.
        cls.signature_name = "anabasis_delegation_admitted"
        cls.marker = "Saved task contract (authoritative scope)"

    def _write_log(self, directory, name, text):
        os.makedirs(directory, exist_ok=True)
        record = {
            "build": {"commit": self.head, "dirty": False},
            # Grounded: a log with no real exchange is skipped by design.
            "request": {
                "usageRole": "anabasisParent",
                "messages": [{"role": "user", "content": text}],
            },
            "response": {"content": "", "finishReason": "tool_calls"},
        }
        path = os.path.join(directory, name)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
        return path

    def _run(self, *argv):
        out = io.StringIO()
        saved = sys.argv
        sys.argv = ["check_fix_firings.py", *argv]
        try:
            with redirect_stdout(out):
                status = self.tool.main()
        finally:
            sys.argv = saved
        self.assertEqual(status, 0, out.getvalue())
        return out.getvalue()

    def _verdict_line(self, output):
        for line in output.splitlines():
            if line.endswith(f"] {self.signature_name}  (8102fab4)"):
                return line
        self.fail(f"signature not reported:\n{output}")

    def test_a_canary_only_hit_is_not_reported_as_used(self):
        with tempfile.TemporaryDirectory() as root:
            wild = os.path.join(root, "wild")
            canary = os.path.join(root, "canary", "run_1", "session_logs")
            self._write_log(wild, "plain.jsonl", "nothing interesting here")
            self._write_log(canary, "hit.jsonl", f"prompt\n\n{self.marker}\n")
            output = self._run(
                "--dir", wild, "--canary-dir", canary, "--repo", REPO_ROOT
            )
        # --dir is an explicit request to scan one corpus, so the canary root
        # must be ignored and the signature must stay unobserved.
        self.assertIn("scanned 1 logs (1 wild)", output)
        self.assertIn("not yet observed", self._verdict_line(output))

    def test_canary_corpus_is_scanned_and_labelled_when_dir_is_default(self):
        with tempfile.TemporaryDirectory() as root:
            wild = os.path.join(root, "wild")
            canary = os.path.join(root, "canary", "run_1", "session_logs")
            self._write_log(wild, "plain.jsonl", "nothing interesting here")
            self._write_log(canary, "hit.jsonl", f"prompt\n\n{self.marker}\n")
            os.environ["CAVERNO_SESSION_LOG_DIR"] = wild
            try:
                output = self._run("--canary-dir", canary, "--repo", REPO_ROOT)
            finally:
                os.environ.pop("CAVERNO_SESSION_LOG_DIR", None)
        self.assertIn("FIRED (canary only)", self._verdict_line(output))
        self.assertIn("proved reachable by a canary only", output)
        # A canary must never raise the in-the-wild count.
        self.assertNotIn("9/15 observed in the wild", output)

    def test_a_wild_hit_outranks_a_canary_hit(self):
        with tempfile.TemporaryDirectory() as root:
            wild = os.path.join(root, "wild")
            canary = os.path.join(root, "canary", "run_1", "session_logs")
            self._write_log(wild, "hit.jsonl", f"prompt\n\n{self.marker}\n")
            self._write_log(canary, "hit.jsonl", f"prompt\n\n{self.marker}\n")
            os.environ["CAVERNO_SESSION_LOG_DIR"] = wild
            try:
                output = self._run("--canary-dir", canary, "--repo", REPO_ROOT)
            finally:
                os.environ.pop("CAVERNO_SESSION_LOG_DIR", None)
        line = self._verdict_line(output)
        self.assertTrue(line.startswith("[FIRED] "), line)
        self.assertNotIn("(canary only)", line)
        self.assertIn("wild)", output)
        self.assertIn("canary)", output)

    def test_no_canaries_scans_real_sessions_only(self):
        with tempfile.TemporaryDirectory() as root:
            wild = os.path.join(root, "wild")
            canary = os.path.join(root, "canary", "run_1", "session_logs")
            self._write_log(wild, "plain.jsonl", "nothing interesting here")
            self._write_log(canary, "hit.jsonl", f"prompt\n\n{self.marker}\n")
            os.environ["CAVERNO_SESSION_LOG_DIR"] = wild
            try:
                output = self._run(
                    "--no-canaries", "--canary-dir", canary, "--repo", REPO_ROOT
                )
            finally:
                os.environ.pop("CAVERNO_SESSION_LOG_DIR", None)
        self.assertIn("scanned 1 logs (1 wild)", output)
        self.assertIn("not yet observed", self._verdict_line(output))


if __name__ == "__main__":
    unittest.main(verbosity=2)
