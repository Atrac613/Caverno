# Caverno v1.3.7

> Release date: 2026-06-16

## Summary

LL16 recovery path, LL17/LL18/LL19/LL21 feature implementations, and idle maintenance pipeline improvements.

## Changes

### Features

- **LL16 recovery path for runtime temperature step-downs** — Added a recovery path that handles runtime temperature step-downs gracefully, preventing performance degradation during thermal events. (`chat_notifier.dart`, `chat_state.dart`)
- **LL17 eval-gated auto-adopt for harness proposals** — Implemented evaluation-gated auto-adoption for LL17 harness proposals, ensuring only validated proposals are automatically adopted. (`eval_harness_notifier.dart`)
- **LL18 idle/overnight maintenance orchestrator** — Added an idle/overnight maintenance orchestrator for LL18, enabling background maintenance tasks during idle periods. (`idle_maintenance_service.dart`)
- **LL18 idle-maintenance gate policy** — Implemented gate policy for LL18 idle maintenance, controlling when and how maintenance tasks are executed. (`idle_maintenance_policy.dart`)
- **LL19 one-tap bake-off (candidate vs incumbent)** — Added a one-tap bake-off feature for LL19, allowing direct comparison between candidate and incumbent implementations. (`bake_off_service.dart`)
- **LL19 replay through the real tool loop** — Wired LL19 replay through the real tool loop for more accurate evaluation. (`replay_executor.dart`)
- **LL19 live personal eval replay executor** — Added a live personal eval replay executor for LL19, enabling real-time replay of evaluation cases. (`eval_replay_executor.dart`)
- **LL19 record-eval-case page** — Added a dedicated page for recording evaluation cases in LL19. (`record_eval_case_page.dart`)
- **LL21 profile revision history and model-swap detection** — Implemented profile revision history tracking and model-swap detection for LL21. (`profile_history_service.dart`)
- **LL21 profile history section in live LLM diagnostic page** — Added a profile history section to the live LLM diagnostic page for LL21. (`llm_diagnostics_page.dart`)
- **Manual debug runner for idle maintenance pipeline** — Added a manual debug runner for the idle maintenance pipeline, allowing on-demand execution of maintenance tasks. (`idle_maintenance_debug_runner.dart`)

### Documentation

- **LL21 profile history UI implementation** — Recorded LL21 profile history UI implementation details.
- **LL16 recovery path implementation** — Documented LL16 recovery path implementation in the LL21 section.
- **LL17/LL18/LL19 done markers** — Marked LL17, LL18, and LL19 as done with full implementation evidence.

## Version

- `1.3.7+19`

## Notes

This release focuses on the LL16-LL21 feature implementations, including recovery paths, maintenance orchestration, evaluation replay, and profile history tracking.
