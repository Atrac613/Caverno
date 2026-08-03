# Ask User Question Policy Integration

## Task

- Goal: route production `ask_user_question` handling through the existing
  owner-aware `AskUserQuestionPolicy` and runtime adapter.
- User-visible behavior: validation, option parsing, saved-task answers,
  repeated-answer reuse, cancellation, and answer JSON remain compatible.
- Non-goals: changing question-sheet presentation, runtime question events,
  remote question transport, or production-release approval semantics.

## Context

- Source adapter:
  `lib/features/chat/presentation/providers/chat_notifier_ask_user_question.dart`.
- Policy:
  `lib/features/chat/domain/services/ask_user_question_policy.dart`.
- Runtime boundary:
  `lib/features/chat/data/datasources/ask_user_question_runtime_adapter.dart`.
- UI contract:
  `lib/features/chat/domain/services/ask_user_question_ui_contract.dart`.
- Direct tests:
  `test/features/chat/domain/services/ask_user_question_policy_test.dart` and
  `test/features/chat/data/datasources/ask_user_question_runtime_adapter_test.dart`.
- Roadmap: WS8-2 in
  `docs/chat_notifier_decomposition_workstream_8_codex_tasks.md`.
- Prerequisite WS8-1 is integrated, so policy and runtime share the notifier's
  exact-owner cache.

## Work Breakdown

1. Instantiate one runtime adapter with the notifier cache, terminal-response
   policy, active-owner check, and typed UI start/cancel callbacks.
2. Replace notifier validation, parsing, saved-task resolution, reuse, result
   mapping, and storage with one exact-owner runtime call.
3. Adapt the existing pending-question UI bridge to conditional start,
   completion, and cancellation acknowledgements.
4. Retire the adapter before clearing an active owner so late completions cannot
   write cache entries or settle another question.
5. Remove duplicated policy and repeated-result formatting from the notifier.
6. Lower shrink-only notifier ratchets by the measured reduction.

## Acceptance Criteria

- Production `ask_user_question` calls require an exact active owner and retain
  the complete tool-call identity through UI completion.
- Missing or retired owners do not present UI or populate the answer cache.
- A completion or cancellation for another call or pending token cannot settle
  the active question.
- Existing option limits, IDs, clipping, saved-task answers, reuse behavior,
  cancellation JSON, and answered JSON remain unchanged.
- Owner cleanup retires the runtime adapter before removing the active-response
  registration.
- Policy and runtime-adapter direct tests retain 100% line coverage, notifier
  ratchets only shrink, and focused/full verification adds no new failure.

## Verification

```bash
fvm dart format \
  lib/features/chat/presentation/providers/chat_notifier_ask_user_question.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/ask_user_question_policy_test.dart \
  test/features/chat/data/datasources/ask_user_question_runtime_adapter_test.dart
fvm flutter test \
  test/features/chat/presentation/providers/chat_notifier_test.dart \
  --name 'ask.?user.?question'
fvm flutter test \
  test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

## Handoff Notes

- Record the exact identity lifecycle, UI acknowledgement behavior, retirement
  ordering, measured shrink, direct coverage, full verifier baseline, and next
  roadmap slice.
