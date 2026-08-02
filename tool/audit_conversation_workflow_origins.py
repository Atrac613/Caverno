#!/usr/bin/env python3
"""Classify persisted conversation workflow origins without mutating storage."""

from __future__ import annotations

import argparse
import json
import pathlib
import sqlite3
import sys
from collections.abc import Mapping, Sequence
from typing import Any
from urllib.parse import quote


SCHEMA_NAME = "caverno_conversation_workflow_origin_audit"
SCHEMA_VERSION = 1

NO_WORKFLOW = "no_workflow_context"
LEGACY_AUTHORED = "legacy_authored"
PLAN_DERIVED_FRESH = "plan_derived_fresh"
PLAN_DERIVED_STALE = "plan_derived_stale"
PLAN_DERIVED_SOURCE_MISSING = "plan_derived_source_missing"
INCOMPLETE_PROJECTION_METADATA = "incomplete_projection_metadata"
APPROVED_PLAN_PROVENANCE_WITHOUT_PROJECTION = (
    "approved_plan_provenance_without_projection"
)
INVALID_RECORD = "invalid_record"

ORIGIN_KINDS = (
    NO_WORKFLOW,
    LEGACY_AUTHORED,
    PLAN_DERIVED_FRESH,
    PLAN_DERIVED_STALE,
    PLAN_DERIVED_SOURCE_MISSING,
    INCOMPLETE_PROJECTION_METADATA,
    APPROVED_PLAN_PROVENANCE_WITHOUT_PROJECTION,
    INVALID_RECORD,
)

BLOCKING_ORIGINS = (
    LEGACY_AUTHORED,
    PLAN_DERIVED_SOURCE_MISSING,
    INCOMPLETE_PROJECTION_METADATA,
    APPROVED_PLAN_PROVENANCE_WITHOUT_PROJECTION,
    INVALID_RECORD,
)


class AuditError(Exception):
    """Raised when the database cannot be audited safely."""


