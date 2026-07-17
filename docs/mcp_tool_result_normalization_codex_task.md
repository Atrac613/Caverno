# MCP Tool Result Normalization Extraction

Status: completed on `feature/mcp-result-normalization`, stacked on
`feature/mcp-provenance-policy-hardening`.

## Task

- Goal: extract repeated `McpToolResult` construction, JSON payload outcome
  interpretation, command failure classification, and structured error-envelope
  encoding behind one independently tested application-internal boundary.
- User-visible behavior: none. Tool names, result text, success flags, error
  messages, serialized entity JSON, structured payload bytes, and remote MCP
  provenance remain compatible.
- Non-goals: changing legacy payload-success asymmetry, imposing one canonical
  error schema on every tool, adding typed public outcome metadata, changing
  approval or taint policy, or moving tool execution out of existing handlers.

## Context

- Affected components:
  - a new pure `McpToolResultNormalizer`
  - `McpToolService` JSON and command result branches
  - `BuiltInLocalCommandToolHandler` structured envelopes
  - `GitFinishWorktreeSessionTool` command result handling
  - `RemoteMcpConnectionManager` external result construction
  - focused normalizer, service, handler, manager, and ratchet tests
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 3
  - `docs/roadmap.md` F5
  - `docs/mcp_filesystem_tool_handler_codex_task.md`
  - `docs/mcp_local_command_tool_handler_codex_task.md`
  - `docs/remote_mcp_provenance_policy_hardening_codex_task.md`
- Reference patterns:
  - computer use, browser, and dependency-grounding results treat malformed,
    non-map, and `ok`-not-false payloads as successful.
  - Git command results prefer a non-empty `error`, then a non-zero
    `exit_code`, then `stderr` over `stdout` for the failure detail.
  - local command failures intentionally use both empty result strings and
    ordered JSON payloads. Some providers intentionally return `ok:false`
    payloads inside successful `McpToolResult` envelopes.
- Compatibility rules:
  - Preserve caller-provided result payloads byte for byte.
  - Preserve insertion order when encoding structured error payloads.
  - Preserve transient `isExternalMcpResult` on remote success and failure.
  - Do not infer failure from arbitrary payloads unless the existing call site
    already performs that inference.

## Implementation Notes

- Preferred approach:
  1. Add a stateless normalizer with explicit success, failure, structured
     failure, `ok` payload, and command payload constructors.
  2. Characterize the boundary directly before integrating it.
  3. Replace duplicated JSON and command parsing in the service and worktree
     tool, then route structured local-command failures through the same
     encoder.
  4. Route remote MCP success and failure through the normalizer while retaining
     explicit external provenance.
- Constraints:
  - Keep the boundary independent of Flutter, Riverpod, services, and mutable
    application state.
  - Accept ordered maps from callers rather than silently reordering fields.
  - Keep fallback messages at call sites because they are part of each tool's
    compatibility contract.
  - Do not replace every `McpToolResult` constructor mechanically when a call
    site has specialized semantics that the boundary does not model.
- Generated files needed: none.
- Migration or data compatibility concerns: none; no persisted entity fields or
  serialized keys change.

## Similar-Pattern Search

- Search terms: `McpToolResult(`, `jsonEncode({`, `_tryDecodeMap`,
  `_commandResultFailureMessage`, `errorMessage:`, `ok`, and `exit_code`.
- Files or modules inspected: `McpToolService`, the three extracted built-in
  handlers, remote MCP connection manager, worktree session finisher, tool-loop
  consumers, validation inference, and existing result entity tests.
- Follow-up tasks found: typed command outcome metadata and a canonical public
  MCP error contract remain separate compatibility changes. Repeated JSON
  decoding in downstream guardrails is broader than result construction and is
  not part of this extraction.

## Acceptance Criteria

- Required behavior:
  - direct success and failure construction preserves every supplied field.
  - structured failures preserve payload key order and exact encoded JSON.
  - `ok:false` payloads retain their original result and use the payload error
    or the existing call-site fallback; malformed and non-map JSON retain the
    existing successful outcome.
  - command payloads preserve error priority, numeric exit-code formatting,
    `stderr`/`stdout` fallback, and the original result string.
  - remote success and exception results remain externally sourced.
  - service and local-command integration retains all existing result-envelope
    expectations.
- Edge cases:
  - absent or null payload errors use the fallback, while an existing empty
    string remains empty without trimming or rewriting the result.
  - `exit_code: 0`, absent exit codes, and invalid JSON remain successful.
  - a non-zero exit code with no output uses only the tool label and code.
  - ordered maps whose first key is `error` remain encoded in that order.
- Failure paths: parsing failure never hides the original payload, and exception
  strings remain unchanged in failed results.
- Accessibility, localization, or platform expectations: no UI or localized
  strings change; tests use fakes and launch no external processes or servers.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/data/datasources/mcp_tool_result_normalizer_test.dart \
  --test test/features/chat/data/datasources/mcp_tool_service_test.dart \
  --test test/features/chat/data/datasources/built_in_local_command_tool_handler_test.dart \
  --test test/features/chat/data/datasources/remote_mcp_connection_manager_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary: `McpToolResultNormalizer` now owns direct success and failure
  construction, ordered structured failure encoding, existing `ok` payload
  interpretation, and command-result failure classification. `McpToolService`,
  local command envelopes, worktree finishing, and remote MCP invocation use
  the boundary without changing payload bytes or provenance.
- Tests run: the focused verifier passed 115 root tests plus 13
  internal-package tests. The full repository gate passed 3,506 root tests plus
  13 internal-package tests, regenerated committed outputs without drift, and
  reported no project or package analyzer findings.
- Coverage or low-coverage notes: full line coverage is 72.18%
  (52,460/72,683). The new normalizer reached 100.00% (35/35), the local
  command handler 99.46% (185/186), the remote manager 88.49% (123/139), the
  worktree finisher 63.16% (24/38), and the service 47.53% (491/1,033).
- Size evidence: `McpToolService` fell from 2,924 to 2,869 lines and its
  same-library aggregate fell from 3,016 to 2,961 lines. The local command
  handler fell from 587 to 581 lines, the remote manager from 319 to 317 lines,
  and the new normalizer is ratcheted at 126 lines.
- Risks or follow-ups: preserve legacy result-envelope asymmetry and keep typed
  public outcome metadata as a separate compatibility task. The next bounded
  service extraction should move BLE definition and execution ownership into an
  independently tested handler while leaving approval interception unchanged.
