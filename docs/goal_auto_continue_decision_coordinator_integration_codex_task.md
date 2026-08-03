# Goal Auto-Continue Decision Coordinator Integration

## Task

- Goal: route goal auto-continuation decisions through the existing pure
  `GoalAutoContinueDecisionCoordinator`.
- User-visible behavior: continuation, stop, block, repair, validation, and
  completion-elicitation behavior remains compatible.
- Non-goals: changing policy thresholds, prompt wording, persistence, or UI.

## Context

- Affected components: goal auto-continuation orchestration and tracker state.
- Related docs: `docs/chat_notifier_decomposition_workstream_8_codex_tasks.md`
  WS8-5 and `docs/large_file_refactor_plan.md`.
- Reference patterns: owner-scoped safe-boundary and tracker collaborators.
- Release gate: preserve owner checks before and after every await.

## Implementation Notes

- Capture the owner conversation, tracker snapshot, completion evidence,
  finalized response, safe boundary, and voice mode in one immutable input.
- Apply the returned tracker delta through `GoalAutoContinueTrackerRegistry`.
- Keep logging, goal status persistence, indicator updates, prompt building,
  and hidden-prompt dispatch in the notifier.
- Use the coordinator's execution snapshot, repair contract, capability
  profile, continuation limits, notice, and elicitation eligibility.
- Do not modify generated entities.

## Similar-Pattern Search

- Search terms: `_maybeAutoContinueCurrentGoal`,
  `_candidateGoalAutoContinueProgressStreak`, `_endsWithQuestionMark`,
  `_effectiveGoalAutoContinueBudget`, `GoalAutoContinuePolicyInput`,
  `StalledDiagnosticRepairContract`, and tracker updates.
- Files inspected: `chat_notifier_goal_auto_continue.dart`,
  `goal_auto_continue_decision_coordinator.dart`,
  `goal_auto_continue_tracker_registry.dart`, and their direct tests.
- Follow-up: extract goal-continuation log record construction after the
  coordinator is live.

## Acceptance Criteria

- The notifier delegates all pure decision and tracker-delta calculation to
  the coordinator.
- The notifier retains owner rechecks around asynchronous side effects.
- Block, stop notice, ordinary skip, elicitation, repair, validation, and
  unrestricted continuation routes remain covered.
- Owner conversation, evidence, boundary, queue, and generation poison tests
  remain green.
- The coordinator remains below 500 lines with 100% line coverage.
- Structural and file-size ratchets pass without raising budgets.

## Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/goal_auto_continue_decision_coordinator.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart \
  test/features/chat/domain/services/goal_auto_continue_decision_coordinator_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/goal_auto_continue_decision_coordinator_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

## Handoff Notes

- Record the input, plan, tracker-delta application, remaining orchestration,
  decision matrix, poison coverage, measured shrink, coverage, and follow-up.
