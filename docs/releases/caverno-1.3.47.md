# Caverno v1.3.47

> Release date: 2026-09-25

## Summary

A focused release on the git command safety layer: read-only git commands are now classified by vetted flags rather than a blanket verb allowlist, pipeline refusals point the agent at git-native options instead of shell pipelines, and a firing signature tracks whether the new refusal path reaches real sessions.

## Changes

### Fixes

- **Read-only git commands classified by vetted flags** — `git branch`, `git tag`, `git stash`, `git config`, `git reflog`, and `git fsck` are now classified as read-only only when their flags match a vetted allowlist. Unknown flags fall through to the approval path instead of bypassing it.
- **Attached values required for read-only options** — Long value options must use `--opt=value` form; only `-n` accepts a detached numeric value. This closes a gap where an unvetted option placed after `--format` or `--pretty` could skip the allowlist.
- **Pipeline refusals point at git-native options** — When a shell pipeline is refused, the message now leads with supported Git count, limit, and format options before mentioning a shell pipeline, and notes that local command execution asks for approval on every attempt.

### Tooling

- **Firing signature for pipeline refusal** — `tool/check_fix_firings.py` gains a signature that records whether the rewritten pipeline refusal reaches real sessions, so the next step can measure whether models switch to git-native options or fall through.

## Version

- `1.3.47+61`