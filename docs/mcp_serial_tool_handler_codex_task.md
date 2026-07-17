# MCP Built-in Serial Tool Handler Extraction

Status: completed on `feature/mcp-serial-tool-handler`, stacked on
`feature/mcp-lan-scan-tool-handler`.

## Task

- Goal: extract built-in serial definition exposure, direct argument
  normalization, execution, and failure handling from `McpToolService` into an
  independently tested application-internal handler without moving the
  approved `serial_open` operation out of ChatNotifier.
- User-visible behavior: none. The same six definitions, ordering, platform
  exposure, five direct execution paths, result bytes, and error envelopes
  remain unchanged. Direct `serial_open` remains denied by `McpToolService`.
- Non-goals: changing `SerialPortService`, opening real ports in tests,
  changing approval or cache policy, moving pending approval state, changing
  serial schemas, or moving the handler into an internal package.

## Context

- Affected components:
  - a new `BuiltInSerialToolHandler`
  - the existing `SerialPortTools` definition registry
  - `McpToolService` construction, registration, reservation, and dispatch
  - focused handler, service integration, and line-count ratchet tests
- Approval boundary that must remain unchanged:
  - `_DeviceToolHandlerModule` maps `serial_open` to
    `ChatNotifier._handleSerialOpen`.
  - `ChatNotifierSerialHandlers` owns argument normalization for open,
    approval resolution, pending UI state, approval-result caching, provider
    lookup, and the actual `SerialPortService.open` call.
  - the extracted direct handler must return the existing internal denial if
    `serial_open` reaches `McpToolService`.
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 3
  - `docs/roadmap.md` F5
  - `docs/mcp_lan_scan_tool_handler_codex_task.md`
  - `docs/mcp_tool_result_normalization_codex_task.md`
- Reference pattern: the independent built-in BLE, WiFi, and LAN handlers.
  Keep application composition and the public `serialPortService` reference in
  `McpToolService` while injecting that service into the new boundary.
- Compatibility rules:
  - Preserve definition order from `serial_list_ports` through
    `serial_close` and placement after LAN scan and before Computer Use.
  - All six names remain reserved against remote MCP collisions even when the
    serial service is unavailable, definitions are disabled, or the platform
    is unsupported.
  - Definitions are exposed only when a service exists and
    `SerialPortService.isSupported` is true.
  - Direct routing remains available whenever a service exists, including on
    unsupported platforms where the service returns its existing JSON result.
  - Disabled definitions remain directly executable when a serial service
    exists, except `serial_open`, which retains its direct denial.
  - Every string payload returned by the five direct service methods remains
    a successful result envelope without JSON reinterpretation.

## Implementation Notes

- Preferred approach:
  1. Characterize exact definition order and placement, unsupported exposure,
     disabled direct routing, `serial_open` denial, and collision reservation.
  2. Add a handler with explicit `toolNames`, `definitions`, `isAvailable`,
     `canExposeDefinitions`, `handles`, and `execute` surfaces. Reuse
     `SerialPortTools` instead of duplicating schemas.
  3. Inject a platform-support predicate for deterministic tests while using
     `SerialPortService.isSupported` by default.
  4. Move the complete direct serial execution switch into the handler and use
     `McpToolResultNormalizer` only to reproduce existing envelopes.
  5. Test through a deterministic `SerialPortService` subclass that records
     calls and returns synthetic payloads without loading port inventory or
     touching hardware.
  6. Replace service definition and dispatch blocks with thin handler
     delegation, then lower primary and aggregate line-count ratchets.
- Constraints:
  - Do not enumerate, open, read, write, or close real serial devices in
    repository tests.
  - Preserve casts, trimming, integer conversion, defaults, field string
    conversion, call order, exact denial and exception strings, and the
    existing log category.
  - Do not modify ChatNotifier approval state, UI resolution, auto-review,
    caching, or `serialPortServiceProvider` execution.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `SerialPortTools`, `_executeSerialPortToolCall`,
  `serial_open`, `_handleSerialOpen`, `_DeviceToolHandlerModule`,
  `PendingSerialOpen`, `serialPortService`, and `SerialPortService.isSupported`.
- Files or modules inspected: `McpToolService`, `SerialPortTools`,
  `SerialPortService`, provider construction, ChatNotifier handler registry,
  serial approval extension, pending state, approval sheet tests, and remote
  collision routing.
- Follow-up tasks found: after serial extraction, choose the next
  application-boundary slice from the remaining service-owned adapters rather
  than changing the approval flow in the same branch.

## Acceptance Criteria

- Required behavior:
  - the handler exposes all six definitions in their current order and handles
    exactly their names.
  - service registration preserves platform exposure, global placement,
    disabled filtering, direct routing, and unconditional collision
    reservation.
  - list, read, decode, write, and close forward to the same service methods
    and retain exact payloads.
  - `serial_open` remains mapped to ChatNotifier and returns the exact existing
    denial when invoked directly through `McpToolService`.
- Edge cases:
  - read preserves port trimming; encoding, clear, max-frame, and stats
    defaults; optional numeric conversions; and frame delimiter forwarding.
  - decode preserves optional data, trimmed port, empty format default, field
    string conversion, and consume default.
  - write and close preserve trimmed ports plus data and encoding defaults.
  - JSON error payloads from direct service methods remain successful tool
    envelopes.
  - malformed arguments and service exceptions become failed results with the
    unchanged exception string.
- Failure paths: unknown handler names return the legacy direct-denial shape,
  and direct execution without a serial service is rejected before dispatch.
- Accessibility, localization, or platform expectations: no UI or localized
  strings change; tests use a fake service and never access serial hardware or
  native port inventory.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/data/datasources/built_in_serial_tool_handler_test.dart \
  --test test/features/chat/data/datasources/mcp_tool_service_test.dart \
  --test test/core/services/serial_port_service_test.dart \
  --test test/features/chat/presentation/widgets/approval/serial_open_approval_sheet_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary: `BuiltInSerialToolHandler` now owns ordered definition exposure,
  availability, direct argument normalization, five direct service calls,
  compatible result envelopes, and the direct `serial_open` denial.
  `McpToolService` retains composition, the public `serialPortService`
  reference, unconditional name reservation, and thin registration and
  dispatch delegation. The ChatNotifier-owned approved open path is unchanged.
- Tests run: the focused verifier passed 124 root tests plus 13
  internal-package tests. The full repository gate passed 3,551 root tests
  plus 13 internal-package tests with root and package analysis clean.
- Coverage or low-coverage notes: full repository line coverage was 72.90%.
  The extracted handler reached 98.18% and `SerialPortTools` reached 98.44%.
  `SerialPortService` remained at 24.00% and the ChatNotifier serial approval
  extension remained at 1.67%; this extraction intentionally used a
  deterministic service subclass rather than native inventory or hardware.
- Risks or follow-ups: preserve the ChatNotifier-owned `serial_open` approval
  path and keep all real hardware validation outside deterministic repository
  tests. The next isolated application-boundary slice is SSH definition and
  service-side dispatch extraction; keep connection and command approval in
  ChatNotifier and do not combine that work with Computer Use policy changes.
