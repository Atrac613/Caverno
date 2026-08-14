# SEC4.4a Project Read Containment Task

## Task

- Goal: Fence every approval-free local filesystem read to the canonical root
  of the selected project or assigned worktree.
- User-visible behavior: Relative paths inside the active project continue to
  work. Absolute paths, home-relative paths, traversal, prefix collisions, and
  symlink escapes fail before any read begins.
- Non-goals: This slice does not authorize host-wide reads, change mutation
  containment (SEC4.4b), or change external MCP permissions (SEC4.4b).

## Context

- Affected components:
  - Built-in filesystem inspection tools.
  - Approval-free internal local shell reads.
  - Interactive and Plan Mode tool dispatch.
  - Routine workspace reads.
  - Worktree-agent reads.
- Related docs:
  - `docs/security_audit_2026-08-14.md` (SA-04 and P0-4).
  - `docs/local_llm_agent_roadmap.md` (SEC4.4a).
- Release gate: P0 release blocker. Host-wide reads remain unavailable until a
  separate capability can require a fresh, non-cacheable approval.

## Implementation Slices

1. Add one asynchronous project-read path fence that canonicalizes the root
   and target, resolves existing symlinks, and returns a structured denial.
2. Apply the fence before built-in filesystem inspection execution. Require a
   project root rather than treating the process working directory as ambient
   authority.
3. Apply the same fence to every filesystem path consumed by approval-free
   internal shell commands. Canonically validate the requested working
   directory against the selected project root.
4. Replace the lexical-only checks in routine and worktree-agent read routes
   with the shared fence. Confirm interactive and Plan Mode share the protected
   dispatch path.
5. Update the audit and roadmap only after the full P0 acceptance suite passes.

## Implementation Notes

- Preferred approach: Resolve the selected root to a canonical directory, then
  resolve the existing target to its canonical identity and compare path
  components rather than string prefixes.
- Constraints:
  - Fail closed when no project or worktree root is available.
  - Do not execute the filesystem operation or shell command after denial.
  - Do not expose host paths outside the authorized root in denial messages.
  - Preserve in-project symlinks and a selected root that is itself a symlink.
  - Keep the authorization at the effect boundary even when an upstream
    argument resolver already emits an absolute path.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

- Search terms: `read_file`, `list_directory`, `executeTool`,
  `LocalShellTools.execute`, `_isInsideWorktree`, `_isInsideOrSame`, and
  `isInsideRoot`.
- Files or modules inspected:
  - `project_scoped_tool_argument_resolver.dart`
  - `project_scoped_read_tool_handler.dart`
  - `built_in_filesystem_tool_handler.dart`
  - `local_shell_tools.dart`
  - `local_command_tool_handler.dart`
  - `routine_execution_service.dart`
  - `worktree_agent_task_executor.dart`
- Follow-up tasks found: SEC4.4b must apply symlink-aware authorization to
  mutations and deny unclassified routine MCP tools by default.

## Acceptance Criteria

- Required behavior:
  - Relative and absolute targets inside the canonical root are readable.
  - A selected root reached through a symlink authorizes its canonical tree.
  - Missing project/worktree authority denies approval-free reads.
- Edge cases:
  - Reject `~`, `~/...`, sibling absolute paths, `..` traversal, and root-name
    prefix collisions.
  - Reject direct and intermediate symlinks that resolve outside the root.
  - Reject an in-root working directory symlinked outside the root.
- Failure paths:
  - Return a stable machine-readable denial code.
  - Record zero downstream filesystem or process executions after denial.
- Platform expectations: Cover POSIX separators and Windows drive-letter path
  comparison rules in pure path tests where the host platform permits it.

## Verification

Run focused tests while implementing, then the repository verification gate:

```bash
tool/codex_verify.sh --test test/features/chat/data/datasources/project_read_path_fence_test.dart
tool/codex_verify.sh --test test/features/chat/domain/services/project_scoped_read_tool_handler_test.dart
tool/codex_verify.sh --test test/features/chat/data/datasources/local_shell_tools_test.dart
tool/codex_verify.sh --test test/features/routines/data/routine_execution_service_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/providers/worktree_agent_task_executor_test.dart
tool/codex_verify.sh --no-codegen
```

## Handoff Notes

- Summary: Implementation and regression reconciliation are complete on the
  feature branch. One canonical
  fence now protects built-in filesystem reads, approval-free internal shell
  reads, interactive and Plan Mode dispatch, routines, worktree agents, Pro
  Reasoning, participant turns, and Personal Eval. Missing authority,
  traversal, prefix collisions, and symlink escapes fail before dispatch.
- Focused verification passed:
  - `project_read_path_fence_test.dart`
  - `project_scoped_read_tool_handler_test.dart`
  - `project_scoped_read_tool_runtime_adapter_test.dart`
  - `built_in_local_command_tool_handler_test.dart`
  - `local_shell_tools_test.dart`
  - `local_command_tool_handler_test.dart`
  - `background_process_tool_handler_test.dart`
  - `routine_execution_service_test.dart`
  - `worktree_agent_task_executor_test.dart`
  - `personal_eval_cases_notifier_test.dart`
  - `personal_eval_chat_replay_turn_driver_test.dart`
  - `participant_tool_production_ports_test.dart`
  - the exact `project_scoped_read_tool_handler.dart` file-size ratchet
  - `fvm flutter analyze`
- Repository gate: The complete machine-readable comparison used identical
  `flutter test --no-pub --reporter silent --file-reporter json:<path>` runs on
  current main `6ba903bf` and the integrated feature content committed as
  `9b56bc31`. Both runs emitted a terminal `done` event, contained zero malformed
  JSON lines, and reported the same 15 failures: four BLE/serial approval tests,
  one model-capability auto-probe test, and ten pre-existing file-size ratchets.
  `tool/flutter_test_failure_set.dart` reported 15 shared failures, zero
  base-only failures, and zero feature-only failures. The initial feature run
  had 48 feature-only ChatNotifier failures; explicit filesystem-effect
  ownership for pure adapters and correct owner-bound `executeFileTool`
  dispatch removed all 48 without relaxing the production fail-closed default.
- Current-main integration: Main commit `6ba903bf` was merged into the feature
  branch without conflicts. The representative ratchet, quit-dialog, and
  model-capability set reports the same 11 failures on current main and the
  integrated feature branch. After integration, `fvm flutter analyze`, all 214
  SEC4.4a focused tests, and all 92 LL39 tests changed by that main commit pass.
- Risks or follow-ups: Host-wide reads require a separate explicit capability.
  SEC4.4b owns mutation and autonomous external-tool containment. The 15 shared
  repository failures remain separate cleanup work and are not regressions from
  SEC4.4a. P0 work proceeds with SEC4.5a-SEC4.5b authenticated transport
  containment.
