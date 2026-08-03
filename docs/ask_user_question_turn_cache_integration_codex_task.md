# Ask User Question Turn Cache Integration

## Task

- Goal: replace the generation-only private ask-user-question cache in
  `ChatNotifier` with the existing exact-owner `AskUserQuestionTurnCache`.
- User-visible behavior: repeated questions within one turn reuse the completed
  answer, while answers never cross conversation or turn ownership boundaries.
- Non-goals: integrating `AskUserQuestionPolicy`, changing question UI behavior,
  changing release-approval semantics, or changing tool dispatch.

## Context

- Source adapters:
  `lib/features/chat/presentation/providers/chat_notifier_ask_user_question.dart`,
  `chat_notifier_command_guardrails.dart`, and `chat_notifier.dart`.
- Domain collaborator:
  `lib/features/chat/domain/services/ask_user_question_turn_cache.dart`.
- Direct tests:
  `test/features/chat/domain/services/ask_user_question_turn_cache_test.dart`.
- Roadmap: WS8-1 in
  `docs/chat_notifier_decomposition_workstream_8_codex_tasks.md`.
- The active-response registry is the authority for resolving a generation to
  its immutable `ChatTurnOwner`.

## Work Breakdown

1. Resolve the exact owner before every cache lookup, write, approval query, and
   cleanup operation.
2. Keep untracked or missing-owner dispatchers cache-free.
3. Delegate option-label normalization and reusable-result matching to the
   domain cache.
4. Remove the generation-only private cache and its private entry type.
5. Preserve direct owner-isolation coverage and detached-turn poison coverage.
6. Lower shrink-only notifier aggregate ratchets by the measured reduction.

## Acceptance Criteria

- No ask-user-question cache API accepts a bare generation in production.
- Repeated questions reuse answers only for the exact owner.
- Equal generations belonging to different conversations cannot share answers
  or production-release approval evidence.
- Clearing one active response removes only that owner's cached answers; global
  cleanup still clears every owner.
- Missing-owner and untracked dispatchers neither read nor write cached answers.
- The domain cache remains below its current size budget with 100% line
  coverage, and notifier size ratchets only shrink.
- Focused detached-owner, structural, and full verification reproduce no new
  failures.

## Verification

```bash
fvm dart format \
  lib/features/chat/presentation/providers/chat_notifier_ask_user_question.dart \
  lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/ask_user_question_turn_cache_test.dart
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

- Record exact-owner lookup, write, approval, and cleanup behavior; poison-test
  evidence; measured shrink; coverage; full verifier baseline; and the next
  roadmap slice.
