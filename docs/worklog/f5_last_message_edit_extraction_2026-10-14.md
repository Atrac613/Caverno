# F5 Last-Message Edit Extraction (2026-10-14)

Follows the 2026-10-11 content-call partition slice, whose next action was to
inspect owner-scoped content-tool message mutation and freeze attached/
detached behavior before another move.

## Frozen first

`detached streaming text never reaches the visible thread`
(`chat_notifier_detached_turn_project_test.dart`): owner A streams after the
user has moved to thread B; A's chunks must stay off the visible state while
streaming and land only in A's conversation. Disabling the detached branch
of `_appendToLastMessageForGeneration` fails it.

## Moved

`_appendToLastMessageForGeneration`, `_replaceLastMessageContentForGeneration`
and `_removeTrailingThinkTagForGeneration` each held an attached and a
detached copy of the same last-message rewrite. The rewrite is now
`LastMessageEdit.withContent` (a pure helper); `_replace...` is the one place
that picks the turn's cached list or the visible state and commits to the
cache, and to the state only when attached. Append and trailing-think read the
last message through the existing `_lastMessageContentForGeneration` and write
through `_replace...`.

## Verification

- Full suite: 12,330 tests pass; analyzer clean.
- ChatNotifier: 7,224 -> 7,172 root, 19,739 -> 19,687 aggregate lines;
  budgets lowered.
- Turn-scope read ratchet: five ambient `state.messages` reads removed, none
  added; the reviewed baseline was lowered by removing exactly those five
  entries. The tool's full `--check-baseline` already differed before this
  slice (method-list drift from earlier extractions); the read ratchet test is
  the maintained gate.

## Next

The other attached/detached pairs (`_stripToolArtifactsFromLastAssistantMessage`,
`_applyFinalAnswerMessageMutation`, the streamed-suffix removal) differ in
what they edit and how they commit (some route through `_routeThreadState`);
freeze each before moving it.

## Second slice (2026-10-15): tool-artifact strip

`_stripToolArtifactsFromLastAssistantMessage` joined the shared rewrite as
`LastMessageEdit.withoutToolArtifacts` (strip a last assistant message's tool
tags, drop it when nothing remains). Disabling its detached branch already
failed `queued work drains only for its visible idle owner`, so no new
characterization test was needed. ChatNotifier 7,172 -> 7,136 root,
19,687 -> 19,651 aggregate; one more ambient read removed from the baseline.
Full suite 12,335 tests pass.

## Third slice (2026-10-15): final-answer notice wrappers

The six notice wrappers (`_appendUnexecuted...NoticeIfNeeded`,
`_replace...CommandSuccessClaimIfNeeded`) each read the turn's final-answer
messages and applied one mutation; they now call one
`_applyFinalAnswerNotice`. `_applyFinalAnswerMessageMutation` itself is
unchanged. ChatNotifier 7,136 -> 7,119 root, 19,651 -> 19,634 aggregate;
the turn-scope baseline was regenerated (one method added, reads unchanged,
a 45-line diff now that its ordering is stable).

Coverage gap found, not closed: removing the detached early return in
`_applyFinalAnswerMessageMutation` fails no test. The owner-routing branch is
covered (forcing the visible-state write fails two suites). A detached-turn
characterization attempt did not reach any notice path (the bracketed answer
in a no-tool-call coding turn did not trigger the unexecuted-tool-request
notice), so it was discarded rather than kept as a test that pins nothing.
Freeze that guard before moving `_applyFinalAnswerMessageMutation`.
