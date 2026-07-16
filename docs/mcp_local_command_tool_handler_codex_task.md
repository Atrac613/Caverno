# MCP Built-in Local Command Tool Handler Extraction

Status: completed on `feature/mcp-local-command-tool-handler`.

## Task

- Goal: extract the built-in local command, background process, and test-command
  tool family from `McpToolService` into an independently testable
  application-internal handler.
- User-visible behavior: preserve existing schemas, definition ordering,
  desktop and capability gating, direct execution, validation, Git-write
  rejection, process monitoring, and result envelopes.
- Non-goals: changing `LocalShellTools`, `BackgroundProcessTools`, or
  `BackgroundProcessMonitorService`; changing approval or permission policy;
  moving `ChatNotifier` command construction and follow-up behavior; normalizing
  legacy success envelopes; or introducing an internal package.

## Context

- Affected components:
  - `lib/features/chat/data/datasources/mcp_tool_service.dart`
  - a new `built_in_local_command_tool_handler.dart`
  - focused service, handler, shell, process, monitor, and line-ratchet tests
- Related docs: `docs/large_file_refactor_plan.md` Phase 3 and
  `docs/roadmap.md` milestone F5.
- Reference pattern: the independent `BuiltInNetworkToolHandler` and
  `BuiltInFilesystemToolHandler` boundaries. Keep this handler in the root
  application and do not add another Dart `part` or internal package.
- Compatibility rules:
  - Preserve all eight names and their relative order:
    `local_execute_command`, `process_start`, `process_status`, `process_tail`,
    `process_wait`, `process_cancel`, `process_list`, and `run_tests`.
  - `local_execute_command` and `run_tests` definitions remain desktop-only.
    The six process definitions additionally require supported background
    process tools.
  - When process tools are unavailable, the local command definition is
    followed directly by `run_tests`.
  - Disabled or capability-hidden definitions remain directly executable by a
    known name, matching the current service contract.
  - All eight names reserve remote MCP collisions even when definitions are
    disabled or capability-hidden.
  - Preserve the existing result-envelope asymmetry. A returned foreground or
    process-provider payload can produce `isSuccess: true` even when its JSON
    body reports an operation error. Unavailable providers also retain their
    tool-specific empty or structured failure payloads.
  - Preserve `run_tests` direct execution as an exact `approval_required`
    sentinel. `ChatNotifier` continues to construct and approve the actual
    command.

## Implementation Notes

- Preferred approach:
  1. Characterize exact schemas and global placement, platform and capability
     gating, disabled direct routing, all eight remote collision aliases,
     validation, unavailable payloads, Git-write rejection, process-list
     behavior, and the `run_tests` sentinel.
  2. Introduce `BuiltInLocalCommandToolHandler` with explicit `toolNames`,
     ordered definitions, `handles`, and `execute` surfaces.
  3. Inject narrow command, background-process, process-monitor, and clock
     dependencies so validation and serialization remain deterministic in
     direct handler tests.
  4. Delegate definitions and one direct execution branch from
     `McpToolService`; retain global disabled-definition filtering and exact
     placement there.
  5. Lower the primary and same-library aggregate ratchets after focused
     behavior and coverage gates pass.
- Constraints:
  - Reject Git-writing commands before invoking either the foreground runner or
    background starter.
  - Preserve required arguments and forwarding for working directory,
    environment, timeout, output limits, polling, tail offsets, and job IDs.
  - Preserve `background` coercion for booleans, nonzero numbers, and the
    strings `true`, `1`, and `yes`.
  - Preserve `process_list` mixed-ID filtering, defaults, refresh selection,
    deterministic timestamp injection, and global active/finished counts.
  - Keep project scoping, permission rules, approval UI and cache, auto-review,
    process follow-up, monitor registration, and recovery policy in
    `ChatNotifier`.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_reservedToolNames`, `_localExecuteCommandTool`,
  `_processStartTool`, `_processListTool`, `_runTestsTool`, `_asBool`,
  `_backgroundProcessUnavailableResult`, `approval_required`, and remote tool
  name collisions.
- Files or modules inspected: `mcp_tool_service.dart`,
  `local_shell_tools.dart`, `background_process_tools.dart`,
  `background_process_monitor_service.dart`, `chat_notifier.dart`, their
  focused tests, and the file-size ratchet.
- Follow-up tasks found: remote MCP connection and trust-state extraction,
  result-envelope normalization as a separate behavior change, and later
  decomposition of the IO-heavy `network_tools.dart` implementation.

## Acceptance Criteria

- Required behavior:
  - Exact definitions and global placement remain unchanged with and without
    supported process tools.
  - `McpToolService.executeTool` delegates all eight names to one handler.
  - All non-local-command tools keep their existing routing.
  - All eight names namespace remote MCP collisions.
  - `ChatNotifier` retains approval and post-execution orchestration ownership.
- Edge cases:
  - Blank required arguments fail without invoking command providers.
  - Git-writing commands fail before foreground or background execution.
  - Mixed `job_ids` values are normalized exactly as before.
  - Process-list refresh uses all active jobs when no IDs are provided and the
    selected IDs otherwise.
- Failure paths:
  - Missing background tools or monitor services retain each tool's current
    result payload and success flag.
  - Provider exceptions continue to propagate where they do today.
  - Unknown names are not handled.
- Platform expectations: direct tests cover desktop and capability branches
  without launching real shell commands or background processes.

## Verification

Run focused checks after each implementation commit:

```bash
tool/codex_verify.sh \
  --no-codegen \
  --test test/features/chat/data/datasources/built_in_local_command_tool_handler_test.dart \
  --test test/features/chat/data/datasources/mcp_tool_service_test.dart \
  --test test/features/chat/data/datasources/local_shell_tools_test.dart \
  --test test/features/chat/data/datasources/background_process_tools_test.dart \
  --test test/features/chat/data/datasources/background_process_monitor_service_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary: `BuiltInLocalCommandToolHandler` now owns the eight ordered local
  command, background-process, and `run_tests` definitions, their validation
  and argument normalization, direct execution, unavailable-provider results,
  process-list aggregation, and the approval sentinel. `McpToolService` keeps
  platform and capability gates, disabled-definition filtering, global
  placement, and remote-collision reservation before delegating execution.
  The service fell from 3,621 to 3,076 lines, its same-library aggregate fell
  from 3,910 to 3,365 lines, and the independent handler is 587 lines.
- Tests run: the focused verifier passed 108 root tests plus 13
  internal-package tests. The full coverage gate passed 3,468 root tests plus
  13 internal-package tests; root and package analysis reported no findings.
- Coverage or low-coverage notes: full repository line coverage is 72.35%
  (51,124/70,665). The new handler reached 99.48% line coverage (191/192)
  without starting real commands or background processes.
- Risks or follow-ups: the legacy result-envelope asymmetry remains
  intentionally compatible and should be normalized only in a separate
  behavior-change task. The next MCP decomposition slice should isolate remote
  server connection and trust-state handling.
