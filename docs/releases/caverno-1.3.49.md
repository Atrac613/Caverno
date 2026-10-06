# Caverno v1.3.49

> Release date: 2026-09-25

## Summary

A fix-focused release for iOS and macOS: built-in tool calls with mistyped
arguments are now rejected cleanly instead of ending the turn, and two
agent-tooling fixes improve `search_files` and git command classification.

## Changes

### Fixes

- **Reject mistyped built-in tool arguments before dispatch** — Handlers cast
  their arguments, so a mistyped one threw and ended the turn unexecuted (in
  one session `write_file` received a JSON object as `content` twice and the
  file was never written). Built-in calls are now checked against their
  declared schema types first and return `invalid_tool_argument_type` instead.
- **Honor line anchors in `search_files` queries** — `search_files` matched
  literal text only, so anchored queries (e.g. `^version:`) found nothing and
  wasted a tool-loop slot. A leading `^` / trailing `$` is now honored as a
  line anchor while still matching the literal text.
- **Classify the command left after a trailing `head`/`tail`** — `isReadOnly`
  read a trailing `| head -N` as unvetted arguments, so
  `tag --list ... | head -3` fell to auto-review and never counted as a
  tag-format inspection. The line limit is now stripped before
  classification, and any remaining shell operator is treated as not
  read-only.
- **Allow dirty trees in the release flow** — The release gate no longer
  fails on a dirty working tree, and the benign iOS upload crash is recorded
  in the lane log.

## Version

- `1.3.49+63` (proposed)

## Notes

The v1.3.48 release notes and version bump were committed on top of the git
classification fix and released from it (tag `1.3.48+62` points at the
unsquashed commit `921e876e2`), so that fix ships in this release.