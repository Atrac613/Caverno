# Execution Snapshot Task Status: Codex Task

## Task

- Goal: Make execution snapshot task aggregates and completion action use
  `ExecutionTaskView.status` consistently with task selectors.
- User-visible behavior: Snapshot counts, remaining task IDs, active status,
  and required action agree on progress-owned execution status.
- Non-goals: Changing verification cadence, snapshot schema, task writers,
  prompt wording, or persistence.

## Context

- Affected files or components:
  - `lib/features/chat/domain/services/execution_snapshot_projector.dart`
  - `test/features/chat/domain/services/execution_snapshot_projector_test.dart`
- Related docs:
  - `docs/conversation_task_selector_execution_status_codex_task.md`
  - `docs/chat_notifier_execution_task_view_codex_task.md`
- Reference implementation or pattern: Plan execution selectors already
  iterate `executionTaskViews` and return status-normalized task snapshots.
- Known quirks, compatibility rules, or release gates: The snapshot currently
  gets its focus task from progress-owned selectors but counts completion and
  remaining IDs from the legacy projection.

## Implementation Notes

- Preferred approach:
  - Keep one local `taskViews` list in `project`.
  - Count completed and remaining entries from view status.
  - Pass views into `_actionFor` for the all-complete decision.
  - Read remaining IDs from view task intent.
- Constraints: Keep `ExecutionSnapshot` fields and serialization unchanged.
- Generated files needed: No.
- Migration or data compatibility concerns: Authored completed status without
  progress is pending and remains in the snapshot's remaining task IDs.

## Similar-Pattern Search

- Search terms: `completedTaskCount`, `remainingTaskCount`,
  `remainingTaskIds`, `_actionFor`, and `projectedExecutionTasks`.
- Files or modules inspected: execution snapshot projector, task selectors,
  verification cadence, goal auto-continue, snapshot tests, and prompt output.
- Follow-up tasks found: Goal auto-continue and planning-prompt aggregates
  still consume the legacy projection.

## Acceptance Criteria

- Required behavior:
  - Progress completed increments completed count even if authored pending.
  - Authored completed without progress remains pending and appears in
    remaining IDs.
  - Progress pending overrides authored completed and appears in remaining IDs.
  - Complete action requires every view status to be completed.
- Edge cases: Empty task lists do not produce complete action.
- Failure paths: Existing clarification, blocked, repair, and verification
  precedence remain unchanged.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
tool/codex_verify.sh --test \
  test/features/chat/domain/services/execution_snapshot_projector_test.dart
```

## Handoff Notes

- Summary: Snapshot completion counts, remaining counts and IDs, and the
  all-complete action now use one `executionTaskViews` list. Active task status
  remains supplied by the already-migrated selector.
- Tests run:
  `tool/codex_verify.sh --test test/features/chat/domain/services/execution_snapshot_projector_test.dart`
  passed, including generated-file verification, project and package analysis,
  package tests, and 20 focused Flutter tests.
- Coverage or low-coverage notes: One contradictory aggregate fixture asserts
  counts, IDs, active status, and action together. Coverage mode was not run.
- Risks or follow-ups: Other aggregate readers remain compatibility-based.
  Goal auto-continue is the highest-risk remaining control-flow aggregate and
  should be migrated with explicit legacy-completed/no-progress fixtures.
