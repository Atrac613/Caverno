# Caverno v1.3.32

> Release date: 2026-09-11

## Summary

This release improves background job lifecycle handling and strengthens completion-state interpretation for coding workflows. It also includes maintenance documentation for recent evaluation results.

## Changes

### Fixes

- **Preserve finished background jobs** — Keep completed background jobs reachable after turn retirement so their results remain available to callers.
- **Distinguish refused commands from failed commands** — Prevent refused commands from being reported as execution failures.
- **Recognize CJK denials** — Treat denial responses written in CJK languages as denials in the completion-claim guard.
- **Bound quiet dependency output** — Limit `flutter pub get` output when running with `--quiet-output`.

### Documentation

- **Record HEU measurements** — Document the HEU3 re-measurement and HEU5's first measured misfire.

## Version

- `1.3.32+45`
- Platforms: iOS, macOS
- Source: Git history after `1.3.31+44` through `HEAD`.
