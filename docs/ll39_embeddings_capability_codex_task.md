# LL39 Embeddings Capability Probe

Status: implemented and live-canary verified on 2026-08-14.

## Task

- Goal: make the LL5 embeddings fallback observable and measure the configured
  embedding model in stable physical units.
- User-visible behavior: Live LLM Diagnostics reports request time, returned
  vector count, vector dimension, model identity, and semantic separation.
- Non-goals: endpoint protocol certification, selecting or loading a model,
  mutating semantic-search data, effective-context probing, or reranking.

## Context

- Production path: `EmbeddingsClient.embed()` posts multiple inputs to
  `/v1/embeddings` and returns `null` so LL5 can fall back to lexical FTS.
- Boundary: COMPAT1 owns why a request was rejected; LL39 owns whether returned
  vectors are structurally usable and semantically separate a paraphrase from
  unrelated text.

## Implementation Notes

- Reuse `EmbeddingsClient`; do not add a second HTTP protocol implementation.
- Send three fixed English sentences in one request: an anchor, a paraphrase,
  and an unrelated control.
- Require three finite, non-zero, equal-width vectors.
- Pass semantic fidelity only when the paraphrase cosine exceeds the unrelated
  cosine by at least 0.05.
- Skip without penalty when no embeddings model is configured or the selected
  provider is Apple Foundation Models.
- Keep all measurements outside synthetic capability totals while retaining a
  bounded conformance contribution in `cavernobench`.

## Acceptance Criteria

- Successful results export dimension, latency, vector count, model, both
  cosine values, and their margin.
- Structurally invalid and semantically weak results are distinguishable.
- The headless canary can opt in through `CAVERNO_EMBEDDINGS_MODEL`.
- No vectors are stored and semantic-search indexes are not mutated.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/domain/entities/live_llm_diagnostic_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_scoring_test.dart \
  --test test/features/settings/domain/services/live_llm_diagnostic_service_test.dart \
  --test test/features/settings/presentation/pages/live_llm_diagnostic_page_test.dart \
  --test test/tool/run_live_llm_benchmark_canary_test.dart
```

The focused suite passed with 57 tests. The standard repository verification
is recorded in the implementation commit handoff.

Live validation against `http://192.168.100.241:1234/v1` used
`qwen3-embedding-0.6b` for both v8 chat-model runs. Each request returned three
finite 1,024-dimensional vectors. The semantic margins were 0.534215 and
0.534107, both above the required 0.05 threshold. No vectors were persisted.
