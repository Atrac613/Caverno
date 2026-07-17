# MCP Built-in SSH Tool Handler Extraction

Status: completed on `feature/mcp-ssh-tool-handler`, stacked on
`feature/mcp-serial-tool-handler`.

## Task

- Goal: extract built-in SSH definition exposure, approved command execution,
  disconnect execution, and compatible failure handling from `McpToolService`
  into an independently tested application-internal handler without moving
  connection or command approval out of ChatNotifier.
- User-visible behavior: none. The same three definitions, ordering, service
  availability, command formatting, disconnect results, and error envelopes
  remain unchanged. Direct `ssh_connect` remains denied by `McpToolService`.
- Non-goals: changing `SshService`, connection credentials, approval or cache
  policy, pending approval state, SSH schemas, remote command semantics, or
  moving the handler into an internal package.

## Context

- Affected components:
  - a new `BuiltInSshToolHandler`
  - `McpToolService` construction, registration, reservation, and dispatch
  - focused handler, service integration, and line-count ratchet tests
- Approval boundary that must remain unchanged:
  - `_SshToolHandlerModule` maps `ssh_connect` and `ssh_execute_command` to
    their ChatNotifier handlers.
  - `ChatNotifierSshHandlers` owns connection argument normalization,
    credential lookup, approval resolution, pending UI state, approval-result
    caching, the actual `SshService.connect` call, and per-command approval.
  - after command approval, ChatNotifier delegates `ssh_execute_command` to
    `McpToolService`; the extracted handler may execute only at that boundary.
  - the extracted handler must return the existing internal denial if
    `ssh_connect` reaches `McpToolService`.
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 3
  - `docs/roadmap.md` F5
  - `docs/mcp_serial_tool_handler_codex_task.md`
  - `docs/mcp_tool_result_normalization_codex_task.md`
- Reference pattern: the independent built-in BLE, WiFi, LAN, and serial
  handlers. Keep application composition and the public `sshService` reference
  in `McpToolService` while injecting that service into the new boundary.
- Compatibility rules:
  - Preserve definition order from `ssh_connect` through `ssh_disconnect` and
    placement after Git and before BLE.
  - All three names remain reserved against remote MCP collisions even when
    the SSH service is unavailable or definitions are disabled.
  - Definitions are exposed only when an SSH service exists.
  - Disabled definitions remain directly routed with the current behavior.
  - Direct `ssh_connect` returns the exact existing internal-error result with
    or without an SSH service.
  - `ssh_execute_command` preserves unavailable-service and inactive-session
    errors, command trimming, empty-command rejection, exact formatted output,
    and exception conversion.
  - `ssh_disconnect` remains idempotent when the service is unavailable or
    inactive and preserves its connected, inactive, and exception results.

## Implementation Notes

- Preferred approach:
  1. Characterize exact definition order and placement, unavailable and
     disabled behavior, direct connect denial, execute and disconnect results,
     and collision reservation.
  2. Add a handler with explicit `toolNames`, `definitions`, `isAvailable`,
     `handles`, and `execute` surfaces.
  3. Move the complete service-side SSH dispatch into the handler and use
     `McpToolResultNormalizer` only where it reproduces existing envelopes.
  4. Test through a deterministic `SshService` subclass that overrides session
     state, command execution, and disconnect without opening sockets.
  5. Replace service definition and dispatch blocks with thin handler
     delegation, then lower primary and aggregate line-count ratchets.
- Constraints:
  - Do not open real sockets, authenticate, read credentials, or contact SSH
    hosts in repository tests.
  - Preserve trimming, call order, exact result bytes, exact denial and
    exception strings, and existing log categories.
  - Do not modify ChatNotifier approval state, UI resolution, auto-review,
    caching, credential storage, or `sshServiceProvider` connection execution.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `ssh_connect`, `ssh_execute_command`, `ssh_disconnect`,
  `_handleSshConnect`, `_handleSshExecuteCommand`, `_SshToolHandlerModule`,
  `sshService`, `SshExecutionResult`, and `sshServiceProvider`.
- Files or modules inspected: `McpToolService`, `SshService`, provider
  construction, ChatNotifier handler registry, SSH approval extension,
  pending state, approval sheet tests, capability classification, and remote
  collision routing.
- Follow-up tasks found: keep Computer Use definition and dispatch extraction
  separate because it has a broader transport, approval, and audit perimeter.

## Acceptance Criteria

- Required behavior:
  - the handler exposes all three definitions in their current order and
    handles exactly their names.
  - service registration preserves availability, global placement, disabled
    filtering, direct routing, and unconditional collision reservation.
  - approved command execution forwards the trimmed command and returns the
    exact `SshExecutionResult.formatted()` payload.
  - disconnect calls the same service method and returns the same connected or
    inactive message.
  - `ssh_connect` remains mapped to ChatNotifier and returns the exact existing
    denial when invoked directly through `McpToolService`.
- Edge cases:
  - unavailable execute returns `SSH service is unavailable`.
  - inactive execute returns the existing `ssh_connect` guidance.
  - whitespace-only commands fail before service execution.
  - service execution and disconnect exceptions remain failed results with the
    unchanged exception string.
  - unavailable and inactive disconnect remain successful and idempotent.
- Failure paths: unknown handler names retain a deterministic failure shape,
  while known calls preserve every current service and session check.
- Accessibility, localization, or platform expectations: no UI or localized
  strings change; tests use a fake service and never access sockets,
  credentials, or the network.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/data/datasources/built_in_ssh_tool_handler_test.dart \
  --test test/features/chat/data/datasources/mcp_tool_service_test.dart \
  --test test/features/chat/presentation/widgets/approval/ssh_connect_approval_sheet_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary: `BuiltInSshToolHandler` now owns the three ordered definitions,
  availability, direct connect denial, approved command normalization and
  execution, disconnect execution, and compatible result envelopes.
  `McpToolService` retains composition, the public `sshService` reference,
  unconditional name reservation, and thin registration and dispatch
  delegation. ChatNotifier connection and command approval are unchanged.
- Tests run: the focused verifier passed 118 root tests plus 13
  internal-package tests. The full repository gate passed 3,563 root tests
  plus 13 internal-package tests with root and package analysis clean.
- Coverage or low-coverage notes: full repository line coverage was 72.95%.
  The extracted handler reached 98.33%. `SshService` remained at 18.46% while
  the ChatNotifier SSH approval extension reached 44.60%; this extraction used
  a deterministic service subclass and never opened sockets or credentials.
- Risks or follow-ups: preserve the ChatNotifier-owned connection and command
  approval paths and keep all real SSH validation outside deterministic
  repository tests. The next isolated application-boundary slice is built-in
  browser definition and service-side dispatch extraction; keep sensitive
  browser approval and redaction in ChatNotifier.
