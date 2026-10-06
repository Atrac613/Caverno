# Caverno v1.3.43

> Release date: 2026-09-23

## Summary

A small release fixing production release approval: the execution identity no longer treats `process_start`'s display-only `label` and an omitted-versus-true `background` flag as semantic, so a retry after an approved production release is no longer refused as a conflicting release.

## Changes

### Fixes

- **Production release approval retries** — The execution identity treated `process_start`'s display-only `label` and an omitted-versus-true `background` as semantic, so every retry after an approved production release was refused as a conflicting release. `label` is dropped from the identity, `process_start` is always treated as background, and the conflict result now includes the pending call's tool, working directory and background so a retry can reproduce it exactly. (`lib/features/chat/`)

## Version

- `1.3.43+57`