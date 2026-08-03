# Goal Auto-Continue Task Status: Codex Task

## Task

- Goal: Make saved-workflow continuation ownership use
  `ExecutionTaskView.status` instead of the legacy projected task status.
- User-visible behavior: Goal auto-continue remains deferred while any
  non-synthetic saved workflow task lacks completed execution progress.
- Non-goals: Changing goal budgets, diagnostic progression, verifier replay,
  the ChatNotifier pre-check, task writers, or persistence.

## Context

- Affected files or components:
  - `lib/features/chat/domain/services/goal_auto_continue_decision_coordinator.dart`
  - `test/features/chat/domain/services/goal_auto_continue_decision_coordinator_test.dart`
- Related docs:
  - `docs/execution_snapshot_task_status_codex_task.md`
  - `docs/conversation_task_selector_execution_status_codex_task.md`
- Reference implementation or pattern: Snapshot aggregates and task selectors
  already treat missing progress as pending.
- Known quirks, compatibility rules, or release gates: Synthetic short-prompt
  contracts remain exempt even though their generated task is pending.

## Implementation Notes

- Preferred approach: Iterate `executionTaskViews` for task presence and the
  any-not-completed ownership test.
- Constraints: Leave the equivalent ChatNotifier pre-check for a separate
  boundary-deduplication slice.
- Generated files needed: No.
- Migration or data compatibility concerns: Authored completed status without
  progress now defers goal auto-continue as unfinished saved workflow work.

## Similar-Pattern Search

- Search terms: `_savedWorkflowOwnsContinuation`,
  `savedWorkflowOwnsContinuation`, `projectedExecutionTasks`, and
  `ShortPromptContractBuilder.isSyntheticRequestContract`.
- Files or modules inspected: domain decision coordinator, ChatNotifier goal
  auto-continue part, decision fixtures, and live-progress notifier fixtures.
- Follow-up tasks found: Remove or delegate the duplicated ChatNotifier
  pre-check after domain decision coverage proves equivalent ordering.

## Acceptance Criteria

- Required behavior:
  - Pending progress defers continuation even if authored status is completed.
  - Missing progress defers continuation even if authored status is completed.
  - Completed progress allows continuation even if authored status is pending.
  - Synthetic saved workflow tasks remain exempt.
- Edge cases: An empty task list does not claim continuation ownership.
- Failure paths: Existing veto reason and detail remain unchanged.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
tool/codex_verify.sh --test \
  test/features/chat/domain/services/goal_auto_continue_decision_coordinator_test.dart
```

## Handoff Notes

- Summary: Saved-workflow continuation ownership now reads task status from
  `executionTaskViews`, so execution progress is authoritative and missing
  progress remains pending.
- Tests run:
  - `fvm flutter test test/features/chat/domain/services/goal_auto_continue_decision_coordinator_test.dart`
  - `tool/codex_verify.sh --test test/features/chat/domain/services/goal_auto_continue_decision_coordinator_test.dart`
- Coverage or low-coverage notes: The 39 focused decision tests cover both
  contradictory authority directions, missing progress, and the synthetic
  exemption.
- Risks or follow-ups: ChatNotifier retains an equivalent compatibility
  pre-check until a separate orchestration-boundary migration.
