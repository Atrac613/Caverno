# Release Notes — 1.3.39+52

## New features

- **Awaiting-you summary**: open questions and blocking assumptions from the
  saved workflow now appear as a summary in the companion pane. Tapping it
  opens the awaiting-you sheet, where each item can be answered directly.
- **LL33 transform evidence**: the tool layer can now read LL33 transforms as
  firing evidence.

## Fixes

- **Plan mode JSON budget**: planning no longer spends its JSON output budget
  on thinking, which could truncate the plan document.
- **Composer shortcuts**: the draft composer's shortcut hints are now shown in
  the app's own language.

## Cleanup

- Removed the plan/workflow panel that had not been rendered since April
  (2026-04-18). Every surface it contained has a live equivalent: tasks in the
  companion pane, plan review and approval in the compact plan footer card,
  and open questions in the awaiting-you sheet. This deleted roughly 3,100
  lines across four part files and four orphaned widget files.

## Tests and quality

- New regression test proves the awaiting-you summary is mounted on the real
  chat page and opens the awaiting-you sheet.
- New quality gate fails the build when a widget file is imported by nothing.
- Settings tests no longer depend on a real file write deciding two
  assertions.
