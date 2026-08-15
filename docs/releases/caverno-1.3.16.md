# Caverno 1.3.16+28

## What's New

### Flutter Run Diagnostics

- Added a coding-panel action to run the project's Flutter app.
- Added device selection from the captured application navigator.
- Added structured Flutter run logging and surfaced build failures and unknown failure shapes.
- Added a bottom dock that combines the terminal, run log, and issues views.
- Added bounded device listing and run issue presentation beside the log.
- Added deduplicated failure analysis and made run issues available to chat.

### Local LLM Health

- Added a local LLM liveness panel to the companion panel.

## Bug Fixes

- Improved recovery of printed tool calls on streaming responses, including unclosed `<tool_call>` tags around complete objects.
- Synchronized the macOS Podfile lockfile with `serious_python 4.5.1`.
- Fixed benchmark score denominators and saturation evaluation to reflect measured and attempted points.
- Fixed unified-diff handling when diffs omit Git path prefixes.
- Improved the live diagnostic vision probe image size.
- Improved diagnostic-page card separation.

## Technical Details

- Version: `1.3.16+28`
- Platforms: iOS, macOS
- Source: Git history through commit `600d44f8`