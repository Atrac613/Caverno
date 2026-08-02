# Workflow Stage Decision Receipt and Replay

## Task

- Goal: Create a persistence-neutral audit receipt for an accepted workflow
  stage decision and validate replay against the current conflict state.
- User-visible behavior: None. This is a pure domain fixture only.
- Non-goals: Choosing authority, writing receipts to storage, building UI,
  transforming conversations, or removing the workflow editor.

## Context

- Affected files or components: A new chat-domain receipt service and focused
  tests, plus the ChatNotifier renewal evidence documents.
- Related docs:
  `docs/chat_notifier_workflow_stage_authority_decision_codex_task.md` and
  `docs/chat_notifier_workflow_conflict_preservation_rehearsal_codex_task.md`.
- Reference implementation or pattern: The schema-v1 stage-decision context,
  routine receipt fingerprints, and exact replay rejection in the preservation
  service.
- Known quirks, compatibility rules, or release gates: The receipt must expose
  no Plan, workflow, or progress content. Validation must rebuild current state
  rather than trusting receipt claims.

## Implementation Notes

- Preferred approach: Build a versioned JSON-round-trippable receipt containing
  decision metadata, context metadata, both stages, selected stage, and a
  SHA-256 receipt digest. Replay reconstructs the decision against the current
  conversation and verifies the accepted stage.
- Constraints: Reject invalid schema, fields, digest, context, decision, or
  selected-stage claims deterministically. Never mutate the conversation.
- Generated files needed: None; use plain immutable transient helpers.
- Migration or data compatibility concerns: The JSON schema and digest
  canonicalization become compatibility boundaries, but no storage is wired.

## Similar-Pattern Search

- Search terms: `Receipt`, `receiptDigest`, `routineCreationDigest`,
  `fromJson`, `contextDigest`, and `stageDecisionContextMismatch`.
- Files or modules inspected: Routine creation receipts, local/browser effect
  receipts, preservation service, stage-decision tests, and schema-v5 audit.
- Follow-up tasks found: Rehearse receipt generation with synthetic explicit
  authority only; live authority remains unavailable and must not be invented.

## Acceptance Criteria

- Required behavior: Build and JSON-round-trip a content-free receipt from a
  ready accepted decision, then validate it against unchanged current state.
- Edge cases: Missing accepted decisions, unsupported schemas, malformed
  fields, receipt tampering, context changes, authority changes, selected-stage
  mismatch, and both authority choices.
- Failure paths: Return typed blockers and no validated stage for every invalid
  or stale receipt.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
fvm flutter test \
  test/features/chat/domain/services/conversation_workflow_stage_decision_receipt_service_test.dart
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Added a schema-v1 persistence-neutral receipt containing decision,
  context, authority, both stages, selected stage, and a SHA-256 receipt digest
  without Plan, workflow, or progress content. Replay validates schema and
  fields, verifies the receipt digest, rebuilds current context, reconstructs
  the manual decision, and accepts only the exact selected stage.
- Tests run: The focused receipt-service test passes 8/8.
  `tool/codex_verify.sh` completes generation, analysis, and package tests; the
  Flutter suite passes 6,526/6,527 tests. Its only failure is the pre-existing
  stale `run_coding_stalled_diagnostic_repair_live_canary` expectation for the
  removed `_isTodoVerifierCall` helper.
- Coverage or low-coverage notes: Fixtures cover both authorities, JSON
  round-trip, content exclusion, input immutability, not-ready and missing
  decisions, malformed JSON, schema and field failures, tampering, stale state,
  selected-stage contradiction, and unavailable current context.
- Risks or follow-ups: This fixture does not authorize a live migration. The
  end-to-end synthetic rehearsal passes for both authorities and the
  persistence-neutral confirmation contract is defined. Audit adapter
  ownership and stale-request disposal next; do not manufacture a decision for
  any live conflict record.