def _non_empty_string(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    normalized = value.strip()
    return normalized or None


def _mapping(value: object) -> Mapping[str, Any]:
    return value if isinstance(value, Mapping) else {}


def _sequence(value: object) -> Sequence[object]:
    if isinstance(value, Sequence) and not isinstance(value, (str, bytes)):
        return value
    return ()


def _has_non_empty_string(values: object) -> bool:
    return any(_non_empty_string(value) is not None for value in _sequence(values))


def _task_has_content(value: object) -> bool:
    task = _mapping(value)
    return any(
        (
            _non_empty_string(task.get("title")) is not None,
            _has_non_empty_string(task.get("targetFiles")),
            _non_empty_string(task.get("validationCommand")) is not None,
            _non_empty_string(task.get("notes")) is not None,
        )
    )


def _workflow_has_content(workflow: Mapping[str, Any]) -> bool:
    return any(
        (
            _non_empty_string(workflow.get("goal")) is not None,
            _has_non_empty_string(workflow.get("constraints")),
            _has_non_empty_string(workflow.get("acceptanceCriteria")),
            _has_non_empty_string(workflow.get("openQuestions")),
            any(_task_has_content(task) for task in _sequence(workflow.get("tasks"))),
        )
    )


def _has_approved_plan_source(workflow: Mapping[str, Any]) -> bool:
    return any(
        _mapping(source).get("kind") == "approvedPlan"
        for source in _sequence(workflow.get("sources"))
    )


def _execution_document(conversation: Mapping[str, Any]) -> str | None:
    artifact = _mapping(conversation.get("planArtifact"))
    return _non_empty_string(artifact.get("approvedMarkdown")) or _non_empty_string(
        artifact.get("draftMarkdown")
    )


def conversation_plan_hash(markdown: str) -> str:
    """Reproduce Dart's FNV-1a hash over UTF-16 code units."""
    value = 0x811C9DC5
    encoded = markdown.encode("utf-16-le")
    for offset in range(0, len(encoded), 2):
        code_unit = int.from_bytes(encoded[offset : offset + 2], "little")
        value ^= code_unit
        value = (value * 0x01000193) & 0xFFFFFFFF
    return f"{value:08x}"


def classify_conversation(value: object) -> str:
    """Classify one decoded persisted conversation payload."""
    if not isinstance(value, Mapping):
        return INVALID_RECORD
    workflow = _mapping(value.get("workflowSpec"))
    workflow_stage = value.get("workflowStage", "idle")
    if not isinstance(workflow_stage, str):
        return INVALID_RECORD
    has_workflow = workflow_stage in {
        "clarify",
        "plan",
        "tasks",
        "implement",
        "review",
    } or _workflow_has_content(workflow)
    if not has_workflow:
        return NO_WORKFLOW

    source_hash = _non_empty_string(value.get("workflowSourceHash"))
    derived_at = _non_empty_string(value.get("workflowDerivedAt"))
    if (source_hash is None) != (derived_at is None):
        return INCOMPLETE_PROJECTION_METADATA

    if source_hash is not None:
        execution_document = _execution_document(value)
        if execution_document is None:
            return PLAN_DERIVED_SOURCE_MISSING
        return (
            PLAN_DERIVED_FRESH
            if source_hash == conversation_plan_hash(execution_document)
            else PLAN_DERIVED_STALE
        )

    if _has_approved_plan_source(workflow):
        return APPROVED_PLAN_PROVENANCE_WITHOUT_PROJECTION
    return LEGACY_AUTHORED


def build_report(payloads: Sequence[object]) -> dict[str, object]:
    """Build a path-free aggregate report for decoded or invalid payloads."""
    counts = {kind: 0 for kind in ORIGIN_KINDS}
    for payload in payloads:
        counts[classify_conversation(payload)] += 1
    blocker_counts = {
        kind: counts[kind] for kind in BLOCKING_ORIGINS if counts[kind] > 0
    }
    blocker_count = sum(blocker_counts.values())
    workflow_count = len(payloads) - counts[NO_WORKFLOW] - counts[INVALID_RECORD]
    return {
        "schemaName": SCHEMA_NAME,
        "schemaVersion": SCHEMA_VERSION,
        "summary": {
            "databaseRowCount": len(payloads),
            "classifiedWorkflowCount": workflow_count,
            "originCounts": counts,
            "retirementBlockerCount": blocker_count,
        },
        "decision": {
            "legacyAuthoredWorkflowRetirementReady": blocker_count == 0,
            "blockerCounts": blocker_counts,
            "nextAction": (
                "proceed_to_compatibility_design"
                if blocker_count == 0
                else "design_backfill_or_provenance_repair"
            ),
        },
        "privacy": {
            "includesDatabasePath": False,
            "includesRecordIdentifiers": False,
            "includesRecordContent": False,
        },
    }


def audit_database(database_path: pathlib.Path) -> dict[str, object]:
    """Read conversation payloads from SQLite using a read-only connection."""
    if not database_path.is_file():
        raise AuditError("Conversation database file does not exist.")
    uri = f"file:{quote(str(database_path.resolve()))}?mode=ro"
    try:
        connection = sqlite3.connect(uri, uri=True)
    except sqlite3.Error as error:
        raise AuditError(
            "Conversation database could not be opened read-only."
        ) from error
    try:
        connection.execute("PRAGMA query_only = ON")
        rows = connection.execute(
            "SELECT payload FROM conversations ORDER BY id"
        ).fetchall()
    except sqlite3.Error as error:
        raise AuditError("Conversation table could not be read.") from error
    finally:
        connection.close()

    payloads: list[object] = []
    for (raw_payload,) in rows:
        try:
            payloads.append(json.loads(raw_payload))
        except (json.JSONDecodeError, TypeError):
            payloads.append(None)
    return build_report(payloads)


def main(arguments: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Audit persisted Caverno workflow origins without writes."
    )
    parser.add_argument("--database", required=True, type=pathlib.Path)
    options = parser.parse_args(arguments)
    try:
        report = audit_database(options.database)
    except AuditError as error:
        print(str(error), file=sys.stderr)
        return 2
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
