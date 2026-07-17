# Remote MCP Prefix-Collision Routing Fix

Status: completed on `feature/mcp-prefix-collision-routing`, stacked on
`feature/mcp-remote-name-collisions`.

## Task

- Goal: keep remote MCP tools reachable when their original names start with
  Caverno's reserved `browser_` or `computer_` dispatch prefixes.
- User-visible behavior: expose each matching remote tool through a neutral,
  deterministic alias and route that alias back to the original MCP tool.
- Non-goals: weakening built-in prefix-based safety policies, changing trusted
  MCP approval or Plan Mode policy, wiring generic MCP result taint, changing
  transport trust, or normalizing result envelopes.

## Context

- Affected components:
  - `lib/features/chat/data/datasources/remote_mcp_connection_manager.dart`
  - `lib/features/chat/data/datasources/mcp_tool_service.dart`
  - manager, service, dispatcher, and file-size ratchet tests
  - F5 status in `docs/large_file_refactor_plan.md` and `docs/roadmap.md`
- Related task: `docs/remote_mcp_reserved_name_collisions_codex_task.md`
  found this prefix-based variant during its similar-pattern audit.
- Reference pattern: exact reserved remote names already receive deterministic
  server-key aliases while retaining `originalName`, `sourceUrl`, and the
  original client binding.
- Compatibility rules:
  - Preserve `BrowserToolPolicy` and computer-use prefix classifications for
    genuine built-in names and unknown unsafe prefix-shaped calls.
  - Prefix-matching remote names use
    `mcp__<original-name>__<server-key>[_N]`, never an exposed `browser_` or
    `computer_` prefix.
  - Prefix matching is case-insensitive so aliases also remain neutral to
    downstream classifiers that normalize tool names before inspection.
  - Preserve encounter order, deterministic collision retries, and the
    64-character OpenAI tool-name limit.
  - Exact-name-only collisions keep their current alias format.

## Implementation Notes

- Preferred approach:
  1. Add optional reserved-prefix configuration to
     `RemoteMcpConnectionManager` and pass `browser_` and `computer_` from the
     service composition boundary.
  2. Namespace every matching remote name, including arbitrary names not found
     in the exact built-in registry, with a neutral `mcp__` lead.
  3. Keep original names only in entity provenance and client bindings so
     execution forwards unchanged arguments without entering built-in dispatch.
- Rejected approach: changing browser/computer routing to exact-name checks.
  Prefix checks also protect planning, capability, prompt, tool-search, and
  claim-handling surfaces; weakening them would create inconsistent policy.
- Constraints:
  - Do not move remote execution ahead of built-in dispatch.
  - Do not connect to live MCP servers or desktop services in tests.
  - Preserve the existing trusted-MCP policy. This task does not claim that
    generic external MCP tools are read-only or that their result taint is wired.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `startsWith('browser_')`, `startsWith('computer_')`,
  `BrowserToolPolicy.isBrowserTool`, `MacosComputerUseToolPolicy`,
  `ToolCapabilityClassifier`, `PlanningToolPolicy`, `_buildExposedToolName`, and
  `x-caverno-external-mcp-tool`.
- Files or modules inspected: remote manager and service routing,
  `ChatToolDispatcher`, browser and computer policies, system-prompt and
  tool-search classification, final-answer claim handling, capability
  classification, and taint recording.
- Follow-up tasks found: generic external MCP results are not consistently
  marked as MCP-derived when ChatNotifier records taint, and generic MCP tools
  retain the existing Plan Mode/read-only policy gap. Address both in a separate
  security task before result-envelope extraction.

## Acceptance Criteria

- Required behavior:
  - Known and arbitrary remote `browser_*` and `computer_*` names receive
    neutral `mcp__` aliases that match neither reserved prefix.
  - Case variants receive the same protection without changing their original
    names or schemas.
  - OpenAI definitions retain external-MCP provenance metadata.
  - Executing each alias calls the originating client with the original name
    and unchanged arguments.
  - ChatToolDispatcher sends neutral aliases only to its fallback handler.
- Edge cases:
  - Long aliases stay within 64 characters.
  - Duplicate prefixed names remain ordered and unique, including `_2` retries
    when the identifier and candidate collide.
  - Empty reserved prefixes are ignored rather than matching every tool.
- Failure paths: unknown aliases and disconnected bindings retain current
  no-match behavior.
- Accessibility, localization, or platform expectations: none; the fix changes
  no user-facing strings and launches no platform services.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh \
  --no-codegen \
  --test test/features/chat/data/datasources/remote_mcp_tool_name_policy_test.dart \
  --test test/features/chat/data/datasources/remote_mcp_connection_manager_test.dart \
  --test test/features/chat/data/datasources/mcp_tool_service_test.dart \
  --test test/features/chat/domain/services/chat_tool_dispatcher_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary: extracted deterministic remote-name generation into
  `RemoteMcpToolNamePolicy`, neutralized reserved prefixes with `mcp__`
  aliases, preserved original client bindings, and reused the computer-use
  policy as the reserved-name source of truth. `McpToolService` fell from 2,945
  to 2,929 lines, its aggregate library fell from 3,037 to 3,021 lines, and the
  connection manager fell from 397 to 319 lines. The new policy is 120 lines.
- Tests run: the focused verifier passed 104 root tests plus 13
  internal-package tests. The full coverage gate passed 3,494 root tests plus
  13 internal-package tests, and both analyzers reported no findings.
- Coverage: repository line coverage is 72.13% (52,430/72,690).
  `RemoteMcpToolNamePolicy` reached 100.00% (51/51),
  `RemoteMcpConnectionManager` reached 88.41% (122/138), and
  `McpToolService` reached 47.59% (504/1,059).
- Review: an independent static review reported no findings. Similar-pattern
  inspection covered dispatcher, browser/computer policy, planning,
  capability, prompt, tool-search, claim-handling, and taint-recording paths.
- Risks or follow-ups: preserve the generic trusted-MCP policy boundary. Before
  result-envelope extraction, wire generic remote MCP provenance into taint
  recording and close the existing Plan Mode/read-only capability-policy gap.
