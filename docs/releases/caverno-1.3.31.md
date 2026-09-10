# Caverno v1.3.31

> Release date: 2026-09-10

## Summary

This release improves delegated coding workflows, harness diagnostics, and visual consistency across chat and run logs. It also adds localized composer controls and strengthens structured issue execution responses.

## Changes

### Fixes

- **Require complete run-issue responses** — Tightened the response schema so every expected property is present before an issue run is accepted.
- **Keep harness notices in logs** — Routed delegation harness plumbing notices to the log instead of exposing them in the user-facing reply.
- **Separate run headers from scrollback** — Improved run-log layout by isolating the header from scrollback content.

### Features

- **Use the bundled monospace face** — Rendered logs and code with the bundled monospace font for consistent presentation.
- **Localize the composer thinking menu** — Added translation support for the composer thinking menu.
- **Register delegation admission signatures** — Added the signatures required by the delegation admission flow.

### Refactors

- **Extract chat collaborators** — Split chat collaborators out of the main implementation to improve maintainability and satisfy file-size constraints.

## Version

- `1.3.31+44`

## Notes

This release is based on the changes after tag `1.3.30+43`.
