# LL39 Effective-Context Failure Triage

## Task

- Goal: determine why `qwen3.6-35b-a3b-vision` repeatedly misses the boundary
  markers in the first effective-context trial and preserve enough evidence to
  classify future failures without exposing the full generated prompt.
- User-visible behavior: exported benchmark artifacts distinguish response
  mismatch, missing token usage, transport failure, and terminal truncation,
  with a bounded response preview for marker failures.
- Non-goals: changing the context ladder thresholds, weakening exact grading,
  certifying the endpoint's advertised context window, or changing benchmark
  points.

## Context

- Affected components: effective-context trial evidence, the LL39 benchmark
  artifact, focused diagnostic tests, and live 35B evidence.
- Related docs: `docs/ll39_effective_context_codex_task.md`,
  `docs/live_llm_canary_agent_runbook.md`, and
  `docs/live_llm_canary_coverage.md`.
- Reference pattern: diagnostic probe results already retain bounded model
  content and machine-readable status details.
- Known quirk: two full 35B runs accepted roughly 2K prompt tokens but missed
  the boundary markers. The current artifact records only a generic mismatch,
  so it cannot distinguish an empty response, one recalled marker, extra text,
  or output truncation.

## Implementation Notes

- First run the current 2K probe three times to establish the unchanged
  baseline.
- Add a stable failure classification and bounded response preview to each
  effective-context trial. Preserve finish reason so terminal truncation is
  explicit.
- Never export the large generated prompt or API credentials.
- Keep successful trial JSON backward compatible by omitting empty diagnostic
  fields.

## Similar-Pattern Search

- Search terms: `modelContent`, `finishReason`, `failure`, `responsePreview`,
  `effectiveContextMetrics`, and `likelyBuffered`.
- Files or modules inspected: diagnostic entities and service, benchmark
  artifact writer, artifact importer, diagnostics page, and focused tests.
- Follow-up tasks found: none yet; classify the live evidence before widening
  the probe or changing its prompt.

## Acceptance Criteria

- Repeated 35B evidence records the exact failure class for every first-stage
  trial.
- Marker mismatches distinguish no markers, begin-only, end-only, both markers
  with extra text, and an otherwise different response.
- A bounded preview and finish reason are exported without retaining the large
  generated prompt.
- Missing usage and transport failures remain distinguishable.
- Existing score, suite version, ladder thresholds, and pass/fail semantics do
  not change.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/domain/entities/live_llm_diagnostic_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/tool/run_live_llm_benchmark_canary_test.dart
```

Live verification uses the managed loopback wrapper, selects only
`effective_context`, pins it as required, sets the approximate maximum to 2,048
tokens, and repeats the run three times against `qwen3.6-35b-a3b-vision`.

## Handoff Notes

- Summary: three unchanged baseline runs reproduced the 35B first-stage failure.
  The diagnostic now exports a stable failure kind, finish reason, and bounded
  response preview for each failed context trial without changing scoring or
  ladder behavior.
- Tests run: `tool/codex_verify.sh --no-codegen` with the three focused test
  files passed project and package analysis, package tests, 54 focused tests,
  and 10 notification-relay tests. A final direct focused run also passed all
  54 tests after adding the preview bound assertion.
- Live evidence: all three instrumented runs accepted 2,165 prompt tokens, used
  all 32 completion tokens, ended with `finishReason=length`, and returned only
  repeated `pad` filler. Both boundary markers were absent. The sanitized
  evidence is retained in
  `docs/evidence/ll39_35b_effective_context_triage_2026-08-14.json`.
- Coverage or low-coverage notes: response mismatches cover empty, begin-only,
  end-only, both-markers-non-exact, and unrelated outputs. Missing usage,
  request errors, finish reasons, and the 240-character preview bound are also
  covered.
- Risks or follow-ups: the result does not prove a 2K context limitation. Run a
  controlled prompt-shape A/B before changing the production ladder prompt or
  bumping its separately versioned contract. **Resolved:** the follow-up A/B in
  `docs/ll39_effective_context_prompt_shape_ab_codex_task.md` isolated ambiguous
  marker selection wording, shipped the explicit-marker prompt as `ladder-v2`,
  and measured a 16,512-token lower bound on the same 35B model.
