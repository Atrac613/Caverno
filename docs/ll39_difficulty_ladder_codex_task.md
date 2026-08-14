# LL39 Difficulty Ladder

Status: implemented and live-canary verified on 2026-08-14. The current prompt
contract is `ladder-v2`; historical `ladder-v1` evidence remains importable.

## Goal

Add separately versioned headroom above the bounded `cavernobench` conformance
score without inventing another weighted score.

## Contract

- Current suite identity: `ladder-v2`, independent from the current
  `cavernobench` version. `ladder-v1` identifies the historical ambiguous
  marker-selection prompt.
- Axis: effective-context boundary recall.
- Unit: endpoint-reported prompt tokens.
- Fixed stages: 4K, 8K, 16K, 32K, 64K, and 128K prompt tokens.
- Primary result: measured prompt-token lower bound, highest passed stage, and
  next stage. No ladder points or synthesized cross-axis score.
- Adding or changing stage thresholds requires a ladder version bump but never
  changes the conformance denominator.

## Acceptance Criteria

- Diagnostic JSON and headless canary artifacts include `difficultyLadder`
  with `suiteVersion`, physical unit, measured lower bound, and stage outcomes.
- A missing effective-context measurement exports an explicit unmeasured
  ladder instead of a zero-capability claim.
- Profile metadata and LL21 revisions persist the ladder identity and physical
  result independently from conformance history.
- Live LLM Diagnostics shows the ladder version, highest passed stage, and next
  stage when effective-context evidence exists.
- Deterministic entity, scoring, profile-builder, and widget tests pass.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/domain/services/live_llm_diagnostic_difficulty_ladder_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_scoring_test.dart \
  --test test/features/settings/domain/services/model_capability_profile_builder_test.dart \
  --test test/features/settings/domain/services/model_capability_profile_revision_test.dart \
  --test test/features/settings/presentation/pages/live_llm_diagnostic_page_test.dart
```

## Live Validation

The focused effective-context canary passed against `qwen3.6-27b-vision` with
main readiness ready. Its `benchmark_run.json` retained `cavernobench-v8` and
exported the independent `ladder-v1` block with a 16,498 prompt-token measured
lower bound, three of six stages passed, 16,384 as the highest passed stage,
and 32,768 as the next stage.

## Ladder v2 Prompt Contract

The stage thresholds and physical unit are unchanged. `ladder-v2` changes only
the marker-selection wording after a reset-controlled 35B A/B proved that
`ladder-v1`'s phrase "first and last data lines" induced filler continuation.
The explicit `CTX_BEGIN_` / `CTX_END_` wording passed 3/3 and then measured the
35B model through 16,512 prompt tokens. Existing v1 artifacts remain historical
evidence and are still accepted by the importer; new runs identify themselves
as v2 so the two prompt contracts are not silently conflated.
