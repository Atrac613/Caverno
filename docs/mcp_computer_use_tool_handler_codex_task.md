# MCP Built-in Computer Use Tool Handler Extraction

Status: complete on `feature/mcp-computer-use-tool-handler`, stacked on
`feature/mcp-browser-tool-handler`.

## Task

- Goal: extract the 19 built-in Computer Use definitions, availability,
  service dispatch, and compatible result normalization from `McpToolService`
  into an independently tested application-internal handler without moving any
  safety policy or approval behavior.
- User-visible behavior: none. Definition order and placement, direct routing,
  argument forwarding and defaults, result bytes, error interpretation, and
  unknown-prefix behavior remain unchanged.
- Non-goals: changing `MacosComputerUseService`, transport selection, tool
  policy, target safety, planning restrictions, action-time confirmation,
  approval caching, smoke arming, audit logging, post-action observation,
  emergency-stop behavior, schemas, or packaging the handler.

## Context

- Affected components:
  - a new `BuiltInComputerUseToolHandler`
  - `McpToolService` construction, registration, reservation, and dispatch
  - focused handler, service integration, and line-count ratchet tests
- Safety boundary that must remain unchanged:
  - `ChatToolDispatcher` uses `MacosComputerUseToolPolicy` before service
    execution to split approval-gated actions from observation operations.
  - `ChatNotifierComputerUseHandlers` owns denial caching, target and exact-text
    safety decisions, approval copy, pending UI state, action-time approval,
    smoke arming, audit records, result redaction, and post-action observation.
  - approved and observation calls then delegate to `McpToolService`; the new
    handler may execute only at this existing service boundary.
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 3
  - `docs/roadmap.md` F5
  - `docs/mcp_browser_tool_handler_codex_task.md`
  - `docs/mcp_tool_result_normalization_codex_task.md`
- Reference pattern: `BuiltInBrowserToolHandler` preserves a prefix namespace
  while leaving interactive approval in ChatNotifier. Keep application
  composition and the public `computerUseService` reference in
  `McpToolService` while injecting that service into the new boundary.
- Compatibility rules:
  - Preserve the exact order from `computer_get_permissions` through
    `computer_stop_system_audio_recording` and placement after serial tools and
    before browser tools.
  - All exact names and the `computer_` prefix remain reserved against remote
    MCP collisions even when the service is unavailable or definitions are
    disabled.
  - Definitions remain available only when the service reports available.
  - Disabled definitions remain directly executable when the service is
    available.
  - Every `computer_*` name remains routed as a Computer Use call. Unknown
    prefixed names retain their structured `tool_not_available` result when
    available and their existing unavailable result otherwise.
  - JSON payloads continue through `McpToolResultNormalizer.fromOkPayload`
    with the exact `Computer use tool failed` fallback.

## Implementation Notes

- Preferred approach:
  1. Characterize exact definition order and placement, unavailable and
     disabled behavior, all 19 service operations, permission defaults and
     legacy aliases, result normalization, unknown-prefix routing, and
     collision policy.
  2. Add a handler with explicit `toolNames`, `definitions`, `isAvailable`,
     `handles`, and `execute` surfaces. Keep prefix handling distinct from the
     exact definition-name registry.
  3. Move only the complete service dispatch switch and schemas into the
     handler.
  4. Test through a deterministic `MacosComputerUseService` subclass that
     records calls and returns synthetic JSON without opening System Settings,
     requesting permissions, capturing the screen, recording audio, or
     generating desktop input.
  5. Replace service definition and dispatch blocks with thin handler
     delegation, then lower primary and aggregate line-count ratchets.
