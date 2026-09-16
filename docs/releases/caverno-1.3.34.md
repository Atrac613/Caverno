# Caverno v1.3.34

> Release date: 2026-09-16

## Summary

Remote Watch voice threads and safe remote coding reconnection, plus chat turn-lifecycle fixes and Flutter SDK 3.47.4 upgrade.

## Changes

### Features

- **Remote Watch voice threads** — Added voice thread support for remote Watch interactions.
- **Safe Watch remote coding reconnection** — Reconnect Watch remote coding sessions safely after disconnection.

### Fixes

- **Stopped turn request finalization** — End a stopped turn's request instead of leaving it in a generating state.
- **Tool-less answer background job hallucination** — Stop the tool-less answer from inventing background job progress.

### Performance

- **Prompt clock pinning** — Pin the prompt clock to the turn that opened it to prevent drift.

### Build & Dependencies

- **iOS scheme sharing** — Share Watch app and widget extension schemes.
- **Flutter SDK 3.47.4** — Upgraded Flutter SDK to 3.47.4.
- **Lockfile refresh** — Refreshed Dart and CocoaPods lockfiles.

## Version

- `1.3.34+47`

## Notes

This release introduces remote Watch voice capabilities and hardens the chat turn lifecycle. The Flutter SDK upgrade to 3.47.4 and lockfile refresh ensure dependency consistency.
