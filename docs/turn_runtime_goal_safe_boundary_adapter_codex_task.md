# TurnRuntime Goal Safe-Boundary Adapter: Codex Task

## Task

- Goal: Replace goal continuation's inline reads of queue, approval, question,
  workflow, participant, loading, and error state with the typed safe-boundary
  port.
- User-visible behavior: None. Every existing continuation veto must remain
  owner-scoped and unchanged.
- Non-goals: Moving continuation orchestration, implementing logging, or
  constructing the complete `TurnRuntime` composition root.

## Context

- Affected files or components:
  - `lib/features/chat/presentation/providers/turn_runtime_goal_safe_boundary_adapter.dart`
  - `lib/features/chat/presentation/providers/chat_notifier.dart`
  - `lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart`
- Related docs:
  - `docs/chat_notifier_turn_runtime_prototype_port_matrix.md`
  - `docs/turn_runtime_owner_lease_registry_codex_task.md`
- Reference implementation or pattern:
  - `_goalAutoContinueSafeBoundaryFor`
  - `GoalAutoContinueSafeBoundaryBuilder`
  - `ThreadScopedChatState`
- Known quirks, compatibility rules, or release gates:
  - Visible loading and error state apply only while the explicit owner lease
    is current.
  - Detached approvals come from the thread stash and must match the complete
    `ChatTurnOwner`, including interaction generation.
  - Queued input and pending questions are conversation-scoped.

## Implementation Notes

- Preferred approach:
  1. Implement `TurnRuntimeGoalSafeBoundaryPort` in a presentation adapter.
  2. Hold only the owner lease and the existing narrow queue, thread-state, and
     question registries.
  3. Synchronize an immutable visible-thread projection immediately before
     capture instead of storing the notifier or a state callback.
  4. Preserve exact approval-owner matching and detached-thread behavior.
  5. Replace the inline builder in the goal continuation extension with the
     adapter capture.
- Constraints:
  - Do not store `ChatNotifier`, `Ref`, a state setter, or callbacks.
  - Do not move presentation state into `TurnRuntime`.
  - Do not weaken `ChatTurnOwner` matching to conversation ID for approvals.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Acceptance Criteria

- Required behavior:
  - All existing safe-boundary veto fields are projected unchanged.
  - Visible loading and error state are ignored for detached owners.
  - Pending approvals count only for their exact owner.
  - Queued input and pending questions remain conversation-scoped.
  - The adapter contains no notifier, Riverpod, callback, or state-setter
    dependency.
- Edge cases:
  - Missing detached state produces an otherwise empty boundary.
  - An approval from another interaction generation does not veto the owner.
- Failure paths: Capturing notifier state or making the runtime own thread maps
  blocks the prototype.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/presentation/providers/turn_runtime_goal_safe_boundary_adapter_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart --plain-name "goal auto-continue dispatches one hidden continuation from current evidence"
git diff --check
```

## Handoff Notes

- Summary: Added a notifier-independent safe-boundary adapter backed by the
  existing owner lease, queue, detached thread-state stash, and pending-question
  registry. The wrapper synchronizes only the visible thread projection before
  capture, and the goal continuation extension no longer assembles veto state
  inline.
- Tests run:
  - All 6 focused adapter and production-wiring tests passed.
  - The reserved `goal auto-continue dispatches one hidden continuation from
    current evidence` regression test passed.
  - All 247 file-size and aggregate ratchet tests passed. `ChatNotifier` is
    8,899 lines against its 8,907-line limit, while the goal continuation part
    decreased from 804 to 777 lines.
  - Targeted analysis of the four changed implementation and test files found
    no issues.
- Coverage or low-coverage notes: Continuation logging was implemented by the
  subsequent `TurnRuntimeGoalContinuationLogAdapter` slice. The runtime
  composition root remains pending.
- Risks or follow-ups: The wrapper still synchronizes visible state immediately
  before invoking the port until continuation orchestration moves.
