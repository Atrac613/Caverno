# MCP Built-in WiFi Tool Handler Extraction

Status: completed on `feature/mcp-wifi-tool-handler`, stacked on
`feature/mcp-ble-tool-handler`.

## Task

- Goal: extract built-in WiFi definition exposure, execution, and failure
  handling from `McpToolService` into an independently tested
  application-internal handler.
- User-visible behavior: none. The same three tool definitions, ordering,
  direct execution behavior, result bytes, and error envelopes remain
  unchanged.
- Non-goals: changing `WifiService`, requesting platform permissions in tests,
  adding connection mutation tools, changing result-envelope semantics, or
  moving the handler into an internal package.

## Context

- Affected components:
  - a new `BuiltInWifiToolHandler`
  - the existing `WifiTools` definition registry
  - `McpToolService` construction, registration, reservation, and dispatch
  - focused handler, service integration, and line-count ratchet tests
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 3
  - `docs/roadmap.md` F5
  - `docs/mcp_ble_tool_handler_codex_task.md`
  - `docs/mcp_tool_result_normalization_codex_task.md`
- Reference pattern: the independent built-in BLE, network, filesystem, and
  local command handlers. Keep application composition in `McpToolService` and
  inject the existing `WifiService` into the new boundary.
- Compatibility rules:
  - Preserve exact definition order from `wifi_scan` through
    `wifi_get_connection_info` and placement after BLE and before LAN scan.
  - All three names remain reserved against remote MCP collisions even when
    WiFi is unavailable or a definition is disabled.
  - Disabled definitions remain directly executable when a WiFi service
    exists.
  - Without a WiFi service, definitions remain hidden and WiFi names continue
    to fall through to existing remote or fallback handling.
  - JSON payloads returned by `WifiService`, including payloads that describe
    unsupported platforms or permission errors, remain successful tool result
    envelopes. This slice must not reinterpret their content.

## Implementation Notes

- Preferred approach:
  1. Characterize the exact ordered definitions and representative schemas.
  2. Add a handler with explicit `toolNames`, `definitions`, `isAvailable`,
     `handles`, and `execute` surfaces. Reuse `WifiTools` as the definition data
     source instead of duplicating schemas.
  3. Move the complete WiFi execution switch into the handler and use
     `McpToolResultNormalizer` only to reproduce the existing envelopes.
  4. Test through a deterministic `WifiService` subclass that records calls
     and returns synthetic payloads without invoking platform plugins.
  5. Replace service definition and dispatch blocks with thin handler
     delegation, then lower primary and aggregate line-count ratchets.
- Constraints:
  - Do not scan, query permissions, or read live connection information in
    repository tests.
  - Preserve the optional `sort_by` cast and forwarding without normalization.
  - Preserve exact exception strings and the existing log category.
  - Do not combine this slice with LAN or serial extraction.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `WifiTools`, `_executeWifiToolCall`, `wifi_scan`,
  `wifi_get_scan_results`, `wifi_get_connection_info`, and `wifiService`.
- Files or modules inspected: `McpToolService`, `WifiTools`, `WifiService`,
  provider construction, tool capability tests, result prompt tests, remote
  collision routing, and existing service tests.
- Follow-up tasks found: LAN scan and serial remain separate service-owned
  adapters. Their capability and approval semantics differ, so they should not
  be bundled into this extraction.

## Acceptance Criteria

- Required behavior:
  - the handler exposes all three definitions in their current order and
    handles exactly their names.
  - service registration preserves global placement, availability, disabled
    filtering, and unconditional collision reservation.
  - scan, cached scan results, and current connection information forward to
    the same service methods and retain exact payloads.
- Edge cases:
  - absent `sort_by` forwards `null`; supplied values forward unchanged.
  - service JSON that represents an unsupported or failed operation remains a
    successful result envelope.
  - argument cast and service exceptions become failed results with the
    unchanged exception string.
- Failure paths: unknown names are rejected before service invocation, and
  direct execution without a WiFi service is rejected before dispatch.
- Accessibility, localization, or platform expectations: no UI or localized
  strings change; tests use a fake service and never access WiFi hardware or
  platform permission APIs.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/data/datasources/built_in_wifi_tool_handler_test.dart \
  --test test/features/chat/data/datasources/mcp_tool_service_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary: `BuiltInWifiToolHandler` now owns the three ordered definitions,
  availability, exact argument forwarding, execution, and compatible result
  envelopes. `McpToolService` retains application composition, global
  placement, disabled-definition filtering, and remote-name reservation.
- Tests run: the focused gate passed 97 root tests plus 13 internal-package
  tests. The full repository gate passed 3,529 root tests plus 13
  internal-package tests.
- Coverage or low-coverage notes: the full gate reached 72.71% line coverage
  (52,863/72,700). The new handler reached 95.45% (21/22), `WifiTools`
  reached 94.44% (17/18), and `McpToolService` reached 60.84% (522/858).
- Risks or follow-ups: real WiFi permissions and hardware were intentionally
  not exercised. The next application-boundary slice should extract the two
  built-in LAN scan tools while preserving subnet, address-family, port,
  timeout, result-ordering, placement, and collision behavior.
