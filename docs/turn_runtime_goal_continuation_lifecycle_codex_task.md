# TurnRuntime Goal Continuation Lifecycle: Codex Task

## Task

- Goal: Replace the notifier-wide goal scheduling flag with an owner-scoped
  active `TurnRuntime` lifecycle shared across recursive entries.
- User-visible behavior: None. Recursive scheduling, synchronous handoff,
  cancellation, and reset behavior must remain safe.
- Non-goals: Changing continuation policy, tracker history, hidden-turn
  arguments, or awaited dispatch behavior.

## Context

- Affected components:
  - `lib/features/chat/application/runtime/turn_runtime.dart`
  - `lib/features/chat/presentation/providers/turn_runtime_production_composition.dart`
  - ChatNotifier continuation, cancellation, and reset paths
- Related docs:
  - `docs/chat_notifier_turn_runtime_prototype_port_matrix.md`
  - `docs/turn_runtime_goal_finalization_codex_task.md`

## Implementation Notes

1. Keep scheduling state on each runtime and let the notifier own the active
   runtime lifecycle from construction, then inject it into the production
   composition.
2. Reject a second runtime while one runtime owns the synchronous dispatch
   handoff.
3. Release the active runtime before awaiting the hidden continuation so its
   own finalization path can schedule safely.
4. Clear the active runtime during cancellation and message reset.
5. Remove `_isSchedulingGoalAutoContinue` from all production files.

## Acceptance Criteria

- One composition permits at most one active continuation runtime.
- Releasing a different runtime cannot release the active owner.
- Release and clear end the exact runtime's scheduling state.
- Failed claims leave the rejected runtime inactive.
- Cancellation and message reset clear the shared lifecycle.
- Production contains no legacy notifier reentrancy flag.
- Existing behavior, structural boundaries, and file-size ratchets remain
  green.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/application/runtime/turn_runtime_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart
git diff --check
```

## Handoff Notes

- Summary: Added a shared active-runtime lifecycle owned eagerly by the
  notifier and injected into the production composition. Each runtime still
  owns its scheduling state, while the shared lifecycle serializes the
  synchronous hidden-dispatch handoff across recursive entries. Release occurs
  before awaiting the continuation, and cancellation or message reset clears
  the exact active runtime even before Riverpod calls `build()`. The legacy
  notifier flag is removed from production.
- Production impact: The lifecycle adds 27 runtime lines and 25 net
  composition lines while the notifier files fall by three net lines, for a
  reported production delta of +49 lines. `chat_notifier.dart` falls from
  8,906 to 8,904 lines and its goal-auto-continue part falls from 793 to 792
  lines. No port, callback, provider capture, or ambient read was added.
- Tests run:
  - 24 focused runtime and production-composition tests passed.
  - 313 ChatNotifier regression tests passed.
  - 28 production-composition, safe-boundary, and terminal-adapter regression
    tests passed, including both pre-build `clearMessages` paths.
  - 262 file-size, collaborator-boundary, and thread-state quality tests
    passed.
  - Targeted analysis of the seven changed Dart files passed.
  - `git diff --check` passed.
- Risks or follow-ups: Formal comparison passes at production delta `+708`, one
  removed identity parameter, ambient-read delta `-1`, and zero new notifier
  callback captures. Full coverage and final live verification remain separate
  closure tasks.
