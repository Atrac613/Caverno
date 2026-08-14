# LL39 Saturation Watchdog

Status: implemented and verified through live evidence plus the artifact-import
UI integration on 2026-08-14.

## Goal

Make `cavernobench` declare when its bounded conformance score has stopped
discriminating across the user's registered models, without adding another
invented ranking score.

## Scope

- Add an explicit 95% high-water signal to every benchmark export.
- Evaluate the current score stored on every unique registered model profile.
- Declare saturation only when at least two registered models have comparable
  scores from the current suite and every one clears the high-water mark.
- Fail closed when a model is unmeasured, belongs to another suite version, or
  carries a different denominator.
- Surface the declaration on the Live LLM Diagnostics page and preserve the
  physical capability tier as the recommended comparison path.

## Acceptance Criteria

- One high-scoring model never declares suite saturation.
- Two or more fully measured current-suite models at or above 95% do declare
  saturation.
- Missing or out-of-range scores, stale suite versions, mismatched
  denominators, or one model below 95% suppress the declaration.
- Copied reports and headless benchmark artifacts expose the current run's
  high-water threshold and outcome.
- Focused service, scoring, and widget tests pass through the standard Codex
  verification entrypoint.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/domain/services/live_llm_benchmark_artifact_importer_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_scoring_test.dart \
  --test test/features/settings/domain/services/model_benchmark_saturation_watchdog_test.dart \
  --test test/features/settings/presentation/providers/live_llm_diagnostic_notifier_test.dart \
  --test test/features/settings/presentation/pages/live_llm_diagnostic_page_test.dart
```

The initial 2026-08-14 v8 comparison produced one 965/1000 high-water run and
one 730/1000 run. After correcting the 35B server's GPU allocation parameters,
the same full v8 run completed without CUDA OOM or transport failure and
improved to 947/1000. Those current artifacts still do not satisfy the
watchdog's all-model high-water precondition. A positive two-model v8
saturation declaration and an end-to-end UI check remain pending a second
model that clears 950 points. The edit-format prompt correction subsequently
bumped the current suite to v9. Full v9 reruns then produced 965/1000 for both
`qwen3.6-27b-vision` and `qwen3.6-35b-a3b-vision`, with the same 1,000-point
denominator and `saturationHighWaterReached: true`. These artifacts satisfy the
watchdog's positive multi-model input contract. A widget integration test now
drives the page import action twice with those v9 model identities and scores,
verifies that one profile still fails closed, persists two distinct
`benchmark_artifact` revisions, and confirms the rendered saturation
declaration after the second import. The native OS file picker remains outside
the automated boundary; artifact parsing, notifier persistence, watchdog
evaluation, and page rendering are covered together.

The standard verifier passed project and package analysis, 31 focused Flutter
tests, package tests, and notification-relay checks.

Artifacts:

- `build/integration_test_reports/ll39_v9_27b_vision_1786671470/benchmark_run.json`
- `build/integration_test_reports/ll39_v9_35b_a3b_vision_1786671349/benchmark_run.json`
