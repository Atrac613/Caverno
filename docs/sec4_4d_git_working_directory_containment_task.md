# SEC4.4d Git Working-Directory Containment Task

Status: complete.

## Task

- Goal: authorize `git_execute_command` working directories against the same
  canonical, symlink-aware project or worktree root used by SEC4.4b file
  mutations. Rewrite the cwd to the authorized canonical path before any git
  process starts.
- User-visible behavior: git commands inside the selected project or assigned
  worktree still run. `~`, `..`, siblings, prefix collisions, and symlink
  escapes fail before `Process.run`. Missing project/worktree authority fails
  closed.
- Non-goals: git pathspecs and `--git-dir` / `--work-tree` / `-C` (SEC4.4e);
  `git_finish_worktree_session` (it must touch the base repository, which can
  sit beside an LL13 worktree); local-command writes (SEC4.4f).

## Context

- Affected components:
  - `GitTools.executeResult` effect boundary;
  - `McpToolService` git dispatch;
  - `GitToolRuntimeAdapter` production adapter;
  - ChatNotifier git handlers injecting the authorized root.
- Related docs:
  - `docs/security_audit_2026-08-14.md` SA-08 remainder;
  - `docs/sec4_4b_project_mutation_containment_task.md`;
  - `docs/sec4_4_write_containment_remainder.md`.
- Release gate: P1. One slice.

## Implementation Slices

1. Call `ProjectMutationPathFence` at the start of `GitTools.executeResult`
   with an explicit `projectRoot`. Deny and skip `Process.run` when the cwd is
   unauthorized.
2. Pass the authorized root from ChatNotifier (worktree path if the
   conversation has one, otherwise the selected project root) and from
   `GitToolRuntimeAdapter` (`ownerWorktreePath ?? ownerRepositoryPath`).
3. Cover missing root, outside cwd, symlink escape, and in-root cwd on the
   real fence. Keep existing git lifecycle tests passing by using the temp
   repo as both cwd and project root.

## Implementation Notes

- Preferred approach: reuse `ProjectMutationPathFence` rather than a second
  path comparator. Keep git-specific denial copy out of the fence; return the
  fence payload as the git failure JSON.
- Constraints:
  - Do not default `projectRoot` to `workingDirectory`; that would make the
    fence always succeed.
  - Do not grow `git_tool_handler.dart` past its F1 budget; the production
    git process starts in `GitTools.executeResult`.
  - Fail closed when `projectRoot` is missing.
- Generated files needed: None.

## Similar-Pattern Search

- Search terms: `GitTools.executeResult`, `working_directory`,
  `ProjectMutationPathFence`, `_isAllowedWorkingDirectory`.
- Files or modules inspected:
  - `git_tools.dart`
  - `mcp_tool_service.dart`
  - `git_tool_runtime_adapter.dart`
  - `chat_notifier_git_handlers.dart`
  - `local_command_tool_handler.dart`
- Follow-up tasks found: SEC4.4e pathspec/global-option escapes; SEC4.4f
  local-command write fencing.

## Acceptance Criteria

- Required behavior:
  - A cwd inside the canonical project or worktree runs.
  - The process uses the authorized canonical cwd.
- Edge cases:
  - Reject `~`, `..`, siblings, prefix collisions, and symlink escapes.
  - Reject a missing project/worktree root.
- Failure paths:
  - Return `project_mutation_*` codes.
  - Zero `Process.run` git invocations after denial.

## Verification

```bash
fvm flutter test test/features/chat/data/datasources/git_tools_test.dart
fvm flutter test test/features/chat/data/datasources/git_tool_runtime_adapter_test.dart
fvm flutter test test/features/chat/domain/services/git_tool_handler_test.dart
fvm flutter test test/quality/file_size_ratchet_test.dart
```

## Handoff Notes

- Summary: `GitTools.executeResult` now authorizes the working directory with
  `ProjectMutationPathFence` before any git process. The fence root is an
  explicit `projectRoot` argument, otherwise the turn-scoped `TurnProjectRoot`.
  Denied paths return `project_mutation_*` codes and never reach `Process.run`.
- Focused verification passed:
  - `git_tools_test.dart` including the working-directory containment group
  - `git_tool_runtime_adapter_test.dart`
  - `mcp_tool_service_test.dart` git init / chained-command cases
  - `file_size_ratchet_test.dart`
- Risks or follow-ups: `git -C`, `--git-dir`, `--work-tree`, and out-of-root
  pathspecs can still mutate files after a legal cwd. That is SEC4.4e.
  Local-command writes are SEC4.4f.
