# Workflow Task Turn Route Policy

## Task

- Goal: extract the saved-workflow turn recovery order and post-recovery gates
  from `WorkflowTaskRunCoordinator` into a small pure typed policy.
- User-visible behavior: saved workflow execution keeps the same evidence
  promotion, recovery precedence, assistant fallback, tool-less recovery,
  retry bounds, stopping, and auto-continuation behavior.
- Non-goals: moving recovery implementations, sending prompts from the policy,
  changing prompt copy, changing evidence semantics, changing retry or
  continuation budgets, moving liveness checks, moving notifier writes, or
  changing recursive task continuation.

## Context

- Affected files or components:
  - `lib/features/chat/domain/services/workflow_task_turn_route_policy.dart`
  - `lib/features/chat/presentation/coordinators/workflow_task_run_coordinator.dart`
  - direct policy and coordinator tests
  - the file-size ratchet and large-file refactor tracking docs
- Related contract:
  `docs/workflow_recovery_route_evidence_contract_codex_task.md`.
- Reference pattern: `WorkflowTaskRunLifecyclePolicy` and
  `WorkflowToolResultFailureDetector` are pure domain services while the
  coordinator retains every side effect.
- Known compatibility rules:
  - tool evidence capture and optional completion promotion happen before the
    recovery policy is consulted;
  - recovery routes run only when tool evidence was not applied;
  - the exact recovery order is validation-first, tool failure, missing target,
    missing Python runtime, missing Python test dependency, Python source
    layout, then task drift;
  - the first successful recovery stops the route sequence;
  - assistant evidence runs only when completion was not promoted and no
    recovery succeeded;
  - tool-less recovery runs only when tool evidence was not applied and no
    recovery succeeded; it still receives the assistant-evidence result;
  - retry bodies, liveness checks, progress writes, and recursion remain in the
    coordinator;
  - the full `tool/codex_verify.sh --coverage --no-codegen` gate is required.

## Implementation Notes

- Preferred approach:
  1. add a typed recovery-route enum and a pure policy exposing the exact
     ordered routes plus assistant-evidence and tool-less gates;
  2. cover the complete route order and boolean gate truth tables directly;
  3. replace the coordinator's repeated boolean ladder with an early-exit loop
     over the typed routes;
  4. keep a coordinator-owned dispatcher that invokes the existing recovery
     methods without changing their arguments or bodies;
  5. lower the coordinator line ratchet and add a non-increasing ratchet for
     the new policy;
  6. run focused and full coverage gates before recording the outcome.
- Constraints: the policy must import no Flutter, Riverpod, notifier,
  filesystem, network, shell, clock, or LLM dependency.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_processTaskTurnResults`, `_maybeRecover`,
  `completionPromoted`, `toolResultApplied`, `recoveredFrom`,
  `WorkflowTaskRunLifecyclePolicy`, and
  `WorkflowToolResultFailureDetector`.
- Files or modules inspected: the coordinator, direct coordinator tests,
  product-path saved-workflow recovery tests, lifecycle policy, failure
  detector, and file-size ratchet.
- Follow-up tasks found: after this extraction, re-rank the coordinator against
  the newly unblocked ChatPage characterization target. Do not combine that
  work with this policy slice.

## Acceptance Criteria

- Required behavior:
  - direct tests freeze the exact seven-route order;
  - applied tool evidence yields no recovery routes;
  - promoted completion or a successful recovery suppresses assistant evidence;
  - applied tool evidence or a successful recovery suppresses tool-less
    recovery;
  - the coordinator stops after the first successful typed recovery route;
  - all existing recovery precedence, evidence, liveness, bounded retry,
    terminal stopping, and continuation tests remain green;
  - the coordinator shrinks and both line budgets are non-increasing.
- Edge cases: no applied tool evidence, applied non-terminal tool evidence,
  promoted completion, failed recovery attempts, and the first successful
  recovery at any position.
- Failure paths: no successful specialized recovery still reaches assistant
  evidence and then the existing bounded tool-less recovery path.
- Accessibility, localization, or platform expectations: no UI, copy,
  localization, accessibility, or platform behavior changes.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/domain/services/workflow_task_turn_route_policy_test.dart \
  --test test/features/chat/presentation/coordinators/workflow_task_run_coordinator_test.dart \
  --test test/features/chat/presentation/pages/chat_page_saved_workflow_recovery_test.dart \
  --test test/features/chat/domain/services/workflow_task_run_lifecycle_policy_test.dart \
  --test test/features/chat/domain/services/workflow_tool_result_failure_detector_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: complete. `WorkflowTaskTurnRoutePolicy` owns the exact seven-route
  recovery order plus the assistant-evidence and tool-less recovery gates.
  `WorkflowTaskRunCoordinator` now iterates that typed order and retains an
  exhaustive dispatcher for every existing side-effecting recovery method.
- Tests run: the focused verifier passed analysis, 110 root tests, and 13
  internal-package tests. The final full verifier passed analysis, 3,913 root
  tests, and 13 internal-package tests.
- Coverage or low-coverage notes: total line coverage reached 75.01%
  (53,400/71,190). The 43-line policy reached 100.00% executable-line coverage
  (3/3). The coordinator shrank from 2,392 to 2,380 physical lines and reached
  62.17% coverage (470/756).
- Risks or follow-ups: preserve the pure policy and both non-increasing line
  ratchets. The next slice is a separate contract-only characterization of the
  remaining ChatPage workspace, project, drawer, and sidebar state cluster.
