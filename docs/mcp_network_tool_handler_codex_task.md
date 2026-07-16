# MCP Built-in Network Tool Handler Extraction

Status: completed on `feature/mcp-network-tool-handler`.

## Task

- Goal: extract the built-in network tool family from `McpToolService` into an
  independently testable application-internal handler.
- User-visible behavior: none. Tool names, schemas, defaults, validation,
  result envelopes, ordering, disabled-tool filtering, and remote collision
  handling must remain unchanged.
- Non-goals: changing `NetworkTools`, adding network features, moving code into
  an internal package, changing approval policy, or adding a live network
  canary.

## Context

- Affected components:
  - `lib/features/chat/data/datasources/mcp_tool_service.dart`
  - `lib/features/chat/data/datasources/network_tools.dart`
  - a new `built_in_network_tool_handler.dart`
  - focused data-source and line-ratchet tests
- Related docs: `docs/large_file_refactor_plan.md` Phase 3 and
  `docs/roadmap.md` milestone F5.
- Reference pattern: an independent root-application class injected into the
  composition service. Do not add another Dart `part`.
- Compatibility rules:
  - Preserve all 21 reserved names: `ping`, `ping6`, `arp`, `ndp`,
    `route_lookup`, `interface_info`, `whois_lookup`, `dns_lookup`,
    `dns_query`, `port_check`, `ssl_certificate`, `http_status`, `http_get`,
    `http_head`, `http_post`, `http_put`, `http_patch`, `http_delete`,
    `traceroute`, `path_mtu`, and `mdns_browse`.
  - Disabled built-ins remain hidden from definitions but reserved names still
    prevent remote tool collisions.
  - Direct execution remains available for a known built-in name even when its
    definition is disabled, matching current service behavior.
  - A successfully executed operation remains a successful `McpToolResult`
    even when its JSON payload reports a negative network fact.

## Implementation Notes

- Preferred approach:
  1. Add characterization for the exact name set, schema ordering, disabled
     filtering, remote collision behavior, validation, and representative
     normalization defaults and clamps.
  2. Introduce `BuiltInNetworkToolHandler` with explicit `toolNames`,
     `definitions`, `handles`, and `execute` surfaces.
  3. Inject a narrow operation runner so unit tests never open sockets, launch
     ping processes, or query DNS. The production adapter delegates to the
     existing `NetworkTools` methods.
  4. Replace the service's definition block and execution chain with thin
     handler delegation.
  5. Lower the `McpToolService` primary and aggregate ratchets and add a ratchet
     for the independent handler.
- Constraints:
  - Keep the handler in the root application. `network_tools.dart` depends on
    `dart:io`, `dart_ping`, and `multicast_dns`, and there is no stable second
    consumer that justifies a package boundary.
  - Preserve exact error messages, header coercion, method-specific arguments,
    defaults, and clamp ranges.
  - Keep the registration order between routine tools and file inspection
    tools.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_reservedToolNames`, `Built-in network tools`, `_pingTool`,
  `NetworkTools.`, `_parseHeaderMap`, and remote tool name collisions.
- Files or modules inspected: `mcp_tool_service.dart`,
  `mcp_tool_service_connection.dart`, `network_tools.dart`,
  `mcp_tool_service_test.dart`, `network_tools_test.dart`, and the file-size
  ratchet.
- Follow-up tasks found: filesystem, Git, and shell adapter extraction; MCP
  connection and trust handling; result normalization.

## Acceptance Criteria

- Required behavior:
  - All 21 definitions are byte-for-byte structurally equivalent and retain
    their order.
  - `McpToolService.executeTool` delegates every network name to the handler.
  - All non-network tools keep their existing routing.
  - Remote tools cannot shadow any built-in network name.
- Edge cases:
  - Required blank arguments fail without invoking the operation runner.
  - Numeric defaults and clamps, HTTP headers/body/content type, redirects,
    mDNS defaults, and optional filters are preserved.
  - Unknown names are not handled.
- Failure paths:
  - Runner exceptions produce the same unsuccessful result and error text as
    the existing service path.
  - JSON payloads that describe closed ports or other negative facts remain
    successful executions.
- Platform expectations: no platform gating changes and no live network access
  in handler unit tests.

## Verification

Run focused checks after each implementation commit:

```bash
tool/codex_verify.sh \
  --no-codegen \
  --test test/features/chat/data/datasources/built_in_network_tool_handler_test.dart \
  --test test/features/chat/data/datasources/mcp_tool_service_test.dart \
  --test test/features/chat/data/datasources/network_tools_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary: extracted all 21 network definitions and execution normalization
  into `BuiltInNetworkToolHandler`; `McpToolService` now registers and routes
  the family through the injected handler. Primary and aggregate service
  ratchets fell from 5,269/5,612 to 4,096/4,439, and the handler is ratcheted
  at 978 lines.
- Tests run: the canonical focused verifier passed 74 root tests plus 13
  internal-package tests. `tool/codex_verify.sh --coverage` passed 3,432 root
  tests plus the package gate with no analyzer or generated-file findings.
- Coverage or low-coverage notes: repository line coverage is 72.16%; the new
  handler is 72.22% covered without live network access. `network_tools.dart`
  remains at 39.31% because this behavior-preserving slice did not exercise
  platform or live network operations.
- Risks or follow-ups: the production runner mapping remains covered by static
  review and existing `NetworkTools` tests rather than live network calls. The
  next F5 slice is a separate filesystem handler that preserves platform
  gating, disabled-definition/direct-execution behavior, remote collisions,
  and rollback checkpoint ownership.
