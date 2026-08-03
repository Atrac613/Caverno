# TurnRuntime Goal Continuation Log Adapter: Codex Task

## Task

- Goal: Route typed goal-continuation records through the runtime logging port
  without storing `ChatNotifier`, `Ref`, or a notifier callback.
- User-visible behavior: None. Log enablement, context, payload, timestamp, and
  write-failure behavior must remain unchanged.
- Non-goals: Moving completion-shadow logging, moving continuation
  orchestration, or constructing the complete `TurnRuntime` composition root.

## Context

- Affected files or components:
  - `lib/features/chat/data/datasources/turn_runtime_goal_continuation_log_adapter.dart`
  - `lib/features/chat/presentation/providers/chat_notifier.dart`
  - `lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart`
- Related docs:
  - `docs/chat_notifier_turn_runtime_prototype_port_matrix.md`
  - `docs/turn_runtime_goal_safe_boundary_adapter_codex_task.md`
- Reference implementation or pattern:
  - `_recordGoalAutoContinueSessionLog`
  - `LlmSessionLogStore.recordGoalAutoContinue`
  - `TurnRuntimeGoalContinuationLogPort`
- Known quirks, compatibility rules, or release gates:
  - Environment configuration overrides the persisted logging setting.
  - Disabled logging returns before reading conversation generations or
    building a session context.
  - The session log store catches write failures and reports them through the
    existing logger instead of failing the turn.

## Implementation Notes

- Preferred approach:
  1. Implement `TurnRuntimeGoalContinuationLogPort` in the data layer.
  2. Accept only the log store, an explicit session context, the settings flag,
     and a clock used for the persisted timestamp.
  3. Preserve the environment-aware enablement rule inside the adapter and
     expose it for the wrapper's pre-read early return.
  4. Map every field from `GoalAutoContinueLogRecord` to the existing store
     method without rebuilding or weakening the typed record.
  5. Construct the adapter in the production wrapper and invoke it through the
     port method.
- Constraints:
  - Do not store `ChatNotifier`, `Ref`, providers, or notifier callbacks.
  - Do not introduce a generic map request in place of the typed record.
  - Do not read conversation state when logging is disabled.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Acceptance Criteria

- Required behavior:
  - Enabled logging persists the same `goal_auto_continue` schema and payload.
  - Settings-disabled and environment-disabled configurations write nothing.
  - Environment enablement still overrides a disabled setting.
  - The production path contains no direct `recordGoalAutoContinue` store call.
  - The adapter contains no notifier, Riverpod, provider, or notifier callback
    dependency.
- Edge cases:
  - Nullable goal and budget fields remain omitted by the store.
  - Empty evidence remains omitted according to the existing store contract.
- Failure paths: A callback that closes over notifier state or a new untyped
  payload blocks the prototype.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/data/datasources/turn_runtime_goal_continuation_log_adapter_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart --plain-name "goal auto-continue dispatches one hidden continuation from current evidence"
git diff --check
```

## Handoff Notes

- Summary: Added a data-layer implementation of the typed continuation logging
  port. The adapter owns only the existing log store, an explicit session
  context, enablement inputs, and a clock. The production wrapper retains its
  disabled-before-read guard and no longer calls `recordGoalAutoContinue`
  directly.
- Tests run:
  - All 6 focused schema, enablement, dependency, and production-wiring tests
    passed.
  - The reserved `goal auto-continue dispatches one hidden continuation from
    current evidence` integration test passed, including its JSONL ordering and
    payload assertions.
  - All 247 file-size and aggregate ratchet tests passed. `ChatNotifier` is
    8,900 lines against its 8,907-line limit, while the goal continuation part
    decreased from 777 to 769 lines.
  - Targeted analysis of the four changed implementation and test files found
    no issues.
- Coverage or low-coverage notes: The runtime composition root remains pending.
- Risks or follow-ups: Completion-shadow logging deliberately remains outside
  this reserved-path slice.
