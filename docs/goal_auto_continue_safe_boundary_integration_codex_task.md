# Goal Auto-Continue Safe-Boundary Integration

## Task

- Goal: route goal auto-continuation veto checks through the pure
  `GoalAutoContinueSafeBoundaryBuilder` with an owner-specific pending-state
  snapshot.
- User-visible behavior: pending work blocks only the conversation or turn that
  owns it; veto ordering and messages remain unchanged.
- Non-goals: changing continuation policy, pending UI behavior, or goal budgets.

## Context

- Affected components: goal auto-continuation, thread-scoped pending state,
  queued messages, and pending tool approvals.
- Related docs: `docs/chat_notifier_decomposition_workstream_8_codex_tasks.md`
  WS8-4 and `docs/large_file_refactor_plan.md`.
- Reference pattern: owner-keyed tracker and active-response registries.
- Compatibility rule: the builder must retain the existing first-veto order.

## Implementation Notes

- Build one immutable `GoalAutoContinuePendingState` for the requested owner.
- Read queued input and questions from conversation-keyed stores, approvals from
  their `ChatTurnOwner`, and thread state from the owner conversation.
- Read visible loading and error state only after confirming that the owner
  conversation is visible.
- Do not change generated entities.

## Similar-Pattern Search

- Search terms: `_goalAutoContinueSafeBoundaryFromState`,
  `GoalAutoContinueSafeBoundary`, `_queuedChatMessages.pendingFor`, pending
  approval fields, pending questions, workflow decisions, and participant turn
  runtime.
- Files inspected: `chat_notifier_goal_auto_continue.dart`, `chat_state.dart`,
  `thread_scoped_chat_state.dart`, `thread_scoped_message_queue.dart`, and
  `participant_turn_control_registry.dart`.
- Follow-up: integrate the decision coordinator after WS8-4 is live.

## Acceptance Criteria

- The notifier invokes `GoalAutoContinueSafeBoundaryBuilder` instead of
  constructing a boundary directly.
- Queued input from another conversation does not veto the owner.
- Pending approvals match the complete `ChatTurnOwner`.
- Pending questions, workflow decisions, and participant runtime are read from
  the owner conversation.
- Existing all-clear, individual-veto, veto-order, whitespace-error, immutable
  input, and detached-thread poison tests pass.

## Verification

```bash
fvm dart format \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart \
  --set-exit-if-changed
fvm flutter test --coverage \
  test/features/chat/domain/services/goal_auto_continue_safe_boundary_builder_test.dart
fvm flutter test \
  test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

## Handoff Notes

- Record owner lookup rules, preserved veto order, poison suites, coverage, and
  the next coordinator-integration slice.
