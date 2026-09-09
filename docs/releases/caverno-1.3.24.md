# Caverno v1.3.24

> Release date: 2026-09-07

## Summary

This patch release prevents Firebase initialization from blocking macOS after
window restoration.

## Changes

### Fixes

- **macOS launch stability** — Stop Firebase swizzling from hanging the app
  after the macOS window is restored.

## Testing

- Release metadata was advanced from `1.3.23+35` to `1.3.24+36`.
- The functional change is based on the commit after the `1.3.23+35`
  release tag.

## Version

- `1.3.24+36`

## Notes

This release contains the macOS startup stability fix committed after
`1.3.23+35`.
