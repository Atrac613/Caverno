# Caverno 1.3.18+30

## What's New

### Video Attachments and HTML Preview

- Added video attachments from the composer, gallery, local files, or URLs.
- Added video playback, poster frames, delivery tracking, and video-aware model capability detection.
- Added an HTML project preview flow from the companion panel.
- Added a built-in viewer for images posted in the conversation.

### Onboarding and Model Routing

- Replaced the onboarding dialog with a full-screen setup wizard.
- Added endpoint video-input detection and persisted the discovered capability.
- Grouped model routing settings and centralized model selection.
- Improved the activity heatmap and dashboard presentation.

## Security and Reliability

- Added SSH host-key verification and known-host approval flow.
- Contained Git working directories, pathspecs, project reads, and local-command writes to the selected project root.
- Denied unclassified external MCP tools by default for routines.
- Hardened Remote Coding with release-mode plaintext listener containment, pinned WSS transport, and per-socket session authorization.
- Improved diagnostic decoding, streaming relay failures, and media-host delivery reporting.

## Technical Details

- Version: `1.3.18+30`
- Platforms: iOS, macOS
- Source: Git history through commit `70fa6135`
