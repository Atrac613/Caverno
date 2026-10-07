# Caverno v1.3.41

> Release date: 2026-09-22

## Summary

A focused hardening pass on Remote Coding destination commands: the client now scopes conversation-clearing to the selected project and conversation, the companion panel reads live state instead of a stale snapshot, and the server validates the bound destination before applying composer settings — discarding any uploaded attachment when the settings cannot be applied.

## Changes

### Fixes

- **Remote coding destination commands** — `clearConversation` now sends the selected project and conversation ids instead of an empty payload, so the command is scoped to the active destination. The companion panel now watches the live client state while open rather than rendering a snapshot captured at open time. On the server side, composer settings are applied only after the bound destination is validated, and an uploaded attachment is discarded when the settings cannot be applied. (`lib/features/remote_coding/`)

### Testing

- **Server notifier destination tests** — New tests cover the hardened destination handling in the remote coding server notifier. (`lib/features/remote_coding/`)

## Version

- `1.3.41+55`
