# MCP Built-in BLE Tool Handler Extraction

Status: completed on `feature/mcp-ble-tool-handler`, stacked on
`feature/mcp-result-normalization`.

## Task

- Goal: extract built-in BLE definition exposure, argument normalization,
  execution, formatting, and failure handling from `McpToolService` into an
  independently tested application-internal handler.
- User-visible behavior: none. The same 16 tool definitions, ordering, direct
  execution behavior, result text, errors, encodings, and approval boundary
  remain unchanged.
- Non-goals: changing `BleService`, adding BLE operations, moving connection
  approval out of ChatNotifier, accessing real BLE hardware in tests, changing
  result envelopes, or moving the handler into an internal package.

## Context

- Affected components:
  - a new `BuiltInBleToolHandler`
  - existing `BleTools` definition registry
  - `McpToolService` construction, registration, reservation, and dispatch
  - focused handler, service, ChatNotifier approval, and ratchet tests
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 3
  - `docs/roadmap.md` F5
  - `docs/mcp_tool_result_normalization_codex_task.md`
  - `docs/mcp_network_tool_handler_codex_task.md`
- Reference pattern: the independent built-in network, filesystem, and local
  command handlers. Keep application composition in `McpToolService` and inject
  the existing `BleService` into the new boundary.
- Compatibility rules:
  - Preserve exact definition order from `ble_start_scan` through
    `ble_get_peripheral_state` and preserve placement after SSH and before WiFi.
  - All 16 names remain reserved against remote MCP collisions even when BLE is
    unavailable or a definition is disabled.
  - Disabled definitions remain directly executable when a BLE service exists.
  - Without a BLE service, definitions remain hidden and BLE names continue to
    fall through to existing remote/fallback handling.
  - `ble_connect` remains intercepted and approved by ChatNotifier; direct
    handler execution returns the existing internal error.

## Implementation Notes

- Preferred approach:
  1. Characterize the exact name and definition order plus representative
     schemas before integration.
  2. Add a handler with explicit `toolNames`, `definitions`, `isAvailable`,
     `handles`, and `execute` surfaces. Reuse `BleTools` as the definition data
     source rather than duplicating its schemas.
  3. Move the complete BLE execution switch and its value-decoding helpers into
     the handler.
  4. Test through a deterministic `BleService` subclass that records calls and
     returns synthetic devices, notifications, services, and peripheral state.
  5. Replace service definition and dispatch blocks with thin handler
     delegation, then lower primary and aggregate ratchets.
- Constraints:
  - Do not initialize central or peripheral platform managers in tests.
  - Preserve exact trimming, defaults, clamps, casts, output newlines, and error
    strings.
  - Preserve `withResponse` as the default and treat only the exact
    `withoutResponse` value as the alternate write type.
  - Preserve hex separator removal and the existing ignored trailing nibble for
    odd-length hex input.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `BleTools`, `_executeBleToolCall`, `ble_connect`,
  `_decodeValueForWrite`, `_hexDecodeValue`, `_missingParam`, `bleService`, and
  `pendingBleConnect`.
- Files or modules inspected: `McpToolService`, `BleTools`, `BleService`,
  ChatNotifier BLE handlers and approval sheets, tool definition consumers,
  remote collision routing, and existing service tests.
- Follow-up tasks found: WiFi, LAN scan, and serial execution remain smaller
  service-owned adapters. Computer Use and browser definitions are much larger
  and should remain separate security-sensitive slices.

## Acceptance Criteria

- Required behavior:
  - the handler exposes all 16 definitions in their current order and handles
    exactly their names.
  - service registration preserves global placement, platform availability,
    disabled filtering, and unconditional collision reservation.
  - scan, scan results, disconnect, service discovery, characteristic read and
    write, subscription, state, advertising, service hosting, characteristic
    update, and peripheral state keep their exact outputs.
  - ChatNotifier remains the only path that performs an approved BLE connect.
- Edge cases:
  - scan timeout defaults to 10 seconds and clamps to 1 through 60.
  - empty scan results, unknown device names, no advertised services, and
    notification buffers retain their current formatting.
  - missing required fields retain exact comma-separated error messages.
  - hex, UTF-8, and base64 values plus both characteristic write types retain
    their current byte conversion.
  - malformed argument casts and service exceptions become failed results with
    the unchanged exception string.
- Failure paths: unknown names are rejected before service invocation and
  `ble_connect` returns the existing ChatNotifier-required error.
- Accessibility, localization, or platform expectations: no UI or localized
  strings change; tests use a fake service and never access Bluetooth hardware.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/data/datasources/built_in_ble_tool_handler_test.dart \
  --test test/features/chat/data/datasources/mcp_tool_service_test.dart \
  --test test/features/chat/presentation/widgets/approval/ble_connect_approval_sheet_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary: `BuiltInBleToolHandler` now owns the 16 ordered BLE definitions,
  availability, argument normalization, execution, formatting, value decoding,
  and compatible result envelopes. `McpToolService` retains construction,
  global ordering, disabled filtering, unconditional remote-name reservation,
  and thin dispatch. ChatNotifier still intercepts and approves `ble_connect`.
- Tests run:
  - the focused verifier passed 99 root tests plus 13 internal-package tests
    with no analyzer findings.
  - the full repository coverage gate passed 3,521 root tests plus 13
    internal-package tests with no generated-file drift or analyzer findings.
- Coverage or low-coverage notes:
  - repository line coverage is 72.98% (51,592/70,691).
  - `BuiltInBleToolHandler` is 99.41% covered (169/170), and the reused
    `BleTools` definition registry is 99.29% covered (139/140).
  - `McpToolService` is 59.27% covered (518/874); its remaining uncovered
    surface spans unrelated built-in adapters and facade paths.
- Risks or follow-ups: deterministic tests do not access Bluetooth hardware.
  Preserve the existing ChatNotifier BLE connection approval boundary and use
  a separate manual device smoke if platform interoperability changes. The next
  small service-owned adapter is the three-tool built-in WiFi family.
