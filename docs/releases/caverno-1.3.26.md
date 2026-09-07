# Caverno v1.3.26

> Release date: 2026-09-08

## Summary

This release improves macOS startup reliability, makes the default MCP
connection behavior safer, and hardens RAG2 child-process execution.

## Changes

### Fixes

- **macOS window startup** — Keep the window hidden until Dart explicitly
  allows it to be shown, and avoid requiring APNs or debugger attachment for
  the normal debug-window path.
- **MCP defaults** — Stop connecting to localhost MCP servers by default when
  no remote server has been configured.
- **RAG2 child processes** — Preload sqlite3 so generated child processes can
  start reliably in Linux CI and replay environments.

## Testing

- Release metadata was advanced from `1.3.25+37` to `1.3.26+38`.
- The changes are based on the commits after the `1.3.25+37` release tag.

## Version

- `1.3.26+38`

## Notes

This release contains the macOS startup, MCP default-connection, and RAG2
child-process reliability fixes committed after the `1.3.25+37` release tag.
