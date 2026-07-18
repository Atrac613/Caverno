# Workflow Task Run Lifecycle Policy Extraction

## Task

- Goal: extract pure auto-continuation selection and terminal-status rules from
  `WorkflowTaskRunCoordinator` into a directly tested domain policy.
- User-visible behavior: saved workflows retain the same eight-continuation
  cap, next-task order, terminal statuses, prompts, and execution sequence.
- Non-goals: changing liveness checks, status writes, prompt text, hidden sends,
  result processing, recovery ordering, retry behavior, or recursion.

## Context

- Affected files or components:
  - `lib/features/chat/presentation/coordinators/workflow_task_run_coordinator.dart`
  - a new
    `lib/features/chat/domain/services/workflow_task_run_lifecycle_policy.dart`
  - focused policy, coordinator, recovery, and file-size tests
- Related docs: `docs/large_file_refactor_plan.md` and
  `docs/large_file_boundary_inventory_2026_07_18.md`.
- Reference pattern: the completed workflow failure detector extraction moved a
  pure decision while retaining every side effect and recovery route in the
  coordinator.
- Known compatibility rules:
  - continuation depth 0 through 7 may continue and depth 8 stops;
  - the refreshed task matching the completed task ID must still exist and have
    `completed` status;
  - the existing execution coordinator selects an `inProgress` task before the
    first `pending` task;
  - no candidate and same-ID candidates stop continuation;
  - only `completed` and `blocked` are terminal statuses;
  - page and context liveness remain coordinator-owned checks before and after
    every side effect;
  - the full `tool/codex_verify.sh --coverage --no-codegen` gate is required.

## Implementation Notes

- Preferred approach:
  1. add direct tests for the depth boundary, missing and non-completed current
     tasks, in-progress and pending precedence, same-ID protection, and every
     status;
  2. introduce an immutable auto-continuation selection containing the refreshed
     completed task and selected next task;
  3. move only selection and terminal classification into
     `WorkflowTaskRunLifecyclePolicy`;
  4. keep prompts, status mutation, sends, result capture, liveness, and
     recursive invocation in `WorkflowTaskRunCoordinator`;
  5. add exact non-increasing line-count ratchets for both files.
- Constraints: the policy may depend on conversation entities and the existing
  `ConversationPlanExecutionCoordinator.nextTask` rule, but not on Flutter,
  Riverpod, providers, notifiers, IO, time, or callbacks.
- Generated files needed: none.
- Migration or data compatibility concerns: none; the selection is transient
  and does not rewrite persisted workflow state.

## Similar-Pattern Search

- Search terms: `_continueToNextPendingTaskIfNeeded`, `depth >= 8`,
  `ConversationPlanExecutionCoordinator.nextTask`,
  `_taskReachedTerminalStatus`, `completed`, and `blocked`.
- Files or modules inspected: `workflow_task_run_coordinator.dart`, its direct
  tests, saved workflow recovery tests, `conversation.dart`, and
  `conversation_plan_execution_coordinator.dart`.
- Follow-up tasks found: recovery route ordering and progress evidence remain
  separate state-machine concerns. Do not include them here.

## Acceptance Criteria

- Required behavior:
  - depth 8 remains a hard stop and depth 7 remains eligible;
  - continuation requires the refreshed current task to be completed;
  - active-task and pending-task precedence remains unchanged;
  - duplicate same-ID candidates cannot create an auto-continuation loop;
  - terminal classification remains exactly completed or blocked;
  - existing coordinator and saved-workflow tests remain green;
  - the policy has no Flutter, provider, notifier, IO, time, or callback
    dependency;
  - both source files have non-increasing line-count ratchets.
- Edge cases: negative depth, missing current task, pending, in-progress, and
  blocked current tasks, no next task, duplicate IDs, and empty workflows.
- Failure paths: invalid selection state returns `null` without throwing.
- Accessibility, localization, or platform expectations: no UI, copy,
  localization, accessibility, or platform behavior changes.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/domain/services/workflow_task_run_lifecycle_policy_test.dart \
  --test test/features/chat/presentation/coordinators/workflow_task_run_coordinator_test.dart \
  --test test/features/chat/presentation/pages/chat_page_saved_workflow_recovery_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: complete. `WorkflowTaskRunLifecyclePolicy` now owns the depth cap,
  refreshed-completed-task requirement, compatible next-task selection,
  same-ID rejection, and terminal-status classification. The coordinator fell
  from 2,402 to 2,392 physical lines and retains every side effect.
- Tests run: the contract-focused gate passed 97 root tests and 13
  internal-package tests. The final policy and line-ratchet confirmation passed
  78 root tests and 13 internal-package tests. The final full gate passed
  analysis, 3,905 root tests, and 13 internal-package tests.
- Coverage or low-coverage notes: the policy reached 100.00% executable-line
  coverage (12/12). The remaining coordinator reached 59.95% (446/744), and
  their combined coverage reached 60.58% (458/756). Overall line coverage was
  74.98% (53,367/71,175). The originally selected continuation and
  terminal-status region was already covered at 100.00% (28/28).
- Risks or follow-ups: keep liveness, status mutation, prompts, recovery
  ordering, progress evidence, result processing, retry limits, and recursion
  out of this extraction. Require a separate route-and-evidence contract before
  moving the remaining recovery state machine.
