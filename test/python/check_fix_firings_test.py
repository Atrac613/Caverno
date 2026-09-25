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


class CheckFixFiringsTransformChannelTest(unittest.TestCase):
    """A transform row reads `turnExit.transforms`, not the log's prose.

    That distinction is the whole reason the key exists. LL33 records a
    transform id precisely so a guard firing stops being inferred from the
    notice it leaked into the answer, and a row that fell back to a substring
    search would re-acquire exactly the contamination LL33 removed -- a log
    quoting the id, including one produced by reading this repository, would
    read as a firing.
    """

    @classmethod
    def setUpClass(cls):
        cls.tool = _load_tool()
        cls.head = _head_commit()
        cls.signature_name = "pending_action_length_recovery"
        cls.signature = cls.tool.SIGNATURES[cls.signature_name]
        cls.transform = cls.signature["transform"]

    def _write_log(self, directory, name, *, transforms=None, prose=""):
        os.makedirs(directory, exist_ok=True)
        grounded = {
            "build": {"commit": self.head, "dirty": False},
            "request": {"messages": [{"role": "user", "content": prose}]},
            "response": {"content": prose, "finishReason": "length"},
        }
        lines = [grounded]
        if transforms is not None:
            lines.append(
                {
                    "build": {"commit": self.head, "dirty": False},
                    "operation": "turn_exit",
                    "turnExit": {
                        "reason": "pending_batch_executed",
                        "noVisibleAnswer": False,
                        "transforms": transforms,
                    },
                }
            )
        path = os.path.join(directory, name)
        with open(path, "w", encoding="utf-8") as handle:
            for line in lines:
                handle.write(json.dumps(line, ensure_ascii=False) + "\n")
        return path

    def _verdict_line(self, output):
        suffix = f"] {self.signature_name}  ({self.signature['commit']})"
        for line in output.splitlines():
            if line.endswith(suffix):
                return line
        self.fail(f"signature not reported:\n{output}")

    def _run(self, wild):
        out = io.StringIO()
        saved = sys.argv
        sys.argv = ["check_fix_firings.py", "--dir", wild, "--repo", REPO_ROOT]
        try:
            with redirect_stdout(out):
                status = self.tool.main()
        finally:
            sys.argv = saved
        self.assertEqual(status, 0, out.getvalue())
        return out.getvalue()

    def test_a_recorded_transform_is_a_firing(self):
        with tempfile.TemporaryDirectory() as wild:
            self._write_log(
                wild,
                "hit.jsonl",
                transforms=[self.transform, "final_answer_concise_retry"],
            )
            output = self._run(wild)
        self.assertTrue(
            self._verdict_line(output).startswith("[FIRED] "),
            self._verdict_line(output),
        )

    def test_prose_quoting_the_id_is_not_a_firing(self):
        # The case that would be silently wrong under a substring match: this
        # very repository's sources, a commit body and this test file all spell
        # the id, and none of them is a turn that ran it.
        with tempfile.TemporaryDirectory() as wild:
            self._write_log(
                wild,
                "quote.jsonl",
                transforms=None,
                prose=f"the guard is named {self.transform} in chat_notifier",
            )
            output = self._run(wild)
        self.assertIn("not yet observed", self._verdict_line(output))

    def test_an_unrelated_transform_is_not_a_firing(self):
        with tempfile.TemporaryDirectory() as wild:
            self._write_log(
                wild, "other.jsonl", transforms=["unwritten_file_claim_notice"]
            )
            output = self._run(wild)
        self.assertIn("not yet observed", self._verdict_line(output))

    def test_every_row_carries_exactly_one_evidence_key(self):
        # A row with neither key, or both, goes dark and reads as "the code
        # never ran" -- the one failure this instrument cannot report on
        # itself. The module refuses to load in that state; assert the
        # invariant here too, so the reason is written down where it is read.
        for name, signature in self.tool.SIGNATURES.items():
            with self.subTest(signature=name):
                self.assertNotEqual(
                    "match" in signature,
                    "transform" in signature,
                    f"{name} must carry exactly one of match/transform",
                )



