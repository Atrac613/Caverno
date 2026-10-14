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
