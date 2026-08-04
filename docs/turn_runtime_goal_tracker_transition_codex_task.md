# TurnRuntime Goal Tracker Transition: Codex Task

## Task

- Goal: Replace wrapper-side tracker-delta application and budget-notice
  reservation with one typed `TurnRuntime` transition.
- User-visible behavior: None. Tracker mutation timing, one-time notices,
  logging snapshots, and post-persistence removal must remain unchanged.
- Non-goals: Moving tracker removal, awaited persistence, logging, policy
  coordination, or effect application.

## Context

- Affected components:
  - `lib/features/chat/application/runtime/turn_runtime.dart`
  - `lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart`
  - runtime contract and production wiring tests
- Related docs:
  - `docs/chat_notifier_turn_runtime_prototype_port_matrix.md`
  - `docs/turn_runtime_goal_coordination_operation_codex_task.md`
- Existing input: `GoalAutoContinueTrackerDelta`

## Implementation Notes

1. Add an owner-bound transition result containing the updated snapshot,
   budget-notice reservation result, and delayed removal request.
2. Apply the existing delta through the tracker port.
3. Reserve the notice only when the delta requests it, preserving
   short-circuit behavior.
4. Invoke the transition at the existing block, stop, and continue points.
5. Keep tracker removal after blocked-status persistence.

## Acceptance Criteria

- Every delta reaches the tracker port unchanged.
- Notice reservation is not called when the delta does not request it.
- The transition result carries the exact runtime owner and removal request.
- The reserved wrapper path no longer calls `applyDelta` or
  `markBudgetNoticePresented` directly.
- Branch-specific transition timing and all existing behavior remain intact.
- No callback, provider capture, ambient read, or ratchet increase is added.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/application/runtime/turn_runtime_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart
git diff --check
```

## Handoff Notes

- Summary: `TurnRuntime.applyGoalTrackerTransition` now applies the existing
  tracker delta and conditionally reserves the one-time budget notice through
  the owner-scoped tracker port. Its typed result carries the exact owner,
  updated snapshot, notice outcome, and delayed-removal request. The wrapper
  invokes this transition at the original block, stop, and continue points.
- Production impact: The runtime boundary adds 30 lines while the reserved
  wrapper part falls from 800 to 795 lines, for a reported production delta of
  +25 lines. `chat_notifier.dart` remains at 8,906 lines. The public runtime
  surface adds one result type and one method, with no new port, callback,
  provider capture, or ambient read.
- Tests run:
  - 18 focused runtime and production-composition tests passed.
  - 313 ChatNotifier regression tests passed.
  - 262 file-size, collaborator-boundary, and thread-state quality tests
    passed.
  - Targeted analysis of the four changed Dart files passed.
  - `git diff --check` passed.
- Risks or follow-ups: Tracker removal and repair-contract cleanup remain
  explicit wrapper operations because their timing follows awaited work or
  failure handling. The next slice should expose typed runtime finalization
  operations without moving either action across those timing boundaries.
