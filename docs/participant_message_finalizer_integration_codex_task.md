# Participant Message Finalizer Integration

## Task

- Goal: route participant assistant-message finalization through the existing
  pure `ParticipantMessageFinalizer`.
- User-visible behavior: final content, handoff metadata, truncation notices,
  response metrics, persisted messages, loading state, and auto-read behavior
  remain compatible.
- Non-goals: changing participant streaming, persistence implementations,
  text-to-speech, tool execution, approval routing, or participant ordering.

## Context

- Source adapter:
  `lib/features/chat/presentation/providers/chat_notifier_participant_turns.dart`.
- Pure collaborator:
  `lib/features/chat/domain/services/participant_message_finalizer.dart`.
- Direct tests:
  `test/features/chat/domain/services/participant_message_finalizer_test.dart`.
- Roadmap: WS8-8 in
  `docs/chat_notifier_decomposition_workstream_8_codex_tasks.md`.
- Prerequisite P10b is complete, so finish reason and response metrics are
  available from the exact owner's `ResponseMetadataRegistry` entry.

## Work Breakdown

1. Capture the exact owner, current-generation status, owner messages, finish
   reason, detached state, participant roster, tool names, and settings flags.
2. Build a `ParticipantMessageFinalizationPlan` without mutating notifier state.
3. Update token usage before consuming or discarding the exact owner's response
   metadata, then complete the plan with the selected metrics disposition.
4. Apply returned messages only to the owner cache and, when attached, visible
   state; persist only the returned persistence set.
5. Invoke auto-read only when the result explicitly supplies eligible content.
6. Preserve detached-owner poison coverage, direct transformer coverage, and
   shrink-only file-size ratchets.

## Acceptance Criteria

- The notifier no longer duplicates handoff extraction, truncation, empty
  assistant removal, tool-name deduplication, or saved-message filtering.
- Stale and missing-message plans discard only the exact owner's metadata and
  perform no message, persistence, loading-state, or auto-read effects.
- Metrics are consumed only for finalized messages and discarded for dropped
  or inactive plans, after token-usage capture.
- Detached participant messages, handoff fields, and response metrics remain
  bound to their owner while another conversation is visible.
- The finalizer remains below 500 physical lines with 100% line coverage.
- Notifier and same-library size ratchets only shrink.
- Focused participant, detached-owner, structural, and full verification
  reproduce no new failures.

## Verification

```bash
fvm dart format \
  lib/features/chat/presentation/providers/chat_notifier_participant_turns.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/participant_message_finalizer_test.dart
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

- Record the exact input capture, metrics disposition ordering, owner-bound
  effects, detached-owner evidence, measured shrink, coverage, full verifier
  baseline, and the next roadmap slice.
