# ChatNotifier Decomposition Slice 2b3: Pending-Question Isolation

## Task

- Goal: make `ask_user_question` ownership and clearing strictly
  conversation-scoped.
- User-visible behavior: a question waiting in thread A remains pending while
  the user reads or sends a message in thread B; only an answer or replacement
  action owned by A clears it.
- Destination API: replace turn-reachable global dismissal with
  `_dismissPendingAskUserQuestionForConversation(String conversationId)` while
  reserving `_dismissAllPendingAskUserQuestions` for true global reset.
- Non-goals:
  - changing question parsing, option limits, answer payloads, or reuse rules;
  - changing workflow-decision prompts;
  - persisting pending questions across application restarts;
  - extracting `ask_user_question` or changing `ChatState` schema.

## Context

- Affected production files:
  - `lib/features/chat/presentation/providers/chat_notifier_ask_user_question.dart`;
  - `lib/features/chat/presentation/providers/chat_notifier.dart`.
- Direct deterministic test file:
  `test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart`.
- Existing regression file:
  `test/features/chat/presentation/providers/chat_notifier_ask_user_question_part.dart`.
- Exact source methods and call sites:
  - `requestAskUserQuestion` resolves a target conversation and stores the
    pending value in `_pendingAskUserQuestionsByThread`;
  - `resolveAskUserQuestion` can already locate a pending question by ID across
    the map and removes only its owning entry;
  - `_dismissAllPendingAskUserQuestions` completes every pending completer and
    clears the whole map;
  - `sendMessage` calls `_dismissAllPendingAskUserQuestions` before it captures
    the new message's `conversationId`;
  - `syncConversation` calls the same global dismissal on one switch path;
  - `clearMessages` calls it during a true global reset and should keep that
    behavior;
  - `syncConversation` already restores the selected thread's pending question
    from `_pendingAskUserQuestionsByThread`.
- Current test gap:
  existing thread-switch and parallel-question tests do not send in B after A's
  question is already pending, so the global dismissal path is not exercised.

## Implementation Notes

- Capture the visible owner ID before dismissal in `sendMessage`.
- Add an owner-scoped dismissal helper with immutable input
  `String ownerConversationId`. It must:
  - remove only that key from `_pendingAskUserQuestionsByThread`;
  - complete only that question's completer with `null`;
  - clear `state.pendingAskUserQuestion` only when its ID matches the removed
    question.
- A new user message in thread A keeps the existing behavior of treating A's
  question as bypassed. A message in B must not complete A's future.
- A navigation-only `syncConversation` call must never globally dismiss another
  thread's pending question. Keep restoration from the map authoritative.
- Keep `_dismissAllPendingAskUserQuestions` only for `clearMessages`, provider
  teardown, or another explicitly global cancellation path.
- Question resolution continues to use the immutable pending question's own
  `conversationId`; it must not infer ownership from the visible conversation.
- Typed side-effect ports:
  - completion is the existing typed `Completer<AskUserQuestionAnswer?>`;
  - UI projection is the existing `ChatState.pendingAskUserQuestion`;
  - runtime question events remain unchanged in this slice.
- Generated files and migrations: none.

## Deterministic Two-Thread Cases

Use different question IDs, prompts, options, and answer values for A and B:

1. Start A and wait until its question is pending. Switch to B, send and finish
   a normal message, and assert A's completer is still incomplete.
2. While B is visible, assert B shows no A dialog and A is the only waiting
   owner. Switch back to A and assert the exact same pending ID and prompt are
   restored.
3. Create pending questions in both threads. Resolve B by ID while A is visible
   or vice versa. Only the matching future and map entry may complete.
4. Type a fresh message in A while A's question is pending. A's question must
   complete with `null`, clear from A, and leave B's pending question untouched.
5. Preserve same-generation question-result reuse and existing remote/coding
   question behavior.

Assert future completion state, pending IDs, visible projection, and persisted
conversation messages. A prompt-string-only assertion is insufficient.

## Similar-Pattern Search

- Search terms:
  - `_dismissAllPendingAskUserQuestions`;
  - `_pendingAskUserQuestionsByThread`;
  - `pendingAskUserQuestion`;
  - `resolveAskUserQuestion`;
  - `syncConversation`;
  - `clearMessages`.
- Inspect every global dismissal call and classify it as owner-scoped or
  application-global.
- Record workflow-decision or other prompt types with global clearing as
  follow-ups; do not mix them into this slice.

## Measurement, Manifest, and Coverage

- Expected declared notifier-part delta: `0`; the count remains `42`.
- Target same-library aggregate delta: `0`; reductions are acceptable, but the
  aggregate must remain at or below `22,900` physical lines.
