# ChatNotifier Decomposition Slice 2b4: Queued-Work Isolation

## Task

- Goal: prove and enforce that queued user work blocks, drains, and resumes only
  within its owning conversation.
- User-visible behavior: a queued message in thread A neither blocks nor runs in
  thread B. It remains queued while A is detached and resumes automatically when
  A is selected and idle.
- Destination API: replace ambient
  `_drainQueuedChatMessagesIfIdle()` with an owner-explicit drain such as
  `_drainQueuedChatMessagesForThreadIfIdle(String ownerConversationId)`.
- Non-goals:
  - adding a global background queue scheduler;
  - allowing `_sendMessageNow` to mutate a hidden conversation through visible
    `ChatState`;
  - changing FIFO order within one conversation;
  - changing queue persistence across application restarts;
  - extracting the queue or adding a notifier part.

## Context

- Affected production files:
  - `lib/features/chat/presentation/providers/chat_notifier.dart`;
  - `lib/features/chat/presentation/providers/chat_notifier_participant_turns.dart`
    only to pass the owning conversation into existing drain call sites;
  - `lib/features/chat/presentation/providers/thread_scoped_message_queue.dart`
    only if a narrow owner query is missing.
- Direct deterministic test file:
  `test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart`.
- Exact source methods and call sites:
  - `ThreadScopedMessageQueue.forThread`, `pendingFor`, and
    `takeNextForThread` already preserve the message's `conversationId`;
  - `sendMessage` captures `conversationId` in `QueuedChatMessage`;
  - `_syncQueuedChatMessagesState` projects only the visible conversation's
    queue;
  - `_drainQueuedChatMessagesIfIdle` reads ambient `conversationId` and
    `state.isLoading`;
  - `_sendMessageNow` resolves the visible `currentConversation` and visible
    `state.messages`;
  - `_finishStreaming` and participant pause/completion paths call the ambient
    drain helper;
  - `syncConversation` restores `queuedMessages` but does not schedule owner
    resumption.
- Current test gap:
  `a queued message survives a thread switch and stays on its thread` proves
  retention only. It does not prove automatic resumption, owner project/history,
  or that B can run while A has queued work.

## Implementation Notes

- Treat `QueuedChatMessage.conversationId` as the immutable owner. Reject or
  leave queued any item whose owner does not match the drain owner.
- The owner-explicit drain must require:
  - a non-empty `ownerConversationId`;
  - `ownerConversationId == conversationId` before invoking `_sendMessageNow`;
  - the owner is not loading and has no active response registration;
  - FIFO removal through `takeNextForThread(ownerConversationId)`.
- Do not temporarily select a hidden conversation to drain it. When A finishes
  while B is visible, leave A's item queued. After `syncConversation` restores A
  and proves it idle, schedule the owner-explicit drain with `unawaited`.
- Re-check owner and idle state after
  `_executionRuntime.ownershipSettled` and before each dequeue. A thread switch
  during the wait must not send the item into the newly visible thread.
- Pass the turn's conversation ID, resolved from
  `_activeResponseConversationIdForGeneration(generation)` before lifecycle
  cleanup, into completion-path drain decisions.
- `_sendMessageNow` remains a visible-owner operation. Add a defensive owner
  assertion or early return so a future caller cannot send a foreign queued
  item through ambient state.
- Typed side-effect ports:
  - queue mutation remains `ThreadScopedMessageQueue`;
  - conversation selection remains `syncConversation`;
  - message submission remains `_sendMessageNow` after the explicit owner
    precondition succeeds.
- Generated files and migrations: none.

## Deterministic Two-Thread Cases

Poison A and B with different projects, histories, and queued text:

1. Hold A's response, queue `queued-A`, then switch to B. B must show an empty
   queue and must be able to start and finish `message-B`.
2. Finish A while B remains visible. `queued-A` must not appear in B's requests,
   transcript, or queue and must remain pending for A.
3. Select A after its original turn is idle. `queued-A` must resume once,
   disappear from A's queue, and use A's project root and message history.
4. Queue different values for both A and B. Selecting and draining one owner
   must preserve the other owner's item and FIFO order.
5. Switch away during `ownershipSettled`. The post-wait owner re-check must keep
   the item queued instead of sending it to the new visible thread.
6. Preserve the existing same-thread live queue behavior and manual queue
   removal.

Assert recorded request owners, project roots, message contents, dequeue counts,
and visible queue projections.

## Similar-Pattern Search

- Search terms:
  - `_drainQueuedChatMessagesIfIdle`;
  - `_sendMessageNow`;
  - `_queuedChatMessages`;
  - `takeNextForThread`;
  - `pendingFor`;
  - `queuedMessages`;
  - `ownershipSettled`.
- Inspect every completion, pause, error, cancellation, and conversation-switch
  call site that can trigger or reveal a queue.
- Record goal-auto-continue or participant-specific queue scheduling issues as
  follow-ups unless the owner-explicit drain signature alone fixes them.

## Measurement, Manifest, and Coverage

- Expected declared notifier-part delta: `0`; the count remains `42`.
- Target same-library aggregate delta: `0`; reductions are acceptable, but the
  aggregate must remain at or below `22,900` physical lines.
