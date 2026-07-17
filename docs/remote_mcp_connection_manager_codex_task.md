# Remote MCP Connection Manager Extraction

Status: completed on `feature/mcp-remote-connection-handler`.

## Task

- Goal: extract remote MCP connection state, trust-aware client resolution,
  tool-name exposure, and remote invocation routing from `McpToolService` into
  an independently testable application-internal manager.
- User-visible behavior: preserve the service's public connection API, server
  diagnostics, remote tool order and schemas, collision aliases, invocation
  results, and SearXNG fallback selection.
- Non-goals: changing HTTP or stdio transport protocols; changing persisted
  trust policy or settings UI; disposing temporary override clients; fixing
  concurrent connection races; normalizing result envelopes; or introducing an
  internal package.

## Context

- Affected components:
  - `lib/features/chat/data/datasources/mcp_tool_service.dart`
  - the current same-library `mcp_tool_service_connection.dart` extension
  - a new `remote_mcp_connection_manager.dart`
  - focused service, manager, settings-entity, and line-ratchet tests
- Related docs: `docs/large_file_refactor_plan.md` Phase 3 and
  `docs/roadmap.md` milestone F5.
- Reference pattern: the independent built-in network, filesystem, and local
  command handler boundaries. Keep application composition in the root package
  and remove the connection `part` instead of adding another shared-private
  extension.
- Compatibility rules:
  - Preserve connection source precedence: `overrideServers`, then
    `overrideUrls` or `overrideUrl`, then configured `mcpClients`.
    An explicitly supplied URL list wins over the single URL even when the
    list is empty, and raw override URL strings remain untrimmed.
  - Explicit server overrides accept enabled, valid pending or trusted servers
    so the settings trust-review flow can inspect tool names. Disabled, invalid,
    and blocked overrides remain excluded. Stdio overrides remain desktop-only.
  - No clients produce `disconnected`, no error, no tools, bindings, or server
    states. Any successful server produces an overall `connected` state;
    partial failures remain visible in `lastError` and per-server state. All
    failures produce `error` and clear tools and bindings.
  - Preserve configured-client order, remote tool order, the 64-character
    exposed-name limit, namespacing for the current `_reservedToolNames` set and
    duplicate names, stable server keys, and collision retries.
  - Preserve remote invocation only while connected, original remote tool-name
    forwarding, success and exception envelopes, and diagnostic log text.
  - Preserve public `McpToolService` constructor parameters, dependency fields,
    `status`, `tools`, `serverStates`, `lastError`, `connect`, and `refresh`.

## Implementation Notes

- Preferred approach:
  1. Characterize empty, success, partial-failure, all-failure, refresh,
     duplicate-name, reserved-name, invocation-failure, and blocked-override
     behavior through the current service boundary.
  2. Introduce `RemoteMcpConnectionManager` with explicit configured clients,
     reserved names, HTTP and stdio factories, and desktop-capability inputs.
  3. Move connection state, client resolution, trust filtering, tool caching,
     exposed-name generation, binding lookup, and remote invocation into the
     manager with direct deterministic tests.
  4. Construct and delegate through the manager from `McpToolService`, retaining
     SearXNG selection and global built-in composition in the service.
  5. Remove the old connection `part` and lower both the primary service and
     same-library aggregate ratchets after focused gates pass.
- Constraints:
  - Do not connect to real HTTP endpoints or start real stdio processes in
    tests; inject factories and fake clients.
  - Keep explicit pending-server connection available only through the existing
    override review path. Normal model exposure continues to receive only the
    prefiltered trusted configured clients.
  - Preserve mutable `tools` getter behavior and the unmodifiable
    `serverStates` view unless a separate compatibility task changes them.
  - Keep client lifetime ownership in Riverpod's `mcpClientsProvider`.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_status`, `_cachedTools`, `_remoteToolBindings`,
  `_serverStates`, `_lastError`, `_connectClient`, `_resolveClients`,
  `_resolveClientsFromServers`, `_buildExposedToolName`, `_buildServerKey`,
  `enabledMcpServers`, `connectableMcpServers`, and `overrideServers`.
- Files or modules inspected: `mcp_tool_service.dart`,
  `mcp_tool_service_connection.dart`, `mcp_client.dart`,
  `mcp_stdio_client.dart`, `mcp_tool_provider.dart`, `app_settings.dart`, the
  MCP settings and live-diagnostic consumers, and their focused tests.
- Follow-up tasks found: reserve intercepted `spawn_subagent`,
  `get_subagent_result`, and `save_skill` names so colliding remote tools remain
  reachable; result-envelope normalization; temporary override client disposal;
  connection-generation race protection; and later extraction of remaining
  built-in adapters.

## Acceptance Criteria

- Required behavior:
  - `McpToolService` delegates all public connection state and operations to one
    independent manager without changing callers.
  - Connected remote tools keep their exact order, definitions, source labels,
    aliases, and original invocation names.
  - Names in the current built-in reserved-name registry keep reserving remote
    aliases even when their definitions are disabled or unavailable.
  - SearXNG remains the fallback when no connected remote tools are exposed.
- Edge cases:
  - Empty configured and override client sets clear stale state.
  - Duplicate remote names, long names, sanitized server keys, and repeated
    alias collisions remain deterministic and at most 64 characters.
  - Refresh reconnects configured clients after a transient override.
  - Pending review overrides connect; blocked, disabled, invalid, and
    unsupported stdio overrides do not.
- Failure paths:
  - Partial failure reports per-server errors while retaining successful tools.
  - Total connection failure clears stale tools and bindings.
  - Remote call exceptions return the existing failed `McpToolResult`.
- Platform expectations: direct tests cover desktop and non-desktop stdio
  resolution without launching platform processes.

## Verification

Run focused checks after each implementation commit:

```bash
tool/codex_verify.sh \
  --no-codegen \
  --test test/features/chat/data/datasources/remote_mcp_connection_manager_test.dart \
  --test test/features/chat/data/datasources/mcp_tool_service_test.dart \
  --test test/features/settings/domain/entities/app_settings_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary: `RemoteMcpConnectionManager` now owns remote connection state,
  override and trust resolution, exposed-name generation, cached bindings, and
  remote invocation. `McpToolService` remains the public facade and preserves
  virtual `refresh()` dispatch, SearXNG fallback selection, and provider-owned
  transport lifetimes. The obsolete same-library connection `part` was removed.
- Compatibility: characterization covers empty, connecting, partial-success,
  total-failure, refresh, override-precedence, trust-filtering, duplicate-name,
  reserved-name, argument-forwarding, and invocation-failure paths. Explicit
  pending-server review remains available while blocked, disabled, invalid, and
  unsupported stdio overrides remain excluded.
- Size: `mcp_tool_service.dart` fell from 3,076 to 2,945 lines, and its
  same-library aggregate fell from 3,365 to 3,037 lines. The independent manager
  is ratcheted at 397 lines.
- Tests run: the focused verifier passed 125 root tests plus 13 internal-package
  tests. The full repository gate passed 3,487 root tests plus 13
  internal-package tests, with clean root and package analysis.
- Coverage: the full gate reached 72.11% line coverage (52,406/72,678); the new
  manager reached 90.40% (160/177) without live HTTP or stdio transports.
- Follow-ups: reserve the intercepted `spawn_subagent`, `get_subagent_result`,
  and `save_skill` names in an isolated behavior-fix task. Keep temporary
  override client disposal, connection-generation race protection, and
  result-envelope normalization as separate ownership and compatibility slices.
