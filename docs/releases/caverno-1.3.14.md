# Caverno v1.3.14

**Release Date:** 2026-08-07

## Overview

Caverno v1.3.14 makes the chat loop interruptible and thread-independent, adds
multi-endpoint LLM management with per-role model routing, brings an interactive
terminal to the coding workspace, and grounds coding goal verification in
mechanical facts instead of the model's own claims. macOS updates now ship
through CloudFront.

## New Features

### LLM Endpoints and Model Routing
- **Multiple LLM endpoints** — Register several OpenAI-compatible endpoints and switch between them without editing settings each time.
- **Per-role model routing** — Plan drafting can be routed to a dedicated planning model, resolved from the pinned endpoint for that role.
- **Endpoint recovery** — A demoted endpoint is retried after a recovery window instead of staying disabled for the rest of the session.
- **Context window probing** — The model's context window is measured during capability probing and used for budgeting.

### Interruption and Thread Independence
- **Interrupt a running turn** — A new message interrupts the turn in progress instead of queueing behind it.
- **Interrupt mid-answer** — Interruption now works while the answer is being written, not only between requests.
- **Per-thread state** — Each thread keeps its own state across concurrent turns, and plan drafting runs on its own thread so it no longer strands the others.

### Coding Workspace
- **Bottom terminal** — An interactive terminal in the coding workspace, with its own persistence and runtime.
- **Coding goals with auto-continue** — Goals track multi-step coding work and continue automatically within a visible budget.
- **Hover project actions** — Project actions appear on hover in the coding drawer.
- **Grounded verification** — Goal completion is decided from mechanical evidence (tool exit status, file mutation facts) rather than the model's wording, and goals can be closed from grounded tool updates.

### Context Management
- **Segmented context breakdown** — The usage popover now shows a segmented context window breakdown, including the tool-definition payload.
- **Smarter compaction** — Old tool results are pruned before compaction, and the protected conversation tail is bounded by tokens.
- **Unchanged re-read detection** — Re-reading a file that has not changed is flagged, and no-op `edit_file` calls report `no_change` instead of false success.

### macOS Updates
- **CloudFront delivery** — macOS Sparkle updates are now delivered through CloudFront.

### Diagnostics
- **Persistent debug logs** — Debug logs are written to `~/.caverno/app_logs`.
- **Session log timestamps in UTC** — Removes ambiguity when correlating logs across machines.

## Bug Fixes

- **Hanging network calls** — Web search, MCP, and LLM calls that never answer are now bounded by a timeout.
- **LAN scan stalls** — LAN scanning no longer stalls on unreachable DNS.
- **Plan Mode from a new coding thread** — Plan Mode is reachable again from a freshly created coding thread, and its temporary files are isolated per session.
- **False verification claims** — Verification a task never actually performed is no longer accepted, and coding goals recover from false completion claims.
- **Fabricated transcripts** — Coding answers are guarded against fabricated tool transcripts.
- **Shell approval bypass** — Blocked a background-execution path that bypassed shell approval.
- **Feedback payload redaction** — Feedback payloads are redacted before being written to S3, and the feedback endpoint requires an auth token.
- **Tool results through budgeting** — A tool's reported outcome survives prompt budgeting instead of being dropped.
- **Structured tool-result replays** — Replayed structured tool results are accepted rather than rejected as malformed.
- **macOS notarization** — Python binaries under `Resources/python.bundle` are signed so notarization succeeds.
- **Test output in session logs** — Flutter test output no longer contaminates the session log corpus.

## Dependency Updates

| Package | Previous | Updated |
|---------|----------|---------|
| `serious_python` | 4.1.1 | 4.4.1 |
| `dartssh2` | 2.18.0 | 2.22.2 |
| `mobile_scanner` | 7.2.0 | 7.4.0 |
| `flutter_local_notifications` | 22.0.1 | 22.2.0 |
| `flutter_markdown_plus` | 1.0.7 | 1.0.12 |
| `drift` | 2.34.0 | 2.34.2 |
| `uuid` | 4.5.3 | 4.6.0 |
| `window_manager` | 0.5.1 | 0.5.2 |
| `openai_dart` | 7.0.0 | 7.0.1 |
| `record` | 7.1.0 | 7.1.1 |
| `image_picker` | 1.2.2 | 1.2.3 |
| `battery_plus` | 7.1.0 | 7.1.1 |
| `dart_ping` | 10.0.0 | 10.0.1 |
| `build_runner` | 2.15.0 | 2.15.1 |

## Technical Details

- **Commit Range**: `fa22686d..382198c6`
- **Build Number**: 26