- Constraints:
  - Preserve the `screen_capture` to legacy `screenCapture` fallback and true
    defaults for both permission flags.
  - Preserve the default System Settings section, exact argument map
    forwarding for all other operations, the argument-free stop-audio call,
    exact payload bytes, and current exception propagation.
  - Do not modify ChatNotifier Computer Use handlers, the dispatcher, tool
    policy, approval copy, audit log, transport, service provider, or UI.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_computerUseTools`, `_executeComputerUseTool`,
  `computerUseService`, `MacosComputerUseToolPolicy`,
  `_handleComputerUseAction`, `_handleComputerUseActionWithoutApproval`,
  `requiresSmokeArming`, `MacosComputerUseAuditLog`, and `computer_`.
- Files or modules inspected: `McpToolService`, `MacosComputerUseService`,
  `MacosComputerUseToolPolicy`, `ChatToolDispatcher`, ChatNotifier Computer Use
  handlers, provider construction, approval-cache regression tests, service
  tests, and remote prefix collision routing.
- Follow-up tasks found: the service adapter extraction must not be combined
  with any approval-cache, arming, transport, audit, or policy refactor.

## Acceptance Criteria

- Required behavior:
  - the handler exposes all 19 definitions in their current order and handles
    the complete `computer_` prefix.
  - service registration preserves availability, global placement, disabled
    filtering, direct routing, and exact and prefix collision reservation.
  - all 19 operations call the same service methods with identical arguments
    and defaults.
  - successful and failed JSON payloads retain exact result bytes and current
    `McpToolResult` success and error interpretation.
  - policy classification, planning restrictions, approval, arming, audit,
    emergency stop, and post-action observation remain outside the handler.
- Edge cases:
  - permission requests default both flags to true.
  - `screen_capture` wins over the legacy `screenCapture` alias.
  - the System Settings section defaults to `privacy`.
  - stop-audio ignores arguments and calls the argument-free service method.
  - unknown prefixed calls retain the exact structured unavailable payload.
  - service-unavailable calls retain the exact direct error result.
- Failure paths: malformed casts and service exceptions propagate exactly as
  before, while JSON `ok: false` payloads become failed results through the
  existing normalizer.
- Accessibility, localization, or platform expectations: no UI or localized
  strings change; tests use a fake service and perform no permission, screen,
  audio, pointer, keyboard, System Settings, or IPC side effects.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/data/datasources/built_in_computer_use_tool_handler_test.dart \
  --test test/features/chat/data/datasources/mcp_tool_service_test.dart \
  --test test/core/services/macos_computer_use_tool_policy_test.dart \
  --test test/features/chat/domain/services/chat_tool_dispatcher_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary: `BuiltInComputerUseToolHandler` now owns the exact ordered 19-tool
  family, availability, complete prefix routing, argument compatibility,
  post-approval native service dispatch, and JSON result normalization.
  `McpToolService` retains application composition and its public
  `computerUseService` reference while delegating definitions and execution to
  the injected handler. Its primary file fell from 1,861 to 1,202 lines and
  its same-library aggregate fell from 1,953 to 1,294 lines; the new handler is
  independently ratcheted at 714 lines.
- Tests run: the focused verifier passed 154 root tests plus 13 internal-package
  tests. The first full run exposed three structural smoke assertions that
  still searched the old facade for Computer Use schema text; M43, M44, and
  M45 now inspect the extracted handler and each passed independently. The
  final full verifier passed 3,589 root tests plus 13 internal-package tests.
- Coverage or low-coverage notes: final line coverage was 73.15% overall. The
  new handler reached 100.00% (230/230), `MacosComputerUseToolPolicy` reached
  91.91% (216/235), `ChatToolDispatcher` reached 100.00% (21/21), and the
  ChatNotifier Computer Use handlers reached 89.95% (340/378).
- Risks or follow-ups: all policy classification, target safety, action-time
  confirmation, approval caching, smoke arming, audit, result redaction,
  emergency stop, and post-action observation remain upstream and unchanged.
  Deterministic tests performed no permission, screen, audio, pointer,
  keyboard, System Settings, IPC, or other real desktop side effects. Move the
  next large-file slice to the Computer Use settings presentation boundary
  instead of extending this adapter extraction into unrelated facade tools.
