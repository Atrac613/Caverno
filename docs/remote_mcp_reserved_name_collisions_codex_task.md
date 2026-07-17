# Remote MCP Reserved-Name Collision Fix

Status: completed on `feature/mcp-remote-name-collisions`, stacked on
`feature/mcp-remote-connection-handler`.

## Task

- Goal: keep remote MCP tools reachable when their original names collide with
  `spawn_subagent`, `get_subagent_result`, or `save_skill`.
- User-visible behavior: expose each colliding remote tool through a stable
  namespaced alias and route that alias back to the original remote tool name.
- Non-goals: changing built-in tool availability, ChatNotifier handler
  dispatch, remote alias formatting, trust policy, transport ownership, or
  result-envelope shapes.

## Context

- Affected components:
  - `lib/features/chat/data/datasources/mcp_tool_service.dart`
  - `test/features/chat/data/datasources/mcp_tool_service_test.dart`
  - F5 status in `docs/large_file_refactor_plan.md` and `docs/roadmap.md`
- Related task: `docs/remote_mcp_connection_manager_codex_task.md` identified
  these omissions during the connection-manager extraction.
- Reference pattern: network, filesystem, and local-command built-ins reserve
  every exact dispatch name even when a definition is disabled or unavailable.
- Compatibility rules:
  - `spawn_subagent` and `get_subagent_result` remain ChatNotifier-owned tools.
  - `save_skill` remains an interactive ChatNotifier operation and keeps the
    current non-interactive refusal in `McpToolService`.
  - Remote aliases remain deterministic, unique, and at most 64 characters.
  - Invoking an alias forwards the unchanged arguments and original remote name.

## Implementation Notes

- Preferred approach:
  1. Add service-boundary regression coverage for all three names in one remote
     client, including definition exposure and invocation routing.
  2. Cover disabled or unavailable built-in definitions so reservation does not
     accidentally depend on the active OpenAI definition list.
  3. Add the three exact dispatch names to the existing reserved-name registry.
- Constraints:
  - Keep the fix in the existing registry; do not introduce a new presentation
    dependency into the data layer.
  - Do not connect to live MCP servers in tests.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_reservedToolNames`, `ToolHandlerRegistry`, `_addIfEnabled`,
  `spawn_subagent`, `get_subagent_result`, `save_skill`, `create_routine`, and
  `tryExecute`.
- Files or modules inspected: `mcp_tool_service.dart`,
  `remote_mcp_connection_manager.dart`, the ChatNotifier tool-handler registry,
  built-in handler registries, and their focused service tests.
- Follow-up tasks found: namespaced remote `browser_*` and `computer_*` tools
  remain unreachable because exact built-in names are reserved but the aliases
  retain prefixes consumed by prefix-based dispatch. Decide whether to use
  exact-name dispatch or prefix-safe remote aliases in a separate behavior task.
  `web_search` remains intentionally unreserved because remote execution wins
  before the mutually exclusive SearXNG fallback. Result normalization and
  error-envelope extraction remain a later F5 refactor slice.

## Acceptance Criteria

- Required behavior:
  - All three colliding remote names receive aliases rather than exact exposed
    names.
  - OpenAI definitions contain the available built-in exact names and all
    remote aliases without duplicate exact names.
  - Executing every alias calls the remote client with its original name and
    unchanged arguments.
- Edge cases:
  - Disabled `spawn_subagent` and `get_subagent_result` definitions still reserve
    their names.
  - A missing skill repository still leaves `save_skill` reserved.
- Failure paths: unknown exact or alias names retain current no-match behavior.
- Accessibility, localization, or platform expectations: none; the fix is
  platform-independent and changes no user-facing strings.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh \
  --no-codegen \
  --test test/features/chat/data/datasources/mcp_tool_service_test.dart \
  --test test/features/chat/data/datasources/remote_mcp_connection_manager_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary: the unconditional reserved-name registry now includes the subagent
  dispatch pair and `save_skill`. Their remote counterparts receive stable
  aliases that bypass exact ChatNotifier handlers and forward unchanged names
  and arguments to the originating MCP client. Built-in availability and exact
  dispatch behavior remain unchanged.
- Tests run: the focused gate passed 90 root tests plus 13 internal-package
  tests. The full repository gate passed 3,489 root tests plus 13
  internal-package tests, with clean root and package analysis. An independent
  review reported no findings.
- Coverage: the full gate reached 72.12% line coverage (52,416/72,678).
  `mcp_tool_service.dart` reached 47.59% (504/1,059), while the connection
  manager remained at 90.40% (160/177).
- Size: `mcp_tool_service.dart` remains at its 2,945-line ratchet and the
  same-library aggregate remains at 3,037 lines.
- Follow-up: fix prefix-based interception of namespaced remote `browser_*` and
  `computer_*` tools before extracting result normalization and error-envelope
  creation.
