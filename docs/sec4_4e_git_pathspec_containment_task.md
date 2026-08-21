# SEC4.4e Git Pathspec and Relocation Containment Task

Status: complete.

## Task

- Goal: stop `git_execute_command` from mutating files outside the authorized
  project after a legal working directory, via relocating git globals
  (`-C`, `--git-dir`, `--work-tree`), relocation environment variables, or
  out-of-root pathspecs.
- User-visible behavior: in-root relative pathspecs and ordinary subcommands
  still run. Relocating globals and `~` / `..` / absolute pathspecs outside the
  root fail before `Process.run`.
- Non-goals: `git_finish_worktree_session`; local-command writes (SEC4.4f);
  rewriting in-root pathspecs to canonical form.

## Context

- Affected components:
  - a dedicated git path-escape guard;
  - `GitTools.executeResult` after the SEC4.4d cwd fence.
- Related docs:
  - `docs/sec4_4d_git_working_directory_containment_task.md`;
  - `docs/sec4_4_write_containment_remainder.md`;
  - `docs/security_audit_2026-08-14.md` SA-08 remainder.
- Release gate: P1. One slice.

## Implementation Slices

1. Deny `-C`, `--git-dir`, and `--work-tree` when they appear as git globals
   (before the subcommand). Do not treat `grep -C` as relocation.
2. Strip `GIT_DIR`, `GIT_WORK_TREE`, and related relocation variables from the
   git process environment.
3. Authorize pathspecs that are absolute, home-relative, contain `..`, or
   follow `--` with `ProjectMutationPathFence`.

## Implementation Notes

- Preferred approach: a new guard next to the mutation fence. Return
  `git_repository_relocation_blocked` for globals/env and `project_mutation_*`
  for pathspecs.
- Constraints:
  - Do not grow `git_tool_handler.dart`.
  - Do not treat branch names like `feature/foo` as pathspecs.
  - Fail closed; do not authorize an out-of-root `-C` even if the user might
    have meant an in-root path.
- Generated files needed: None.

## Similar-Pattern Search

- Search terms: `--git-dir`, `-C`, `splitArgs`, `ProjectMutationPathFence`.
- Files or modules inspected:
  - `git_tools.dart`
  - `project_mutation_path_fence.dart`
- Follow-up tasks found: SEC4.4f local-command write fencing.

## Acceptance Criteria

- Required behavior:
  - `add lib/foo.dart` and `status` still run in an in-root cwd.
- Edge cases:
  - Reject `-C <outside>`, `--git-dir=`, `--work-tree=`.
  - Allow `grep -C 3 pattern`.
  - Reject `checkout -- <outside>`, `add ../sibling`, `add ~`.
- Failure paths:
  - Zero target-command `Process.run` after denial.

## Verification

```bash
fvm flutter test test/features/chat/data/datasources/git_command_path_escape_guard_test.dart
fvm flutter test test/features/chat/data/datasources/git_tools_test.dart
fvm flutter test test/quality/file_size_ratchet_test.dart
```

## Handoff Notes

- Summary: `GitCommandPathEscapeGuard` denies `-C` / `--git-dir` /
  `--work-tree` before preflight, strips relocation environment variables, and
  fences escaping pathspecs after git-specific preflights so recovery codes
  like `git_worktree_force_remove_blocked` stay intact.
- Focused verification passed:
  - `git_command_path_escape_guard_test.dart`
  - `git_tools_test.dart`
- Full suite: 8060 passed.
- Risks or follow-ups: SEC4.4f local-command writes.
