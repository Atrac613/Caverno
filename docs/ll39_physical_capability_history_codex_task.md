# LL39 Physical Capability History

Status: implemented and deterministically verified.

## Task

- Goal: retain LL39 physical capability measurements in model profiles and LL21
  revisions so saturated conformance models remain comparable over time.
- User-visible behavior: stored revisions retain the measured TTFT, decode rate,
  tool-loop cost, embedding evidence, and effective-context evidence from each
  diagnostic run.
- Non-goals: combining unlike units into a weighted score or declaring a total
  winner when physical axes disagree.

## Context

- Affected components: `ModelCapabilityProfileBuilder`, benchmark artifact
  import, `ModelCapabilityProfileRevision`, and profile history UI.
- Related docs: `docs/local_llm_agent_roadmap.md` LL39.
- Compatibility rule: revision JSON predating this slice must decode with an
  empty metrics map.

## Acceptance Criteria

- Store physical measurements with units encoded in stable metadata keys.
- Omit decode throughput when delivery was buffered and the diagnostic could
  not measure it honestly.
- Carry the metrics into every LL21 revision without changing the bounded
  conformance denominator.
- Import the same metrics from a headless benchmark artifact.
- Preserve old revision JSON compatibility.
- Show stored physical values independently from bounded score history.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/domain/services/model_capability_physical_metrics_test.dart \
  --test test/features/settings/domain/services/model_capability_profile_builder_test.dart \
  --test test/features/settings/domain/services/model_capability_profile_revision_test.dart \
  --test test/features/settings/domain/services/live_llm_benchmark_artifact_importer_test.dart \
  --test test/features/settings/presentation/pages/live_llm_diagnostic_page_test.dart
```

The standard verifier passed project and package analysis, 50 focused Flutter
tests, package tests, and notification-relay checks.
