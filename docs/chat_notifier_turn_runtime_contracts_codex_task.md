# TurnRuntime Goal Continuation Contracts: Codex Task

## Task

- Goal: Define and test the typed boundary required before moving the two
  manifest-reserved goal-continuation symbols into `TurnRuntime`.
- User-visible behavior: None. The new runtime shell does not participate in
  production dispatch in this slice.
- Non-goals: Moving `_maybeAutoContinueCurrentGoal`, moving
  `_recordGoalAutoContinueSessionLog`, changing goal policy, adding production
  adapters, wiring `ChatToolHandlerCatalog`, or running the live canary.

## Context

- Affected files or components:
  - `lib/features/chat/application/runtime/turn_runtime.dart`
  - `test/features/chat/application/runtime/turn_runtime_test.dart`
  - `docs/chat_notifier_turn_runtime_contracts_codex_task.md`
- Related docs:
  - `docs/chat_notifier_turn_runtime_prototype_port_matrix.md`
  - `docs/chat_notifier_turn_runtime_preprototype_decision.md`
  - `tool/chat_notifier_turn_runtime_prototype_verification.json`
- Reference implementation or pattern:
  - `lib/features/chat/data/datasources/goal_update_tool_runtime_adapter.dart`
  - `lib/features/chat/domain/services/goal_auto_continue_decision_coordinator.dart`
- Known quirks, compatibility rules, or release gates:
  - The runtime owns one exact `ChatTurnOwner`; continuation input must not
    repeat owner or generation identity.
  - Five narrow collaborators cover owner lease, conversation goal access,
    continuation tracking, safe-boundary capture, and logging.
  - UI projection and hidden-turn dispatch are returned typed effects, not
    injected callbacks.
  - No contract may import Riverpod, `ChatState`, or `ChatNotifier`.

## Implementation Notes

- Preferred approach:
  1. Add a minimal `TurnRuntime` shell owning the exact turn identity and the
     continuation reentrancy guard.
  2. Add a port bundle containing the five abstract collaborator interfaces.
  3. Add immutable continuation input, goal-status request, UI effects, and
     hidden-turn request values.
  4. Defensively copy collection-bearing evidence and tool allowlists.
  5. Test identity ownership, reentrancy, immutability, and forbidden imports.
- Constraints:
  - Do not add callback typedefs or callback-backed production adapters.
  - Keep conversation, tracker, queue, thread, settings, UI, and logging state
    outside the runtime.
  - Every collaborator request and returned effect must carry the exact owner.
  - Do not alter generated entities.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

- Search terms: `abstract interface class`, `RuntimePort`, `RuntimeInput`,
  `ChatTurnOwner`, `ownerExpired`, `Effect`, `Acknowledgement`.
- Files or modules inspected:
  - `lib/features/chat/application/runtime/caverno_execution_lease.dart`
  - `lib/features/chat/data/datasources/goal_update_tool_runtime_adapter.dart`
  - `lib/features/chat/data/datasources/participant_tool_runtime_contract.dart`
  - `lib/features/chat/domain/services/goal_auto_continue_tracker_registry.dart`
- Follow-up tasks found:
  - Implement production collaborators from narrow underlying services without
    storing `ChatNotifier` or `Ref`.
  - Move only the two reserved symbols and the required pure helpers.

## Acceptance Criteria

- Required behavior:
  - `TurnRuntime` owns one `ChatTurnOwner` and continuation reentrancy state.
  - Continuation input contains no owner or generation parameter.
  - The port bundle contains exactly five capability interfaces.
  - UI and hidden dispatch are represented by typed owner-bound values.
  - Collection-bearing inputs cannot be mutated through their source lists or
    sets after construction.
  - Runtime contracts contain no Riverpod, `ChatState`, `ChatNotifier`, or
    callback typedef dependency.
- Edge cases:
  - A second scheduling attempt fails while scheduling is active.
  - Ending scheduling is idempotent.
  - A nullable tool allowlist remains nullable; a supplied allowlist is
    unmodifiable.
- Failure paths: Any implicit application-state access or callback capture
  blocks the production migration.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/application/runtime/turn_runtime_test.dart
git diff --check
```

## Handoff Notes

- Summary: Added an owner-bound `TurnRuntime` shell, five capability
  interfaces, immutable continuation input, owner-bound goal status and UI
  values, and typed hidden-turn requests without production wiring.
- Tests run:
  - `flutter test --no-pub
    test/features/chat/application/runtime/turn_runtime_test.dart`: passed, 7
    tests.
  - Focused Flutter analysis for the runtime and test: passed with no issues.
  - `git diff --check`: passed.
- Coverage or low-coverage notes: The runtime shell is intentionally unused by
  production until the next migration slice.
- Risks or follow-ups: Production boundary construction remains the next
  capture-risk checkpoint; no callback-backed adapter is authorized.
