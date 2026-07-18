# Network Socket Tools Extraction

Status: complete on the current F5 refactoring stack.

## Task

- Goal: move raw TCP port checks, TLS certificate inspection, and WHOIS
  execution out of `network_tools.dart` behind injectable socket connectors.
- User-visible behavior: none. Existing public method signatures, JSON payloads,
  timeout values, WHOIS server routing, referrals, truncation, and errors remain
  compatible.
- Non-goals: HTTP, DNS, routing, interface inspection, neighbor caches, mDNS,
  ping, traceroute, process execution, certificate policy, or tool schemas.

## Current Behavior Contract

- `portCheck` reports host, port, open state, and response time on success. A
  `SocketException` becomes an open-false payload with the exception message.
- Successful and failed port checks preserve their current asymmetric timing
  fields and always destroy a connected socket.
- `sslCertificate` accepts an invalid peer certificate so metadata remains
  inspectable, destroys the socket, reports an explicit missing-certificate
  error, and otherwise returns subject, issuer, validity, current validity, and
  SHA-1 fingerprint fields.
- WHOIS normalizes the query to trimmed lowercase text, selects the existing
  TLD registry, queries TCP port 43 with ten-second connect and stream timeouts,
  follows a distinct registrar referral when present, falls back to the first
  response when the referral fails or is empty, and caps returned text at 4,000
  characters plus the existing suffix.

## Implementation Notes

1. Add `NetworkSocketTools` with injected plain and secure socket connectors
   plus an injected clock for deterministic certificate validity tests.
2. Move the three public operations and their WHOIS-only private helpers.
3. Leave exact-signature static delegates in `NetworkTools`.
4. Add direct fake-socket tests covering success, failure, certificate and
   missing-certificate paths, registry selection, normalization, referral,
   fallback, timeout configuration, writes, cleanup, and truncation.
5. Lower exact line-count ratchets for the source and extracted boundary.

## Constraints

- Do not open real sockets in tests.
- Do not add a WHOIS package or external endpoint dependency.
- Do not change certificate acceptance, validity boundaries, registry values,
  response key names, or error propagation.
- Do not move adjacent process-backed or parser-heavy network operations.
- Generated files needed: none.

## Similar-Pattern Search

- Search terms: `Socket.connect`, `SecureSocket.connect`, `portCheck`,
  `sslCertificate`, `whoisLookup`, `_queryWhoisServer`, `_whoisServerForTld`,
  `_extractTld`, and `_truncate`.
- Files inspected: network tools, built-in network handler, MCP compatibility
  tests, network tests, file-size ratchets, refactoring plan, and ROADMAP.

## Acceptance Criteria

- Existing callers continue using unchanged `NetworkTools` APIs.
- The extracted component imports only Dart SDK libraries.
- Direct tests execute every branch without real network access.
- Socket targets, ports, timeouts, writes, referral order, and cleanup are
  directly asserted.
- Focused network and MCP compatibility tests plus the repository gate pass.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/data/datasources/network_socket_tools_test.dart \
  --test test/features/chat/data/datasources/network_tools_test.dart \
  --test test/features/chat/data/datasources/mcp_tool_service_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run `tool/codex_verify.sh --coverage --no-codegen` before closing F5.

## Handoff Notes

- Summary: extracted port checks, TLS certificate inspection, and WHOIS behind
  injected socket connectors and a deterministic clock while preserving the
  static `NetworkTools` API and payloads.
- Tests run: targeted analysis passes; the focused network and MCP gate passes
  all 171 tests; the full repository gate passes 3,787 root tests plus 13
  internal-package tests; root and package analysis report no findings.
- Coverage or low-coverage notes: the extracted boundary reached 93.65% line
  coverage (59/63). The four uncovered lines are the production connector
  wrappers that would open real sockets; all injected behavior branches are
  covered. Overall line coverage is 74.30% (52,722/70,954).
- Risks or follow-ups: continue with topology and discovery parsing, then
  refresh the oversized inventory. Git writes remain deferred while the
  approval reviewer usage limit prevents updating repository metadata.
