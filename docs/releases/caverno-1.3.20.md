# Caverno 1.3.20+32

## What's New

### Plan Mode and CLI Reliability

- Improved Plan Mode task proposals, validation handoffs, execution watchdogs, and recovery behavior.
- Added replay coverage for CLI execution stalls, timeouts, malformed scaffolds, duplicate verification tasks, and incomplete validation.
- Strengthened documentation and integration coverage for Plan Mode MVP handoff behavior.

### Testing and Diagnostics

- Added scenario fixtures covering successful entrypoint validation, workspace completion, task handoffs, and post-approval execution.
- Added regression coverage for missing files, weak validation, truncated proposals, unknown tools after completion, and verification stalls.

## Technical Details

- Version: `1.3.20+32`
- Platforms: iOS, macOS
- Source: Git history from `1.3.19+31` through `HEAD`
