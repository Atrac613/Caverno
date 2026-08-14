# LL39 Model Capability Comparison

Status: implemented and deterministically verified.

## Task

- Goal: compare registered models after bounded conformance saturates without
  inventing a second weighted score.
- User-visible behavior: Live LLM Diagnostics lists models best-first within
  each comparable physical axis.
- Non-goals: producing one overall winner, combining unlike units, or comparing
  embedding margins produced by different embedding models.

## Context

- Affected components: stored model capability profiles, physical metric
  metadata, and Live LLM Diagnostics.
- Related docs: `docs/local_llm_agent_roadmap.md` LL39 and
  `docs/ll39_physical_capability_history_codex_task.md`.
- Compatibility rule: profiles without a measured axis remain absent from that
  axis rather than being ranked as zero.

## Acceptance Criteria

- Higher-is-better and lower-is-better axes sort in the correct direction.
- Equal best values remain tied.
- Invalid and missing values never enter a ranking.
- Effective context can use existing `ladder-v1` measured-token evidence during
  migration to the new physical metadata keys.
- The UI exposes each value with its physical unit and does not show an overall
  capability score.
- At least two measured models are required for an axis to be comparable.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/domain/services/model_capability_comparison_test.dart \
  --test test/features/settings/presentation/pages/live_llm_diagnostic_page_test.dart
```

The standard verifier passed project and package analysis, 19 focused Flutter
tests, package tests, and notification-relay checks.
