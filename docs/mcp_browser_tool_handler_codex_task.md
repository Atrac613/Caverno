# MCP Built-in Browser Tool Handler Extraction

Status: complete on `feature/mcp-browser-tool-handler`, stacked on
`feature/mcp-ssh-tool-handler`.

## Task

- Goal: extract built-in browser definition exposure, availability, argument
  normalization, service dispatch, and compatible result normalization from
  `McpToolService` into an independently tested application-internal handler
  without moving sensitive browser approval or redaction out of ChatNotifier.
- User-visible behavior: none. The same 12 definitions, ordering, service
  availability, direct execution paths, argument conversions, JSON result
  interpretation, and unknown-prefix behavior remain unchanged.
- Non-goals: changing `BrowserSessionService`, `BrowserToolPolicy`, approval or
  auto-review policy, pending approval state, secret redaction, save-target
  previews, browser schemas, browser panel behavior, or packaging the handler.

## Context

- Affected components:
  - a new `BuiltInBrowserToolHandler`
  - `McpToolService` construction, registration, reservation, and dispatch
  - focused handler, service integration, and line-count ratchet tests
- Approval boundary that must remain unchanged:
  - `ChatToolDispatcher` routes sensitive browser tools to
    `ChatNotifier._handleBrowserAction` and read/observe tools to
    `_handleBrowserActionWithoutApproval`.
  - `ChatNotifierBrowserHandlers` owns approval resolution, reviewer argument
    redaction, warning and target summaries, pending UI state, secret previews,
    save-target resolution for review, and denial results.
  - after approval, ChatNotifier delegates to `McpToolService`; the extracted
    handler may execute only at that existing service boundary.
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 3
  - `docs/roadmap.md` F5
  - `docs/mcp_ssh_tool_handler_codex_task.md`
  - `docs/mcp_tool_result_normalization_codex_task.md`
- Reference pattern: the independent built-in device and SSH handlers. Keep
  application composition and the public `browserService` reference in
  `McpToolService` while injecting that service into the new boundary.
- Compatibility rules:
  - Preserve definition order from `browser_open` through `browser_save_data`
    and placement after Computer Use and before remote MCP tools.
  - All exact names and the `browser_` prefix remain reserved against remote
    MCP collisions even when the browser service is unavailable or definitions
    are disabled.
  - Definitions are exposed only when the browser service reports available.
  - Disabled definitions remain directly executable when the service is
    available.
  - Every `browser_*` name remains routed as a browser call. Unknown prefixed
    names retain their structured `tool_not_available` result when available
    and their existing unavailable result otherwise.
  - JSON payloads continue through `McpToolResultNormalizer.fromOkPayload`
    with the exact `Browser tool failed` fallback.

## Implementation Notes

- Preferred approach:
  1. Characterize exact definition order and placement, unavailable and
     disabled behavior, every argument conversion and default, JSON success
     and failure normalization, unknown-prefix routing, and collision policy.
  2. Add a handler with explicit `toolNames`, `definitions`, `isAvailable`,
     `handles`, and `execute` surfaces. Keep prefix handling distinct from the
     exact definition-name registry.
  3. Move the complete browser dispatch switch and schemas into the handler.
  4. Test through a deterministic `BrowserSessionService` subclass that
     records every call and returns synthetic JSON without mounting a webview
     or writing files.
  5. Replace service definition and dispatch blocks with thin handler
     delegation, then lower primary and aggregate line-count ratchets.
- Constraints:
  - Do not mount a webview, browse the network, evaluate JavaScript, or write
    browser save files in handler tests.
  - Preserve selector trimming, ref parsing from int/num/string, numeric
    conversion, default values, call order, exact payload bytes, and current
    exception propagation.
  - Do not modify ChatNotifier approval, redaction, review packet, pending UI,
    save-target preview, or `browserSessionServiceProvider` behavior.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_browserTools`, `_executeBrowserTool`, `browserService`,
  `BrowserToolPolicy`, `BrowserSessionService`, `_handleBrowserAction`,
  `_handleBrowserActionWithoutApproval`, and `BrowserSaveTarget`.
- Files or modules inspected: `McpToolService`, `BrowserSessionService`,
  `BrowserToolPolicy`, `ChatToolDispatcher`, ChatNotifier browser approval
  extension, browser session tests, provider construction, and remote prefix
  collision routing.
- Follow-up tasks found: keep Computer Use definition and dispatch extraction
  separate because its transport, arming, approval, and audit perimeter is
  materially broader.

## Acceptance Criteria

- Required behavior:
  - the handler exposes all 12 definitions in their current order and handles
    the complete `browser_` prefix.
  - service registration preserves availability, global placement, disabled
    filtering, direct routing, and exact/prefix collision reservation.
  - all 12 operations forward to the same service methods with identical
    argument normalization and defaults.
  - successful and failed JSON payloads retain exact result bytes and current
    `McpToolResult` success and error interpretation.
  - sensitive actions remain classified and approved by ChatNotifier before
    the service handler executes them.
- Edge cases:
  - ref accepts int, numeric values, and numeric strings; invalid refs become
    null.
  - selectors are trimmed and empty selectors become null.
  - omitted format, history direction, script, filename, data, save format,
    and destination retain existing defaults.
  - unknown prefixed calls retain the exact structured unavailable payload.
  - service-unavailable calls retain the exact direct error result.
- Failure paths: malformed casts and service exceptions propagate exactly as
  before, while JSON `ok: false` payloads become failed results through the
  existing normalizer.
- Accessibility, localization, or platform expectations: no UI or localized
  strings change; tests use a fake service and never mount a webview or perform
  network, JavaScript, or filesystem side effects.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/data/datasources/built_in_browser_tool_handler_test.dart \
  --test test/features/chat/data/datasources/mcp_tool_service_test.dart \
  --test test/core/services/browser_session_service_test.dart \
  --test test/core/services/browser_tool_policy_test.dart \
  --test test/features/chat/domain/services/chat_tool_dispatcher_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary: `BuiltInBrowserToolHandler` now owns all 12 ordered definitions,
  availability, prefix routing, argument normalization, service dispatch, and
  compatible JSON result normalization. `McpToolService` remains the public
  facade and retains the public `browserService` reference while delegating
  registration and direct execution through an injectable handler.
- Tests run:
  - characterization: 91 `McpToolService` tests passed before extraction
  - focused gate: 143 root tests plus 13 internal-package tests passed with
    project and package analysis clean
  - full gate: 3,578 root tests plus 13 internal-package tests passed with
    project and package analysis clean
- Coverage: repository line coverage is 73.47% (51,985/70,756), the extracted
  handler is 100.00% (140/140), `McpToolService` is 80.91% (513/634), the
  dispatcher is 100.00% (21/21), and the ChatNotifier browser approval adapter
  is 72.73% (104/143).
- Size: `McpToolService` fell from 2,191 to 1,861 lines and its same-library
  aggregate fell from 2,283 to 1,953 lines. The handler is independently
  ratcheted at 395 lines.
- Safety: deterministic tests use a fake `BrowserSessionService`; they do not
  mount a webview, access the network, evaluate JavaScript, or write save
  files. ChatNotifier-owned approval, smoke state, review redaction, pending
  UI, and save-target previews were not changed.
- Follow-up: characterize the 19 Computer Use definitions and post-approval
  service dispatch before extracting them. Keep policy classification, target
  safety, action-time confirmation, smoke arming, audit, and emergency-stop
  behavior outside the service adapter and unchanged.
