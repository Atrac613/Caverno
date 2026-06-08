# Caverno 1.3.4 Release Notes

## What's New

- **On-device Python script execution** — Run Python scripts locally with an embedded runtime, supporting image metadata analysis and staged file attachments.
- **Apple Foundation Models provider** — Added support for Apple's on-device models as a new LLM provider option.
- **Improved Python tool reliability** — Staged attachment paths are now signaled to the model, with automatic retry logic for missing code or failed analysis.

## Bug Fixes

- Clarified code execution tool labels for better readability.
- Fixed Python attachment analysis: skipped analyses are now recovered, and original image attachments are persisted for reuse.
- Honored tool calls even when the LLM returns a `length` finish reason, preventing premature termination.
- Removed redundant image drop success snackbar.

## Build & Platform

- Added embedded Python support for macOS and Android builds.
- Bundled `piexif` into the embedded Python worker for image processing.
- Staged serious\_python iOS native frameworks for builds.
- Added iOS and macOS release wrapper script.

## Test

- Added worker regression suite and embedded-runtime integration tests.
