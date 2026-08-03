# TurnRuntime Conversation Goal Adapter: Codex Task

## Task

- Goal: Add an owner-bound conversation goal boundary that never writes to an
  implicitly selected conversation.
- User-visible behavior: None. Existing goal status behavior is preserved.
- Non-goals: Moving continuation orchestration, validating live turn ownership,
  implementing safe-boundary or logging ports, or wiring `TurnRuntime`.

## Context

- Affected files or components:
  - `lib/features/chat/application/runtime/turn_runtime_conversation_goal_adapter.dart`
  - `lib/features/chat/presentation/providers/conversations_notifier.dart`
  - `lib/features/chat/presentation/providers/conversations_notifier_goal_runtime_store.dart`
  - focused application and presentation tests
- Related docs:
  - `docs/chat_notifier_turn_runtime_prototype_port_matrix.md`
  - `docs/chat_notifier_turn_runtime_contracts_codex_task.md`
- Reference implementation or pattern:
  - `ConversationsState.conversationForId`
  - `ConversationsNotifier.markCurrentGoalStatus`
- Known quirks, compatibility rules, or release gates:
  - A detached turn may finish after the user selects another conversation.
  - Existing `markCurrentGoalStatus` reads the selected conversation, so it is
    unsafe as a runtime boundary without an explicit conversation ID.
  - Live generation ownership remains the separate owner-lease port's job.

## Implementation Notes

- Preferred approach:
  1. Add explicit conversation-ID read and goal-status methods to
     `ConversationsNotifier`.
  2. Preserve `markCurrentGoalStatus` as a compatibility wrapper that captures
     the current ID before delegating.
  3. Add a narrow store wrapper holding only `ConversationsNotifier`.
  4. Add an application adapter that rejects missing or mismatched owner
     conversations before writing.
  5. Test detached writes against two conversations and poison the adapter
     with a mismatched store response.
- Constraints:
  - The application adapter must not import presentation providers, Riverpod,
    `ChatState`, `ChatNotifier`, or `Ref`.
  - The production store must not hold `ChatNotifier`, `Ref`, or callbacks.
  - Goal persistence must use the explicit owner conversation ID.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

- Search terms: `markCurrentGoalStatus`, `_persistCurrentGoal`,
  `conversationForId`, `selectConversation`.
- Files or modules inspected:
  - `lib/features/chat/presentation/providers/conversations_notifier.dart`
  - `test/features/chat/presentation/providers/conversations_notifier_goal_test.dart`
- Follow-up tasks found:
  - The reserved symbol migration will replace direct current-goal writes with
    this port.

## Acceptance Criteria

- Required behavior:
  - Reads and writes use `owner.conversationId` explicitly.
  - A detached owner updates its own goal while the visible goal is unchanged.
  - Missing or mismatched conversation snapshots suppress persistence.
  - Existing current-conversation callers preserve behavior.
  - Neither boundary object captures `ChatNotifier`, `Ref`, or callbacks.
- Edge cases:
  - A missing goal or objective remains a no-op.
  - Blocked reasons are normalized by the existing notifier behavior.
- Failure paths: Any implicit current-conversation write blocks runtime wiring.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/application/runtime/turn_runtime_conversation_goal_adapter_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/providers/conversations_notifier_goal_test.dart
git diff --check
```

## Handoff Notes

- Summary: Added an owner-addressable application adapter and a narrow
  `ConversationsNotifier` store, then generalized goal status persistence to an
  explicit conversation ID while preserving the current-conversation wrapper.
- Tests run:
  - Conversation adapter and notifier goal tests: passed, 21 tests.
  - Reserved goal auto-continue focused test: passed.
  - Focused Flutter analysis for five affected Dart files: passed with no
    issues.
  - `git diff --check`: passed.
- Coverage or low-coverage notes: Boundary remains unwired in production.
- Risks or follow-ups: Owner lease must still reject expired generations before
  invoking this conversation-scoped port.
