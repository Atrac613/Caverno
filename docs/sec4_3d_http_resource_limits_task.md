# SEC4.3d HTTP Resource Limits

Status: completed on 2026-08-22.

## Task

- Goal: bound memory and time consumed by every model-triggered built-in HTTP
  response.
- User-visible behavior: oversized or stalled responses fail with a clear
  resource-limit error instead of buffering indefinitely.
- Non-goals: changing destination/redirect authorization, adding private-network
  grants, or applying this policy to unrelated application-owned HTTP clients.

## Context

- Affected components: `NetworkHttpTools` and
  `NetworkHttpRequestExecutor`.
- Related findings: SA-03 and SA-10 in
  `docs/security_audit_2026-08-14.md`.
- Reference pattern: `chat_completion_bounds.dart` uses explicit total and idle
  timeout failures for model traffic.
- Release gate: P1 resource and credential transport containment.

## Implementation Notes

- Read response bodies as bounded chunks; never buffer the complete response
  before applying the limit.
- Apply the same byte and time boundary while discarding status, HEAD, and
  redirect bodies.
- Use a 1 MiB wire-byte ceiling and a five-second response idle timeout.
- Treat the existing tool `timeout` as one total budget across DNS, connection,
  redirects, headers, and body consumption.
- Force-close the active client when the total deadline expires.

## Similar-Pattern Search

- Search terms: `response.drain`, `BytesBuilder`, `TimeoutException`,
  `request.close`, `followRedirects`, and `body_bytes`.
- Files inspected: built-in HTTP executor and handler, egress policy tests,
  chat completion bounds, browser session timeouts, and Remote Coding resource
  policy.
- Follow-up tasks found: SEC4.6 owns persisted-data redaction and filesystem
  permission hardening; other application-owned HTTP clients need separate
  threat-model review.

## Acceptance Criteria

- Declared and streamed bodies over 1 MiB stop before excess bytes are stored.
- Chunk progress cannot extend a request beyond its total timeout.
- A silent response fails after the idle timeout.
- Redirect and discarded-body paths use the same limits.
- Existing successful response envelopes remain compatible.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/data/datasources/network_http_tools_test.dart
```

## Handoff Notes

- Summary: all built-in HTTP response paths now share one bounded streaming
  consumer with a 1 MiB byte ceiling, a five-second idle timeout, and a
  monotonic total request deadline.
- Tests run: the standard Codex verification entrypoint passed; 17 focused HTTP
  executor tests and the six built-in network-handler tests passed together.
- Risks or follow-ups: the tool timeout remains user-selectable from 1 to 30
  seconds. SEC4.6 is the next audit slice.
