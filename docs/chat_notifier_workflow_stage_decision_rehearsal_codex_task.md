# Workflow Stage Decision End-to-End Rehearsal

## Task

- Goal: Rehearse the complete accepted workflow-stage decision path for both
  authorities using synthetic conflict fixtures only.
- User-visible behavior: None. This is test-only migration evidence.
- Non-goals: Selecting authority for live records, adding production APIs,
  persisting receipts, building confirmation UI, transforming conversations,
  or removing the workflow editor.

## Context

- Affected files or components: A focused chat-domain integration test and the
  ChatNotifier renewal evidence documents.
- Related docs:
  `docs/chat_notifier_workflow_stage_authority_decision_codex_task.md`,
  `docs/chat_notifier_workflow_stage_decision_receipt_codex_task.md`, and
  `docs/chat_notifier_workflow_conflict_preservation_rehearsal_codex_task.md`.
- Reference implementation or pattern: The two-pass preservation service and
  schema-v1 receipt JSON round-trip and replay validator.
- Known quirks, compatibility rules, or release gates: Synthetic fixtures must
  contain divergent stages and meaningful orphan progress. No live record may
  receive an inferred or manufactured decision.

## Implementation Notes

- Preferred approach: In a test-only composed flow, build an authority-free
  envelope, create an explicit manual decision from its context, rebuild the
  preservation envelope, create and JSON-round-trip a content-free receipt,
  and replay it against the unchanged synthetic conversation.
- Constraints: Exercise workflow and approved-Plan authority independently,
  prove progress preservation and input immutability, and stop on any blocker
  or selected-stage mismatch.
- Generated files needed: None.
- Migration or data compatibility concerns: None. This rehearsal does not
  authorize persistence or a transformer.

## Similar-Pattern Search

- Search terms: `stageAuthorityRequired`, `stageDecision`, `receiptDigest`,
  `replay`, `orphanExecutionProgress`, and `conflictPreservationRehearsal`.
- Files or modules inspected: Preservation and receipt services, their focused
  tests, the schema-v5 live authority-free rehearsal, and renewal evidence.
- Follow-up tasks found: Both synthetic paths pass and the persistence-neutral
  confirmation contract is now defined. Audit adapter ownership and stale
  request lifecycle before wiring any UI, storage, or transformation.

## Acceptance Criteria

- Required behavior: Both explicit authorities complete the full two-pass,
  receipt round-trip, and current-state replay flow with the expected selected
  stage and no mutation.
- Edge cases: Authority-free blocking, divergent stages, active and orphan
  progress preservation, content-free receipts, and authority-specific stage
  selection.
- Failure paths: Any missing envelope, unexpected blocker, lossy progress,
  receipt parse failure, replay rejection, or mutation fails the rehearsal.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
fvm flutter test \
  test/features/chat/domain/services/conversation_workflow_stage_decision_rehearsal_test.dart
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Added a test-only composed rehearsal for workflow and approved-Plan
  authority. Each path performs the authority-free pass, creates an explicit
  manual synthetic decision, rebuilds the lossless envelope, creates and JSON
  round-trips a content-free receipt, and validates current-state replay.
- Tests run: The focused rehearsal passes 2/2. `tool/codex_verify.sh`
  completes generation, all analyzers, and package tests; the Flutter suite
  passes 6,529 tests. Its only failure is the pre-existing stale
  `run_coding_stalled_diagnostic_repair_live_canary` expectation for the
  removed `_isTodoVerifierCall` helper.
- Coverage or low-coverage notes: Both authority choices prove the expected
  selected stage, stable context binding, exact active-plus-orphan progress
  preservation, receipt field minimization, JSON round-trip, replay, and input
  immutability.
- Risks or follow-ups: This rehearsal does not authorize a live migration.
  The confirmation contract is now defined without an adapter. Audit its
  owner-scoped UI lifecycle and stale-request disposal next; keep receipt
  storage and conversation transformation outside that slice.
