# Goal Auto-Continue Tracker Registry Integration: Codex Task

## Task

- Goal: Make `ChatNotifier` use `GoalAutoContinueTrackerRegistry` as the sole
  owner of goal continuation tracker state.
- User-visible behavior: None; diagnostic streaks, verifier replay selection,
  replay-once behavior, continuation counters, notices, and resets remain
  compatible.
- Non-goals: Integrating `GoalAutoContinueDecisionCoordinator`, changing
  continuation policy, changing prompts, or changing persistence.

## Context

- Affected files or components:
  - `lib/features/chat/presentation/providers/chat_notifier.dart`
  - `lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart`
  - `lib/features/chat/domain/services/goal_auto_continue_tracker_registry.dart`
  - goal auto-continue provider and registry tests
- Related plan:
  `docs/chat_notifier_decomposition_workstream_8_codex_tasks.md`, WS8-3.
- Existing state: The registry and direct tests exist, but `ChatNotifier` still
  owns a duplicate mutable tracker class, map, and budget-notice set.

## Implementation Notes

- Replace direct tracker mutation with owner-aware registry operations.
- Build task context from the explicit turn owner and owner conversation.
- Keep logging, tool execution, UI state, persistence, and await ordering in
  `ChatNotifier`.
- Inject verifier replay IDs through the registry constructor.
- Leave decision-coordinator integration for the next slice after this
  prerequisite is live.

## Similar-Pattern Search

- Search terms: `_GoalAutoContinueTracker`, `_goalAutoContinueTrackers`,
  `_goalAutoContinueBudgetNotifiedConversations`, verifier replay candidate,
  command diagnostic focus, and tracker reset.
- Required outcome: No caller-owned mutable tracker fields remain.

## Acceptance Criteria

- `ChatNotifier` owns one `GoalAutoContinueTrackerRegistry` instance.
- Every tracker read and write is owner-aware.
- Diagnostic and verifier replay behavior remains covered by provider tests.
- Registry lifecycle and defensive-copy tests remain green.
- No duplicate mutable tracker class, map, or budget-notice set remains.

## Verification

```bash
tool/codex_verify.sh --coverage --test \
  test/features/chat/domain/services/goal_auto_continue_tracker_registry_test.dart \
  test/features/chat/presentation/providers/chat_notifier_test.dart \
  test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
```

## Handoff Notes

- Summary: `ChatNotifier` now delegates all goal tracker state, diagnostic
  focus, verifier candidates, replay-once bookkeeping, notices, and resets to
  one owner-aware `GoalAutoContinueTrackerRegistry`. The duplicate private
  tracker class, map, budget set, and verifier policy seam were removed.
- Tests run:
  - `fvm flutter analyze`
  - registry and detached-owner tests: 107 passed
  - focused verifier replay and task-change provider tests: 2 passed
  - collaborator, size, and thread-scoped ratchets: 259 passed
  - `tool/codex_verify.sh --coverage` with registry, full ChatNotifier,
    detached-owner, and ratchet tests: 679 Flutter tests passed plus all
    internal-package coverage tests
- Coverage: `goal_auto_continue_tracker_registry.dart` reached 99.49%
  (197/198 lines).
- Size: `chat_notifier_goal_auto_continue.dart` fell from 1,020 to 936 lines;
  the ChatNotifier test aggregate is 33,218 lines within its 33,219 budget.
- Adjacent correction: The prior execution-status slice left
  `workflow_task_run_lifecycle_policy.dart` over its 56-line ratchet. Its
  equivalent task-view lookup is now 55 lines without increasing the budget.
- Risks or follow-ups: Integrate `GoalAutoContinueDecisionCoordinator` next;
  notifier tracker state is now available as immutable registry snapshots.
