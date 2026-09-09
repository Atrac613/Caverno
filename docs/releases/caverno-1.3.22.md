# Caverno v1.3.22

> Release date: 2026-09-07

## Summary

This patch release improves coding-goal continuity after inspection-only Git operations, hardens macOS shutdown around Drift and SQLite persistence, reports uncaught crashes, and unblocks macOS launch when the conversation store is large.

## Changes

### Features

- **Crash reporting** — Report uncaught crashes with Firebase Crashlytics.

### Fixes

- **Coding goal continuity** — Keep coding goals active after inspection-only Git operations and preserve the associated continuation evidence and tool-result context.
- **macOS shutdown stability** — Close Drift persistence before Sparkle or window-manager termination tears down the Flutter engine, cancel exit when closing fails, and resume idle maintenance when exit is cancelled.
- **macOS launch hang** — Show the window before Hive and Drift hydrate, skip migrated Hive conversation boxes, and load sidebar listings without decoding every message payload.

### Testing

- **Goal and persistence coverage** — Add regression tests for continuation decisions, tool-result prompts, retryable persistence close failures, concurrent close requests, and the macOS exit lifecycle.
- **Launch-path coverage** — Add tests for listing-only conversation hydrate, skipped Hive opens after F4 migration, delayed Sparkle startup, and Apple Events entitlements.

## Version

- `1.3.22+34`

## Notes

This release contains focused stability fixes for coding workflows and macOS application launch and shutdown. The changes are based on the commits after `1.3.21+33`.
