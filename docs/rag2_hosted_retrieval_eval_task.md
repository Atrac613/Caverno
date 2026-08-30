# RAG2 Hosted Retrieval Evaluation Task

## Task

- Goal: evaluate one frozen lexical retrieval candidate through the real
  AppDatabase-hosted RAG2 FTS5 slot before any production retrieval work.
- User-visible behavior: none. This is an offline evidence slice.
- Non-goals: production indexing, prompt injection, `search_knowledge`, model
  calls, vector retrieval, routing, settings, UI, and agent-kb federation.

## Context

- Affected components: the RAG1 fixture/evaluator, the RAG2 Drift generation
  store, the AppDatabase-hosted `rag2_chunk_search` slot, and tool-only reports.
- Related docs: `docs/rag1_completion_audit_2026-08-25.md`,
  `docs/rag2_investigation_handoff_2026-08-25.md`, and
  `docs/rag2_fts5_hosted_query_projection_hypothesis_2026-08-27.md`.
- Reference pattern: tool-level RAG2 replay programs with deterministic JSON
  and Markdown output plus focused Flutter tests.
- Release gate: RAG2 remains No-Go unless the frozen candidate clears every
  gate below. A failed evaluation is a valid completed result.

## Implementation Notes

- Build one deterministic RAG2 generation from the frozen RAG1 mini-repository.
  Preserve one object and one chunk per fixture document so the existing qrels
  remain reviewable without rewriting the RAG1 fixture.
- Apply and index the generation through `Rag2DriftDaoGenerationStore` with
  `indexSearch: true`.
- Evaluate the already-frozen `trigram_or_idf` candidate at threshold `0.15`.
  Query the hosted FTS5 table with OR terms and BM25 order, compute IDF-weighted
  segment coverage from the committed generation payload, and discard hits
  below the threshold.
- Project every retained hit back onto the same committed generation envelope.
  Unknown, duplicate, mismatched, or cross-identity rows fail closed.
- Feed the resulting lexical rankings into the existing RAG1 evaluator together
  with `NONE`, `FULL`, unavailable optional arms, and the mandatory empty
  negative control.
- Keep retrieval relevance separate from semantic answerability. This slice
  measures retrieval only and must not invent answer or citation scores.

## Constraints

- Do not change the RAG1 fixture, corpus hash, metric policy, or qrels.
- Do not tune the candidate after reading evaluation results.
- Do not weaken the earlier candidate gate from at most one no-answer retrieval.
- Do not change AppDatabase schema version 5, the frozen hosted query/projection
  APIs, LL5 conversation search, or existing embedding rows.
- Reports must omit source text, absolute paths, stored terms, and secret-like
  content. Case IDs and repository-relative fixture object IDs are allowed
  because they are already part of the committed RAG1 evaluation contract.

## Acceptance Criteria

- The RAG1 fixture identity remains `rag1-seed-v1` with the committed corpus
  hash and 20 cases.
- The candidate is evaluated through an actual file-backed AppDatabase RAG2
  generation and hosted FTS5 slot.
- The report records answerable hits, Japanese hits, no-answer retrievals,
  object MRR/nDCG, context-token estimate, provenance validation, and the RAG1
  negative-control result.
- Promotion requires all of the following:
  - at least 15 of 16 answerable cases hit at K=5;
  - all 4 Japanese cases hit;
  - at most 1 of 4 no-answer cases return evidence;
  - every retained hit matches the committed generation and remains inside the
    selected project/declaration identity;
  - the existing RAG1 empty negative control is detected.
- Any unmet or unverifiable requirement produces an explicit No-Go without
  changing production behavior.

## Verification

```bash
tool/codex_verify.sh --test test/tool/rag2_hosted_retrieval_eval_test.dart
fvm flutter test test/tool/rag_retrieval_eval_test.dart
fvm dart run tool/rag2_hosted_retrieval_eval.dart \
  --fixture tool/fixtures/rag_retrieval_eval/fixture.json \
  --out-dir build/integration_test_reports/rag2_hosted_retrieval_eval
```

## Handoff Notes

- Update the canonical RAG2 handoff and both roadmaps with the measured result.
- Preserve the generated report as reproducible build evidence; record the
  aggregate decision in committed documentation.
- Do not advance RAG3 or add production retrieval on a No-Go.
