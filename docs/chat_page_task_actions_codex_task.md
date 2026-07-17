# ChatPage Task Action Extraction

Status: complete on `feature/chat-page-task-actions`.

## Task

- Goal: extract legacy workflow task editing and persistence actions from the
  ChatPage library into independently tested presentation boundaries.
- User-visible behavior: none. Task proposal application, add/edit/delete,
  status transitions, blocker actions, notifications, and plan-document guards
  remain unchanged.
- Non-goals: workflow quick actions, scoped replan execution, blocked-reason
  dialog presentation, plan-document editing, task execution, or layout changes
  outside the task editor modal.

## Context

- Affected files or components:
  - `lib/features/chat/presentation/pages/chat_page.dart`
  - `lib/features/chat/presentation/pages/chat_page_workflow_support.dart`
  - a standalone workflow task editor widget
  - a workflow task action coordinator
  - direct widget, coordinator, and exact line-count tests
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 2, Tranche 3
  - `docs/chat_page_workflow_editor_actions_codex_task.md`
  - `docs/roadmap.md` F5
- Reference implementation or pattern: follow `WorkflowEditorSheet` and
  `WorkflowEditorActionCoordinator`, keeping modal presentation, localization,
  mounted checks, blocker dialogs, and scoped replanning in ChatPage.
- Known quirks, compatibility rules, or release gates:
  - task proposals replace only the task list, retain the latest workflow
    metadata, persist the tasks stage, and dismiss after persistence.
  - task editing is unavailable when the approved plan document is the source
    of truth; direct editor launch still shows the existing blocked notice.
  - legacy task status changes rewrite the workflow task list, while approved
    plan tasks update execution progress and preserve the workflow projection.
  - completed tasks move to review; in-progress and blocked tasks move to
    implement. Pending plan tasks do not force a stage change.
  - menu unblocking uses pending status and records an unblocked event.
  - blocker editing and scoped replanning remain page-owned UI flows.

## Implementation Notes

- Preferred approach:
  1. Move the private task editor sheet and typed submission values into a
     standalone widget without changing controls, copy, spacing, or parsing.
  2. Add direct widget tests for add, edit, normalization, status selection,
     delete, and cancel.
  3. Add `WorkflowTaskActionCoordinator` for task proposal application,
     add/replace/delete, status persistence, and menu-action routing through
     typed outcomes.
  4. Keep plan-document guards, modal launch, blocker dialogs, scoped replan,
     localized notifications, and mounted-context checks in thin page methods.
  5. Remove task action types and modal code from the ChatPage part file, then
     lower primary, aggregate, widget, and coordinator ratchets.
- Constraints:
  - Do not pass `BuildContext`, `WidgetRef`, `_ChatPageState`, localized strings,
    or modal callbacks into the coordinator.
  - Do not move workflow quick actions, task execution, or scoped replan logic.
  - Do not add another ChatPage `part` file; extracted boundaries must be
    independently imported so the aggregate library shrinks.
  - Preserve persistence ordering, workflow metadata, event summaries, and
    proposal dismissal after successful persistence.
- Generated files needed: none.
- Migration or data compatibility concerns: none. Conversation, workflow, and
  execution-progress schemas remain unchanged.

## Similar-Pattern Search

- Search terms: `_applyTaskProposal`, `_handleWorkflowTaskMenuAction`,
  `_showWorkflowTaskEditor`, `_replaceWorkflowTasks`,
  `_setWorkflowTaskStatus`, `_markWorkflowTaskUnblocked`,
  `_WorkflowTaskEditorSheet`, `_WorkflowTaskEditorSubmission`, and
  `_WorkflowTaskMenuAction`.
- Files or modules inspected: ChatPage primary and workflow part files,
  workflow and plan builders, conversation notifier, task run coordinator,
  workflow editor extraction, page tests, roadmap, and line-count ratchets.
- Follow-up tasks found: workflow quick actions remain separate because they
  persist a stage and then send an execution prompt. Scoped replanning remains
  page-owned until its dialog and planning-context boundary are characterized.

## Acceptance Criteria

- Required behavior:
  - the standalone modal renders the same status selector and four text fields.
  - save returns a trimmed title, normalized non-empty target file lines,
    trimmed validation and notes, selected status, and the existing task ID.
  - delete is available only for an existing task; cancel returns no submission.
  - new tasks receive a generated ID, existing tasks retain their position, and
    delete removes only the selected task.
  - proposal application uses the latest conversation metadata, persists the
    tasks stage, and dismisses the proposal after persistence.
  - legacy and plan-document status persistence retain their distinct storage
    paths and stage-transition rules.
  - ChatPage keeps plan-document blocking, modal launch, blocker dialogs,
    scoped replan, mounted checks, localization, and notifications.
- Edge cases:
  - an empty edited task title remains accepted, matching current behavior.
  - deleting a new unsaved task is ignored.
  - an empty replacement task list clears an otherwise empty workflow spec.
  - a newer current conversation supersedes the caller snapshot when tasks are
    replaced.
  - blocked status clears or supplies blocker text exactly as before.
- Failure paths: existing notifier failures continue to propagate. Task
  proposal dismissal must not run before a failed persistence call, and UI-only
  menu outcomes must not mutate persistence.
- Accessibility, localization, or platform expectations: retain Material field
  semantics, labels, button order, keyboard inset handling, safe area, and all
  existing translation keys. Direct tests perform no LLM, filesystem, network,
  or platform action.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/presentation/widgets/workflow/workflow_task_editor_sheet_test.dart \
  --test test/features/chat/presentation/coordinators/workflow_task_action_coordinator_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: moved the task editor modal into `WorkflowTaskEditorSheet` and
  extracted task proposal application, editor CRUD, menu routing, and legacy or
  plan-document status persistence into `WorkflowTaskActionCoordinator`.
  ChatPage retains modal launch, plan-document guards, blocker dialogs, scoped
  replanning, localization, notifications, and mounted-context checks. The page
  fell from 2,609 to 2,506 lines and its same-library aggregate fell from 9,986
  to 9,654 lines. The coordinator is ratcheted at 258 lines and the widget at
  209 lines.
- Tests run: the focused verifier passed 51 root tests plus 13
  internal-package tests. The full coverage verifier passed 3,680 root tests
  plus 13 internal-package tests with no analyzer findings or generated-file
  drift.
- Coverage or low-coverage notes: full repository line coverage was 73.98%
  (52,411/70,841). The coordinator and widget each reached 100.00% line
  coverage (70/70 and 99/99), while the remaining ChatPage primary file reached
  53.14% (516/971).
- Risks or follow-ups: ChatPage Tranche 3 is complete. Keep workflow quick
  actions page-owned because they send execution prompts after persistence.
  The next reviewable ChatPage slice is the Tranche 4 slash command handler,
  pinned by the existing slash-command product-path test.
