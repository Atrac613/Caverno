# Workflow Recovery Route And Evidence Contract

## Task

- Goal: freeze the current workflow recovery route order, evidence precedence,
  retry ceiling, and liveness boundaries with direct coordinator tests before
  another extraction is designed.
- User-visible behavior: saved workflow execution keeps the same recovery
  prompts, completion decisions, bounded retries, stop conditions, and
  auto-continuation behavior.
- Non-goals: moving the recovery state machine, adding a policy abstraction,
  changing prompt copy, changing evidence semantics, increasing retry or
  continuation budgets, or modifying notifier and persistence ownership.

## Context

- Affected files or components:
  - `test/features/chat/presentation/coordinators/workflow_task_run_coordinator_test.dart`
  - `lib/features/chat/presentation/coordinators/workflow_task_run_coordinator.dart`
    only if characterization exposes a confirmed behavior defect
  - the large-file refactor plan and boundary inventory
- Related docs: `docs/large_file_refactor_plan.md` and
  `docs/large_file_boundary_inventory_2026_07_18.md`.
- Reference implementation or pattern: existing public-path coordinator tests
  use scripted visible and hidden turns, real production inference and
  guardrails, and an in-memory `ConversationsNotifier`.
- Known quirks, compatibility rules, or release gates:
  - initial tool evidence is captured before recovery routing;
  - successful validation promotion precedes recovery;
  - specialized recovery attempts precede assistant evidence;
  - assistant evidence precedes tool-less recovery;
  - edit mismatch may issue one read-context recovery and one edit retry, but
    must not loop;
  - page liveness must prevent post-unmount progress mutation;
  - the initial task plus at most eight auto-continuations remains unchanged;
  - the full `tool/codex_verify.sh --coverage --no-codegen` gate is required.

## Implementation Notes

- Preferred approach:
  1. retain the existing coordinator harness and add only the scripted result
     helpers needed by the new scenarios;
  2. prove assistant completion evidence prevents a tool-less recovery prompt;
  3. prove repeated edit mismatch evidence receives exactly one retry and
     leaves any third scripted recovery turn unused;
  4. prove unmounting during a hidden recovery send prevents later status or
     evidence mutation;
  5. rely on the existing continuation, blocked-task, incomplete-task, and
     visible-send liveness tests for the rest of the contract;
  6. run focused and full gates before recording the outcome.
- Constraints: tests must use no real LLM, network, shell command, filesystem
  mutation, Flutter UI, or wall clock.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_processTaskTurnResults`, `_maybeRecover`,
  `_captureExecutionProgress`, `onlyReadMismatchedFiles`, `depth + 1`,
  `_isPageMounted`, and `_isContextMounted`.
- Files or modules inspected: the coordinator, its direct tests, lifecycle
  policy tests, guardrail tests, and saved-workflow recovery tests.
- Follow-up tasks found: after this contract is green, define the smallest pure
  route-selection or evidence-assessment boundary. Do not combine that
  extraction with these characterization tests.

## Acceptance Criteria

- Required behavior:
  - assistant completion evidence finishes an eligible task without a hidden
    tool-less recovery prompt;
  - an edit mismatch receives no more than one retry after the initial recovery
    prompt;
  - hidden recovery completion after page unmount cannot mutate task progress;
  - existing eight-continuation, blocked-task, incomplete-task, validation,
    and visible-send liveness tests remain green;
  - production source remains unchanged unless a test proves an actual defect.
- Edge cases: empty tool results, repeated edit mismatch, an unused extra
  scripted hidden turn, and liveness changing while a hidden send is awaiting.
- Failure paths: incomplete evidence leaves the current task non-terminal and
  does not auto-continue.
- Accessibility, localization, or platform expectations: no UI, copy,
  localization, accessibility, or platform changes.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/presentation/coordinators/workflow_task_run_coordinator_test.dart \
  --test test/features/chat/presentation/pages/chat_page_saved_workflow_recovery_test.dart \
  --test test/features/chat/domain/services/workflow_task_run_lifecycle_policy_test.dart \
  --test test/features/chat/domain/services/workflow_tool_result_failure_detector_test.dart \
  --test test/features/chat/domain/services/conversation_plan_execution_guardrails_test.dart
```

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: complete. Three direct coordinator scenarios now freeze assistant
  evidence precedence, the bounded edit-mismatch retry, and liveness after a
  hidden recovery send. Characterization exposed and fixed one false-progress
  defect: a matching `read_file` result after `edit_mismatch` could complete a
  task with no target metadata before the edit retry ran. Matching recovery
  reads now remain context evidence and proceed to the single retry.
- Tests run: the focused verifier passed analysis, 94 root tests, and 13
  internal-package tests. The coordinator file-size ratchet passed at 2,392
  lines. The final full verifier passed analysis, 3,908 root tests, and 13
  internal-package tests.
- Coverage or low-coverage notes: total line coverage is 75.00%
  (53,384/71,175). Coordinator coverage rose from 59.95% (446/744) to 61.69%
  (459/744).
- Risks or follow-ups: define the smallest pure route-selection input and
  output contract before moving implementation. Keep prompts, retries,
  liveness checks, notifier writes, evidence capture, and recursion owned by
  the coordinator until that boundary is independently proven.
