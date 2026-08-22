# SEC4.5e-A Remote Coding Connection Admission Limits

## Task

- Goal: Bound unauthenticated Remote Coding WebSocket occupancy before adding
  frame-size and message-rate enforcement in a separate SEC4.5e-B slice.
- User-visible behavior: Excess connections are rejected before WebSocket
  upgrade, and clients that do not authenticate before the deadline are closed.
- Non-goals: Frame byte limits, authenticated message-rate limits, HTTP body
  streaming limits, reconnect UX, and changes to the pairing protocol.

## Context

- Affected components: Remote Coding server admission, socket lifecycle, and
  server notifier tests.
- Related docs: `docs/roadmap.md`, `docs/security_audit_2026-08-14.md`, and
  `docs/remote_coding_p0_release_gate.md`.
- Reference pattern: `RemoteCodingListenPolicy` keeps transport decisions in a
  directly tested domain policy while the server owns socket lifecycle effects.
- Release gate: This is the first SEC4.5e remainder after pinned WSS and
  challenge-bound session authorization.

## Implementation Notes

- Add a small immutable resource policy with explicit total, per-address, and
  authentication-deadline defaults.
- Count every upgraded socket, not only authenticated sessions. Reject excess
  requests before `WebSocketTransformer.upgrade`.
- Retain the peer address on the socket client, start an authentication timer
  after upgrade, cancel it after successful authentication, and make cleanup
  idempotent so every exit releases capacity.
- Keep the current `activeConnectionCount` product metric defined as the number
  of authenticated connections.
- Generated files and data migrations are not required.

## Similar-Pattern Search

- Search terms: `WebSocketTransformer.upgrade`, `HttpServer.bindSecure`,
  `activeConnectionCount`, `Timer`, and `isAuthenticated`.
- Files inspected: Remote Coding server, client connector, media host listener,
  and notification relay HTTP client.
- Follow-up: SEC4.5e-B must bound frame bytes and authenticated message rate.

## Acceptance Criteria

- A request over the global socket cap is rejected before upgrade.
- A request over the per-address socket cap is rejected before upgrade.
- An unauthenticated upgraded socket closes after the configured deadline.
- Successful authentication cancels the deadline.
- Closing any socket releases both global and per-address capacity exactly once.
- Existing pairing, challenged authentication, revocation, and relay tests stay
  green.

## Verification

```bash
fvm flutter test --no-pub \
  test/features/remote_coding/domain/remote_coding_resource_policy_test.dart \
  test/features/remote_coding/presentation/remote_coding_server_notifier_test.dart
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Pending implementation.
- Tests run: Pending implementation.
- Coverage notes: Exercise admission rejection and timer cleanup directly.
- Risks or follow-ups: Frame and message-rate enforcement remain SEC4.5e-B.
