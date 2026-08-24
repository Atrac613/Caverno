# SEC4.6k-B MCP Diagnostic Redaction

Status: completed 2026-08-24.

## Task

- Goal: prevent MCP credentials and response content from leaking through
  debug diagnostics.
- User-visible behavior: MCP initialization, discovery, and tool execution
  remain unchanged.
- Non-goals: changing MCP protocol behavior or the new-install session logging
  default, which remains SEC4.6k-C.

## Context

- Affected components: `SensitiveDataRedactor`, the application logger, and
  the HTTP and stdio MCP clients.
- Related finding: SA-22 in
  `docs/security_followup_review_2026-08-24.md`.
- Reference pattern: key-aware recursive redaction used by session and approval
  audit logs.

## Diagnostic Contract

- Structured values are recursively redacted before rendering.
- JSON objects and arrays embedded in string fields are decoded before the same
  recursive redaction pass.
- MCP session identifiers and sensitive response headers are never emitted.
- Tool arguments may be diagnosed only through the structured redaction
  boundary.
- HTTP response bodies and stdio stderr lines are omitted by default;
  diagnostics retain only status and size metadata.
- Redaction affects diagnostics only and never changes MCP request or response
  semantics.

## Similar-Pattern Search

- Search terms: `McpClient`, `Request:`, `Response body`, `headers`,
  `Session ID`, `arguments`, and `full response`.
- Files inspected: HTTP MCP client, stdio MCP client, shared logger and
  redactor, and MCP transport tests.
- Follow-up found and repaired: stdio MCP exposed process arguments, stderr,
  server info, and JSON-RPC error text through string diagnostics. Session
  logging defaults remain SEC4.6k-C.

## Acceptance Criteria

- Nested header and credential keys are redacted.
- Serialized JSON credentials are parsed and redacted.
- MCP session identifiers do not appear in diagnostics.
- Successful and error response bodies are omitted from diagnostics.
- Returned MCP tool content remains byte-for-byte unchanged.

## Verification

```bash
tool/codex_verify.sh --coverage \
  --test test/core/utils/logger_test.dart \
  --test test/features/chat/data/datasources/mcp_client_test.dart \
  --test test/features/chat/data/datasources/mcp_stdio_client_test.dart
```

## Handoff Notes

- Summary: structured diagnostics now decode nested JSON strings before
  recursive key-aware redaction. HTTP MCP omits response bodies and session
  identifiers; stdio MCP omits stderr contents and process arguments.
- Tests run: all 23 focused logger and MCP transport tests pass;
  `flutter analyze --no-pub` reports no issues.
- Coverage or low-coverage notes: the focused verification reports 82.5% line
  coverage across the selected root and workspace-package surface.
- Risks or follow-ups: the helper limits serialized-JSON expansion to eight
  layers. SEC4.6k-C must default session logging off for new installations while
  preserving explicit and migrated existing choices.
