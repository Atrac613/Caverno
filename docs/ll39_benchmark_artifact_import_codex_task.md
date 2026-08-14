# LL39 Benchmark Artifact Import

Status: implemented and deterministically verified.

## Task

- Goal: import a headless LL39 benchmark artifact into the matching LL21 model
  capability profile and revision history.
- User-visible behavior: Live LLM Diagnostics can select a
  `benchmark_run.json` artifact and retain its conformance and difficulty-ladder
  evidence.
- Non-goals: running the expensive effective-context probe inside the app,
  importing arbitrary settings, or synthesizing a capability score.

## Context

- Affected components: benchmark canary export, model capability profiles,
  settings persistence, and Live LLM Diagnostics.
- Related docs: `docs/local_llm_agent_roadmap.md` LL39 and
  `docs/ll39_difficulty_ladder_codex_task.md`.
- Reference pattern: `SettingsFileService` for cross-platform JSON selection and
  `SettingsNotifier.upsertModelCapabilityProfile` for revision persistence.
- Compatibility rule: a bounded run with zero attempted points is capability-only
  evidence and must not overwrite a real conformance score with zero.

## Acceptance Criteria

- Reject malformed artifacts, missing model identity, and artifacts without
  bounded or ladder evidence.
- Preserve existing categorical capability evidence when importing a focused
  ladder-only run.
- Import bounded score metadata only when at least one point was attempted.
- Import measured ladder identity, axis, unit, lower bound, and stages without a
  ladder point total.
- Refuse an artifact older than the matching stored profile so stale evidence
  cannot replace a newer run.
- Persist the imported profile through the normal LL21 revision path.
- Emit the provider in newly generated canary artifacts while accepting legacy
  artifacts that predate the field.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/domain/services/live_llm_benchmark_artifact_importer_test.dart \
  --test test/features/settings/presentation/providers/live_llm_diagnostic_notifier_test.dart \
  --test test/tool/run_live_llm_benchmark_canary_test.dart
```

The standard verifier passed with project and package analysis, 31 focused
Flutter tests, package tests, and notification-relay checks.
