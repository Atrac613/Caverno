# Caverno v1.3.25

> Release date: 2026-09-07

## Summary

This patch release improves macOS startup rendering reliability.

## Changes

### Fixes

- **macOS window startup** — Paint a Flutter frame before showing the macOS
  window so the initial presentation is rendered reliably.

## Testing

- Release metadata was advanced from `1.3.24+36` to `1.3.25+37`.
- The functional change is based on the commit after the `1.3.24+36`
  release tag.

## Version

- `1.3.25+37`

## Notes

This release contains the macOS initial-frame rendering fix committed after
the `1.3.24+36` release tag.
