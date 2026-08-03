# Goal Update Tool Handler Integration

## Task

- Goal: route `update_goal` acknowledgement evaluation through the existing
  owner-input `GoalUpdateToolHandler`.
- User-visible behavior: acknowledgement text, evidence checks, completion
  acceptance, and completion-shadow outcomes remain compatible.
- Non-goals: changing goal persistence, finalization re-checks, shadow-log
  writes, tool registration, or completion policy.

## Context

- Affected components: `handleUpdateGoal` in
  `chat_notifier_goal_auto_continue.dart` and its shared imports.
- Related docs: `docs/chat_notifier_decomposition_workstream_8_codex_tasks.md`
  WS8-7 and `docs/large_file_refactor_plan.md`.
- Existing collaborator:
  `lib/features/chat/domain/services/goal_update_tool_handler.dart`.
- Release gate: another owner, call ID, or argument digest must not influence
  the acknowledgement or stored finalization state.

## Implementation Notes

- Capture an immutable `GoalUpdateToolRequest` from the exact turn owner and
  incoming tool call.
- Capture the matching owner goal, completed tool-result ledger, and current
  completion-evidence snapshot in `GoalUpdateOwnerSnapshot`.
- Let the handler recompute call-time evidence and resolve the acknowledgement.
- Store only returned completion-shadow outcomes and accepted claims through
  the existing owner-keyed `TurnFinalizationStateRegistry`.
- Keep missing-generation and missing-owner failures in the notifier adapter.
- Keep final completion-evidence reconciliation and goal persistence in
  `TurnGoalCompletionFinalizer`.
- Do not modify generated entities.

## Similar-Pattern Search

- Search terms: `handleUpdateGoal`, `GoalUpdateAckResolver`,
  `combinedToolResultsFor`, `setGoalOutcome`, `markGoalClaimed`,
  `takeGoalOutcome`, and `takeGoalClaim`.
- Files inspected: handler and contract, direct tests, goal continuation
  notifier part, tool-handler registry, completion-evidence registry,
  finalization-state registry, and detached-owner tests.
- Existing poison coverage includes owner, call ID, argument digest, goal,
  result, accepted claim, and shadow-log isolation.

## Acceptance Criteria

- The notifier does not evaluate `GoalUpdateAckResolver` directly.
- Handler inputs contain only the exact owner's immutable request and snapshot.
- Only completion claims write shadow outcomes; only accepted claims mark
  completion for finalization.
- Finalization continues to consume claim, shadow, and evidence by exact owner.
- Direct handler coverage remains 100%.
- Registry binding, acknowledgement, detached-owner, and structural tests pass.
- File-size ratchets are lowered where the integration shrinks the notifier.

## Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/goal_update_tool_handler.dart \
  lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_handler_registry.dart \
  test/features/chat/domain/services/goal_update_tool_handler_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/goal_update_tool_handler_test.dart
fvm flutter test \
  test/features/chat/presentation/providers/chat_notifier_test.dart \
  test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

## Handoff Notes

- Record explicit request/snapshot inputs, outcome persistence, unchanged
  finalization responsibilities, poison coverage, measured size, coverage,
  and the next roadmap slice.
