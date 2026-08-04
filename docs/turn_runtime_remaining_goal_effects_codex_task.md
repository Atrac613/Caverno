# TurnRuntime Remaining Goal Effects: Codex Task

## Task

- Goal: Route completion elicitation and every remaining stop/clear projection
  in `_maybeAutoContinueCurrentGoal` through owner-bound runtime effects.
- User-visible behavior: Preserve notices and completion elicitation while
  preventing a stale owner from clearing or replacing the current owner's UI.
- Non-goals: Moving policy coordination, status persistence, logging
  projection, or the legacy cross-invocation reentrancy flag.

## Context

- Affected components:
  - `lib/features/chat/application/runtime/turn_runtime.dart`
  - `lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart`
  - runtime contract and production wiring tests
- Related docs:
  - `docs/chat_notifier_turn_runtime_prototype_port_matrix.md`
  - `docs/turn_runtime_typed_dispatch_effects_codex_task.md`
- Existing effect applier: `_applyTurnRuntimeGoalUiEffect`
- Existing hidden dispatcher: `_dispatchTurnRuntimeHiddenTurn`

## Implementation Notes

1. Add runtime factories for clear and notice UI effects.
2. Add one completion-elicitation dispatch containing a clear effect and an
   `update_goal`-only hidden-turn request.
3. Build the elicitation prompt inside the runtime operation from the supplied
   language code.
4. Replace direct clear and notice mutations inside the reserved orchestration
   method with the typed UI effect applier.
5. Reuse the hidden-turn dispatcher so owner validation remains centralized.

## Acceptance Criteria

- Completion elicitation returns the exact runtime owner, completion kind,
  normalized prompt, copied evidence, and `update_goal` allowlist.
- Every clear or notice projection in `_maybeAutoContinueCurrentGoal` uses an
  owner-bound runtime effect.
- A stale owner cannot clear the current owner's progress indicator.
- The wrapper performs owner validation before UI application and hidden
  dispatch.
- No callback, provider capture, or ambient read is added.
- Existing behavior, file-size limits, structural boundaries, and tests remain
  green.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/application/runtime/turn_runtime_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart
git diff --check
```

## Handoff Notes

- Summary: Completion elicitation now returns a clear UI effect and an
  `update_goal`-only hidden-turn request from `TurnRuntime`. All clear and stop
  notice projections in the reserved orchestration method now pass through the
  owner-validating typed effect applier.
- Tests run:
  - All 14 runtime contract and production wiring tests passed.
  - All 313 `chat_notifier_test.dart` tests passed.
  - All 262 file-size, collaborator-boundary, and thread-scope quality tests
    passed.
  - Targeted analysis of all 4 changed Dart files reported no issues.
  - `git diff --check` passed.
- Gate report:
  - Public surface: one immutable elicitation dispatch and three runtime effect
    factories.
  - Production line delta: +32 reported lines. `chat_notifier.dart` remains at
    8,906 lines, and its goal-auto-continue part fell from 806 to 804 lines.
  - No port, callback, provider capture, or ambient read was added.
  - Both hidden-turn kinds and all reserved-path UI projections are now typed,
    owner-bound effects.
- Risks or follow-ups: Policy coordination and goal-status effects remain in
  the wrapper. Cross-invocation runtime ownership is still required before the
  legacy reentrancy flag can be retired.
