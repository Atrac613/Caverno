# TurnRuntime Goal Tracker Adapter: Codex Task

## Task

- Goal: Implement the first production `TurnRuntime` boundary by adapting the
  conversation-spanning goal continuation tracker without capturing
  presentation state.
- User-visible behavior: None. The adapter remains unwired in this slice.
- Non-goals: Moving goal-continuation orchestration, implementing the other
  four runtime boundaries, changing tracker policy, or wiring the runtime.

## Context

- Affected files or components:
  - `lib/features/chat/application/runtime/turn_runtime.dart`
  - `lib/features/chat/application/runtime/turn_runtime_goal_tracker_adapter.dart`
  - `test/features/chat/application/runtime/turn_runtime_test.dart`
  - `test/features/chat/application/runtime/turn_runtime_goal_tracker_adapter_test.dart`
- Related docs:
  - `docs/chat_notifier_turn_runtime_prototype_port_matrix.md`
  - `docs/chat_notifier_turn_runtime_contracts_codex_task.md`
- Reference implementation or pattern:
  - `lib/features/chat/domain/services/goal_auto_continue_tracker_registry.dart`
  - `_applyGoalAutoContinueTrackerDelta` in
    `chat_notifier_goal_auto_continue.dart`
- Known quirks, compatibility rules, or release gates:
  - Tracker state intentionally spans hidden turns and is keyed by conversation.
  - `TurnRuntime` may use the tracker but must not own its storage.
  - Failed hidden dispatch clears only the pending repair-contract outcome.

## Implementation Notes

- Preferred approach:
  1. Add the missing explicit clear operation to the tracker port contract.
  2. Implement the port by holding only `GoalAutoContinueTrackerRegistry`.
  3. Map every typed tracker delta field without defaults that could drift.
  4. Test cross-generation conversation persistence, conversation isolation,
     budget notice behavior, pending repair clearing, and removal.
- Constraints:
  - Do not import presentation providers, Riverpod, `ChatState`, or
    `ChatNotifier`.
  - Do not introduce callbacks or service locators.
  - Preserve explicit `ChatTurnOwner` on every operation.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

- Search terms: `_applyGoalAutoContinueTrackerDelta`,
  `pendingRepairContractOutcome`, `markBudgetNoticePresented`, `removeTracker`.
- Files or modules inspected:
  - `lib/features/chat/domain/services/goal_auto_continue_tracker_registry.dart`
  - `lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart`
- Follow-up tasks found:
  - Replace the notifier helper only when orchestration moves in the reserved
    symbol migration.

## Acceptance Criteria

- Required behavior:
  - The adapter implements every `TurnRuntimeGoalTrackerPort` operation.
  - Tracker deltas preserve every field used by the decision coordinator.
  - State persists across owners from the same conversation and remains
    isolated between conversations.
  - Clearing pending repair state does not reset unrelated tracker fields.
  - The adapter holds no notifier, `Ref`, callback, or presentation state.
- Edge cases:
  - Budget notice returns true only once per conversation.
  - Removing a tracker resets its snapshot for the next turn.
- Failure paths: A missing delta field or forbidden dependency blocks wiring.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/application/runtime/turn_runtime_goal_tracker_adapter_test.dart
tool/codex_verify.sh --test test/features/chat/application/runtime/turn_runtime_test.dart
git diff --check
```

## Handoff Notes

- Summary: Added a tracker-only production adapter, mapped the complete typed
  continuation delta, and added an explicit pending-repair clear operation
  without moving conversation-spanning storage into `TurnRuntime`.
- Tests run:
  - Goal tracker adapter and runtime contract tests: passed, 14 tests.
  - Focused Flutter analysis for four affected Dart files: passed with no
    issues.
  - `git diff --check`: passed.
- Coverage or low-coverage notes: Adapter remains unwired in production.
- Risks or follow-ups: Four production boundaries remain before orchestration
  migration.
