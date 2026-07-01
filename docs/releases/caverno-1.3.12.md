# Caverno v1.3.12

**Release Date:** 2026-07-01

## Overview

Caverno v1.3.12 brings worktree-based coding sessions, a redesigned dashboard landing view, design system foundations, and significant security hardening around tool approvals and auto-review.

## New Features

### Worktree Coding Sessions
- **Worktree-based coding sessions** — Create isolated git worktree workspaces for feature development, separate from the main branch. Each worktree runs its own coding agent tasks with full git operations (commit, push, merge) without affecting the base repository.
- **Worktree agent tasks companion panel** — Agent tasks running in worktrees are now displayed in the companion panel for easy monitoring and management.

### Dashboard
- **Dashboard landing view** — New dashboard as the workspace entry point, providing an overview of conversations, routines, and coding projects.
- **Dashboard stats calculator** — Computes and displays key metrics across conversations, routines, and coding sessions.

### Design System
- **Design system token foundation** — Introduced unified color tokens, typography tokens (including JetBrains Mono for monospace), and spacing tokens.
- **Primary accent color** — Set to `#0288D1` for consistent branding across the app.
- **Flattened chat composer** — Removed input area background, frame, and focus border for a cleaner look.
- **Unified selection states** — Drawer and workspace tab selected backgrounds now match hover states.

### Remote Coding
- **Remote ask-user questions on mobile** — Mobile devices can now display and respond to ask-user questions from remote coding sessions.
- **Coding thread busy indicator** — Visual indicator showing when a coding thread is actively processing.
- **Coding thread delete action on hover** — Delete action appears on hover for easier thread management.

### Session Logs
- **Turn-provenance correlation keys** — Session logs now include correlation keys linking request/response pairs for easier debugging.
- **Post-LLM transform recording** — Applied post-LLM transforms are recorded on the turn_exit record for full traceability.
- **Git build provenance stamping** — Build provenance (git commit hash, branch) is stamped into session logs.
- **Routine companion session logs** — Routine executions now generate companion session logs for debugging.

### Security
- **User-directed auto-review denial escalation** — When a user explicitly denies an auto-review verdict, the request is escalated to manual approval rather than being silently rejected.

## Bug Fixes

- **Tool loop denial** — Prevented tool loops from re-issuing denied commands under reworded reasons.
- **Profile item deduplication** — Fixed affix-tiled profile items missed by bigram similarity check.
- **Coding continuation recovery** — Preserved progress when re-prompting after coding continuation recovery.
- **Markdown table borders** — Improved visibility of markdown table borders with brighter colors.
- **Verification guard false positives** — Git, SSH, and process command results are now correctly counted as read-only inspection verification.
- **iOS App Store release flow** — Hardened the iOS App Store release flow for more reliable builds.
- **Dashboard startup stability** — Fixed dashboard startup test flakiness.
- **Dashboard workspace lists** — Hidden workspace lists from the dashboard view.
- **Chat page size ratchet** — Kept chat page within size ratchet limits.
- **safe-flutter macOS guard** — Resolved safe-flutter macOS guard resolution from cwd instead of script path.

## Dependency Updates

| Package | Previous | Updated |
|---------|----------|---------|
| `serious_python` | 2.0.0 | 4.1.1 |
| `dart_ping` | 9.0.1 | 10.0.0 |
| `battery_plus` | 6.2.3 | 7.1.0 |
| `audioplayers` | 6.7.1 | 6.8.1 |
| `openai_dart` | 6.2.0 | 7.0.0 |
| `path_provider` | 2.1.5 | 2.1.6 |
| `actions/checkout` (GitHub Actions) | 6 | 7 |

## Migration Notes

- **serious_python 4.x** — The `run` call signature changed. If you have custom integrations with SeriousPython, update to the new API.
- **dart_ping 10.x** — Event structure changed. Custom ping handlers may need updates.
- **openai_dart 7.x** — Breaking changes in the OpenAI client library. Verify API compatibility if using custom endpoints.

## Known Issues

None reported at the time of release.

## Contributors

Thanks to all contributors who made this release possible.
