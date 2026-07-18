# Network HTTP Tools Extraction

Status: complete on the current F5 refactoring stack.

## Task

- Goal: move HTTP status and method execution out of `network_tools.dart` into
  a focused component with an injectable `HttpClient` factory and direct
  in-memory transport characterization.
- User-visible behavior: none. Existing built-in tool names, public
  `NetworkTools` method signatures, JSON envelopes, headers, redirects, body
  encoding, truncation, timeouts, and errors remain compatible.
- Non-goals: DNS, route and interface inspection, neighbor caches, path MTU,
  mDNS, ping, traceroute, port checks, TLS certificates, WHOIS, or external
  network access in tests.

## Context

- The refreshed inventory reports `network_tools.dart` at 2,578 lines and
  39.31% line coverage.
- HTTP status plus GET, HEAD, DELETE, POST, PUT, PATCH, and their shared request
  implementation form one contiguous responsibility of roughly 300 lines.
- Production code constructs `HttpClient` directly, so the boundary cannot be
  isolated from socket creation. The extracted component introduces a factory
  seam while preserving the default `dart:io` implementation.

## Current Behavior Contract

- `httpStatus` performs GET, drains the response, reports URL, status code,
  reason phrase, response time, flattened headers, and redirect status/location
  pairs, and always closes the client.
- Method wrappers preserve verbs, optional headers, timeout, redirect policy,
  maximum redirects, body, and content-type arguments.
- Explicit header names are matched case-insensitively. An explicit
  `Content-Type` header takes precedence over the convenience parameter.
- A non-empty body is UTF-8 encoded, sets content length, and defaults to
  `application/json` when no content type is supplied. Null and empty bodies do
  not set a convenience content type or content length.
- HEAD drains the body and omits body fields.
- Other methods collect raw bytes. Valid UTF-8 is returned as text; invalid
  UTF-8 is base64 encoded.
- Returned bodies are capped at 4,000 characters and report byte count,
  encoding, and truncation state.
- Response content type and flattened response headers retain the current
  `dart:io` string representation.
- Every request closes its client on success or failure.

## Implementation Notes

1. Add `NetworkHttpTools` and `NetworkHttpClientFactory` in a standalone data
   source file. Keep the default factory equivalent to `HttpClient()`.
2. Move the HTTP constant, status method, wrappers, and shared implementation
   without changing control flow or payload construction.
3. Leave thin static compatibility delegates in `NetworkTools` with the exact
   existing signatures.
4. Add direct tests using in-memory `HttpClient`, request, response, and header
   fakes; never open a socket. Cover status, redirects, headers, all verbs,
   content-type precedence, HEAD, text and binary bodies, truncation, and
   failure cleanup.
5. Lower exact line-count ratchets for `network_tools.dart` and the extracted
   boundary.

## Constraints

- Do not change built-in tool definitions or dispatcher routing.
- Do not add external network calls, DNS dependencies, certificates, or real
  production endpoints to tests.
- Do not bind a test server or open any real socket. All HTTP transport objects
  must come from the injected factory.
- Do not broaden HTTP redirect, certificate, proxy, authentication, or cookie
  behavior.
- Do not move non-HTTP methods or private network topology models in this
  tranche.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `httpStatus`, `httpGet`, `httpHead`, `httpDelete`, `httpPost`,
  `httpPut`, `httpPatch`, `_httpRequest`, `_kHttpBodyMaxChars`, `HttpClient`,
  and `NetworkTools.http`.
- Files inspected: network tools, built-in network tool handler, MCP service
  compatibility tests, network tool tests, file-size ratchets, coverage output,
  active worktrees, refactoring plan, and ROADMAP.
- Adjacent work deliberately excluded: raw socket tools and topology/discovery
  parsing, which remain later network tranches.

## Acceptance Criteria

- Existing callers continue using unchanged `NetworkTools.http*` APIs.
- The extracted class can be instantiated with an alternate client factory and
  imports no chat, provider, or presentation types.
- Direct tests exercise every public HTTP method without external network
  access and pin the existing JSON contract.
- `network_tools.dart` shrinks and both files have exact non-increasing
  line-count ratchets.
- Focused network and MCP compatibility tests plus the full repository gate
  pass without analyzer findings.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/data/datasources/network_http_tools_test.dart \
  --test test/features/chat/data/datasources/network_tools_test.dart \
  --test test/features/chat/data/datasources/mcp_tool_service_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: extracted the HTTP family behind unchanged `NetworkTools` delegates,
  added an injectable client factory, and added in-memory transport contract
  tests plus exact line-count ratchets.
- Tests run: targeted `dart analyze` passes for both production files and the
  direct test. The focused HTTP, network, MCP compatibility, and file-size
  ratchet gate passes all 165 tests. `git diff --check` also passes.
- Coverage or low-coverage notes: direct in-memory tests cover every extracted
  public method and the response-body branches without opening real sockets.
  The extracted boundary reached 98.88% line coverage (88/89).
- Risks or follow-ups: the broader gate passes 3,787 root tests plus 13 package
  tests at 74.30% line coverage. Continue with topology and discovery parsing
  before re-inventorying F5. Git writes remain deferred while the approval
  reviewer usage limit prevents updating the repository metadata.
