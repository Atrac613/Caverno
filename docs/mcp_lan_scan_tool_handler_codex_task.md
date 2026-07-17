# MCP Built-in LAN Scan Tool Handler Extraction

Status: completed on `feature/mcp-lan-scan-tool-handler`, stacked on
`feature/mcp-wifi-tool-handler`.

## Task

- Goal: extract built-in LAN scan definition exposure, argument normalization,
  execution, and failure handling from `McpToolService` into an independently
  tested application-internal handler.
- User-visible behavior: none. The same two definitions, ordering, direct
  execution behavior, argument conversions, result bytes, and error envelopes
  remain unchanged.
- Non-goals: changing `LanScanService`, changing scan limits or discovery
  behavior, performing live network scans in tests, changing tool capability
  policy, or moving the handler into an internal package.

## Context

- Affected components:
  - a new `BuiltInLanScanToolHandler`
  - the existing `LanScanTools` definition registry
  - `McpToolService` construction, registration, reservation, and dispatch
  - focused handler, service integration, and line-count ratchet tests
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 3
  - `docs/roadmap.md` F5
  - `docs/mcp_wifi_tool_handler_codex_task.md`
  - `docs/mcp_tool_result_normalization_codex_task.md`
- Reference pattern: the independent built-in BLE and WiFi handlers. Keep
  application composition in `McpToolService` and inject the existing
  `LanScanService` into the new boundary.
- Compatibility rules:
  - Preserve definition order from `lan_scan` through
    `lan_get_scan_results` and placement after WiFi and before serial tools.
  - Both names remain reserved against remote MCP collisions even when LAN
    scanning is unavailable or a definition is disabled.
  - Disabled definitions remain directly executable when a LAN scan service
    exists.
  - Without a LAN scan service, definitions remain hidden and LAN names
    continue to fall through to existing remote or fallback handling.
  - Trim optional `subnet` and `ip_version`, convert numeric `timeout` and
    `ports` values to integers, preserve port order, and default timeout to
    1000 milliseconds before invoking `LanScanService`.
  - Every string payload returned by `LanScanService` remains a successful
    result envelope without JSON reinterpretation.

## Implementation Notes

- Preferred approach:
  1. Characterize exact definition placement, unavailable and disabled
     behavior, collision reservation, and representative direct routing.
  2. Add a handler with explicit `toolNames`, `definitions`, `isAvailable`,
     `handles`, and `execute` surfaces. Reuse `LanScanTools` as the definition
     data source instead of duplicating schemas.
  3. Move the complete LAN execution switch into the handler and use
     `McpToolResultNormalizer` only to reproduce existing result envelopes.
  4. Test through a deterministic `LanScanService` subclass that records
     calls and returns synthetic payloads without starting network discovery.
  5. Replace service definition and dispatch blocks with thin handler
     delegation, then lower primary and aggregate line-count ratchets.
- Constraints:
  - Do not enumerate interfaces, probe hosts, run ping, read ARP/NDP state, or
    access mDNS in repository tests.
  - Preserve casts, integer conversion, trimming, defaults, call order, exact
    exception strings, and the existing log category.
  - Preserve the legacy unknown-name failure returned by the extracted
    execution switch.
  - Do not combine this slice with serial extraction.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `LanScanTools`, `_executeLanScanToolCall`, `lan_scan`,
  `lan_get_scan_results`, `lanScanService`, and `LanScanService`.
- Files or modules inspected: `McpToolService`, `LanScanTools`,
  `LanScanService`, provider construction, planning capability policy, routine
  tests, remote collision routing, and existing service tests.
- Follow-up tasks found: serial remains the next service-owned adapter, but its
  `serial_open` approval boundary requires a separate contract and must not be
  bundled into this extraction.

## Acceptance Criteria

- Required behavior:
  - the handler exposes both definitions in their current order and handles
    exactly their names.
  - service registration preserves global placement, availability, disabled
    filtering, and unconditional collision reservation.
  - scan and cached-result calls forward to the same service methods and
    retain exact payloads.
- Edge cases:
  - absent values forward `null`, `null`, 1000, and `null` for subnet,
    address family, timeout, and ports respectively.
  - surrounding whitespace is trimmed from subnet and address family.
  - numeric timeout and port values are converted with `toInt()` without
    handler-level clamping or reordering.
  - absent `sort_by` forwards `null`; supplied values forward unchanged.
  - malformed arguments and service exceptions become failed results with the
    unchanged exception string.
- Failure paths: unknown handler names return the legacy failed result and
  direct execution without a LAN scan service is rejected before dispatch.
- Accessibility, localization, or platform expectations: no UI or localized
  strings change; tests use a fake service and never access the network or
  platform discovery APIs.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/data/datasources/built_in_lan_scan_tool_handler_test.dart \
  --test test/features/chat/data/datasources/mcp_tool_service_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary: `BuiltInLanScanToolHandler` now owns the two ordered definitions,
  availability, argument normalization, execution, and compatible result
  envelopes. `McpToolService` retains application composition, global
  placement, disabled-definition filtering, and remote-name reservation.
- Tests run: the focused gate passed 103 root tests plus 13 internal-package
  tests. The full repository gate passed 3,539 root tests plus 13
  internal-package tests.
- Coverage or low-coverage notes: the full gate reached 72.84% line coverage
  (52,958/72,709). The new handler reached 96.43% (27/28), `LanScanTools`
  reached 95.45% (21/22), `McpToolService` reached 62.69% (526/839), and
  `LanScanService` reached 57.82% (244/422).
- Risks or follow-ups: live interfaces, host probes, ARP/NDP, and mDNS were
  intentionally not exercised. The next application-boundary slice should
  extract serial definitions and direct execution while preserving
  `serial_open` as a ChatNotifier-owned approval path.
