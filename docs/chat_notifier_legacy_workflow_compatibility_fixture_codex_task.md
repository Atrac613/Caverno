# ChatNotifier Legacy Workflow Compatibility Fixture Task

## Task

- Goal: Define and verify a deterministic compatibility gate for converting a
  legacy-authored workflow into a plan-derived execution projection.
- User-visible behavior: None. This slice provides migration evidence only.
- Non-goals: Do not mutate persisted conversations, wire a migration, remove
  the workflow editor, or change runtime projection behavior.

## Context

- Affected files or components: Conversation workflow and plan domain
  services, focused domain tests, and the ChatNotifier renewal ranking.
- Related docs: `docs/chat_notifier_workflow_origin_audit_codex_task.md` and
  `docs/chat_notifier_renewal_candidate_ranking.md`.
- Reference implementation or pattern:
  `ConversationPlanDocumentBuilder.buildApprovedArtifact`,
  `ConversationPlanProjectionService.deriveExecutionProjection`, and
  `ConversationPlanProjectionService.stabilizeTaskIds`.
- Known quirks, compatibility rules, or release gates: Projection replaces
  contract sources and provenance with approved-plan provenance. Conversation
  checkpoints hold independent workflow snapshots used by rewind.

## Implementation Notes

- Preferred approach: Add a pure compatibility evaluator that constructs the
  same plan and projection a future backfill would use, then compares semantic
  workflow fields and referenced progress without mutating the input.
- Constraints: Fail closed when source or provenance replacement would discard
  information, progress references unknown task or question IDs, a checkpoint
  cannot be converted independently, or a plan fails to round-trip.
- Generated files needed: None.
- Migration or data compatibility concerns: Treat timestamps and approved-plan
  provenance as expected migration metadata, but require stage, goal, lists,
  task IDs, task status, target files, validation commands, notes, execution
  progress, open-question progress, and checkpoint restoration to remain
  compatible.

## Similar-Pattern Search

- Search terms: `buildApprovedArtifact`, `deriveExecutionProjection`,
  `stabilizeTaskIds`, `executionProgress`, `openQuestionProgress`,
  `ConversationCheckpoint`, and `rewindCurrentConversationToMessage`.
- Files or modules inspected: Conversation entities, plan document builder,
  plan projection service, provenance service, conversation notifier, and
  existing projection and rewind tests.
- Follow-up tasks found: Run an aggregate-only read-only compatibility audit
  against the 19 legacy-authored records only after the fixture contract is
  stable.

## Acceptance Criteria

- Required behavior: A representative legacy workflow round-trips without
  losing semantic workflow fields, task IDs, progress metadata, or checkpoint
  state.
- Edge cases: Existing non-legacy provenance, dangling task progress, dangling
  open-question progress, empty task IDs, and incompatible checkpoints block
  migration readiness with deterministic reason codes.
- Failure paths: Invalid generated plan documents or projections return a
  blocked result instead of throwing from the evaluator.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
fvm flutter test \
  test/features/chat/domain/services/conversation_legacy_workflow_compatibility_service_test.dart
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Added a pure fail-closed compatibility evaluator. It verifies the
  current workflow and every workflow-bearing checkpoint independently without
  mutating the conversation or connecting to persistence.
- Tests run: All 5 focused tests pass and focused analysis reports no issues.
  `tool/codex_verify.sh` passed generation, full analysis, package tests, and
  6,486 of 6,487 Flutter tests; the only failure is the pre-existing stale
  `run_coding_stalled_diagnostic_repair_live_canary_test.dart` expectation.
- Coverage or low-coverage notes: Fixtures cover a complete lossless workflow,
  provenance replacement, dangling task and question progress, empty task IDs,
  plan conflicts, malformed projections, input immutability, and incompatible
  checkpoints.
- Risks or follow-ups: This fixture does not authorize a live migration. The
  next slice is an aggregate-only read-only compatibility audit of the 19
  legacy-authored records.
