# Caverno v1.3.9

> Release date: 2026-06-25

## Summary

LL31 tool-loop exit reason instrumentation, in-chat routine authoring (ROUTINE1), session log visibility improvements, and hardening of coding harness evidence guards and release workflows.

## Changes

### Features

- **LL31 tool-loop exit-reason classifier and explainer** — Added instrumentation to classify and explain why tool loops exit, improving observability for complex task execution. (`chat_notifier.dart`, `chat_state.dart`)
- **LL31 turn-exit persistence** — Persisted LL31 turn-exit reasons to the session log for post-hoc analysis.
- **In-chat routine authoring (ROUTINE1)** — Added `create_routine` capability for authoring routines directly within the chat interface.
- **Near-duplicate skill detection** — Added detection for near-duplicate skills before saving to prevent redundancy.
- **Session log section in UI** — Added a session log section to the chat and coding companion panel for better visibility into raw model outputs and tool interactions.
- **Git tag validation** — Added a guard to block git tags that disagree with the `pubspec.yaml` version.

### Fixes

- **Coding harness evidence guards** — Hardened coding tool-loop and command-claim guards to prevent speculative log-target substitution and self-recursion.
- **Release workflow guards** — Added checks to block mismatched release notes versions and accept direct production release approvals.
- **iOS deployment target** — Adjusted iOS minimum deployment target override in Podfile post_install (12.0 to 13.0).
- **Turn-finalization recovery** — Extracted and stabilized turn-finalization recovery logic from `chat_notifier`.

### Refactors

- **Turn-finalization extraction** — Refactored turn-finalization recovery into a dedicated module (F1).
- **Freezed regeneration** — Regenerated freezed outputs for `conversation` and `chat_state`.

### Testing

- **Release claim coverage** — Added tests to cover unexecuted production release claims.
- **File-size ratchet budgets** — Reconciled file-size ratchet budgets with current main.

### Documentation

- **LL29-31 roadmap** — Added documentation for the LL29-31 complex-task robustness roadmap track.
- **Tools MVP roadmap** — Added the Tools MVP roadmap document.
- **Session logs clarification** — Clarified that session logs record raw model output, not post-guard UI.

## Version

- `1.3.9+21`

## Notes

This release focuses on improving the observability and robustness of the tool loop (LL31), adding routine authoring capabilities, and hardening the coding harness against speculative execution and release inconsistencies.
