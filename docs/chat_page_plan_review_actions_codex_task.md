# ChatPage Plan Review Action Extraction

Status: complete on `feature/chat-page-plan-review-actions`.

## Task

- Goal: extract ChatPage plan review edit, cancel, and approve-and-start
  orchestration into an independently tested coordinator with narrow inputs and
  explicit outcomes.
- User-visible behavior: none. Plan editing, cancellation, approval,
  projection refresh, task selection, notifications, and execution start retain
  their existing order and copy.
- Non-goals: workflow editor handlers, task-menu handlers, plan review sheet
  presentation, automatic sheet presentation, slash commands, workflow task
  execution internals, or layout changes.

## Context

- Affected files or components:
  - `lib/features/chat/presentation/pages/chat_page.dart`
  - a new presentation coordinator under
    `lib/features/chat/presentation/coordinators/`
  - focused product-path and coordinator tests
  - exact primary-file, aggregate-library, and coordinator ratchets
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 2, Tranche 3
  - `docs/chat_page_decomposition_tranche2.md`
  - `docs/roadmap.md` F5
- Reference implementation or pattern:
  `WorkflowTaskRunCoordinator` keeps execution orchestration outside the page
  while the page owns navigation, localized UI, and mounted widget state.
- Known quirks, compatibility rules, or release gates:
  - the 2026-07-17 inventory recheck confirmed `chat_page.dart` at 2,738 lines
    and its same-library aggregate at 10,344 lines.
  - editing enters planning only when necessary, then pre-fills different copy
    for approved and draft plans and schedules a scroll after the frame.
  - cancellation restores approved Markdown only when pending edits exist,
    records a restored revision with the existing label, clears unapproved
    drafts, exits planning, and dismisses the proposal.
  - approval validates before mutation, chooses the existing workflow-stage
    fallback, records the approved revision, refreshes the persisted projection,
    falls back to the parsed workflow spec when needed, then selects the next
    task.
  - when no task can be selected, the page sends the existing localized generic
    execution prompt. Otherwise it enters the existing workflow task runner.
  - every current page and context liveness check remains in the same relative
    position.

## Implementation Notes

- Preferred approach:
  1. Add focused page-level characterization for edit, cancel, invalid
     approval, and successful approval entry points.
  2. Introduce `PlanReviewActionCoordinator` without Flutter, localization, or
     Riverpod imports.
  3. Move plan artifact mutation, projection refresh, stage fallback, task
     selection, and liveness decisions into the coordinator.
  4. Return typed outcomes for missing documents, blocked approval, aborted
     liveness, and approved execution.
  5. Keep composer state, post-frame scrolling, localized SnackBars, the generic
     execution prompt, and `_runWorkflowTask` calls in thin page delegates.
  6. Add direct coordinator coverage before deleting the page implementation,
     then lower exact line-count ratchets.
- Constraints:
  - Do not pass `BuildContext`, `WidgetRef`, `_ChatPageState`, or localized text
    into the coordinator.
  - Do not change persisted plan Markdown, revision labels, timestamps,
    workflow stage selection, task identity, prompt copy, or execution order.
  - Do not add another ChatPage `part` file; the extraction must reduce the
    aggregate library.
  - Keep workflow editor and task-menu work as later Tranche 3 slices.
- Generated files needed: none.
- Migration or data compatibility concerns: none. Existing conversation and
  plan artifact schemas remain unchanged.

## Similar-Pattern Search

- Search terms: `_editPlanInChat`, `_cancelPlanReview`,
  `_approveCurrentPlanAndStart`, `updateCurrentPlanArtifact`,
  `refreshCurrentWorkflowProjectionFromApprovedPlan`, `dismissPlanProposal`,
  `PlanReviewSheetAction`, and `_buildPlanEditSeed`.
- Files or modules inspected: ChatPage primary and part files, compact plan
  footer, plan review sheet, conversation notifier, plan projection and
  execution services, saved-workflow page tests, coordinator tests, roadmap,
  and file-size ratchets.
- Follow-up tasks found: workflow editor handlers and task-menu handlers remain
  separate Tranche 3 slices; slash commands and layout remain Tranches 4 and 5.

## Acceptance Criteria

- Required behavior:
  - edit enters planning only for a non-planning conversation and returns the
    exact approved or draft composer seed after a successful liveness check.
  - cancel uses the latest selected conversation, restores approved pending
    edits with the exact revision metadata, clears an unapproved draft, retains
    an unchanged approved plan, exits planning, and dismisses the proposal.
  - approve uses the latest selected conversation, rejects missing or invalid
    documents before persistence, and returns the validation error unchanged.
  - successful approval persists normalized stage Markdown, refreshes or
    reconstructs workflow projection as today, exits planning, dismisses the
    proposal, and returns the correct next task or generic-prompt decision.
  - the page keeps UI state, localization, scrolling, notifications, and task
    runner ownership behind thin delegates.
- Edge cases:
  - the selected conversation may change between opening review and acting.
  - a page may unmount after planning entry, artifact persistence, projection
    refresh, fallback workflow persistence, or planning exit.
  - a valid plan may produce no next task until the parsed workflow fallback is
    persisted, or may still produce no task afterward.
- Failure paths: invalid plan documents show the existing blocked-approval
  message and perform no plan, workflow, execution, or proposal mutation.
- Accessibility, localization, or platform expectations: keep all existing
  Material controls and translated strings in the page and widgets. Direct
  coordinator tests perform no platform, filesystem, network, or LLM action.

## Verification

Run the focused gate after characterization and extraction commits:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/presentation/pages/chat_page_plan_review_actions_test.dart \
  --test test/features/chat/presentation/coordinators/plan_review_action_coordinator_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: added `PlanReviewActionCoordinator` with typed missing-document,
  blocked, aborted, and ready outcomes. The coordinator now owns planning-entry
  decisions, cancellation persistence, approval validation and persistence,
  projection fallback, liveness checks, and next-task selection. ChatPage keeps
  composer state, post-frame scrolling, localization, SnackBars, the generic
  execution prompt, and the existing workflow task runner. `chat_page.dart`
  fell from 2,738 to 2,632 lines, its same-library aggregate fell from 10,344
  to 10,230 lines, and the independent coordinator is ratcheted at 198 lines.
- Tests run: the canonical focused verifier passed 47 root tests plus 13
  internal-package tests. The full coverage verifier passed the complete root
  suite plus 13 internal-package tests with no analyzer findings or generated
  file drift.
- Coverage or low-coverage notes: full repository line coverage was 73.27%
  (53,347/72,809). The new coordinator reached 88.89% line coverage (56/63),
  while the remaining ChatPage primary file reached 50.39% (520/1,032).
- Risks or follow-ups: workflow editor handlers and task-menu handlers remain
  separate Tranche 3 slices. Start with workflow editor actions because they
  form the next coherent modal-and-persistence boundary; keep task execution,
  slash commands, and layout out of that task.
