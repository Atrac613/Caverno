# Workflow Conflict Preservation Rehearsal

## Task

- Goal: Rehearse the pure preservation envelope read-only against the complete
  persisted plan/progress conflict cohort with stage authority absent.
- User-visible behavior: None. This extends a local diagnostic only.
- Non-goals: Selecting stage authority, persisting envelopes, transforming
  conversations, remapping progress, or removing the workflow editor.

## Context

- Affected files or components:
  `tool/audit_legacy_workflow_compatibility.dart`, its focused tests, and the
  ChatNotifier renewal evidence documents.
- Related docs:
  `docs/chat_notifier_workflow_conflict_preservation_envelope_codex_task.md` and
  `docs/chat_notifier_plan_progress_conflict_policy_audit_codex_task.md`.
- Reference implementation or pattern: The schema-v4 conflict-policy aggregate
  and `ConversationWorkflowConflictPreservationService`.
- Known quirks, compatibility rules, or release gates: Authority must remain
  null in this rehearsal. The live database must be opened query-only and must
  remain byte-identical.

## Implementation Notes

- Preferred approach: Add a schema-v5 aggregate for the exact combined-conflict
  cohort. Invoke the pure service without authority and count envelope creation,
  blocker and merge-blocker outcomes, selected-stage absence, meaningful orphan
  preservation, complete execution-progress preservation, and input mutation.
- Constraints: Emit aggregate counts and stable enum names only. Do not emit
  record identifiers, progress identifiers, content, stages, or source locators.
- Generated files needed: None.
- Migration or data compatibility concerns: This is proof of preservation
  readiness only and does not authorize a transformer.

## Similar-Pattern Search

- Search terms: `planProgressConflictPolicy`, `stageAuthorityRequired`,
  `orphanExecutionProgress`, `inputMutation`, and `schemaVersion`.
- Files or modules inspected: The schema-v4 audit, focused aggregate tests, the
  pure preservation service, and provenance merge blocker reporting.
- Follow-up tasks found: If every live record produces a lossless envelope with
  only `stageAuthorityRequired`, define the source and audit trail for an
  explicit stage-authority decision next.

## Acceptance Criteria

- Required behavior: Evaluate every combined conflict exactly once with null
  authority and prove whether every execution-progress object is retained in
  either the active or orphan envelope partition.
- Edge cases: Empty cohorts, missing envelopes, extra blockers, merge blockers,
  meaningful versus passive orphans, selected stages, and detected mutation.
- Failure paths: Any missing or lossy envelope, unexpected readiness, selected
  stage, extra blocker, merge blocker, or mutation prevents a positive decision.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
fvm flutter test test/tool/audit_legacy_workflow_compatibility_test.dart
fvm dart run tool/audit_legacy_workflow_compatibility.dart --database <path>
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Added a privacy-safe schema-v5 aggregate and rehearsed all four live
  conflict records with null stage authority. Every record produced an
  envelope, preserved every execution-progress object, retained meaningful
  orphan progress, selected no stage, and reported only
  `stageAuthorityRequired` with zero merge blockers or input mutation.
- Tests run: The focused audit test passes 10/10. `tool/codex_verify.sh`
  completes generation, analysis, and package tests; the Flutter suite passes
  6,516/6,517 tests. Its only failure is the pre-existing stale
  `run_coding_stalled_diagnostic_repair_live_canary` expectation for the
  removed `_isTodoVerifierCall` helper. The live database SHA-256 was
  `ad5fc676bbca7a2fc926587b8c14f72940bff465f93825d01167d8ea960c9698`
  both before and after the read-only rehearsal.
- Coverage or low-coverage notes: Fixtures cover positive authority-free
  rehearsal, complete progress multiset preservation, meaningful orphans,
  selected-stage absence, blocker aggregates, mutation detection, and privacy.
- Risks or follow-ups: This rehearsal does not authorize a live migration. The
  next slice must define an explicit stage-authority source and audit trail; it
  must not infer authority from timestamps, enum ordering, or current storage.
