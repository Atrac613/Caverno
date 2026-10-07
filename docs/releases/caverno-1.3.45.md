# Caverno v1.3.45

> Release date: 2026-09-23

## Summary

A release focused on keeping multi-step coding turns on track and making releases reproducible: earlier read results now survive a file write within the same turn, the release script refuses to publish a version its tag does not describe, and read-only `git tag` filters are no longer mistaken for tag creation.

## Changes

### Fixes

- **Read results carried across file writes** — A file write no longer discards every earlier read in the turn. Only reads of the written path are dropped; older results are still carried, labelled with the writes they predate, so a version bump no longer sends the agent back to re-inspect tags and history it already had. (`lib/features/chat/`)
- **Release provenance guards** — `tool/release_ios_macos.sh` now refuses to publish unless the `VERSION+BUILD` tag points at a clean HEAD, and the macOS lane refuses a build number the live appcast already lists. Both checks run in dry runs; each has a `CAVERNO_ALLOW_*` override for intentional exceptions. (`tool/`)
- **Read-only `git tag` filters** — `git tag --points-at`, `--contains`, `--no-contains`, `--merged`, `--no-merged` and `-n` are classified as read-only listings, so a lookup such as `tag --points-at HEAD` is no longer blocked as a tag creation. (`lib/features/chat/`)

### Tooling

- **Fix-firing signature** — `tool/check_fix_firings.py` tracks whether the read-result carry fires in real sessions. (`tool/`)

## Version

- `1.3.45+59`

## Notes

The macOS 1.3.44+58 archive was republished on 2026-09-23 from a build two commits past the `1.3.44+58` tag. 1.3.45+59 supersedes it with a build that matches its tag; the new provenance guards prevent a repeat.
