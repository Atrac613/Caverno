# SEC4.4f Local-Command Write Containment Task

Status: complete.

## Task

- Goal: stop `local_execute_command` and `process_start` from mutating files
  outside the selected project after a lexical working-directory check, via a
  symlink-escaping cwd or write argv that names `~`, `..`, or an absolute path
  outside the root.
- User-visible behavior: in-root relative writes still run. When a coding
  project is selected, `~` / `..` / sibling / symlink-escaping working
  directories and write operands fail before the native shell. Ordinary chat
  without a selected project is unchanged.
- Non-goals: parsing arbitrary shell into a complete AST; host-wide writes as a
  separate capability; `git_finish_worktree_session`; growing
  `local_command_tool_handler.dart`.

## Context

- Affected components:
  - a dedicated local-command mutation guard;
  - `BuiltInLocalCommandToolHandler.execute` next to the SEC4.4a read preflight;
  - `LocalShellTools.executeResult` as the process-start boundary.
- Related docs:
  - `docs/sec4_4a_project_read_containment_task.md`;
  - `docs/sec4_4d_git_working_directory_containment_task.md`;
  - `docs/sec4_4_write_containment_remainder.md`;
  - `docs/security_audit_2026-08-14.md` SA-08 remainder.
- Release gate: P1. One slice.

## Implementation Slices

1. Authorize the working directory with `ProjectMutationPathFence` when a
   project or turn-scoped root is present. Rewrite the cwd to the canonical
   path before any process starts.
2. For commands that are not approval-free internal reads, authorize escaping
   write operands (`~`, `..`, absolute paths) against the same fence, resolving
   relatives against the authorized cwd rather than the project root.
3. Skip the fence when no project is selected so general-mode local commands
   keep working.

## Implementation Notes

- Preferred approach: a new guard next to the mutation fence, called from the
  built-in handler and from `LocalShellTools.executeResult`. Reuse
  `project_mutation_*` denial codes.
- Constraints:
  - Do not grow `local_command_tool_handler.dart` past its F1 budget.
  - Do not treat the command executable (`/usr/bin/python3`) as a write path.
  - Do not default `projectRoot` to `workingDirectory`.
  - Fail closed when a project is selected; do not fail closed when none is.
- Generated files needed: None.

## Similar-Pattern Search

- Search terms: `_isAllowedWorkingDirectory`, `ProjectMutationPathFence`,
  `authorizeBuiltInLocalCommandRead`, `LocalShellTools.executeResult`.
- Files or modules inspected:
  - `local_command_tool_handler.dart`
  - `built_in_local_command_tool_handler.dart`
  - `local_shell_tools.dart`
  - `out_of_root_command_paths.dart`
- Follow-up tasks found: SEC4.5c pinned Remote Coding transport; SEC4.3d HTTP
  body/time limits.

## Acceptance Criteria

- Required behavior:
  - `touch output.txt` still runs in an in-root cwd when a project is selected.
  - Local commands without a selected project still run.
- Edge cases:
  - Reject `~`, `..`, siblings, prefix collisions, and symlink-escaping cwd.
  - Reject `touch ../sibling/secret` and `touch /tmp/secret` when a project is
    selected.
  - Allow `/usr/bin/python3` as the executable.
- Failure paths:
  - Zero target-command `Process.start` / runner calls after denial.

## Verification

```bash
fvm flutter test test/features/chat/data/datasources/local_command_mutation_guard_test.dart
fvm flutter test test/features/chat/data/datasources/built_in_local_command_tool_handler_test.dart
fvm flutter test test/features/chat/data/datasources/local_shell_tools_test.dart
fvm flutter test test/quality/file_size_ratchet_test.dart
```

## Handoff Notes

- Summary: `LocalCommandMutationGuard` authorizes the working directory with
  `ProjectMutationPathFence` when a project or turn-scoped root is present,
  rewrites the cwd to the canonical path, and fences escaping write operands
  (`~`, `..`, absolute paths) after resolving relatives against that cwd. No
  selected project skips the fence so general-mode chat still runs.
- Focused verification passed:
  - `local_command_mutation_guard_test.dart`
  - `built_in_local_command_tool_handler_test.dart`
  - `local_shell_tools_test.dart`
  - `local_command_tool_handler_test.dart`
  - `file_size_ratchet_test.dart`
- Full suite: 8077 passed.
- Risks or follow-ups: SEC4.5c pinned Remote Coding transport; SEC4.3d HTTP
  body/time limits. Arbitrary shell is still not a complete AST; host-wide
  writes remain a separate capability.
