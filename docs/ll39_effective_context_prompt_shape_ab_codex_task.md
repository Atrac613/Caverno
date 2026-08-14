# LL39 Effective-Context Prompt-Shape A/B

## Task

- Goal: determine whether the 35B first-stage failure comes from repetitive
  single-token filler, instruction placement, or an actual inability to recall
  the boundary markers.
- User-visible behavior: effective-context evidence should measure boundary
  recall rather than a prompt-induced filler continuation loop.
- Non-goals: changing conformance points, increasing completion length to hide
  a loop, weakening exact marker grading, or claiming an endpoint maximum.

## Context

- Affected components: effective-context prompt construction, the separately
  versioned difficulty ladder, focused tests, and live A/B evidence.
- Related docs: `docs/ll39_effective_context_failure_triage_codex_task.md` and
  `docs/ll39_effective_context_codex_task.md`.
- Reference pattern: the LL39 unified-diff prompt used a rotated 3-by-3 live A/B
  before changing a scored benchmark contract.
- Known quirk: the 35B model accepted 2,165 prompt tokens in three consecutive
  runs, then copied `pad` until the 32-token output limit without returning
  either marker.

## Experiment Arms

1. `control`: current instruction before the data and repeated `pad` filler.
2. `trailingInstruction`: the same repeated filler, with the exact reply
   instruction repeated after `END DATA`.
3. `variedFiller`: instruction remains before the data, but filler rotates
   through a fixed vocabulary of common neutral words instead of one token.
4. `explicitMarkers` follow-up: keep the control filler and placement but name
   the `CTX_BEGIN_` and `CTX_END_` prefixes instead of referring ambiguously to
   the first and last data lines.

Run three blocks and rotate arm order. Reset the target model before every arm.
Keep model preset, endpoint, target size, system prompt, temperature, completion
limit, markers, and exact grader fixed. Restore the original loaded model state
after the experiment.

## Implementation Notes

- Target only the first 2,048 approximate-token stage.
- Keep `temperature=0` and `max_tokens=32` so an arm cannot pass merely because
  it receives a larger output budget.
- Record endpoint-reported prompt/completion usage, content, finish reason,
  marker presence, and elapsed time for every arm.
- Do not emit an importable `benchmark_run.json` for experimental candidates.
- If the production prompt changes, bump only the difficulty-ladder version;
  the zero-point effective-context probe does not change `cavernobench-v9`.

## Similar-Pattern Search

- Search terms: `ll39_edit_prompt`, `cold_path_ab`, `warmupMode`,
  `effective_context`, and `LiveLlmDiagnosticDifficultyLadder.version`.
- Files or modules inspected: the effective-context probe and ladder, LL39
  cold-path runner, benchmark canary artifact writer, and prior v9 A/B evidence.
- Follow-up tasks found: none yet; choose the production prompt only after the
  three-arm result is mechanically clear.

## Acceptance Criteria

- Every arm has three reset-controlled observations.
- The control reproduces the known filler loop or the result is declared
  inconclusive.
- A candidate must pass exact marker grading in all three runs before it can
  replace the production prompt.
- Candidate prompt-token usage remains close enough to the control to test the
  same first-stage range and is always reported rather than assumed.
- A production prompt change bumps `ladder-v1` to `ladder-v2`, preserves
  `cavernobench-v9`, and invalidates no bounded score history.
- Sanitized evidence contains no API key or generated long prompt.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_difficulty_ladder_test.dart \
  --test test/tool/run_live_llm_benchmark_canary_test.dart
```

After deterministic verification, rerun the selected production prompt three
times through `tool/with_live_llm_loopback.sh` with only `effective_context`
selected and required.

## Handoff Notes

- Summary: control, trailing-instruction, and varied-filler arms all failed 0/3
  with length-limited filler continuation. The explicit-marker candidate passed
  3/3, so production now names both marker prefixes and exports `ladder-v2`.
  `cavernobench-v9`, marker values, exact grading, filler, temperature, and
  completion limit remain unchanged.
- Tests run: `tool/codex_verify.sh --no-codegen` passed project and package
  analysis, package tests, 89 focused tests, and 10 notification-relay tests.
- Live evidence: the production-path 2K canary passed 3/3 with 2,174 prompt
  tokens, 16 completion tokens, and `finishReason=stop`. A subsequent 32K
  ceiling run passed through 16,512 reported prompt tokens, then the endpoint
  rejected the 32K trial because 32,896 prompt tokens exceeded its 32,768-token
  context. Sanitized evidence is in
  `docs/evidence/ll39_effective_context_prompt_ab_2026-08-14.json`.
- Risks or follow-ups: `ladder-v1` context measurements remain historical and
  are not silently compared as the current prompt contract. The 35B evidence
  now supports the 16K stage and identifies 32K as the next stage.
