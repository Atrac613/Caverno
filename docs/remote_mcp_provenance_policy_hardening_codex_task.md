# Remote MCP Provenance And Planning Policy Hardening

Status: completed on `feature/mcp-provenance-policy-hardening`, stacked on
`feature/mcp-prefix-collision-routing`.

## Task

- Goal: preserve external MCP provenance through execution so conversation
  taint is accurate, and prevent capability-unknown external MCP tools from
  executing during Plan Mode.
- User-visible behavior: external MCP content influences later approval review
  as untrusted evidence, while Plan Mode returns a deterministic read-only
  policy denial instead of calling an external MCP server.
- Non-goals: changing MCP server trust configuration, adding interactive
  approval to ordinary trusted-MCP execution, changing Routine external-MCP
  availability, interpreting server-declared read-only hints, or normalizing
  result envelopes.

## Context

- Affected components:
  - `McpToolResult` execution provenance
  - `RemoteMcpConnectionManager` and `McpToolService` remote-name lookup
  - ChatNotifier tool-result taint recording and participant tool execution
  - `PlanningToolPolicy`
  - focused entity, manager, service, planning, and notifier tests
- Related docs:
  - `docs/remote_mcp_prefix_collision_routing_codex_task.md`
  - `docs/large_file_refactor_plan.md`
  - `docs/roadmap.md`
- Reference patterns:
  - `McpToolEntity.openAiExternalToolKey` marks external definitions.
  - `DataSourceClassifier` already classifies `isMcpTool: true` results as
    `mcpResource` with untrusted trust.
  - `ParticipantToolPolicy` uses an explicit read-only allowlist; Plan Mode
    needs an equally explicit boundary for capability-unknown external tools.
- Compatibility rules:
  - Preserve all public tool names, arguments, result text, success states, and
    serialized `McpToolResult` JSON shapes.
  - Keep ordinary chat/coding and Routine trusted-MCP behavior unchanged.
  - Local policy denials for an external tool name are local results and must
    not be marked as MCP-derived because no server call occurred.

## Implementation Notes

- Preferred approach:
  1. Add non-serialized execution provenance to `McpToolResult`, defaulting to
     local, and set it only in remote manager success and failure results.
  2. Expose exact remote-binding lookup through the manager and service so
     Plan Mode can identify aliases without name heuristics.
  3. Pass result provenance into ChatNotifier taint recording, including the
     participant execution path.
  4. Extend `PlanningToolPolicy.enforce` with an explicit external-MCP input and
     deny it before any built-in or fallback execution.
- Constraints:
  - Do not infer provenance from tool-name prefixes or descriptions.
  - Do not mark pre-dispatch guards, approval denials, or Plan Mode denials as
    external MCP results.
  - Do not trust MCP descriptions or schemas as proof of read-only behavior.
  - Preserve the existing generic planning denial reason for compatibility,
    while adding an external-MCP-specific detail.
- Generated files needed: regenerate the Freezed and JSON outputs for
  `McpToolResult`.
- Migration or data compatibility concerns: none; execution provenance is
  transient and excluded from JSON serialization.

## Similar-Pattern Search

- Search terms: `recordToolResult`, `isMcpTool`, `McpToolResult`,
  `openAiExternalToolKey`, `PlanningToolPolicy`, `RoutineToolPolicy`,
  `ParticipantToolPolicy`, and `_remoteToolBindings`.
- Files or modules inspected: main and participant ChatNotifier tool paths,
  security classifiers and approval gates, remote manager and service,
  Plan Mode policy, Routine tool filtering, and participant allowlisting.
- Follow-up tasks found: MCP contract annotations and trust-level governance
  remain a later `MCP-GOV` concern. Routine external MCP remains an intentional
  trusted-server capability and is not silently changed by this slice.

## Acceptance Criteria

- Required behavior:
  - Successful and failed remote MCP calls return transient external-MCP
    provenance; local results default to local provenance.
  - `McpToolResult.toJson()` remains unchanged and `fromJson()` defaults to
    local provenance.
  - Main and participant ChatNotifier paths record external MCP results as
    untrusted conversation influence.
  - Plan Mode blocks every currently bound external MCP tool before client
    invocation, including ordinary, duplicate, exact-collision, and neutral
    prefix aliases.
  - The same external MCP tools remain executable outside Plan Mode.
- Edge cases:
  - A local Plan Mode denial for an external name is not marked MCP-derived.
  - Unknown and disconnected names keep existing unavailable behavior.
  - Built-in tools with similar names keep their current planning policy.
- Failure paths: remote invocation exceptions retain external-MCP provenance so
  remote-controlled error content cannot bypass taint.
- Accessibility, localization, or platform expectations: no UI or localized
  strings change; tests use fake MCP clients and launch no platform services.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/domain/entities/mcp_tool_entity_test.dart \
  --test test/features/chat/domain/services/tool_result_taint_recorder_test.dart \
  --test test/features/chat/data/datasources/remote_mcp_connection_manager_test.dart \
  --test test/features/chat/data/datasources/mcp_tool_service_test.dart \
  --test test/features/chat/domain/services/planning_tool_policy_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary: remote success and failure results now carry transient, non-JSON
  provenance. Exact live bindings identify external tools for Plan Mode, and
  main and participant tool paths record actual result provenance rather than
  inferring it from requested names. Plan Mode blocks capability-unknown
  external tools before dispatch; ordinary and Routine execution are unchanged.
- Tests run: the focused verifier passed 109 root tests plus 13 internal-package
  tests. The full repository gate passed 3,500 root tests plus 13
  internal-package tests, with project and package analysis reporting no
  findings.
- Coverage or low-coverage notes: full line coverage is 72.15%
  (52,454/72,700). `ToolResultTaintRecorder` reached 100.00%,
  `PlanningToolPolicy` 93.41%, `RemoteMcpConnectionManager` 88.49%,
  `McpToolEntity` 77.78%, and `McpToolService` 47.69%. The service remains a
  large composition facade and is the subject of the next extraction.
- Size evidence: `McpToolService` fell from 2,929 to 2,924 lines and its
  same-library aggregate fell from 3,021 to 3,016 lines.
  `RemoteMcpConnectionManager` remains at 319 lines and `ChatNotifier` remains
  at 9,468 lines; all ratchets were lowered or preserved without budget growth.
- Risks or follow-ups: preserve Routine trusted-MCP behavior and defer MCP
  annotation and trust governance to a separate milestone. The next F5 slice
  should extract result normalization and error-envelope creation without
  changing public JSON shapes.
