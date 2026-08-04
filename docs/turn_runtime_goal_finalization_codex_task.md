# TurnRuntime Goal Finalization: Codex Task

## Task

- Goal: Move delayed tracker removal and failed-dispatch repair cleanup behind
  typed `TurnRuntime` finalization operations.
- User-visible behavior: None. Removal and cleanup timing must remain exact.
- Non-goals: Moving awaited persistence, changing dispatch, or replacing the
  cross-invocation reentrancy flag.

## Context

- Affected components:
  - `lib/features/chat/application/runtime/turn_runtime.dart`
  - `lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart`
  - runtime contract and production wiring tests
- Related docs:
  - `docs/chat_notifier_turn_runtime_prototype_port_matrix.md`
  - `docs/turn_runtime_goal_tracker_transition_codex_task.md`

## Implementation Notes

1. Finalize a requested tracker removal only when the wrapper explicitly
   reports that blocked-status persistence completed.
2. Reject a transition produced for a different runtime owner.
3. Clear a pending repair contract only through the failed-dispatch
   finalization operation.
4. Keep both operations synchronous and owner-bound.

## Acceptance Criteria

- Applying a tracker transition never performs delayed removal.
- Persisted-block finalization removes only when requested by that transition.
- Cross-owner finalization fails before mutating tracker state.
- Repair cleanup occurs only when failed-dispatch finalization is invoked.
- The reserved wrapper path no longer calls either tracker cleanup method.
- Existing behavior, structural boundaries, and file-size ratchets remain
  green.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/application/runtime/turn_runtime_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart
git diff --check
```

## Handoff Notes

- Summary: Added owner-bound persisted-block and failed-dispatch finalization
  results. The runtime now delays requested tracker removal until the wrapper
  reports completed blocked-status persistence, rejects cross-owner
  transitions, and clears repair state only through explicit failed-dispatch
  finalization. The reserved wrapper path no longer calls tracker cleanup
  methods directly.
- Production impact: The runtime adds 48 lines while the reserved wrapper part
  falls from 795 to 793 lines, for a reported production delta of +46 lines.
  `chat_notifier.dart` remains at 8,906 lines. No port, callback, provider
  capture, or ambient read was added.
- Tests run:
  - 22 focused runtime and production-composition tests passed.
  - 313 ChatNotifier regression tests passed.
  - 262 file-size, collaborator-boundary, and thread-state quality tests
    passed.
  - Targeted analysis of the four changed Dart files passed.
  - `git diff --check` passed.
- Risks or follow-ups: The notifier reentrancy flag remains until the next
  slice defines an owner-scoped active runtime lifecycle.
