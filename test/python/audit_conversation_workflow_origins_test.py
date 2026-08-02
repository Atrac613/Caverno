#!/usr/bin/env python3
"""Focused tests for ``tool/audit_conversation_workflow_origins.py``."""

import contextlib
import hashlib
import importlib.util
import io
import json
import pathlib
import sqlite3
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "audit_conversation_workflow_origins",
    ROOT / "tool" / "audit_conversation_workflow_origins.py",
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("Could not load workflow-origin audit")
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)


class ConversationWorkflowOriginAuditTest(unittest.TestCase):
    def _database(self, directory, payloads):
        path = pathlib.Path(directory) / "caverno.sqlite"
        connection = sqlite3.connect(path)
        connection.execute(
            "CREATE TABLE conversations (id TEXT PRIMARY KEY, payload TEXT NOT NULL)"
        )
        for index, payload in enumerate(payloads):
            encoded = payload if isinstance(payload, str) else json.dumps(payload)
            connection.execute(
                "INSERT INTO conversations(id, payload) VALUES (?, ?)",
                (f"conversation-{index}", encoded),
            )
        connection.commit()
        connection.close()
        return path

    def test_classifies_every_origin_and_keeps_database_bytes_unchanged(self):
        plan = "# Plan\n\n## Stage\nimplement"
        fresh_hash = audit.conversation_plan_hash(plan)
        workflow = {"goal": "Ship it"}
        payloads = [
            {},
            {
                "workflowStage": "implement",
                "workflowSpec": workflow,
                "planArtifact": {"approvedMarkdown": plan},
            },
            {
                "workflowStage": "implement",
                "workflowSpec": {
                    **workflow,
                    "sources": [{"kind": "approvedPlan"}],
                },
                "workflowSourceHash": fresh_hash,
                "workflowDerivedAt": "2026-08-02T00:00:00Z",
                "planArtifact": {"approvedMarkdown": plan},
            },
            {
                "workflowStage": "implement",
                "workflowSpec": workflow,
                "workflowSourceHash": "00000000",
                "workflowDerivedAt": "2026-08-02T00:00:00Z",
                "planArtifact": {"approvedMarkdown": plan},
            },
            {
                "workflowStage": "implement",
                "workflowSpec": workflow,
                "workflowSourceHash": fresh_hash,
                "workflowDerivedAt": "2026-08-02T00:00:00Z",
            },
            {
                "workflowStage": "implement",
                "workflowSpec": workflow,
                "workflowSourceHash": fresh_hash,
            },
            {
                "workflowStage": "implement",
                "workflowSpec": {
                    **workflow,
                    "sources": [{"kind": "approvedPlan"}],
                },
                "planArtifact": {"approvedMarkdown": plan},
            },
            "not-json",
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = self._database(directory, payloads)
            before = hashlib.sha256(path.read_bytes()).hexdigest()
            report = audit.audit_database(path)
            after = hashlib.sha256(path.read_bytes()).hexdigest()

        self.assertEqual(before, after)
        self.assertEqual(report["summary"]["databaseRowCount"], 8)
        self.assertEqual(report["summary"]["classifiedWorkflowCount"], 6)
        self.assertEqual(
            report["summary"]["originCounts"],
            {
                audit.NO_WORKFLOW: 1,
                audit.LEGACY_AUTHORED: 1,
                audit.PLAN_DERIVED_FRESH: 1,
                audit.PLAN_DERIVED_STALE: 1,
                audit.PLAN_DERIVED_SOURCE_MISSING: 1,
                audit.INCOMPLETE_PROJECTION_METADATA: 1,
                audit.APPROVED_PLAN_PROVENANCE_WITHOUT_PROJECTION: 1,
                audit.INVALID_RECORD: 1,
            },
        )
        self.assertEqual(report["summary"]["retirementBlockerCount"], 5)
        self.assertFalse(
            report["decision"]["legacyAuthoredWorkflowRetirementReady"]
        )
        self.assertEqual(
            report["privacy"],
            {
                "includesDatabasePath": False,
                "includesRecordIdentifiers": False,
                "includesRecordContent": False,
            },
        )

    def test_allows_compatibility_design_for_proven_safe_origins(self):
        plan = "# Plan\n\n## Stage\nreview"
        report = audit.build_report(
            [
                {},
                {
                    "workflowStage": "review",
                    "workflowSpec": {"goal": "Ship"},
                    "workflowSourceHash": audit.conversation_plan_hash(plan),
                    "workflowDerivedAt": "2026-08-02T00:00:00Z",
                    "planArtifact": {"approvedMarkdown": plan},
                },
                {
                    "workflowStage": "review",
                    "workflowSpec": {"goal": "Ship"},
                    "workflowSourceHash": "stale",
                    "workflowDerivedAt": "2026-08-02T00:00:00Z",
                    "planArtifact": {"approvedMarkdown": plan},
                },
            ]
        )

        self.assertTrue(
            report["decision"]["legacyAuthoredWorkflowRetirementReady"]
        )
        self.assertEqual(report["decision"]["blockerCounts"], {})
        self.assertEqual(
            report["decision"]["nextAction"],
            "proceed_to_compatibility_design",
        )

    def test_matches_dart_utf16_plan_hash_semantics(self):
        self.assertEqual(
            audit.conversation_plan_hash("Plan 🧪"),
            "bc251116",
        )

    def test_reports_missing_database_without_echoing_its_path(self):
        stderr = io.StringIO()
        missing = pathlib.Path("/private/sensitive/missing.sqlite")
        with contextlib.redirect_stderr(stderr):
            exit_code = audit.main(["--database", str(missing)])

        self.assertEqual(exit_code, 2)
        self.assertNotIn(str(missing), stderr.getvalue())
        self.assertIn("does not exist", stderr.getvalue())

    def test_rejects_a_database_without_the_conversation_table(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / "empty.sqlite"
            connection = sqlite3.connect(path)
            connection.close()
            with self.assertRaisesRegex(audit.AuditError, "could not be read"):
                audit.audit_database(path)


if __name__ == "__main__":
    unittest.main()
