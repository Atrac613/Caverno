# SEC4.5g Remote Interaction Ownership

Status: completed 2026-08-24.

## Task

- Goal: enforce Remote Coding interaction origin and device ownership at the
  approval and question mutation boundary.
- User-visible behavior: only the paired device that initiated a remote turn
  can view or resolve that turn's pending approvals and questions.
- Non-goals: changing pairing credentials, the WSS session protocol, or the
  approval policy applied by `ChatNotifier`.

## Context

- Affected components: remote message dispatch, pending chat interactions,
  per-client snapshots, and Remote Coding resolution handlers.
- Related finding: SA-23 in
  `docs/security_followup_review_2026-08-24.md`.
- Authorization policy: paired devices are separate principals. A reconnect is
  authorized when it authenticates as the same active `deviceId`; another
  paired device is not authorized to view or resolve the interaction.

## Implementation Notes

- Carry the authenticated initiating `deviceId` through queued remote turns to
  every remotely resolvable pending object.
- Filter pending interaction snapshots by the authenticated client device.
- Recheck remote origin, exact device ownership, and active pairing immediately
  before resolution.
- Return the existing generic not-found response for absent and unauthorized
  identifiers.

## Similar-Pattern Search

- Search terms: `resolveApproval`, `resolveQuestion`, `pendingApproval`,
  `pendingQuestion`, `ChatInteractionOrigin.remote`, and `deviceId`.
- Files inspected: Remote Coding server/client notifiers and protocol, pending
  chat interaction models, chat tool approval creation, question creation,
  pairing revocation, and focused Remote Coding tests.
- Follow-up found: none; file, local-command, git-command, and question
  interactions share this boundary.

## Acceptance Criteria

- Desktop-origin pending interactions cannot be resolved remotely.
- Missing or stale interaction identifiers return the generic not-found error.
- A revoked device cannot view or resolve its former pending interaction.
- A reconnect authenticated as the initiating device can resolve it.
- Another active paired device cannot view or resolve it.
- File, local-command, git-command, and question paths apply the same policy.

## Verification

```bash
tool/codex_verify.sh --coverage \
  --test test/features/chat/presentation/providers/chat_notifier_test.dart \
  --test test/features/remote_coding/presentation/remote_coding_server_notifier_test.dart
```

## Handoff Notes

- Summary: remote pending interactions now carry the initiating device and are
  filtered and resolved only for that active paired-device principal.
- Tests run: five focused ChatNotifier propagation tests, the complete 14-test
  Remote Coding server suite, all workspace package tests, the 10-test relay
  suite, and project/package analysis pass.
- Coverage or low-coverage notes: the focused standard gate reports 4.15% line
  coverage across the broad application surface; all changed authorization
  branches are directly asserted.
- Risks or follow-ups: real two-device promotion evidence remains part of the
  RC1 release gate even after the source-level authorization boundary closes.
  A combined full ChatNotifier-plus-server run exposed unrelated existing
  command-runner timeouts; the changed ChatNotifier tests pass when isolated,
  and the repository standard gate is green.
