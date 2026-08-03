# Conversation Task Selector Execution Status: Codex Task

## Task

- Goal: Make active, pending, and blocked task selection use
  `ExecutionTaskView.status` as the single execution-status authority.
- User-visible behavior: Task focus follows recorded execution progress;
  authored status without progress is treated as pending.
- Non-goals: Migrating every `projectedExecutionTasks` reader, changing task
  writers, changing selector priority, or removing authored status.

## Context

- Affected files or components:
  - `lib/features/chat/domain/services/conversation_plan_execution_coordinator.dart`
  - `test/features/chat/domain/services/conversation_plan_execution_coordinator_test.dart`
  - `test/features/chat/domain/services/workflow_task_run_lifecycle_policy_test.dart`
- Related docs:
  - `docs/workflow_task_lifecycle_execution_status_codex_task.md`
  - `docs/chat_notifier_execution_task_view_codex_task.md`
- Reference implementation or pattern: The lifecycle policy already resolves
  completed-task eligibility through `ExecutionTaskView` and returns a task
  snapshot with the authoritative status.
- Known quirks, compatibility rules, or release gates: Selector priority must
  remain in-progress, then blocked for execution focus, then pending. A task
  with authored completed status and no progress becomes pending by design.

## Implementation Notes

- Preferred approach:
  - Add one private adapter that copies view status onto task intent.
  - Iterate `executionTaskViews` in `activeTask`, `nextTask`, and `blockedTask`.
  - Keep public return types unchanged for existing callers.
- Constraints: Do not alter `validationTask` fallback ordering or unrelated
  prompt-building projection reads in this slice.
- Generated files needed: No.
- Migration or data compatibility concerns: Legacy authored non-pending status
  without progress no longer controls focus and is interpreted as pending.

## Similar-Pattern Search

- Search terms: `activeTask`, `nextTask`, `blockedTask`,
  `executionFocusTask`, `validationTask`, and `projectedExecutionTasks`.
- Files or modules inspected: plan execution coordinator, lifecycle policy,
  execution snapshots, prompt context, plan actions, coding verification,
  turn-owner snapshots, and direct selector tests.
- Follow-up tasks found: Migrate aggregate snapshot and prompt readers that
  still count or serialize legacy projected status.

## Acceptance Criteria

- Required behavior:
  - Progress in-progress wins over authored status.
  - Progress blocked wins over authored status.
  - Missing progress is pending even when authored status is completed.
  - Progress completed is skipped by pending selection.
  - Returned task snapshots expose the selected authoritative status.
- Edge cases: Task order remains stable within each status class.
- Failure paths: No matching active or blocked task returns null.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
fvm flutter test \
  test/features/chat/domain/services/conversation_plan_execution_coordinator_test.dart \
  test/features/chat/domain/services/workflow_task_run_lifecycle_policy_test.dart
tool/codex_verify.sh --test \
  test/features/chat/domain/services/conversation_plan_execution_coordinator_test.dart
```

## Handoff Notes

- Summary: Migrated active, pending, and blocked selectors to
  `executionTaskViews`. Public APIs still return workflow task snapshots, with
  the selected authoritative status copied onto task intent.
- Tests run:
  - Coordinator and lifecycle affected tests passed: 34 tests.
  - Execution snapshot, context-surgery path, and model-switch handoff
    regressions passed: 32 tests.
  - `tool/codex_verify.sh --test test/features/chat/domain/services/conversation_plan_execution_coordinator_test.dart`
    passed, including generated-file verification, project and package
    analysis, package tests, and 27 focused Flutter tests.
- Coverage or low-coverage notes: Contradictory authored/progress fixtures must
  cover active, blocked, pending, and completed selection. Coverage mode was
  not run.
- Risks or follow-ups: Aggregate projection readers remain compatibility-based.
  `validationTask` still uses the legacy projection as its metadata fallback,
  while its focus and next-task candidates now use progress-owned selectors.
