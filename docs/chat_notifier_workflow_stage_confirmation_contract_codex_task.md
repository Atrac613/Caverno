# Workflow Stage User-Confirmation Contract

## Task

- Goal: Define a persistence-neutral request/result boundary for explicit user
  confirmation of workflow-versus-approved-Plan stage authority.
- User-visible behavior: None. This adds a pure domain contract and no adapter.
- Non-goals: Building confirmation UI, choosing authority automatically,
  persisting requests, results, decisions, or receipts, transforming
  conversations, or removing the workflow editor.

## Context

- Affected files or components: A new chat-domain confirmation contract,
  focused tests, and the ChatNotifier renewal evidence documents.
- Related docs:
  `docs/chat_notifier_workflow_stage_decision_rehearsal_codex_task.md`,
  `docs/chat_notifier_workflow_stage_authority_decision_codex_task.md`, and
  `docs/chat_notifier_workflow_stage_decision_receipt_codex_task.md`.
- Reference implementation or pattern: Owner-tagged immutable request/result
  approval ports and the schema-v1 preservation decision context.
- Known quirks, compatibility rules, or release gates: A request is valid only
  for an authority-free envelope blocked solely on divergent stage authority.
  Confirmation must echo the exact request identity and context digest.

## Implementation Notes

- Preferred approach: Build a content-free immutable request containing its
  identity, context identity, both candidate stages, progress counts, and UTC
  creation time. Define a port returning either confirmed or declined. Convert
  only a matching, valid confirmed result into a manual stage decision.
- Constraints: Never infer authority, never trust a stale or mismatched result,
  and keep UI strings, callbacks, persistence, and conversation mutation out of
  the contract.
- Generated files needed: None; use plain immutable transient values.
- Migration or data compatibility concerns: None. The contract is not stored
  and does not authorize a transformer.

## Similar-Pattern Search

- Search terms: `ApprovalRequest`, `ApprovalResult`, `ApprovalPort`,
  `manualUserConfirmation`, `stageAuthorityRequired`, and `contextDigest`.
- Files or modules inspected: Participant, Browser, and Routine approval
  request/result ports; workflow preservation, decision receipt, and composed
  rehearsal fixtures.
- Follow-up tasks found: After the contract is proven, specify the adapter
  ownership and stale-state lifecycle before adding any confirmation UI.

## Acceptance Criteria

- Required behavior: Build one content-free request from an exact
  authority-required context and convert confirmed workflow or approved-Plan
  results into valid manual decisions bound to that request and context.
- Edge cases: Equal stages, non-authority blockers, blank identities, non-UTC
  times, declined confirmation, identity or digest mismatch, invalid decision
  identity, and responses predating the request.
- Failure paths: Return typed blockers and no decision for every unavailable,
  declined, malformed, mismatched, or stale confirmation.
- Accessibility, localization, or platform expectations: None; presentation is
  explicitly outside this slice.

## Verification

```bash
fvm flutter test \
  test/features/chat/domain/services/conversation_workflow_stage_confirmation_contract_test.dart
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Pending.
- Tests run: Pending.
- Coverage or low-coverage notes: Pending.
- Risks or follow-ups: Pending.
