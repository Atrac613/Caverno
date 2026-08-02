# Workflow Stage Authority Decision Contract

## Task

- Goal: Replace bare stage-authority selection with an explicit, auditable
  decision bound to the exact preservation-envelope state.
- User-visible behavior: None. This is a pure domain contract only.
- Non-goals: Building a confirmation UI, persisting decisions, choosing an
  authority, migrating conversations, or removing the workflow editor.

## Context

- Affected files or components:
  `conversation_workflow_conflict_preservation_service.dart`, its focused
  tests, and the ChatNotifier renewal evidence documents.
- Related docs:
  `docs/chat_notifier_workflow_conflict_preservation_rehearsal_codex_task.md`
  and `docs/chat_notifier_workflow_conflict_preservation_envelope_codex_task.md`.
- Reference implementation or pattern: The two-pass authority-free envelope
  rehearsal and SHA-256 canonical contract fingerprints used by tool contracts.
- Known quirks, compatibility rules, or release gates: All four live records
  are blocked only on authority. Authority must not be inferred from timestamps,
  enum ordering, current storage, or call-site defaults.

## Implementation Notes

- Preferred approach: Emit a versioned SHA-256 decision-context digest from the
  lossless envelope. Accept a second-pass decision only when it carries a
  non-empty decision ID, manual-user-confirmation source, UTC decision time,
  exact context digest, and explicit workflow-versus-approved-plan authority.
- Constraints: A state change must invalidate replay. Keep decision objects and
  result lists immutable. Preserve the authority-free rehearsal behavior.
- Generated files needed: None; use plain immutable transient helpers.
- Migration or data compatibility concerns: The decision contract is not yet
  persisted. Its version and digest become compatibility boundaries for a
  future audit record.

## Similar-Pattern Search

- Search terms: `argumentDigest`, `configurationFingerprint`, `sha256`,
  `decisionId`, `manualDecisions`, and `stageAuthorityRequired`.
- Files or modules inspected: Git/local-command tool contracts, routine
  receipts, the preservation service, its focused tests, and schema-v5 audit.
- Follow-up tasks found: Define a persistence-neutral audit receipt and
  read-only replay fixture before UI or migration wiring.

## Acceptance Criteria

- Required behavior: Produce a deterministic context digest and accept only an
  exact explicit decision, returning the selected stage and decision receipt.
- Edge cases: Missing decision, empty ID, non-UTC time, unsupported source,
  malformed digest, context mismatch, state-change replay, both authorities,
  and already-equal stages.
- Failure paths: Invalid or stale decisions return deterministic blockers and
  never select a stage.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
fvm flutter test \
  test/features/chat/domain/services/conversation_workflow_conflict_preservation_service_test.dart
fvm flutter test test/tool/audit_legacy_workflow_compatibility_test.dart
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Replaced bare authority input with a two-pass manual decision. The
  authority-free envelope emits a schema-v1 SHA-256 context over both stages,
  the exact approved Plan document, merged workflow provenance, and active plus
  orphan progress. A decision selects a stage only when its non-empty ID,
  manual source, UTC time, digest, and authority all validate against that exact
  context; accepted decisions are retained as the envelope receipt.
- Tests run: The focused preservation service passes 10/10 and the focused
  schema-v5 audit passes 10/10. `tool/codex_verify.sh` completes generation,
  analysis, and package tests; the Flutter suite passes 6,518/6,519 tests. Its
  only failure is the pre-existing stale
  `run_coding_stalled_diagnostic_repair_live_canary` expectation for the
  removed `_isTodoVerifierCall` helper.
- Coverage or low-coverage notes: Fixtures cover deterministic context digests,
  both authorities, accepted receipt identity, empty IDs, automated inference,
  non-UTC times, malformed digests, state-change replay, authority-free
  rehearsal compatibility, and existing preservation blockers.
- Risks or follow-ups: This contract does not authorize a live migration.
  The persistence-neutral receipt and replay validator are defined, and both
  synthetic explicit-authority paths pass end to end. The confirmation contract
  is defined without an adapter. The adapter audit now selects a dedicated
  owner registry and owner-bound port; implement those without UI before any
  persistence or transformer wiring.
