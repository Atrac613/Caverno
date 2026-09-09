# Caverno v1.3.28

> Release date: 2026-09-09

## Summary

This release improves Remote Coding notifications and conversation recovery.

## Features

- Set up push notifications during mobile pairing.
- Authorize push notifications over paired connections.
- Preserve remote notifications during notification relay outages.

## Fixes

- Retry failed Firebase notification initialization.
- Ignore stale notification token refresh results.
- Reduce conversation hydrate and save races during startup and terminal resume.
- Improve checkpointing and continuation behavior for long-running conversations.

## Maintenance

- Update Flutter and notification relay dependencies.
- Improve Linux CI helper extraction and SQLite initialization coverage.

## Version

- `1.3.28+41`
- Platforms: iOS, macOS
- Source: Git history after `1.3.27+40` through `fe8180501`.
