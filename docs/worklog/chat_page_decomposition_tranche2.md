# ChatPage Decomposition - Tranche 2

Status: completed on 2026-07-16.

## Goal

Extract saved-workflow task execution, validation, recovery, evidence capture,
and auto-continuation from `_ChatPageState` into a presentation-layer
coordinator. Preserve every prompt, recovery priority, task status transition,
and mounted-state boundary.

## Current Boundary

- Source: `lib/features/chat/presentation/pages/chat_page.dart`
- Primary file size at tranche start: 5,168 lines.
- Aggregate ChatPage library size at tranche start: 12,774 lines.
- Extraction region: `_runWorkflowTask` through the execution evidence helpers,
  currently about 2,500 lines.
- Destination:
  `lib/features/chat/presentation/coordinators/workflow_task_run_coordinator.dart`
- Expected result: keep thin page delegates and reduce the primary file to
  roughly 2,700 lines and the aggregate library to roughly 10,300 lines.

## Invariants

- Keep `ChatPage` navigation, UI state, and public constructor unchanged.
- Do not change localized copy, generated prompts, tool-result interpretation,
  recovery priority, auto-continue depth, or task status semantics.
- Do not add `BuildContext`, `WidgetRef`, or widget ownership to the extracted
  coordinator.
- Keep `_setWorkflowTaskStatus` in the page during this tranche because later
  plan-review actions still use it.
- Pass language codes and translated prompt fragments into the coordinator.
- Keep workspace target-file checks behaviorally identical. A filesystem
  abstraction is a separate follow-up.
- Do not combine this tranche with plan approval actions, slash commands,
  layout changes, MCP decomposition, or another package extraction.

## Task 1 - Pin Product-Path Behavior

Add or extend widget tests that enter through the saved-plan UI and exercise
the real ChatPage orchestration path. Provider overrides and scripted notifier
results are preferred over production-only test hooks.

Required characterization coverage:

1. Successful validation-shaped task evidence completes the current task
   without a recovery prompt.
2. Failed task evidence blocks the current task and does not auto-continue.
3. Completing one task starts the next task in a separate hidden turn.
4. Auto-continuation stops at the depth limit and never advances past a blocked
   or incomplete task.
5. Each recovery family has at least one representative result, and only the
   first matching recovery path executes.
6. Hidden assistant fallback evidence is consumed at most once.
7. No prompt, task mutation, or recursive continuation occurs after unmount.

Commit characterization tests before moving production code. If a test exposes
an existing defect, fix it in a separate bug-fix commit before extraction.

`_runWorkflowTaskValidation` has two legacy UI call sites, but both are under
the unused `_buildWorkflowPanel`. The active compact footer and plan review
sheet do not expose `Run validation` or `Retry validation`. Do not restore that
action as part of this behavior-preserving tranche. Test the coordinator's
public validation entry point directly after extraction, and track any product
UI restoration as a separate behavior change.

## Task 2 - Close the Python Runtime Recovery Guard

The initial and auto-continue execution paths currently track
`recoveredFromPythonRuntimeDependency`, but their later assistant-evidence and
tool-less recovery conditions do not include it. Add a deterministic regression
test first. If it reproduces duplicate processing, add the missing guard in both
paths without changing the recovery prompt.

## Task 3 - Extract the Coordinator

Create `WorkflowTaskRunCoordinator` with explicit dependencies for:

- the chat notifier;
- the conversations notifier;
- the current-conversation lookup;
- the active-project-root lookup;
- the page-owned task-status callback;
- mounted-state checks; and
- a clock callback where timestamps are produced.

Move one behavior cluster at a time while keeping thin page delegates:

1. task execution and validation;
2. auto-continuation;
3. the recovery pipeline;
4. completion promotion; and
5. assistant and tool-result evidence capture.

Add direct coordinator coverage for successful and failed saved validation
before deleting the page implementation. This replaces the unavailable public
widget path without introducing a production-only test hook.

Do not let the coordinator read Riverpod providers directly. It may depend on
the existing notifier types while this remains an application-internal
presentation boundary.

## Task 4 - Consolidate and Ratchet

After the mechanical extraction is green, consolidate the duplicated evidence
pipeline used by direct task execution and auto-continuation. Keep this cleanup
in a separate commit, then lower both ChatPage line-count ratchets to the new
measured values.

## Completion Evidence

- The saved-workflow product path has 12 characterization scenarios covering
  execution, recovery routing and priority, hidden fallback consumption, and
  direct plus auto-continued Python runtime dependency recovery.
- The coordinator has 7 direct scenarios covering saved validation success and
  failure, the initial-plus-eight continuation limit, blocked and incomplete
  stopping, and page-unmount liveness for task execution and validation.
- A Python runtime recovery fallthrough and a validation-after-unmount defect
  were fixed in separate commits before closeout.
- `chat_page.dart` fell from 5,168 to 2,738 lines. Its same-library aggregate
  fell from 12,774 to 10,344 lines, while the independent coordinator is held
  at a 2,442-line ratchet.
- The page keeps thin delegates and the coordinator imports neither Flutter,
  localization, nor Riverpod directly.
- The canonical focused verifier passed root and package analysis, 13 internal
  package tests, and 31 focused root tests.
- The broader coverage gate passed all 3,422 root tests with 72.05% line
  coverage and no generated-file drift or analyzer findings.

## Verification

Run focused checks after each commit:

```bash
tool/codex_verify.sh \
  --no-codegen \
  --test test/features/chat/presentation/pages/chat_page_saved_workflow_recovery_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate after the final extraction:

```bash
tool/codex_verify.sh --coverage
```

No live LLM canary is required because this tranche must preserve orchestration
behavior. Add a canary only if a separate behavior change is approved.
