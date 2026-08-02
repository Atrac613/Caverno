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

- Summary: Added a privacy-safe schema-v4 aggregate for the combined conflict
  cohort. All four live plans parse, are workflow-semantically equivalent, and
  accept the provenance merge, but all four disagree on stage. Every dangling
  progress entry is meaningful and is owned by neither the existing plan nor
  any single or combined legacy checkpoint task graph.
- Tests run: The focused audit test passes 9/9. `tool/codex_verify.sh`
  completes generation, analysis, and package tests; the Flutter suite passes
  6,507/6,508 tests. Its only failure is the pre-existing stale
  `run_coding_stalled_diagnostic_repair_live_canary` expectation for the
  removed `_isTodoVerifierCall` helper. The live database SHA-256 was
  `ad5fc676bbca7a2fc926587b8c14f72940bff465f93825d01167d8ea960c9698`
  both before and after the read-only audit.
- Coverage or low-coverage notes: Fixtures cover parsed and invalid plans,
  semantic equality and divergence, exact existing-plan ownership, exact
  checkpoint ownership, passive and meaningful progress, merge readiness, and
  privacy-safe output.
- Risks or follow-ups: This audit does not authorize a live migration. Never
  discard or heuristically remap the four meaningful orphan progress records.
  A preservation envelope and explicit stage-authority decision are required
  before a conflict transformer can be considered.
