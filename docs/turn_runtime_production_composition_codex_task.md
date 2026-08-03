# TurnRuntime Production Composition: Codex Task

## Task

- Goal: Construct an owner-scoped `TurnRuntime` from all five production
  boundary implementations and route the reserved continuation path through
  the conversation, tracker, safe-boundary, and logging ports.
- User-visible behavior: None. Goal decisions, persistence, logging, and hidden
  dispatch must remain unchanged.
- Non-goals: Moving `_maybeAutoContinueCurrentGoal` into `TurnRuntime`, moving
  hidden-turn dispatch, or replacing the existing reentrancy flag.

## Context

- Affected files or components:
  - `lib/features/chat/presentation/providers/turn_runtime_production_composition.dart`
  - `lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart`
  - the five existing runtime boundary adapters
- Related docs:
  - `docs/chat_notifier_turn_runtime_prototype_port_matrix.md`
  - `docs/chat_notifier_turn_runtime_contracts_codex_task.md`
- Reference implementation or pattern:
  - `TurnRuntimeGoalContinuationPorts`
  - `_maybeAutoContinueCurrentGoal`
  - `ConversationsNotifierGoalRuntimeStore`
- Known quirks, compatibility rules, or release gates:
  - Goal continuation runs after the normal execution runtime and active
    response have been retired.
  - The composition scope therefore belongs to one continuation invocation,
    not `_startRuntimeTurn` or `_terminalizeRuntimeTurn`.
  - Tracker history remains conversation-spanning, while scheduling state is
    turn-local.
  - Logging context must remain lazy so non-recording paths do not add ambient
    conversation reads.

## Implementation Notes

- Preferred approach:
  1. Add a production composition object that owns the four shared boundaries
     and creates an owner scope with the fifth, owner-specific logging port.
  2. Construct the conversation and tracker adapters inside that composition
     object from their narrow stores.
  3. Keep log store and session context unbound until a record is actually
     emitted, then bind them explicitly without callbacks.
  4. Create one owner scope after the existing reentrancy and lease guards.
  5. Route conversation reads and status writes, tracker reads and deltas,
     safe-boundary capture, and logging through the runtime port bundle.
- Constraints:
  - Do not register the runtime with normal execution-turn terminalization.
  - Do not store `ChatNotifier`, `Ref`, providers, or notifier callbacks in the
    composition object or adapters.
  - Do not increase turn-reachable ambient reads.
  - Do not move the reentrancy guard until hidden dispatch becomes a returned
    typed effect.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Acceptance Criteria

- Required behavior:
  - Every owner scope contains the exact owner and all five concrete ports.
  - Conversation goal reads and writes in the reserved path use the runtime
    conversation port.
  - Continuation tracker reads and mutations in the reserved path use the
    runtime tracker port.
  - Safe-boundary and logging operations use the same owner runtime.
  - Disabled or unused logging does not build a session context or read the log
    store.
  - Tracker history is shared across generations, while runtime scheduling
    state is not.
- Edge cases:
  - An enabled log port fails clearly if recording is attempted before explicit
    configuration.
  - A missing owner conversation still exits before policy evaluation.
- Failure paths: Tying the composition scope to normal runtime terminalization,
  storing notifier callbacks, or adding ambient reads blocks the migration.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/presentation/providers/turn_runtime_production_composition_test.dart
tool/codex_verify.sh --test test/features/chat/data/datasources/turn_runtime_goal_continuation_log_adapter_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart --plain-name "goal auto-continue dispatches one hidden continuation from current evidence"
git diff --check
```

## Handoff Notes

- Summary: Added an owner-scoped production composition root, wired all five
  runtime ports into the reserved goal-continuation path, and kept logging
  dependencies lazy until a record is emitted. The tracker and conversation
  adapters are now used in production without storing `ChatNotifier`, `Ref`,
  providers, or callbacks.
- Tests run:
  - 11 focused composition and logging-adapter tests passed.
  - The focused hidden-continuation integration test passed.
  - All 313 `chat_notifier_test.dart` tests passed.
  - All 262 file-size, collaborator-boundary, and thread-scope quality tests
    passed.
  - Targeted analysis of all 7 changed Dart files reported no issues.
  - `git diff --check` passed.
- Gate report:
  - Reused ports: owner lease, conversation goal, tracker, safe boundary, and
    continuation log. No port or callback was added.
  - Returned effects: None moved in this slice.
  - Production files touched: 4, including the new composition file.
  - Public surface: `TurnRuntimeProductionComposition`,
    `TurnRuntimeProductionScope`, lazy log configuration, and log enablement.
  - Production line delta: +109 reported lines. The parent
    `chat_notifier.dart` moved from 8,900 to 8,906 lines, one line below its
    8,907-line ratchet limit.
  - Turn-reachable ambient reads do not increase: disabled and non-recording
    log paths do not read the conversation log store or build session context.
- Coverage or low-coverage notes: Moving the reserved orchestration method and
  hidden dispatch behind typed returned effects remains pending.
- Risks or follow-ups: The legacy reentrancy flag deliberately remains in the
  wrapper until hidden dispatch moves out of the runtime. The parent file has
  only one line of remaining headroom, so the next slice must be line-neutral
  or reduce it before adding declarations.