- Manifest record `ask_user_question` remains `remaining`; no collaborator
  record or discovery marker is added.
- No size budget may increase.
- Current target-file coverage baseline:
  `chat_notifier_ask_user_question.dart` is `148/169` lines (`87.57%`).
- Coverage expectation: remain at or above `87.57%`, with every owner-scoped
  dismissal and independent-resolution branch hit.

## Acceptance Criteria

1. A pending question blocks only its owning conversation.
2. Sending or navigating in B does not dismiss A's question.
3. Resolving one ID completes and clears only its matching pending question.
4. A fresh message dismisses only the question owned by that message's
   conversation.
5. Switching back restores the exact pending question object for that thread.
6. `clearMessages` still completes and clears every pending question.
7. Same-turn reuse, answer payloads, and existing single-thread behavior remain
   compatible.
8. No part, manifest, marker, schema, generated file, or budget change.

## Verification

```bash
fvm dart format \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  lib/features/chat/presentation/providers/chat_notifier_ask_user_question.dart \
  test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart \
  --set-exit-if-changed
tool/codex_verify.sh \
  --test test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart \
  --test test/features/chat/presentation/providers/chat_notifier_test.dart
fvm flutter test test/quality/file_size_ratchet_test.dart
tool/codex_verify.sh --coverage
awk -v target='lib/features/chat/presentation/providers/chat_notifier_ask_user_question.dart' \
  -v minimum=87.57 '
    /^SF:/ { selected = index(substr($0, 4), target) > 0 }
    selected && /^LF:/ { found = substr($0, 4) + 0 }
    selected && /^LH:/ { hit = substr($0, 4) + 0 }
    END {
      rate = 100 * hit / found
      printf "%s: %.2f%% (%d/%d)\n", target, rate, hit, found
      exit !(found > 0 && rate + 0.001 >= minimum)
    }
  ' coverage/lcov.info
git diff --check
```

The ordered work-plan table does not require the live canary for a test-only
Slice 2b3. If production question or lifecycle code changes, run the corrected
Slice 2b1 canary and record the exact model and base URL.

## Stop Conditions

- Stop if the test cannot hold A's question pending before B sends.
- Stop if the proposed fix uses the visible conversation at resolution time
  instead of the immutable pending question's owner ID.
- Stop if application-wide reset semantics must change.
- Stop and record a follow-up if workflow decisions or participant approvals
  need the same repair; those belong to their own slices.
- Stop if the fix requires persistence migration, provider schema changes, a
  new notifier part, an aggregate budget increase, or extraction.

## Handoff Notes

- Record poisoned question IDs, prompts, and owner conversation IDs.
- Record which futures completed at each transition.
- Record the target-file hit/line count and aggregate line count.
- Record every global dismissal call and its final classification.
- Keep this slice in one focused Conventional Commit.

## Implementation Evidence

Implementation commit `805cd3c9` captures one immutable owner conversation ID
for question dismissal and queued-message construction. Before the production
fix, the thread B message fixture completed thread A's future unexpectedly, and
the two-owner fixture restored a null thread A projection. The fixed
deterministic fixtures prove:

- thread A's `thread-a-staging` question remains incomplete while thread B
  sends and persists a normal user/assistant exchange, then restores the exact
  pending object, ID, and prompt when A is selected;
- resolving thread B's `thread-b-eu` question by ID while A is visible
  completes only B and leaves A's `thread-a-package` question projected;
- a fresh A message completes only A with `null`, while B's
  `thread-b-build-cache` question remains incomplete and restores unchanged;
- `clearMessages` still completes both owners with `null` and leaves no pending
  map entry.

The two direct verification files pass all 335 tests. Fresh coverage is
`152/169` lines (`89.94%`) for `chat_notifier_ask_user_question.dart`, above the
`87.57%` floor. The declared part count remains 42, the same-library aggregate
remains exactly 22,900 lines, and the manifest remains unchanged.

The final global-dismissal classification is:

- `_cancelStreaming` remains application-global;
- `clearMessages` remains application-global;
- `sendMessage` is owner-scoped;
- navigation through `syncConversation` dismisses no pending question.

Workflow-decision and participant prompt clearing were inspected and remain
outside this slice. The exact-model corrected Slice 2b1 live canary passed on
2026-07-28 against loaded `qwen3.6-27b-vision` at
`http://192.168.100.241:1234/v1`. Its exact exit maps and zero-busy-owner
evidence are recorded in the Slice 2b1 handoff. This completes Slice 2b3.
