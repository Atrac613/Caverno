# SEC4.4c Routine External MCP Deny-By-Default Task

Status: complete.

## Task

- Goal: deny unclassified external MCP tools in unattended routines by default.
  Filter them out of the routine tool catalog, and refuse dispatch even when
  the model invents a name that collides with a namespaced built-in allowlist
  entry.
- User-visible behavior: scheduled and manual routines keep the existing
  built-in, workspace, Computer Use allowlist, Google Chat, and
  `x-caverno-routine-tool` extras. External MCP tools disappear from the
  routine prompt and return a stable denial if the model still calls them.
  Interactive chat and Plan Mode are unchanged.
- Non-goals: a reviewed grant UI or persisted allowlist; git/shell mutation
  fencing (remaining SA-08); SEC4.5c Remote Coding transport; changing
  `PlanningToolPolicy`; restoring `searxng_web_search` after the built-in
  search removal.

## Context

- Affected components:
  - `RoutineToolPolicy.filterAllowedToolDefinitions`;
  - `RoutineExecutionService._allowedRoutineTools` /
    `_dispatchRoutineToolCall`;
  - focused policy tests plus the existing execution-service regression that
    currently keeps external MCP tools available.
- Related docs:
  - `docs/security_audit_2026-08-14.md` SA-09 and P1-1;
  - `docs/sec4_4b_project_mutation_containment_task.md`;
  - `docs/local_llm_agent_roadmap.md` SEC4.4.
- Release gate: P1. Do not combine with git/shell write containment or a
  grant-management UI. Any later grant must bind server identity, tool name,
  schema digest, and reviewed read-only intent; a name-only allowlist is not
  an acceptable follow-up.

## Implementation Slices

1. Stop treating `x-caverno-external-mcp-tool` as an automatic catalog pass in
   `RoutineToolPolicy.filterAllowedToolDefinitions`.
2. Deny at dispatch when `McpToolService.isExternalMcpToolName` is true, even
   if the tool name would otherwise match `_allowedToolNames` through the
   `__` namespace split (`get_dns_health__zeek_server` is the in-tree
   fixture). Do this before `executeTool` / `executeFileTool`.
3. Return a distinct machine-readable reason
   (`routine_external_mcp_denied`) instead of reusing
   `routine_requires_read_only_tools`.
4. Invert the execution-service test that currently asserts external MCP
   tools stay available, and add a focused `RoutineToolPolicy` test so the
   1,900-line execution suite does not become the only coverage.

## Implementation Notes

- Preferred approach: keep authorization in `RoutineToolPolicy`. Planning
  already denies unclassified external MCP through
  `PlanningToolPolicy.enforce(isExternalMcpTool: true)`; reuse that
  fail-closed shape, not a new grant store.
- Constraints:
  - Fail closed with an empty grant set. Do not add an unused grant type in
    this slice.
  - Built-in tools without `sourceUrl` stay on the existing allowlist,
    workspace-write, Computer Use, and routine-extra paths.
  - A catalog marker beats a namespaced built-in name. Removing only the
    filter shortcut is not enough.
  - Zero `McpToolService.executeTool` / `executeFileTool` calls after denial.
  - Do not grow `routine_execution_service.dart` when the check can live in
    `routine_tool_policy.dart`.
  - Do not expose remote server URLs beyond the existing source-label helper
    in denial payloads.
- Generated files needed: None.
- Migration: existing routines that depended on an unclassified external MCP
  tool will stop seeing it and receive the denial if the model still calls
  it. That is the intended default.

## Similar-Pattern Search

- Search terms: `isExternalMcpToolDefinition`, `openAiExternalToolKey`,
  `isExternalMcpToolName`, `filterAllowedToolDefinitions`,
  `planning_mode_requires_read_only_tools`.
- Files or modules inspected:
  - `routine_tool_policy.dart`
  - `routine_execution_service.dart`
  - `planning_tool_policy.dart`
  - `mcp_tool_entity.dart`
  - `mcp_tool_service.dart`
  - `routine_execution_service_test.dart`
- Follow-up tasks found:
  - SA-08 remaining git/local-command write fencing;
  - a later grant slice that binds server identity, tool name, schema
    digest, and reviewed read-only intent;
  - SEC4.5c before enabling Remote Coding in a release artifact.

## Acceptance Criteria

- Required behavior:
  - External MCP definitions are absent from routine tool requests.
  - An external MCP call is denied with `routine_external_mcp_denied` and
    causes zero execute-port calls.
  - Allowed built-ins such as `lan_scan` / `web_url_read` still run.
- Edge cases:
  - `router_health_snapshot` with `sourceUrl` is denied.
  - `get_dns_health__zeek_server` with `sourceUrl` is denied even though
    `get_dns_health` is an allowed built-in name.
  - A built-in `get_dns_health` without `sourceUrl` remains allowed.
  - `write_file` stays denied unless the routine has workspace write access.
  - `x-caverno-routine-tool` extras such as Google Chat post still pass when
    the routine allows them.
- Failure paths:
  - Missing MCP service still returns `routine_tool_service_unavailable`
    only for tools that would otherwise be allowed.
  - Denial payload uses `permission_denied` / `routine_external_mcp_denied`.
- Platform expectations: English denial copy. No new user-facing settings
  strings in this slice.

## Verification

```bash
fvm flutter test test/features/routines/domain/services/routine_tool_policy_test.dart
fvm flutter test test/features/routines/data/routine_execution_service_test.dart
fvm flutter test test/quality/file_size_ratchet_test.dart
tool/codex_verify.sh --no-codegen
```

Update `docs/security_audit_2026-08-14.md` SA-09, `docs/roadmap.md` Active
Focus, and the SEC4.4 note in `docs/local_llm_agent_roadmap.md` only after
the focused tests pass.

## Handoff Notes

- Summary: Unclassified external MCP tools are omitted from the routine
  catalog and denied at dispatch with `routine_external_mcp_denied` before
  `executeTool`. Namespaced collisions such as `get_dns_health__zeek_server`
  are treated as external MCP, not as allowed built-ins.
- Focused verification passed:
  - `routine_tool_policy_test.dart`
  - `routine_execution_service_test.dart`
  - `file_size_ratchet_test.dart`
- Risks or follow-ups: a later grant slice must bind server identity, tool
  name, schema digest, and reviewed read-only intent. Git and local-command
  write fencing remain the SA-08 remainder.
