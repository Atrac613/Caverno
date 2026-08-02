# Conversations Notifier Execution Task View Preservation: Codex Task

## Task

- Goal: Read existing workflow-task presence from `executionTaskViews` when an
  empty projection refresh requests preservation of the current task intent.
- User-visible behavior: Approved-plan tasks remain intact when a preservation
  update supplies no replacement tasks, including before progress is recorded.
- Non-goals: Changing preservation policy, migrating status writers, changing
  projection refresh parsing, or removing legacy task status.

## Context

- Affected files or components:
  - `lib/features/chat/presentation/providers/conversations_notifier.dart`
  - `test/features/chat/presentation/providers/conversations_notifier_test.dart`
- Related docs:
  - `docs/chat_notifier_execution_task_view_codex_task.md`
  - `docs/chat_notifier_execution_task_view_read_migration_codex_task.md`
  - `docs/chat_page_execution_task_view_presence_codex_task.md`
- Reference implementation or pattern: The coding-verification presence guard
  already uses `executionTaskViews` for a status-independent cardinality check.
- Known quirks, compatibility rules, or release gates: This guard affects which
  workflow spec is persisted, so a no-progress preservation regression is
  required even though both task lists have identical cardinality.

## Implementation Notes

- Preferred approach:
  - Replace only the existing-task presence clause in
    `updateCurrentWorkflow`.
  - Add a notifier test where an approved task has no execution progress and an
    empty replacement spec is supplied with preservation enabled.
- Constraints: Preserve the current workflow spec object and projection
  metadata exactly; do not migrate any status-based consumer.
- Generated files needed: No.
- Migration or data compatibility concerns: Legacy authored status may remain
  in the preserved task, but the guard must not inspect or reinterpret it.

## Similar-Pattern Search

- Search terms: `projectedExecutionTasks.isNotEmpty`,
  `preserveWorkflowProjection`, and `updateCurrentWorkflow`.
- Files or modules inspected: conversations notifier, workflow task actions,
  coding-verification feedback, assistant-turn progress updates, notifier
  preservation tests, and the unconnected ChatPage workflow panel.
- Follow-up tasks found: After this slice, no active cardinality-only legacy
  projection reads should remain. Status-reading consumers require separate
  fixture-backed migrations.

## Acceptance Criteria

- Required behavior:
  - Existing-task presence is read from `executionTaskViews`.
  - A task without progress survives an empty preservation update.
  - Workflow source hash and derived timestamp remain preserved.
- Edge cases: A legacy non-pending authored status without progress must not
  affect the presence decision.
- Failure paths: With no existing tasks, preservation must not invent tasks.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
fvm flutter test \
  test/features/chat/presentation/providers/conversations_notifier_test.dart \
  --plain-name "updateCurrentWorkflow preserves task intent without progress"
tool/codex_verify.sh --test test/features/chat/domain/entities/conversation_test.dart
```

## Handoff Notes

- Summary: Pending implementation.
- Tests run: Pending.
- Coverage or low-coverage notes: The focused notifier test covers the
  persistence-affecting no-progress branch.
- Risks or follow-ups: Status-based readers remain on the legacy projection.
