#!/usr/bin/env python3
"""Regression tests for tool/run_farm_matrix.py (run with system python3):

    python3 test/python/run_farm_matrix_test.py

Covers the refusal that keeps a matrix run from sending fixtures to an
external model or running under an approval mode the operator did not choose,
and the event summary that names what stopped each run.
"""
import importlib.util
import json
import os
import unittest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
_spec = importlib.util.spec_from_file_location(
    "run_farm_matrix", os.path.join(REPO_ROOT, "tool", "run_farm_matrix.py")
)
matrix = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(matrix)


def _preferences(**settings):
    base = {
        "baseUrl": "http://192.168.100.241:1234/v1",
        "codingApprovalMode": "fullAccess",
        "llmEndpoints": [
            {"id": "lan", "baseUrl": "http://192.168.100.241:1234/v1"},
            {"id": "cloud", "baseUrl": "https://api.openai.com/v1"},
        ],
        "codeReviewEndpointId": "lan",
    }
    base.update(settings)
    return {matrix.SETTINGS_KEY: json.dumps(base)}


def _problems(preferences, **kwargs):
    options = {
        "base_url_override": None,
        "allow_external": False,
    }
    options.update(kwargs)
    return matrix.preference_problems(preferences, **options)


class PrivateUrlTest(unittest.TestCase):
    def test_classifies_hosts(self):
        for url in (
            "http://localhost:1234/v1",
            "http://127.0.0.1:8000",
            "http://192.168.100.241:1234/v1",
            "http://10.0.0.5/v1",
        ):
            self.assertTrue(matrix.is_private_url(url), url)
        for url in ("https://api.openai.com/v1", "https://8.8.8.8", "", "nonsense"):
            self.assertFalse(matrix.is_private_url(url), url)


class PreferenceProblemsTest(unittest.TestCase):
    def test_accepts_an_all_lan_copy(self):
        self.assertEqual(_problems(_preferences()), [])

    def test_refuses_a_role_routed_to_an_external_model(self):
        # The live runs' review route pointed at api.openai.com until the
        # operator switched it; a matrix run would have sent every fixture.
        problems = _problems(_preferences(codeReviewEndpointId="cloud"))
        self.assertEqual(len(problems), 1)
        self.assertIn("codeReview", problems[0])
        self.assertEqual(
            _problems(_preferences(codeReviewEndpointId="cloud"), allow_external=True),
            [],
        )

    def test_a_base_url_flag_replaces_the_stored_primary(self):
        preferences = _preferences(baseUrl="https://api.x.ai/v1")
        self.assertTrue(_problems(preferences))
        self.assertEqual(
            _problems(preferences, base_url_override="http://localhost:1234/v1"), []
        )

    def test_refuses_unreadable_settings(self):
        self.assertTrue(_problems({}))


class SummarizeSessionLogsTest(unittest.TestCase):
    def test_reads_decisions_and_turns(self):
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as root:
            log = Path(root, "coding", "task.jsonl")
            log.parent.mkdir()
            log.write_text("\n".join([
                json.dumps({"operation": "project_task_decision",
                            "projectTaskDecision": {"phase": "review",
                                                    "decision": "clean"}}),
                json.dumps({"operation": "turn_exit"}),
                "not json",
            ]))
            summary = matrix.summarize_session_logs(Path(root))
        self.assertEqual(summary, {"decisions": ["review:clean"], "turns": 1})


class ConsoleFilterTest(unittest.TestCase):
    def test_shows_prompts_and_hides_diagnostics(self):
        # A Debug build's log buried the prompt until the fixture timed out.
        shown = []
        console = matrix.ConsoleFilter(shown.append)
        console.feed("[LLM] model: qwen\n[McpToolService]   - kb_search: ...\n")
        console.feed("[approval] command_execution (high): run tests\n")
        console.feed('Command: python3 -c "\nprint(1)\n"\nTarget: /tmp/p\n')
        console.feed("Approve once? [y/N] ")
        self.assertEqual(shown[-1], "Approve once? [y/N] ")
        console.feed("[LLM] === Response ===\n[farm] review progress\n")
        self.assertEqual("".join(shown), (
            "[approval] command_execution (high): run tests\n"
            'Command: python3 -c "\nprint(1)\n"\n'
            "Target: /tmp/p\n"
            "Approve once? [y/N] "
            "[farm] review progress\n"
        ))


class SummarizeEventsTest(unittest.TestCase):
    def test_names_the_approval_that_stopped_the_run(self):
        lines = [
            "flutter: The Dart VM service is listening on http://127.0.0.1:1/",
            json.dumps({"type": "project_task_decision", "turnId": "farm",
                        "payload": {"phase": "implement", "decision": "progress"}}),
            json.dumps({"type": "tool_lifecycle", "turnId": "gen-2",
                        "payload": {"toolName": "read_file", "state": "completed"}}),
            json.dumps({"type": "approval_required", "turnId": "gen-2",
                        "payload": {"capability": "command_execution",
                                    "summary": "Run tests", "command": "pytest"}}),
            json.dumps({"type": "run_failed", "turnId": "gen-2",
                        "payload": {"code": "approval_unavailable"}}),
            json.dumps({"type": "run_failed", "turnId": "farm",
                        "payload": {"code": "approval_unavailable", "exitCode": 77}}),
        ]
        summary = matrix.summarize_events(lines)
        self.assertEqual(summary["decisions"], ["implement:progress"])
        self.assertEqual(summary["lastApproval"]["command"], "pytest")
        self.assertEqual(summary["completedTools"], {"read_file": 1})
        self.assertEqual(summary["terminal"]["exitCode"], 77)
        self.assertIn("command_execution", matrix.render_markdown(
            [{"fixture": "f", "exitCode": 77, "elapsedSeconds": 1, **summary}]
        ))


if __name__ == "__main__":
    unittest.main()
