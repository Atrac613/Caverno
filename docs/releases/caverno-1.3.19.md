# Caverno 1.3.19+31

## What's New

### Apple Watch Companion

- Added a companion watch app with mirrored chat threads, thread switching,
  deferred message delivery, approval actions, and a Smart Stack glance.
- Improved cold-start delivery, message rendering, dictation, and spoken
  responses on watchOS.

### Attachments and Chat Experience

- Added PDF reading with paging, bounded extraction, platform viewing, and
  attachment capability checks.
- Expanded video attachments, media delivery tracking, and HTML project
  previews.
- Improved conversation opening, tool approvals, streaming follow-ups, and
  response recovery diagnostics.

### Security and Privacy

- Added encrypted settings backup and moved credentials out of settings
  exports and general-purpose storage.
- Added sensitive log redaction and permission hardening, bounded MCP,
  network, HTML preview, and settings QR inputs, and stronger Remote Coding
  transport and ownership checks.
- Reconciled the iOS privacy manifest and Android backup exclusions for the
  release build.

### Grounded Responses and Reliability

- Added retrieval and answer-grounding diagnostics with citation support.
- Improved Plan Mode assumptions, tool-loop outcome reporting, release
  approval evidence, and cancellation/retry handling.
- Updated Firebase, notification, SQLite, desktop drop, OpenAI, and SSH
  dependencies with the pinned Flutter 3.44.8 toolchain.

## Technical Details

- Version: `1.3.19+31`
- Platforms: iOS, macOS
- Source: Git history through commit `1e15287b1`
