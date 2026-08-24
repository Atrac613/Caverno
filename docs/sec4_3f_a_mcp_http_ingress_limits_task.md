# SEC4.3f-A MCP HTTP Ingress Limits

Status: completed 2026-08-24.

## Task

- Goal: reject oversized or stalled MCP HTTP responses before buffering the
  complete response body.
- User-visible behavior: normal MCP HTTP servers remain compatible; responses
  exceeding 1 MiB or stalling between chunks fail with a bounded transport
  error instead of holding or exhausting the chat turn.
- Non-goals: stdio line limits, JSON document/content limits, QR decompression
  limits, or changing MCP trust/approval policy.

## Context

- Affected component: `McpClient` streamable HTTP transport and focused tests.
- Related docs: `docs/security_followup_review_2026-08-24.md` SA-21 and the
  SEC4.3d streamed HTTP executor pattern.
- Release role: first independently reviewable sub-slice of SEC4.3f.

## Implementation Notes

- Replace body-buffering `http.post` with `http.Client.send` and bounded stream
  consumption.
- Reject declared Content-Length before reading the body and count actual bytes
  for chunked or misleading responses.
- Apply the existing total request timeout across send and body consumption,
  plus a separate idle timeout between response chunks.
- Keep UTF-8 decoding after the byte ceiling succeeds.
- Inject an HTTP client for deterministic ownership and future transport tests.

## Similar-Pattern Search

- Search terms: `http.post`, `Response.fromStream`, `contentLength`,
  `maxResponseBodyBytes`, `idleTimeout`, and `NetworkHttpRequestExecutor`.
- Files inspected: MCP HTTP/stdio clients, network HTTP request executor, QR
  service, and focused tests.
- Follow-up tasks found: SEC4.3f-B owns stdio line/diagnostic plus JSON document
  and aggregate content limits; SEC4.3f-C owns QR compressed/decompressed limits.

## Acceptance Criteria

- A declared response length over the configured ceiling is rejected before
  body buffering.
- A chunked response crossing the ceiling is rejected at the crossing chunk.
- A response that stops producing chunks fails at the idle deadline.
- Existing JSON, concatenated JSON, SSE, session header, and total-timeout
  behavior remains green.
- Client-owned HTTP resources close on dispose; injected clients remain caller
  owned.

## Verification

```bash
tool/codex_verify.sh --coverage \
  --test test/features/chat/data/datasources/mcp_client_test.dart
```

## Handoff Notes

- Summary: MCP HTTP responses now reject an oversized declared length before
  body consumption, count actual streamed bytes against a 1 MiB default
  ceiling, and enforce total and between-chunk idle deadlines before UTF-8 or
  JSON decoding. Client ownership is explicit and disposed clients fail closed.
- Tests run: all 8 focused MCP HTTP transport tests pass; `flutter analyze
  --no-pub` reports no issues.
- Coverage or low-coverage notes: `mcp_client.dart` has 222/270 covered lines
  (82.2%) in the focused coverage run. The remaining lines are primarily
  protocol error and less common result-shape paths outside this ingress slice.
- Risks or follow-ups: SEC4.3f remains open until stdio, JSON-content, and QR
  decompression sub-slices complete.
