#!/usr/bin/env python3
"""Regression tests for ``tool/triage_session_logs.py``.

The case that motivated these: `execution_shadow` and `goal_completion_shadow`
markers were scored as aborted requests because the tool skipped markers by an
operation allowlist that predated them, inflating the reported transport-error
count 9x and reordering the ranking the triage exists to produce.
"""

import importlib.util
import json
import pathlib
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "triage_session_logs",
    ROOT / "tool" / "triage_session_logs.py",
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Could not load triage tool")
triage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(triage)


def _completion(*, response=None, error=None, title="t"):
    entry = {
        "operation": "createChatCompletion",
        "context": {"sessionTitle": title},
        "request": {"messages": [{"role": "user", "content": "hi"}]},
    }
    if response is not None:
        entry["response"] = response
    if error is not None:
        entry["error"] = error
    return entry


def _marker(operation, payload=None, title="t"):
    """A marker entry, shaped exactly as LlmSessionLogStore writes one.

    The defining property is the absence of both `request` and `response`.
    """
    entry = {
        "operation": operation,
        "context": {"sessionTitle": title},
    }
    if payload:
        entry.update(payload)
    return entry


def _analyze(entries):
    with tempfile.TemporaryDirectory() as directory:
        path = pathlib.Path(directory) / "session.jsonl"
        path.write_text("".join(json.dumps(e) + "\n" for e in entries))
        return triage.analyze(str(path))


class TriageDiscoveryTest(unittest.TestCase):
    def test_finds_logs_at_canary_report_depth(self):
        """Live canaries write to
        `<run>/session_logs/<surface>/*.jsonl` — three levels below the
        directory a triage run would be pointed at."""
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            deep = root / "coding_todo_app_mvp_live_canary_1" / "session_logs" / "coding"
            deep.mkdir(parents=True)
            (deep / "a.jsonl").write_text("{}\n")
            (root / "flat.jsonl").write_text("{}\n")
            (root / "surface" / "b").mkdir(parents=True)
            (root / "surface" / "b" / "c.jsonl").write_text("{}\n")

            found = {pathlib.Path(p).name for p in triage._iter_log_files(str(root))}

        self.assertEqual(found, {"a.jsonl", "flat.jsonl", "c.jsonl"})

    def test_yields_each_file_once(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / "chat").mkdir()
            (root / "chat" / "a.jsonl").write_text("{}\n")

            found = list(triage._iter_log_files(str(root)))

        self.assertEqual(len(found), 1)


class TriageMarkerScoringTest(unittest.TestCase):
    def test_shadow_markers_are_not_transport_errors(self):
        row = _analyze(
            [
                _completion(response={"finishReason": "stop", "content": "ok"}),
                _marker("execution_shadow", {"executionShadow": {"action": "a"}}),
                _marker("execution_shadow", {"executionShadow": {"action": "b"}}),
                _marker(
                    "goal_completion_shadow",
                    {"goalCompletionShadow": {"label": "x", "lexicalCompleted": True}},
                ),
                _marker(
                    "tool_outcome_shadow",
                    {"toolOutcomeShadow": {"agreement": "parsedMissing"}},
                ),
            ]
        )

        self.assertEqual(row["transport"], 0)
        self.assertEqual(row["score"], 0)
        self.assertEqual(row["completions"], 1)

    def test_unknown_future_marker_is_not_scored(self):
        """The predicate is structural, so a marker this tool has never heard
        of is still excluded — the failure mode being fixed."""
        row = _analyze(
            [
                _completion(response={"finishReason": "stop", "content": "ok"}),
                _marker("some_marker_invented_later", {"payload": {"a": 1}}),
            ]
        )

        self.assertEqual(row["transport"], 0)

    def test_real_transport_errors_still_count(self):
        row = _analyze(
            [
                _completion(
                    error={"type": "RequestTimeoutException", "message": "timed out"}
                ),
                # An aborted stream: request logged, response never terminated.
                _completion(response={"content": "", "toolCalls": []}),
                _completion(response={"finishReason": "stop", "content": "ok"}),
            ]
        )

        self.assertEqual(row["transport"], 2)
        self.assertEqual(row["score"], 2 * triage.WEIGHT_TRANSPORT)

    def test_marker_only_log_stays_ungrounded_and_unscored(self):
        """Test output writes markers without inference; it must score zero so
        the grounding filter (2026-08-05) keeps rejecting it."""
        row = _analyze(
            [
                _marker("turn_exit", {"turnExit": {"reason": "text_response"}}),
                _marker("execution_shadow", {"executionShadow": {"action": "a"}}),
            ]
        )

        self.assertEqual(row["completions"], 0)
        self.assertEqual(row["transport"], 0)
        self.assertEqual(row["score"], 0)

    def test_marker_only_session_keeps_its_title(self):
        row = _analyze(
            [
                _marker("execution_shadow", {"executionShadow": {}}, title="shadowed"),
                _completion(response={"finishReason": "stop", "content": "ok"}, title=""),
            ]
        )

        self.assertEqual(row["title"], "shadowed")

    def test_markers_still_feed_their_own_distributions(self):
        row = _analyze(
            [
                _completion(response={"finishReason": "stop", "content": "ok"}),
                _marker(
                    "turn_exit",
                    {
                        "turnExit": {
                            "reason": "empty_response",
                            "noVisibleAnswer": True,
                            "transforms": ["unwritten_file_claim_notice"],
                        }
                    },
                ),
                _marker(
                    "goal_auto_continue",
                    {"goalAutoContinue": {"decision": "continue", "reason": "gaps"}},
                ),
                _marker(
                    "tool_outcome_shadow",
                    {
                        "toolOutcomeShadow": {
                            "toolName": "local_execute_command",
                            "agreement": "agree",
                            "verdictSource": "typed",
                            "structuredExitCode": 1,
                            "parsedExitCode": 1,
                        }
                    },
                ),
            ]
        )

        self.assertEqual(row["exit_reasons"], {"empty_response": 1})
        self.assertEqual(row["no_answer"], 1)
        self.assertEqual(row["transforms"], {"unwritten_file_claim_notice": 1})
        self.assertEqual(row["goal_auto_continue"], {"continue: gaps": 1})
        self.assertEqual(row["tool_outcome_shadow"], {"agree": 1})
        self.assertEqual(row["tool_outcome_verdict_source"], {"typed": 1})


if __name__ == "__main__":
    unittest.main()
