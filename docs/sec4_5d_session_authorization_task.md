# SEC4.5d Short-Lived Session Authorization Task

Status: complete.

## Task

- Goal: replace reusable Remote Coding transport tokens as session
  authorization with a short-lived, challenge- and channel-bound session.
  A pairing secret or device token must not authenticate a socket unless it
  answers that socket's challenge.
- User-visible behavior: after WSS upgrade the host sends `authChallenge`.
  The phone answers with a proof bound to that challenge, the certificate
  pin, and the pairing secret or saved device token. Reconnects repeat the
  handshake. Previously captured `auth` frames cannot start a new session.
- Non-goals: connection/frame/rate limits and authentication deadlines
  (SEC4.5e); HTTPS for LLM endpoints (SEC4.5f); changing the notification
  relay HTTPS contract; storing a MAC key in settings JSON.

## Context

- Affected components:
  - session challenge policy and registry;
  - desktop WebSocket accept/auth;
  - mobile connect/auth.
- Related docs:
  - `docs/sec4_5c_pinned_wss_transport_task.md`;
  - `docs/remote_coding_p1_release_gate.md`;
  - `docs/security_audit_2026-08-14.md` SA-06 remainder.
- Release gate: P1. Required before treating Remote Coding transport tokens
  as closed.

## Implementation Slices

1. Issue a per-connection challenge (id, nonce, expiry) bound to the
   socket and certificate pin.
2. Require `challengeId` plus HMAC proof in `auth`. Reject missing, expired,
   foreign-socket, and replayed challenges before pairing or token lookup.
3. Mark the socket authenticated with an in-memory session that dies when
   the socket closes. Keep `tokenHash` at rest; do not send the device token
   except during first pairing issuance.

## Implementation Notes

- Preferred approach: HMAC-SHA256 over `v1|{challengeId}|{nonce}|{pin}`
  using the pairing secret or device token as the key. The desktop still
  stores only `tokenHash` in settings.
- Constraints:
  - Do not grow `remote_coding_server_notifier.dart` or
    `remote_coding_client_notifier.dart` more than a thin call-site.
  - Do not accept a raw `token` field as sufficient auth.
  - Do not burn a challenge that belongs to another connection.
- Generated files needed: None.
- Migration: phones on this protocol wait for `authChallenge` before `auth`.
  Older clients that send token-only `auth` fail closed.

## Similar-Pattern Search

- Search terms: `type == 'auth'`, `deviceToken`, `tokenHash`, `_handleAuth`.
- Files or modules inspected:
  - `remote_coding_server_notifier.dart`
  - `remote_coding_client_notifier.dart`
  - `remote_coding_pairing_registry.dart`
  - `remote_coding_security.dart`
- Follow-up tasks found: SEC4.5e connection/frame/rate limits.

## Acceptance Criteria

- Required behavior:
  - A matching challenge and proof authenticates; the snapshot session is
    not the reusable device token.
  - Pairing still issues a device token once, over pinned WSS.
- Edge cases:
  - Token-only `auth` fails before pairing or token lookup.
  - Replaying a consumed challenge fails.
  - A challenge from connection A cannot authorize connection B.
- Failure paths:
  - Zero sessions established from a captured `auth` frame on a new socket.

## Verification

```bash
fvm flutter test test/features/remote_coding/domain/remote_coding_session_policy_test.dart
fvm flutter test test/features/remote_coding/data/remote_coding_session_challenge_registry_test.dart
fvm flutter test test/features/remote_coding/data/remote_coding_security_test.dart
fvm flutter test test/features/remote_coding/data/remote_coding_protocol_test.dart
fvm flutter test test/features/remote_coding/presentation/remote_coding_client_state_test.dart
fvm flutter test test/features/remote_coding/presentation/remote_coding_server_notifier_test.dart
```

## Handoff Notes

- Summary: After WSS upgrade the host sends `authChallenge`. Auth must include
  that challenge id and an HMAC proof over the nonce and certificate pin.
  Token-only `auth`, replayed challenges, and foreign-socket challenges fail
  before pairing or token lookup. The in-memory session dies with the socket.
  Pairing still issues a device token once; reconnects prove possession without
  treating that token as a reusable bearer.
- Focused verification passed:
  - `remote_coding_session_policy_test.dart`
  - `remote_coding_session_challenge_registry_test.dart`
  - `remote_coding_security_test.dart`
  - `remote_coding_protocol_test.dart`
  - `remote_coding_client_state_test.dart`
  - `remote_coding_server_notifier_test.dart`
- Full suite: 8091 passed.
- Risks or follow-ups: older phones that send token-only `auth` fail closed.
  SEC4.5e connection/frame/rate limits.
