# ChatPage Workflow Editor Action Extraction

Status: complete on `feature/chat-page-workflow-editor-actions`.

## Task

- Goal: extract the legacy workflow editor modal and its save, clear, and
  workflow-proposal persistence actions from the ChatPage library into
  independently tested presentation boundaries.
- User-visible behavior: none. Initial values, field parsing, task retention,
  save and clear ordering, proposal merging, dismissal, notifications, and
  plan-document blocking remain unchanged.
- Non-goals: task proposal application, workflow quick actions, task editors,
  task-menu actions, plan-document editing, slash commands, workflow execution,
  or layout changes outside the modal extraction.

## Context

- Affected files or components:
  - `lib/features/chat/presentation/pages/chat_page.dart`
  - `lib/features/chat/presentation/pages/chat_page_workflow_support.dart`
  - a standalone workflow editor widget
  - a workflow editor persistence coordinator
  - direct widget, coordinator, and exact line-count tests
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 2, Tranche 3
  - `docs/chat_page_plan_review_actions_codex_task.md`
  - `docs/roadmap.md` F5
- Reference implementation or pattern: follow `PlanReviewActionCoordinator`
  for persistence orchestration without Flutter, localization, or Riverpod
  imports, while keeping modal presentation and localized feedback in widgets
  and the page.
- Known quirks, compatibility rules, or release gates:
  - plan-document-first conversations never open the legacy workflow editor;
    the page optionally opens the plan document editor and always shows the
    existing blocked-edit notification afterward.
  - the modal seeds from explicit proposal values when present and otherwise
    uses the conversation workflow stage and effective workflow spec.
  - save trims the goal, splits multiline lists, trims each line, removes empty
    lines, and retains the conversation's existing effective tasks rather than
    any task list from the initial proposal spec.
  - clear writes the idle stage with a cleared workflow spec before clearing the
    plan artifact.
  - empty saved specs are persisted as a cleared workflow spec.
  - proposal application replaces only workflow metadata while retaining the
    current conversation tasks, then dismisses the workflow proposal.
  - editor save or clear dismisses a proposal only when the caller requested
    `dismissWorkflowProposalOnSave`.

## Implementation Notes

- Preferred approach:
  1. Move `_WorkflowEditorSheet` and its submission values into a standalone
     widget file without changing controls, copy, spacing, or parsing.
  2. Add direct widget tests for conversation fallback, explicit initial-value
     precedence, line normalization, task retention, clear, and cancel.
  3. Add `WorkflowEditorActionCoordinator` for save, clear, and workflow
     proposal application with explicit typed outcomes.
  4. Keep the plan-document guard, modal launch, localized SnackBars, and
     mounted-context checks in thin ChatPage delegates.
  5. Remove the private sheet and submission types from the ChatPage part file,
     then lower primary, aggregate, widget, and coordinator ratchets.
- Constraints:
  - Do not pass `BuildContext`, `WidgetRef`, `_ChatPageState`, localized strings,
    or modal callbacks into the coordinator.
  - Do not move task proposal, quick action, task editor, or task-menu behavior.
  - Do not add another ChatPage `part` file; both extracted boundaries must be
    independently imported so the aggregate library shrinks.
  - Preserve switch ordering and proposal dismissal after persistence.
- Generated files needed: none.
- Migration or data compatibility concerns: none. Conversation and workflow
  schemas remain unchanged.

## Similar-Pattern Search

- Search terms: `_showWorkflowEditor`, `_WorkflowEditorSheet`,
  `_WorkflowEditorSubmission`, `_WorkflowEditorAction`,
  `_applyWorkflowProposal`, `_workflowLinesFromText`,
  `dismissWorkflowProposalOnSave`, `updateCurrentWorkflow`, and
  `updateCurrentPlanArtifact`.
- Files or modules inspected: ChatPage primary and workflow part files,
  workflow and plan builders, conversation notifier, chat state proposal
  values, plan-review coordinator, translations, page tests, roadmap, and
  line-count ratchets.
- Follow-up tasks found: task proposal application, task editor and task-menu
  actions remain the next Tranche 3 task-action slice. Workflow quick actions
  remain separate because they send an execution prompt after persistence.

## Acceptance Criteria

- Required behavior:
  - the standalone modal renders the same stage selector and four text fields,
    using explicit initial values before conversation fallbacks.
  - save returns the selected stage, trimmed goal, normalized non-empty list
    lines, and the conversation's existing effective tasks.
  - clear returns a typed clear submission and cancel returns no submission.
  - the coordinator saves non-empty specs, clears empty specs, and performs the
    two-step workflow-then-plan clear in the existing order.
  - proposal application retains current tasks, persists the proposal stage and
    metadata, and dismisses the proposal after persistence.
  - ChatPage keeps plan-document blocking, modal launch, mounted checks,
    localization, and notifications.
- Edge cases:
  - an explicit empty initial spec overrides non-empty conversation metadata but
    still retains conversation tasks on save.
  - whitespace-only goal and list lines produce an empty spec and therefore a
    cleared persisted workflow spec.
  - proposal metadata may be empty while current tasks remain non-empty.
  - the page may unmount while persistence is in progress; persistence and
    requested proposal dismissal still complete, but no notification is shown.
- Failure paths: no new error handling is introduced. Existing notifier errors
  continue to propagate, and proposal dismissal must not run before a failed
  persistence call.
- Accessibility, localization, or platform expectations: retain Material field
  semantics, labels, button order, keyboard inset handling, safe area, and all
  existing translation keys. Direct tests perform no LLM, filesystem, network,
  or platform action.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/presentation/widgets/workflow/workflow_editor_sheet_test.dart \
  --test test/features/chat/presentation/coordinators/workflow_editor_action_coordinator_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: moved the workflow editor modal into `WorkflowEditorSheet` and
  extracted save, clear, and workflow-proposal persistence into
  `WorkflowEditorActionCoordinator`. ChatPage retains the plan-document guard,
  modal launch, localized notifications, and mounted-context checks. The page
  fell from 2,632 to 2,609 lines, its same-library aggregate fell from 10,230
  to 9,986 lines, the coordinator is ratcheted at 88 lines, and the widget is
  ratcheted at 218 lines.
- Tests run: the focused verifier passed 44 root tests plus 13
  internal-package tests. The full coverage verifier passed the complete root
  suite plus 13 internal-package tests with no analyzer findings or generated
  file drift.
- Coverage or low-coverage notes: full repository line coverage was 73.43%
  (53,471/72,820). The coordinator reached 100.00% line coverage (25/25), the
  widget reached 97.06% (99/102), and the remaining ChatPage primary file
  reached 51.23% (520/1,015).
- Risks or follow-ups: task proposal application, task editor, and task-menu
  behavior remain the next Tranche 3 task-action slice. Characterize that
  ownership before deciding whether editor and menu actions fit one reviewable
  extraction. Keep workflow quick actions separate because they send execution
  prompts after persistence.
