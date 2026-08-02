# Chat Page Execution Task View Presence: Codex Task

## Task

- Goal: Read hydrated-plan task presence from `executionTaskViews` instead of
  the legacy projected task list.
- User-visible behavior: The current execution view remains visible for an
  approved plan with workflow tasks, including when no progress exists yet.
- Non-goals: Migrating hydrated task status rendering, changing status labels,
  changing plan actions, or modifying persistence.

## Context

- Affected files or components:
  - `lib/features/chat/presentation/pages/chat_page_plan_builders.dart`
  - `test/features/chat/presentation/pages/chat_page_saved_workflow_recovery_test.dart`
- Related docs:
  - `docs/chat_notifier_execution_task_view_codex_task.md`
  - `docs/chat_notifier_execution_task_view_read_migration_codex_task.md`
- Reference implementation or pattern: The coding-verification presence guard
  already reads `executionTaskViews` without changing downstream status logic.
- Known quirks, compatibility rules, or release gates: The selected condition
  reads only list emptiness. `_buildHydratedPlanView` still consumes the legacy
  projection, preserving current labels and source-status fallback.

## Implementation Notes

- Preferred approach:
  - Replace only the hydrated-view presence condition.
  - Add a widget regression proving a task with no progress still renders the
    current execution view.
- Constraints: Leave `conversations_notifier` as the final cardinality-only
  production consumer because its decision affects persisted workflow state.
- Generated files needed: No.
- Migration or data compatibility concerns: None. `executionTaskViews` retains
  workflow task cardinality independently of progress.

## Similar-Pattern Search

- Search terms: `projectedExecutionTasks.isNotEmpty`,
  `projectedExecutionTasks.isEmpty`, `_buildHydratedPlanView`, and
  `plan_document_hydrated_title`.
- Files or modules inspected: plan builders, saved-workflow widget harness,
  coding-verification feedback, and conversation workflow preservation.
- Follow-up tasks found: Audit the remaining `conversations_notifier`
  cardinality check with persistence-focused tests before migrating it.

## Acceptance Criteria

- Required behavior:
  - Hydrated-plan presence is read from `executionTaskViews`.
  - A workflow task without progress still renders the current execution view.
  - Hydrated status rendering remains on the compatibility projection.
- Edge cases: Missing progress is pending in the view and must not hide the UI.
- Failure paths: An empty workflow task list still omits the hydrated view.
- Accessibility, localization, or platform expectations: Existing localized
  labels and widget semantics remain unchanged.

## Verification

```bash
fvm flutter test \
  test/features/chat/presentation/pages/chat_page_saved_workflow_recovery_test.dart \
  --plain-name "approved plan task without progress shows current execution view"
tool/codex_verify.sh --test test/features/chat/domain/entities/conversation_test.dart
```

## Handoff Notes

- Summary: Stopped before implementation. Repository-wide invocation search
  found no caller for `_buildWorkflowPanel`; the method is explicitly covered
  by an unused-element suppression. Its nested hydrated-view condition is not
  an active production read path.
- Tests run: The proposed widget regression failed because the hydrated view
  was absent from the mounted `ChatPage`, confirming the invocation audit. The
  uncommitted production and test changes were removed.
- Coverage or low-coverage notes: No coverage was added because the candidate
  path is not mounted. Existing workflow UI tests do not reach this method.
- Risks or follow-ups: Do not count this dead nested condition as M1 migration
  progress. Audit whether `_buildWorkflowPanel` should be removed or reconnected
  as a separate ChatPage cleanup. Continue M1 with the active
  `conversations_notifier` workflow-preservation guard.