class InternalGrepSignatureTest(unittest.TestCase):
    """The internal_grep row fires on a decoded result object, never on text.

    The payload shape is what LocalShellTools._executeInternally encodes and
    the session log stores decoded under request.toolResults[].result.
    """

    @classmethod
    def setUpClass(cls):
        cls.match = staticmethod(_load_tool().SIGNATURES["internal_grep"]["match"])

    @staticmethod
    def _result(command):
        return {
            "command": command,
            "working_directory": "/repo",
            "exit_code": 0,
            "stdout": 'version: "1.3.44+58"\n',
            "stderr": "",
            "executed_internally": True,
        }

    def _blob(self, request):
        return json.dumps([{"request": request}], ensure_ascii=False)

    def test_a_structured_internal_grep_result_fires(self):
        for command in ["grep -E '^version:' pubspec.yaml",
                        'grep -n "^version:" pubspec.yaml']:
            with self.subTest(command=command):
                blob = self._blob(
                    {"toolResults": [{"result": self._result(command)}]}
                )
                self.assertTrue(self.match(blob))

    def test_the_same_result_quoted_as_text_does_not_fire(self):
        quoted = json.dumps(self._result("grep x a.txt"))
        blob = self._blob({"messages": [{"role": "tool", "content": quoted}]})
        self.assertFalse(self.match(blob))

    def test_another_internal_command_does_not_fire(self):
        blob = self._blob(
            {"toolResults": [{"result": self._result("rg x lib")}]}
        )
        self.assertFalse(self.match(blob))


class GitNativePipelineRefusalSignatureTest(unittest.TestCase):
    """The row fires on the decoded refusal payload, never on quoted text."""

    _ERROR = (
        "git_execute_command accepts one git subcommand per call and runs "
        'without a shell; operator "|" is unsupported. Use Git options first: '
        "`rev-list --count <range>` for commit counts."
    )

    @classmethod
    def setUpClass(cls):
        cls.match = staticmethod(
            _load_tool().SIGNATURES["git_native_pipeline_refusal"]["match"]
        )

    @staticmethod
    def _blob(request):
        return json.dumps([{"request": request}], ensure_ascii=False)

    def _result(self, error):
        return {
            "command": "git log --oneline | wc -l",
            "working_directory": "/repo",
            "executed": False,
            "code": "command_rejected_before_execution",
            "error": error,
        }

    def test_the_new_refusal_fires(self):
        blob = self._blob({"toolResults": [{"result": self._result(self._ERROR)}]})
        self.assertTrue(self.match(blob))

    def test_the_previous_refusal_does_not_fire(self):
        old = (
            "git_execute_command accepts one git subcommand per tool call and "
            "runs it without a shell"
        )
        blob = self._blob({"toolResults": [{"result": self._result(old)}]})
        self.assertFalse(self.match(blob))

    def test_the_same_result_quoted_as_text_does_not_fire(self):
        quoted = json.dumps(self._result(self._ERROR))
        blob = self._blob({"messages": [{"role": "tool", "content": quoted}]})
        self.assertFalse(self.match(blob))


class ToolArgumentTypeGuardSignatureTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.match = staticmethod(
            _load_tool().SIGNATURES["tool_argument_type_guard"]["match"]
        )

    @staticmethod
    def _blob(request):
        return json.dumps([{"request": request}], ensure_ascii=False)

    _RESULT = {"ok": False, "code": "invalid_tool_argument_type", "argument": "content"}

    def test_the_decoded_rejection_fires(self):
        blob = self._blob({"toolResults": [{"result": self._RESULT}]})
        self.assertTrue(self.match(blob))

    def test_the_rejection_quoted_as_text_does_not_fire(self):
        quoted = json.dumps(self._RESULT)
        blob = self._blob({"messages": [{"role": "tool", "content": quoted}]})
        self.assertFalse(self.match(blob))


class SearchFilesLineAnchorSignatureTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.match = staticmethod(
            _load_tool().SIGNATURES["search_files_line_anchor"]["match"]
        )

    @staticmethod
    def _blob(result):
        return json.dumps(
            [{"request": {"toolResults": [{"result": result}]}}],
            ensure_ascii=False,
        )

    @staticmethod
    def _result(query, matches):
        return {
            "path": "/repo",
            "query": query,
            "matches": matches,
            "match_count": len(matches),
        }

    def test_an_anchored_hit_fires(self):
        blob = self._blob(
            self._result("^version:", ["pubspec.yaml:19: version: 1.3.48+62"])
        )
        self.assertTrue(self.match(blob))

    def test_an_anchored_miss_does_not_fire(self):
        self.assertFalse(self.match(self._blob(self._result("^version:", []))))

    def test_an_unanchored_hit_does_not_fire(self):
        blob = self._blob(
            self._result("version:", ["pubspec.yaml:19: version: 1.3.48+62"])
        )
        self.assertFalse(self.match(blob))


if __name__ == "__main__":
    unittest.main(verbosity=2)