- Manifest statuses and collaborator records: unchanged. No discovery marker is
  added because no collaborator is extracted.
- No size budget may increase.
- Current coverage baselines:
  - `thread_scoped_message_queue.dart`: `18/20` lines (`90.00%`);
  - `chat_notifier.dart`: `3,089/3,688` lines (`83.76%`).
- Coverage expectation:
  - reach `20/20` for the queue container;
  - do not regress `chat_notifier.dart` below `83.76%`;
  - hit every new owner re-check and deferred-resumption branch.

## Acceptance Criteria

1. Foreign queued work never blocks a visible idle conversation.
2. A queued item is never submitted with another conversation's state, history,
   or project.
3. A detached owner's item remains queued until that owner is selected and idle.
4. Selecting the idle owner resumes its queue automatically and exactly once.
5. Per-owner FIFO order and manual removal remain correct.
6. Switching during runtime ownership settlement cannot misroute an item.
7. Existing same-thread queue behavior remains compatible.
8. No part, manifest, marker, schema, generated file, or budget change.

## Verification

```bash
fvm dart format \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  lib/features/chat/presentation/providers/chat_notifier_participant_turns.dart \
  lib/features/chat/presentation/providers/thread_scoped_message_queue.dart \
  test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart \
  --set-exit-if-changed
tool/codex_verify.sh \
  --test test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart \
  --test test/features/chat/presentation/providers/chat_notifier_test.dart
fvm flutter test test/quality/file_size_ratchet_test.dart
tool/codex_verify.sh --coverage
awk -v target='lib/features/chat/presentation/providers/thread_scoped_message_queue.dart' \
  -v minimum=100 '
    /^SF:/ { selected = index(substr($0, 4), target) > 0 }
    selected && /^LF:/ { found = substr($0, 4) + 0 }
    selected && /^LH:/ { hit = substr($0, 4) + 0 }
    END {
      rate = 100 * hit / found
      printf "%s: %.2f%% (%d/%d)\n", target, rate, hit, found
      exit !(found > 0 && rate + 0.001 >= minimum)
    }
  ' coverage/lcov.info
awk -v target='lib/features/chat/presentation/providers/chat_notifier.dart' \
  -v minimum=83.76 '
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

The corrected Slice 2b1 live canary is required because this slice changes
production queue and active-response lifecycle behavior. Record the actually
reachable base URL and exact warmed model.

## Stop Conditions

- Stop if the proposed fix sends a hidden conversation by temporarily changing
  the global selection.
- Stop if `_sendMessageNow` can be reached with an owner different from the
  visible conversation.
- Stop if a global scheduler, persistence migration, or per-thread notifier
  redesign is required.
- Stop and record a follow-up if another lifecycle path cannot supply its owner
  before clearing generation state.
- Stop if the fix requires a new notifier part, production extraction, or
  aggregate budget increase.

## Handoff Notes

- Record request order, queue owner IDs, and project roots for both threads.
- Record the switch point at which A becomes eligible to resume.
- Record target-file coverage and aggregate line counts.
- Record every drain call site and the owner value it now supplies.
- Keep this slice in one focused Conventional Commit.

## Implementation Evidence

Implementation commit `048cdb55` binds queued work to an explicit conversation
owner. Audit-baseline follow-up `c63f5cf9` records the owner-explicit drain
methods and owner-visibility read. The deterministic fixtures prove:

- thread A retains its queued item while thread B remains idle and can complete
  its own message;
- selecting idle thread A drains its item exactly once with A's history and
  project, while per-owner FIFO and the foreign queue remain unchanged;
- switching during runtime ownership settlement restores the dequeued item to
  its owner instead of sending it through the newly visible thread;
- rejected runtime starts and draft-owner materialization races restore the
  exact queued item without losing or duplicating work;
- the queue container preserves exact owners, defensive copies, per-owner FIFO,
  and manual removal.

The queue-focused run passed all 29 tests, and the combined ChatNotifier run
passed all 314 tests. Analyze, the file-size and quality gates, the refreshed
turn-scope baseline check, and `git diff --check` passed. At this slice boundary
the primary file was 9,376 lines, the declared part count remained 42, and the
same-library aggregate remained exactly 22,900 lines. The final focused LCOV
artifact retained on the integrated tranche reports
`thread_scoped_message_queue.dart` at `47/47` (`100.00%`) and
`chat_notifier.dart` at `3,127/3,731` (`83.81%`), above the specified floors.

The later integrated full-coverage run completed generation, analysis, and
package tests before the root suite reached `+4208 -2`. Its only failures were
the pre-existing `M33 release packaging report validates static packaging lane`
and `M33 release packaging CLI writes JSON and Markdown outputs` tests. The
latter reported `Ready: false` with `sparkle_appcast_configuration`,
`sparkle_s3_public_read_config`, and `sparkle_public_release_verifier` failed.
Slice 2b4 changes no M33 path, so those failures are unrelated.

The exact-model corrected Slice 2b1 live canary passed on 2026-07-28 against
loaded `qwen3.6-27b-vision` at `http://192.168.100.241:1234/v1`. Its exact exit
maps and zero-busy-owner evidence are recorded in the Slice 2b1 handoff. This
completes Slice 2b4.
