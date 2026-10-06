#!/usr/bin/env python3
"""Regression tests for ``tool/triage_session_logs.py``.

The case that motivated these: `execution_shadow` and `goal_completion_shadow`
markers were scored as aborted requests because the tool skipped markers by an
operation allowlist that predated them, inflating the reported transport-error
count 9x and reordering the ranking the triage exists to produce.
"""

import importlib.util
import io
import json
import pathlib
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "triage_session_logs",
    ROOT / "tool" / "triage_session_logs.py",
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Could not load triage tool")
triage = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(triage)


def _completion(*, response=None, error=None, title="t", tool_results=None):
    entry = {
        "operation": "createChatCompletion",
        "context": {"sessionTitle": title},
        "request": {"messages": [{"role": "user", "content": "hi"}]},
    }
    if tool_results is not None:
        entry["request"]["toolResults"] = tool_results
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
    def test_pro_reasoning_inference_operations_ground_a_session(self):
        entries = []
        for operation in (
            "pro_reasoning_frame",
            "pro_reasoning_investigate",
            "pro_reasoning_candidate",
            "pro_reasoning_critique",
            "pro_reasoning_synthesis",
        ):
            entry = _completion(
                response={"finishReason": "stop", "content": "ok"}
            )
            entry["operation"] = operation
            entries.append(entry)

        row = _analyze(entries)

        self.assertEqual(row["completions"], 5)
        self.assertEqual(row["transport"], 0)

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
                _marker(
                    "goal_completion_shadow",
                    {
                        "goalCompletionShadow": {
                            "agreement": "agree",
                            "lexicalCompleted": False,
                        }
                    },
                ),
            ]
        )

        self.assertEqual(row["completions"], 0)
        self.assertEqual(row["transport"], 0)
        self.assertEqual(row["score"], 0)
        self.assertEqual(row["goal_completion_shadow_agreement"], {"agree": 1})

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
                    "goal_completion_shadow",
                    {
                        "goalCompletionShadow": {
                            "agreement": "agree",
                            "lexicalCompleted": False,
                        }
                    },
                ),
                _marker(
                    "goal_completion_shadow",
                    {
                        "goalCompletionShadow": {
                            "agreement": "disagree",
                            "label": "goal_completion_tool_accepted_lexical_missed",
                            "toolOutcome": "completionRecorded",
                            "lexicalCompleted": False,
                        }
                    },
                ),
                # Pre-denominator records had a label but no agreement field.
                _marker(
                    "goal_completion_shadow",
                    {
                        "goalCompletionShadow": {
                            "label": "goal_completion_lexical_only",
                            "lexicalCompleted": True,
                        }
                    },
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
        self.assertEqual(
            row["goal_completion_shadow_agreement"],
            {"agree": 1, "disagree": 2},
        )
        self.assertEqual(
            row["goal_completion_shadow_disagreement"],
            {
                "goal_completion_tool_accepted_lexical_missed": 1,
                "goal_completion_lexical_only": 1,
            },
        )
        self.assertEqual(row["tool_outcome_shadow"], {"agree": 1})
        self.assertEqual(row["tool_outcome_verdict_source"], {"typed": 1})


class TriageGoalCompletionOutputTest(unittest.TestCase):
    def test_prints_goal_completion_denominator_and_disagreements(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "coding" / "session.jsonl"
            path.parent.mkdir()
            entries = [
                _completion(response={"finishReason": "stop", "content": "ok"}),
                _marker(
                    "goal_completion_shadow",
                    {
                        "goalCompletionShadow": {
                            "agreement": "agree",
                            "lexicalCompleted": False,
                        }
                    },
                ),
                _marker(
                    "goal_completion_shadow",
                    {
                        "goalCompletionShadow": {
                            "agreement": "disagree",
                            "label": "goal_completion_tool_accepted_lexical_missed",
                            "lexicalCompleted": False,
                        }
                    },
                ),
            ]
            path.write_text("".join(json.dumps(entry) + "\n" for entry in entries))
            output = io.StringIO()
            with mock.patch(
                "sys.argv",
                ["triage_session_logs.py", "--dir", directory, "--top", "5"],
            ), redirect_stdout(output):
                status = triage.main()

        self.assertEqual(status, 0)
        rendered = output.getvalue()
        self.assertIn(
            "Goal completion shadow agreement (LL35, 2 comparisons)", rendered
        )
        self.assertIn(
            "Goal completion shadow disagreements (LL35, 1 disagreement)",
            rendered,
        )
        self.assertIn("goal_completion_tool_accepted_lexical_missed", rendered)


class TriageWorkflowFailureEvidenceTest(unittest.TestCase):
    def test_deduplicates_resent_results_and_classifies_evidence_sources(self):
        results = [
            {
                "id": "typed",
                "name": "local_execute_command",
                "result": {"exit_code": 0, "stdout": "legacy contradiction"},
                "outcome": {"exit_code": 2},
            },
            {
                "id": "parsed",
                "name": "local_execute_command",
                "result": {"exit_code": 3},
                "outcome": None,
            },
            {
                "id": "structured",
                "name": "edit_file",
                "result": {"success": False, "error": "edit failed"},
                "outcome": None,
            },
            {
                "id": "output",
                "name": "local_execute_command",
                "result": {"exit_code": 0, "stdout": "No data found."},
                "outcome": {"exit_code": 0},
            },
            {
                "id": "lexical",
                "name": "third_party_tool",
                "result": "FAILED TO reach the remote service",
                "outcome": None,
            },
            {
                "id": "success",
                "name": "read_file",
                "result": {"content": "ok"},
                "outcome": None,
            },
        ]
        row = _analyze(
            [
                _completion(
                    response={"finishReason": "stop", "content": "ok"},
                    tool_results=results,
                ),
                _completion(
                    response={"finishReason": "stop", "content": "ok"},
                    tool_results=results,
                ),
            ]
        )

        self.assertEqual(
            row["workflow_failure_evidence"],
            {
                "typed_exit": 1,
                "parsed_exit": 1,
                "structured_payload": 1,
                "zero_exit_output_issue": 1,
                "lexical_only": 1,
                "no_failure": 1,
            },
        )

    def test_typed_success_overrides_conflicting_parsed_exit(self):
        row = _analyze(
            [
                _completion(
                    response={"finishReason": "stop", "content": "ok"},
                    tool_results=[
                        {
                            "id": "result",
                            "name": "local_execute_command",
                            "result": {"exit_code": 9, "stdout": "all good"},
                            "outcome": {"exit_code": 0},
                        }
                    ],
                )
            ]
        )

        self.assertEqual(row["workflow_failure_evidence"], {"no_failure": 1})

    def test_prints_deduplicated_workflow_failure_distribution(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "coding" / "session.jsonl"
            path.parent.mkdir()
            entries = [
                _completion(
                    response={"finishReason": "stop", "content": "ok"},
                    tool_results=[
                        {
                            "id": "legacy",
                            "name": "third_party_tool",
                            "result": "Error: unavailable",
                            "outcome": None,
                        }
                    ],
                )
            ]
            path.write_text("".join(json.dumps(entry) + "\n" for entry in entries))
            output = io.StringIO()
            with mock.patch(
                "sys.argv",
                ["triage_session_logs.py", "--dir", directory, "--top", "5"],
            ), redirect_stdout(output):
                status = triage.main()

        self.assertEqual(status, 0)
        rendered = output.getvalue()
        self.assertIn(
            "Workflow tool-result failure evidence "
            "(LL36, 1 deduplicated results)",
            rendered,
        )
        self.assertIn("lexical_only", rendered)


def _search_call(query):
    return {"toolCalls": [{"name": "search_files", "arguments": {"query": query}}]}


class SearchChurnTest(unittest.TestCase):
    """Distinct phrasings hunting one needle — invisible to tool_loop/reread.

    Modelled on session c79826af, where `_formatDuration` was searched five
    ways over ten iterations while the answer already sat in the tool results.
    """

    def test_phrasings_of_one_symbol_collapse_onto_one_needle(self):
        row = _analyze([
            _completion(response=_search_call("_formatDuration")),
            _completion(response=_search_call("_formatDuration(")),
            _completion(response=_search_call("formatDuration")),
            _completion(response=_search_call("static String _formatDuration")),
        ])
        self.assertEqual(row["search_churn_needle"], "formatduration")
        self.assertEqual(row["search_churn_max"], 4)
        self.assertEqual(row["search_churn"], 3)

    def test_repeated_identical_query_is_not_churn(self):
        """Byte-identical repeats are tool_loop/reread territory, not churn.

        Churn counts *rephrasings*; counting identical repeats here would
        double-score what the existing signals already catch.
        """
        row = _analyze([
            _completion(response=_search_call("widget")),
            _completion(response=_search_call("widget")),
            _completion(response=_search_call("widget")),
        ])
        self.assertEqual(row["search_churn"], 0)

    def test_distinct_needles_do_not_accumulate_churn(self):
        row = _analyze([
            _completion(response=_search_call("elapsedMilliseconds")),
            _completion(response=_search_call("pointerLock")),
            _completion(response=_search_call("sessionTitle")),
        ])
        self.assertEqual(row["search_churn"], 0)

    def test_one_rephrase_is_free_and_does_not_score(self):
        row = _analyze([
            _completion(response=_search_call("version")),
            _completion(response=_search_call("version:")),
        ])
        self.assertEqual(row["search_churn"], 1)
        self.assertEqual(row["score"], 0)

    def test_churn_beyond_the_free_allowance_scores(self):
        """Churn contributes to the score independently of tool_loop.

        The searches are interleaved with a read so the tool-name signature is
        never consecutive — otherwise tool_loop also fires and the assertion
        would be measuring both weights at once.
        """
        read = {"toolCalls": [{"name": "read_file", "arguments": {"path": "a"}}]}
        row = _analyze([
            _completion(response=_search_call("_formatDuration")),
            _completion(response=read),
            _completion(response=_search_call("_formatDuration(")),
            _completion(response=read),
            _completion(response=_search_call("formatDuration")),
        ])
        self.assertEqual(row["search_churn"], 2)
        self.assertEqual(row["max_tool_run"], 0)
        self.assertEqual(
            row["score"],
            round(
                (row["search_churn"] - triage.SEARCH_CHURN_FREE)
                * triage.WEIGHT_SEARCH_CHURN,
                2,
            ),
        )

    def test_churn_is_content_level_where_tool_loop_is_name_level(self):
        """Four consecutive searches score the same on tool_loop either way.

        Only churn separates four rephrasings of one question from four
        searches that each asked something different — tool_loop sees the
        identical `('search_files',)` signature in both cases.
        """
        hunting = _analyze([
            _completion(response=_search_call("_formatDuration")),
            _completion(response=_search_call("_formatDuration(")),
            _completion(response=_search_call("formatDuration")),
            _completion(response=_search_call("static String _formatDuration")),
        ])
        exploring = _analyze([
            _completion(response=_search_call("elapsedMilliseconds")),
            _completion(response=_search_call("pointerLock")),
            _completion(response=_search_call("sessionTitle")),
            _completion(response=_search_call("buildContext")),
        ])
        self.assertEqual(hunting["max_tool_run"], exploring["max_tool_run"])
        self.assertEqual(hunting["search_churn"], 3)
        self.assertEqual(exploring["search_churn"], 0)
        self.assertGreater(hunting["score"], exploring["score"])

    def test_bare_short_numeric_query_carries_no_needle(self):
        row = _analyze([
            _completion(response=_search_call("02")),
            _completion(response=_search_call("13")),
        ])
        self.assertEqual(row["search_churn"], 0)
        self.assertEqual(row["search_churn_needle"], "")


if __name__ == "__main__":
    unittest.main()
