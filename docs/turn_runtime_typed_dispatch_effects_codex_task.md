# TurnRuntime Typed Dispatch Effects: Codex Task

## Task

- Goal: Make the normal goal-continuation branch obtain its progress UI update
  and hidden-turn request from one owner-bound `TurnRuntime` operation.
- User-visible behavior: None. The same progress values, prompt, evidence,
  verifier flags, tool allowlist, and error recovery must be preserved.
- Non-goals: Moving continuation policy coordination, completion elicitation,
  logging projection, or the legacy cross-invocation reentrancy flag.

## Context

- Affected components:
  - `lib/features/chat/application/runtime/turn_runtime.dart`
  - `lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart`
  - runtime contract and production integration tests
- Related docs:
  - `docs/chat_notifier_turn_runtime_prototype_port_matrix.md`
  - `docs/turn_runtime_production_composition_codex_task.md`
- Known lifecycle rule: A continuation runtime is scoped to one invocation
  after the active response has retired. Runtime scheduling state covers the
  synchronous hidden-dispatch handoff; the wrapper flag remains until
  cross-invocation ownership is migrated deliberately.

## Implementation Notes

1. Add one immutable dispatch result containing a UI effect and hidden-turn
   request.
2. Add a runtime operation that begins scheduling and returns that result, or
   returns no result when the same runtime is already scheduling.
3. Preserve defensive copying through `TurnRuntimeHiddenTurnRequest`.
4. Apply the UI effect only after validating its exact owner.
5. Validate the hidden-turn owner again before calling `sendHiddenPrompt`.
6. End runtime scheduling on synchronous handoff and in `finally`.

## Acceptance Criteria

- The runtime returns `TurnRuntimeShowGoalProgress` and a continuation-kind
  `TurnRuntimeHiddenTurnRequest` bound to its exact owner.
- A second begin attempt on the same runtime is rejected until scheduling ends.
- The wrapper no longer constructs the continuation prompt dispatch arguments
  directly after policy coordination.
- UI and hidden dispatch are both preceded by owner validation.
- No callback, Riverpod, `ChatState`, or `ChatNotifier` dependency enters the
  runtime contract.
- Existing goal continuation behavior and structural ratchets remain green.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/application/runtime/turn_runtime_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart
git diff --check
```

## Handoff Notes

- Summary: The normal continuation branch now asks `TurnRuntime` for one
  owner-bound dispatch containing its progress UI effect and hidden-turn
  request. The wrapper validates the owner independently before applying the UI
  effect and before dispatching the hidden turn.
- Tests run:
  - All 12 runtime contract and production composition tests passed.
  - The focused real hidden-continuation integration test passed.
  - All 313 `chat_notifier_test.dart` tests passed.
  - All 262 file-size, collaborator-boundary, and thread-scope quality tests
    passed.
  - Targeted analysis of all 4 changed Dart files reported no issues.
  - `git diff --check` passed.
- Gate report:
  - Public surface: one immutable dispatch result and one runtime begin method.
  - Production line delta: +80 reported lines. `chat_notifier.dart` remains at
    8,906 lines; its goal-auto-continue part moved from 770 to 806 lines.
  - No port, callback, provider capture, or ambient read was added.
  - Existing prompt, evidence, verifier flags, tool allowlist, persistence, and
    error recovery are preserved.
- Risks or follow-ups: Completion elicitation, stop/clear UI effects, and the
  full policy result remain wrapper-owned. Retire the legacy reentrancy flag
  only after a later slice defines cross-invocation runtime ownership.
