# Caverno v1.3.5

> Release date: 2026-06-08

## Summary

Streaming response finalization fix and test improvements.

## Changes

### Fixes

- **Finalize streaming after monitor follow-up** — Improved handling of streaming response completion to ensure the chat UI properly finalizes when the monitor service sends follow-up results. (`chat_notifier.dart`)

### Testing

- **Expanded streaming finalization tests** — Added test cases covering streaming response completion paths to prevent regressions. (`chat_notifier_test.dart`)

## Version

- `1.3.5+16`

## Notes

This is a targeted fix release focused on streaming response handling stability.
