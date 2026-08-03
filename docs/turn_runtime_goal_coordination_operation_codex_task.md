# TurnRuntime Goal Coordination Operation: Codex Task

## Task

- Goal: Move owner conversation lookup, tracker snapshot, safe-boundary
  capture, and continuation policy coordination behind one synchronous
  `TurnRuntime` operation.
- User-visible behavior: None. Policy inputs, decisions, logging, persistence,
  and returned effects must remain unchanged.
- Non-goals: Moving presentation-state synchronization, awaited logging,
  status persistence, tracker mutation, or effect application.

## Context

- Affected components:
  - `lib/features/chat/application/runtime/turn_runtime.dart`
  - `lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart`
  - runtime contract and production wiring tests
- Related docs:
  - `docs/chat_notifier_turn_runtime_prototype_port_matrix.md`
  - `docs/turn_runtime_remaining_goal_effects_codex_task.md`
- Existing input contract: `TurnRuntimeGoalContinuationInput`
- Existing coordinator: `GoalAutoContinueDecisionCoordinator`

## Implementation Notes

1. Add a sealed unavailable/ready coordination result bound to the runtime
   owner.
2. Have the runtime read the owner conversation exactly once.
3. When present, capture the tracker and safe boundary and invoke the existing
   coordinator with the immutable continuation input.
4. Keep visible-state synchronization in the wrapper immediately before the
   runtime operation.
5. Keep all awaited operations and mutations in the wrapper.

## Acceptance Criteria

- A missing owner conversation returns a typed unavailable result without
  reading tracker or safe-boundary state.
- A ready result contains the exact owner, conversation, tracker snapshot,
  safe boundary, and existing decision plan.
- The reserved wrapper path no longer calls `conversationFor`, `snapshotFor`,
  safe-boundary `capture`, or `GoalAutoContinueDecisionCoordinator` directly.
- No callback, provider capture, new ambient read, or behavior change is added.
- Existing structural and file-size ratchets remain green.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/application/runtime/turn_runtime_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart
git diff --check
```

## Handoff Notes

- Summary: `TurnRuntime.coordinateGoalContinuation` now performs the exact
  owner conversation lookup, tracker snapshot, safe-boundary capture, and
  existing decision-coordinator invocation. It returns a sealed unavailable or
  ready result; the wrapper retains visible-state synchronization and all
  awaited work.
- Tests run:
  - All 16 runtime contract and production wiring tests passed.
  - All 313 `chat_notifier_test.dart` tests passed.
  - All 262 file-size, collaborator-boundary, and thread-scope quality tests
    passed.
  - Targeted analysis of all 4 changed Dart files reported no issues.
  - `git diff --check` passed.
- Gate report:
  - Public surface: one sealed coordination result family and one synchronous
    runtime operation.
  - Production line delta: +54 reported lines. `chat_notifier.dart` remains at
    8,906 lines, and its goal-auto-continue part fell from 804 to 800 lines.
  - Missing conversation exits before tracker or safe-boundary reads; focused
    tests assert both call counts remain zero.
  - No callback, provider capture, new ambient read, or behavior change was
    added.
- Risks or follow-ups: Tracker mutations, logging, persistence, and effect
  application remain wrapper-owned. Cross-invocation runtime ownership remains
  separate from this synchronous coordination boundary.
