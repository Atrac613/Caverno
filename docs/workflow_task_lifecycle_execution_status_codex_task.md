# Workflow Task Lifecycle Execution Status: Codex Task

## Task

- Goal: Make auto-continuation eligibility read completed-task status from
  `ExecutionTaskView` instead of the legacy compatibility projection.
- User-visible behavior: Automatic continuation starts only after execution
  progress records the completed task as completed.
- Non-goals: Migrating next-task selection, changing the continuation depth
  limit, changing status writers, or removing authored task status.

## Context

- Affected files or components:
  - `lib/features/chat/domain/services/workflow_task_run_lifecycle_policy.dart`
  - `test/features/chat/domain/services/workflow_task_run_lifecycle_policy_test.dart`
- Related docs:
  - `docs/chat_notifier_execution_task_view_codex_task.md`
  - `docs/chat_notifier_concept_overlap_inventory.md`
- Reference implementation or pattern: `ExecutionTaskView.status` treats
  progress as authoritative and missing progress as pending.
- Known quirks, compatibility rules, or release gates:
  `ConversationPlanExecutionCoordinator.nextTask` still reads the compatibility
  projection. This slice changes only the completed-task eligibility gate.

## Implementation Notes

- Preferred approach:
  - Find the completed task by ID in `conversation.executionTaskViews`.
  - Reject continuation unless the view status is completed.
  - Return a task snapshot whose status reflects the authoritative view.
- Constraints: Do not migrate the downstream next-task selector in the same
  slice.
- Generated files needed: No.
- Migration or data compatibility concerns: A legacy authored completed status
  without progress must stop authorizing automatic continuation.

## Similar-Pattern Search

- Search terms: `selectAutoContinuation`, `nextTask`, `activeTask`,
  `blockedTask`, and `projectedExecutionTasks`.
- Files or modules inspected: workflow task lifecycle policy, run coordinator,
  plan execution coordinator, execution snapshots, and lifecycle tests.
- Follow-up tasks found: Migrate `activeTask`, `nextTask`, and `blockedTask` as
  a separate selector slice with contradictory-status fixtures.

## Acceptance Criteria

- Required behavior:
  - Progress-completed permits eligibility even when authored status is pending.
  - Authored-completed without progress does not permit eligibility.
  - The returned completed task reports completed.
  - Depth and next-task safeguards remain unchanged.
- Edge cases: Missing task ID and non-completed progress still return null.
- Failure paths: No progress means pending and therefore no continuation.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
tool/codex_verify.sh --test \
  test/features/chat/domain/services/workflow_task_run_lifecycle_policy_test.dart
```

## Handoff Notes

- Summary: Auto-continuation now requires the completed task's
  `ExecutionTaskView.status` to be completed and returns a task snapshot with
  that authoritative status.
- Tests run:
  `tool/codex_verify.sh --test test/features/chat/domain/services/workflow_task_run_lifecycle_policy_test.dart`
  passed, including generated-file verification, project and package analysis,
  package tests, and 7 focused Flutter tests.
- Coverage or low-coverage notes: Contradictory authored/progress status
  fixtures cover both authority directions. Coverage mode was not run.
- Risks or follow-ups: Next-task selection remains compatibility-based. Migrate
  `activeTask`, `nextTask`, and `blockedTask` together so their ordering and
  returned task snapshots use one status authority consistently.
