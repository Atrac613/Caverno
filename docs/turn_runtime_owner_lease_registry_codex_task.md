# TurnRuntime Owner Lease Registry: Codex Task

## Task

- Goal: Replace the reserved goal-continuation path's ambient mounted and
  visible-conversation reads with a narrow owner lease registry.
- User-visible behavior: None. Owner-current behavior must remain unchanged.
- Non-goals: Treating active-response registration as the lease, implementing
  safe-boundary snapshots, moving continuation orchestration, or creating the
  complete runtime composition root.

## Context

- Affected files or components:
  - `lib/features/chat/application/runtime/turn_runtime_owner_lease_registry.dart`
  - `lib/features/chat/presentation/providers/chat_notifier.dart`
  - focused runtime and notifier tests
- Related docs:
  - `docs/chat_notifier_turn_runtime_prototype_port_matrix.md`
  - `docs/chat_notifier_turn_runtime_contracts_codex_task.md`
- Reference implementation or pattern:
  - `_queueOwnerIsVisible`
  - `_isGoalAutoContinueOwnerCurrent`
  - `ChatNotifier.syncConversation`
- Known quirks, compatibility rules, or release gates:
  - Goal auto-continuation runs after `_completeRuntimeTurn` releases the
    owner's active-response registration.
  - The existing current check therefore means notifier mounted plus equality
    between the visible conversation, selected conversation, and owner.
  - Entry into the reserved path separately checks the latest interaction
    generation before calling continuation.

## Implementation Notes

- Preferred approach:
  1. Implement `TurnRuntimeOwnerLeasePort` as an application-layer registry
     containing only lifecycle, visible conversation, and selected
     conversation values.
  2. Route every assignment to `ChatNotifier.conversationId` through a setter
     that updates visible state.
  3. Update selected state from the conversation provider listener, including
     no-op synchronization paths.
  4. Mount the registry during build and retire it during notifier disposal.
  5. Replace `_queueOwnerIsVisible` and the reserved path's `ref.mounted` read
     with direct registry queries.
  6. Keep final-message visibility checks outside `ChatNotifier` so the
     existing file-size ratchet does not need to increase.
- Constraints:
  - Do not store `ChatNotifier`, `Ref`, `ChatState`, callbacks, or providers.
  - Do not require `ActiveResponseRegistry.containsOwner`; the registration is
    already released before continuation.
  - Preserve explicit `ChatTurnOwner` validation at the port method.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

- Search terms: `conversationId =`, `_queueOwnerIsVisible`,
  `_isCurrentInteractionGeneration`, `_completeRuntimeTurn`,
  `_clearActiveResponseForGeneration`, `ref.onDispose`.
- Files or modules inspected:
  - `lib/features/chat/presentation/providers/chat_notifier.dart`
  - `lib/features/chat/presentation/providers/chat_notifier_execution_runtime.dart`
  - `lib/features/chat/presentation/providers/active_response_registry.dart`
- Follow-up tasks found:
  - Safe-boundary capture needs a separate live thread-state snapshot and must
    not be folded into this lifecycle registry.

## Acceptance Criteria

- Required behavior:
  - A lease is current only while mounted and both conversation IDs match the
    explicit owner.
  - Visible or selected conversation divergence retires the current check.
  - Disposal retires every owner.
  - Rebuild can mount the registry again with a fresh synchronized snapshot.
  - The reserved focused auto-continue behavior remains green.
  - The registry contains no presentation or callback dependency.
- Edge cases:
  - A null visible or selected conversation rejects the owner.
  - Updating the selected conversation on an otherwise no-op sync still
    refreshes lease state.
- Failure paths: Using active-response registration or capturing notifier state
  blocks the prototype.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/application/runtime/turn_runtime_owner_lease_registry_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart --plain-name "goal auto-continue dispatches one hidden continuation from current evidence"
git diff --check
```

## Handoff Notes

- Summary: Added a lifecycle-aware owner lease registry and production-wired it
  to visible and selected conversation synchronization. Queue ownership,
  finalization, and goal auto-continuation now query the registry directly;
  the reserved continuation path no longer reads `ref.mounted`. Final-message
  visibility moved to `TurnFinalMessage` and is shared by normal finalization,
  cancellation, and recovery.
- Tests run:
  - 13 focused owner-lease and final-message tests passed.
  - The reserved `goal auto-continue dispatches one hidden continuation from
    current evidence` regression test passed.
  - All 247 file-size and aggregate ratchet tests passed. `ChatNotifier` is
    8,892 lines against its 8,907-line limit.
  - Targeted analysis of the eight changed implementation and test files found
    no issues.
- Coverage or low-coverage notes: The runtime composition root remains pending.
- Risks or follow-ups: Safe-boundary state was addressed by the subsequent
  `TurnRuntimeGoalSafeBoundaryAdapter` slice. Continuation logging remains the
  next production boundary.
