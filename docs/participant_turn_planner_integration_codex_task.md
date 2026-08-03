# Integrate Participant Turn Planner

## Goal

Delegate participant normalization, speaker progression, stop handling, pause
state, completion selection, and runtime projection from `ChatNotifier` to the
existing deterministic `ParticipantTurnPlanner` state machine.

## Scope

- Start one immutable planner state for each new or resumed participant turn.
- Persist normalized participants only for a newly sent conversation turn.
- Keep participant streaming, persistence, queue draining, and control-registry
  mutations as notifier effects.
- Apply planner-produced active and paused runtime projections to the exact
  owner thread.
- Feed each participant completion, handoff, and exact-owner stop request back
  into the planner before selecting the next typed step.

## Non-goals

- Moving participant completion streaming or message finalization.
- Changing `ParticipantTurnControlRegistry` ownership or pause snapshots.
- Changing participant ordering, round limits, handoff semantics, or runtime
  labels.
- Regenerating the stale turn-scope baseline in this focused slice.

## Acceptance Criteria

1. The notifier does not call `ParticipantTurnCoordinator.nextSpeaker` or
   construct active or paused runtime decisions directly.
2. New and resumed turns execute planner steps until the exact owner reaches a
   typed pause, completion, or empty-roster terminal state.
3. Final-turn completion remains higher priority than a simultaneous stop
   request, and handoff preferences remain one-shot.
4. Cursor, handoff, stop, pause snapshot, runtime projection, and terminal
   effects remain scoped to the planner state's exact owner during visible
   thread switches and concurrent detached turns.
5. Direct planner coverage remains 100%, focused notifier and owner-poison tests
   pass, and the notifier same-library aggregate does not grow.
6. Full verification introduces no failure beyond the recorded
   stalled-diagnostic canary-runner baseline mismatch.

## Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/participant_turn_planner.dart \
  test/features/chat/domain/services/participant_turn_planner_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/participant_turn_planner_test.dart
fvm flutter test \
  test/features/chat/presentation/providers/chat_notifier_test.dart \
  test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

## Completion Evidence

- `ParticipantTurnPlanner` direct coverage: 100% (85/85 lines).
- Focused planner, notifier, detached-owner, collaborator-boundary, and size
  ratchet tests pass.
- The participant notifier part decreased from 802 to 779 lines, and the
  notifier same-library aggregate decreased from 19,298 to 19,276 lines.
- `tool/codex_verify.sh --coverage` completed with 6,565 passing tests and only
  the recorded `stalled-diagnostic runner selects the constrained repair
  scenario` baseline mismatch failing.
