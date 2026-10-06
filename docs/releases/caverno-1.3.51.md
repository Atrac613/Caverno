# Caverno v1.3.51

> Release date: 2026-09-25

## Summary

A fix-focused release for iOS and macOS: loop-limit recovery requests now
carry the same context as a normal follow-up, and carried reads survive
`git add` instead of being dropped right before the commit that names them.

## Changes

### Fixes

- **Give loop-limit recovery the carried results and digest** — The recovery
  request told the model to use the latest tool results and finish, but sent
  only the last batch: no sticky skill, no carried reads, no turn digest. In
  sessions 50e3f486, d84f819b and e6b3d03c the model finished blind, re-listing
  tags instead of tagging or committing a guessed build number. The recovery
  request now resolves through the same carry and digest as a normal
  follow-up; the recovery prompt still reads the recovery-specific list.
  (`lib/features/chat/presentation/providers/chat_notifier.dart`)

- **Keep carried reads across git add** — `RecentReadResultCarry` stopped at
  any mutating command, and `git add` counted as one, so the tag and bumped
  version dropped out right before the commit message that names them;
  sessions d84f819b and e6b3d03c re-read both after staging. `git add` only
  changes the index, so it is now carried past with a "git add" change label
  and only status/diff results it made stale are dropped.
  (`lib/features/chat/domain/services/recent_read_result_carry.dart`)

### Testing

- **Add firing signatures for recovery carry and git add carry** — Both fixes
  fired on their first real sessions; their firing signatures are now recorded
  in the fix-firing checks.
  (`tool/check_fix_firings.py`)

## Version

- `1.3.51+65` (proposed)