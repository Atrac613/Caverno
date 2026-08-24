# SEC4.3f-B MCP Stdio And JSON Limits

Status: completed 2026-08-24.

## Task

- Goal: reject oversized MCP stdio lines and excessive application-owned MCP
  JSON or tool text before unbounded buffering or downstream use.
- User-visible behavior: normal MCP HTTP and stdio servers remain compatible;
  a server that emits an oversized unterminated stdout/stderr line, too many
  JSON documents, or excessive aggregate text content fails with a bounded
  transport error and the unsafe stdio process is terminated.
- Non-goals: settings QR compressed/decompressed limits, MCP trust policy,
  destination policy, or protocol/schema redesign.

## Context

- Affected components: `McpStdioClient`, `McpClient`, their bounded decoding
  helper, and focused transport tests.
- Related finding: SA-21 in
  `docs/security_followup_review_2026-08-24.md`.
- Release role: second independently reviewable sub-slice of SEC4.3f.

## Implementation Notes

- Replace `utf8.decoder` plus `LineSplitter` on child stdout/stderr with a byte
  scanner that rejects a line before it crosses the configured ceiling.
- Treat decoder or line-limit failures on either child stream as fatal: fail
  pending requests, cancel subscriptions, and terminate the process.
- Cap extracted HTTP/SSE JSON documents before `jsonDecode` iterates them.
- Cap aggregate text returned from a tool across all content entries before
  joining or returning it.
- Keep limits configurable for deterministic boundary tests and validate all
  configured values at construction.

## Similar-Pattern Search

- Search terms: `LineSplitter`, `jsonDecode`, `_splitJsonDocuments`,
  `result['content']`, and `stderr`.
- Files inspected: MCP HTTP and stdio clients, MCP transport tests, LSP process
  transport tests, and the SEC4.3f roadmap evidence.
- Follow-up found: SEC4.3f-C remains responsible for settings QR compressed and
  decompressed byte limits.

## Acceptance Criteria

- A stdout response without a newline is rejected as soon as it crosses the
  configured byte ceiling, and the child process is terminated.
- Oversized stderr diagnostics cannot accumulate indefinitely or block an
  unconsumed child pipe.
- Plain concatenated and SSE responses reject more than the configured JSON
  document count before decoding the excess document.
- HTTP and stdio tool results reject aggregate text beyond the configured
  character ceiling.
- Exact-boundary lines, document counts, and text content remain accepted.
- Existing MCP transport compatibility and timeout tests remain green.

## Verification

```bash
tool/codex_verify.sh --coverage \
  --test test/features/chat/data/datasources/mcp_client_test.dart \
  --test test/features/chat/data/datasources/mcp_stdio_client_test.dart
```

## Handoff Notes

- Summary: MCP stdout and stderr now pass through a fixed-capacity UTF-8 line
  decoder with a 1 MiB default ceiling. A decoder or line-limit failure is
  terminal, fails pending requests with the original error, and kills the child
  process. HTTP/SSE parsing accepts at most 32 JSON documents, and HTTP/stdio
  tool text is capped at 524,288 characters including inserted separators.
- Tests run: all 18 focused MCP HTTP and stdio tests pass; `flutter analyze
  --no-pub` reports no issues.
- Coverage or low-coverage notes: focused line coverage is 231/273 (84.6%) for
  `mcp_client.dart`, 97/132 (73.5%) for `mcp_stdio_client.dart`, and 35/39
  (89.7%) for `mcp_response_limits.dart`. Remaining stdio branches primarily
  cover platform-specific process launch diagnostics and uncommon protocol
  errors outside this resource-boundary slice.
- Risks or follow-ups: SA-21 remains open until SEC4.3f-C bounds compressed and
  decompressed settings QR input.
