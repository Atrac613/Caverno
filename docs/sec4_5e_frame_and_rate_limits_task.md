# SEC4.5e-B Remote Coding Frame And Rate Limits

## Task

- Goal: Complete SEC4.5e by bounding every inbound Remote Coding WebSocket
  message before JSON decoding and limiting per-connection command rates.
- User-visible behavior: Oversized frames and clients that exceed their message
  budget receive a stable protocol error and are disconnected.
- Non-goals: HTTP response streaming limits (SEC4.3d), credential-bearing LLM
  endpoint HTTPS enforcement (SEC4.5f), reconnect UX, or server-to-client event
  throttling.

## Context

- Affected components: `RemoteCodingResourcePolicy`, the Remote Coding server
  receive loop, socket lifecycle, and focused policy/server tests.
- Related docs: `docs/roadmap.md`, `docs/local_llm_agent_roadmap.md`,
  `docs/security_audit_2026-08-14.md`, and
  `docs/remote_coding_p0_release_gate.md`.
- Reference pattern: SEC4.5e-A keeps resource decisions in a directly tested
  domain policy while the server owns WebSocket effects and cleanup.
- Release gate: SEC4.5e completion requires both frame-size and message-rate
  limits to reject abusive clients mechanically.

## Implementation Notes

- Default the maximum inbound frame to 256 KiB of UTF-8 or binary data.
- Reject oversized text before JSON decoding. Use the UTF-16 length as a cheap
  lower-bound check before calculating exact UTF-8 length.
- Apply separate sliding-window budgets to unauthenticated and authenticated
  traffic. The unauthenticated budget bounds repeated HMAC/auth work; the
  authenticated budget allows ordinary UI bursts without permitting sustained
  command flooding.
- Default to 8 unauthenticated messages and 60 authenticated messages per
  10-second window, per connection.
- Close oversized frames with WebSocket status 1009 and rate violations with
  status 1008 after sending stable error codes when the socket remains writable.
- Preserve SEC4.5e-A global/per-address admission and authentication-deadline
  behavior.
- Generated files and data migrations are not required.

## Similar-Pattern Search

- Search terms: `WebSocket`, `utf8.encode`, `maxBytes`, `rate limit`,
  `messageTooBig`, and `policyViolation`.
- Files inspected: Remote Coding server/protocol/resource policy, notification
  relay HTTP client, WebSocket connector, and existing byte-bound utilities.
- Follow-up tasks found: HTTP byte/time ceilings remain SEC4.3d and
  credential-bearing non-loopback LLM HTTPS remains SEC4.5f.

## Acceptance Criteria

- Text frames at or below the exact UTF-8 limit can reach protocol decoding.
- Multibyte text over the UTF-8 limit is rejected before protocol decoding.
- Oversized binary frames are rejected even though binary messages are not
  valid Remote Coding protocol input.
- An unauthenticated connection cannot exceed its auth-message budget.
- A successfully authenticated connection receives a fresh, larger command
  budget and cannot exceed it.
- Rate capacity recovers only after the configured sliding window elapses.
- Violations close the socket and release SEC4.5e-A connection capacity.
- Existing pairing, challenged authentication, revocation, relay, admission,
  and authentication-deadline tests remain green.

## Verification

```bash
fvm dart analyze \
  lib/features/remote_coding/domain/remote_coding_resource_policy.dart \
  lib/features/remote_coding/presentation/remote_coding_server_notifier.dart \
  test/features/remote_coding/domain/remote_coding_resource_policy_test.dart \
  test/features/remote_coding/presentation/remote_coding_server_notifier_test.dart
fvm flutter test --no-pub \
  test/features/remote_coding/domain/remote_coding_resource_policy_test.dart \
  test/features/remote_coding/presentation/remote_coding_server_notifier_test.dart
```

## Handoff Notes

- Summary: Added a 256 KiB inbound text/binary limit and separate 10-second
  sliding-window budgets for 8 unauthenticated and 60 authenticated messages.
  Violations send stable protocol errors, close with status 1009 or 1008, and
  release connection capacity.
- Tests run: Targeted analysis passed; 20 focused SEC4.5e policy/server tests
  passed; all 180 Remote Coding feature and P0 release-gate tests passed; and
  repository-wide `fvm flutter analyze --no-pub` plus
  `tool/codex_verify.sh --no-codegen --no-tests` passed.
- Coverage notes: Direct tests cover exact ASCII and multibyte byte boundaries,
  oversized text and binary frames, both rate phases, window recovery, global
  and per-address caps, close status, authentication deadlines, and capacity
  reuse.
- Risks or follow-ups: Dart's WebSocket API delivers a complete frame before
  application code can inspect its size; this limit prevents unbounded JSON
  decoding and repeated processing but cannot avoid the transport allocation.
