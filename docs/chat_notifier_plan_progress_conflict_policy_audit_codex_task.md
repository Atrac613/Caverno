# Plan/Progress Conflict Policy Audit

## Task

- Goal: Classify the four legacy workflow records that combine dangling
  execution progress with a conflicting plan document, then state fail-closed
  repair-policy invariants from aggregate evidence.
- User-visible behavior: None. This is a read-only diagnostic and documentation
  slice.
- Non-goals: Mutating persisted conversations, choosing an authored document
  by heuristic, deleting the workflow editor, or wiring a migration.

## Context

- Affected files or components:
  `tool/audit_legacy_workflow_compatibility.dart`, its focused tests, and the
  ChatNotifier renewal evidence documents.
- Related docs: `docs/chat_notifier_renewal_candidate_ranking.md`,
  `docs/chat_notifier_legacy_workflow_item_identity_reconciliation_codex_task.md`,
  and `docs/chat_notifier_legacy_workflow_provenance_merge_audit_codex_task.md`.
- Reference implementation or pattern: The privacy-safe schema-v3 provenance
  merge aggregate in `audit_legacy_workflow_compatibility.dart`.
- Known quirks, compatibility rules, or release gates: A textual plan conflict
  does not prove semantic divergence. Progress references must not be remapped
  by position or title, and plan projection must remain deterministic.

## Implementation Notes

- Preferred approach: Add a schema-v4 aggregate for records carrying both
  `danglingExecutionProgress` and `existingPlanDocumentConflict`. Project the
  existing execution document read-only, compare semantic workflow shape,
  test exact progress-reference ownership, and evaluate the existing
  provenance merge fixture without emitting record-level data.
- Constraints: Fail closed on projection, semantic, reference, or merge
  ambiguity. Report only counts and stable enum names. Preserve database bytes.
- Generated files needed: None.
- Migration or data compatibility concerns: The result may define policy
  preconditions but must not authorize or perform a migration.

## Similar-Pattern Search

- Search terms: `danglingExecutionProgress`, `existingPlanDocumentConflict`,
  `executionMarkdown`, `stabilizeTaskIds`, and `provenanceMergeCandidate`.
- Files or modules inspected:
  `conversation_legacy_workflow_compatibility_service.dart`,
  `conversation_workflow_provenance_merge_service.dart`,
  `conversation_plan_projection_service.dart`, and the aggregate audit tests.
- Follow-up tasks found: A transformer remains separate and is allowed only if
  every policy precondition is proven for the conflict cohort.

## Acceptance Criteria

- Required behavior: Count every combined conflict record exactly once and
  classify existing-plan projection, semantic relation, exact dangling-progress
  ownership, meaningful progress state, and provenance merge readiness.
- Edge cases: Unparseable plans, semantically equivalent textual conflicts,
  divergent plans, progress owned by the plan, progress owned by neither
  document, partial ownership, and passive versus meaningful progress.
- Failure paths: Projection and merge failures produce deterministic aggregate
  classifications and never an optimistic repair recommendation.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
fvm flutter test test/tool/audit_legacy_workflow_compatibility_test.dart
fvm dart run tool/audit_legacy_workflow_compatibility.dart --database <path>
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Pending implementation.
- Tests run: Pending.
- Coverage or low-coverage notes: Pending.
- Risks or follow-ups: This audit does not authorize a live migration.
