# Caverno v1.3.39

> Release date: 2026-09-20

## Summary

A plan/workflow panel that nothing had rendered since April is deleted, the two surfaces worth keeping move to a live awaiting-you sheet, and planning stops spending its JSON budget on thinking. Two new quality gates cover the blind spots that let the first two go unnoticed.

## Changes

### Features

- **Awaiting-you summary and sheet** — The companion pane's summary now counts the union of unresolved open questions and blocking material assumptions, marking the assumption kind apart, and tapping it opens `AwaitingYouSheet` where each item can be answered or confirmed. Before this its `onOpen` reached a markdown preview with no questions in it, because both answering surfaces were reachable only from an unmounted panel. (`lib/features/chat/presentation/widgets/plan/awaiting_you_sheet.dart`)
- **LL33 transforms as firing evidence** — `tool/check_fix_firings.py` can key a signature on a `turnExit.transforms` id, read structurally, instead of matching prose the guard leaked into the answer. A log that merely quotes the id is not a firing. (`tool/check_fix_firings.py`)

### Fixes

- **Planning no longer thinks away its own JSON budget** — All four planning calls of a release turn had been ending on `finishReason: length`, each spending its whole budget inside `<think>` and emitting no JSON, so the plan came out with zero tasks. `ModelUsageRole.planning` joins the structured utility roles that suppress thinking. Measured on the same prompt afterwards: 2 calls, both `stop`, 60s against 274s, and a real task list.
- **Composer shortcuts in the app's own language** — `suggest()` took a `languageCode` its only caller never passed, so every draft since the feature shipped asked for English. It now resolves the app's language preference through the same path the UI uses.
- **A real file write no longer decides two assertions** — The diagnostics export writes to `Directory.systemTemp` before calling `setState`. One test asserted immediately after the tap; another polled a three-second wall-clock deadline and broke out silently, so a timeout surfaced as an unrelated finder failure. Both now share `pumpUntilFound`, which fails with the elapsed time and what it was waiting for.

### Refactors

- **The plan/workflow panel is deleted** — `_buildWorkflowPanel` lost its only call site on 2026-04-18 and was moved into a part file under an `// ignore: unused_element` a month later, so the analyzer stayed green for five months. Every surface below it was called exactly once, from inside it. Scoped per surface first: all seven have a live equivalent. The cascade came to 3,116 lines across four part files, plus four widget files that lost their last importer.

### Testing

- **The awaiting-you summary is proved to reach a real page** — Mounting a section in isolation proves it works, never that anything renders it, and that gap is where the deleted panel sat. A ChatPage-level test seeds a conversation carrying both kinds and asserts the summary appears in the companion pane and opens the sheet.
- **A widget file nothing imports now fails the build** — `unused_element` covers private declarations, so a public widget class alone in its file is invisible to `flutter analyze`. 151 widget files were checked and 6 were unreachable; all six are deleted. (`test/quality/widget_reachability_test.dart`)

## Version

- `1.3.39+52`

## Notes

Two things this release does not settle. `workflowStage` is not dead code — `chat_notifier_prompt_context.dart` puts it in the system prompt, so the model reads it and only the user has no display; whether it deserves one is open. And the release-notes conventions live in a skill whose content does not survive the turn it is loaded in, which is why this file was first written to the repository root in the wrong format.
