# RAG2 Hosted Retrieval Evaluation — 2026-08-30

## Decision

The AppDatabase-hosted evaluation contract is Go, but the frozen lexical
candidate is No-Go. Production retrieval, prompt injection, `search_knowledge`,
and RAG3 remain No-Go.

The actual file-backed AppDatabase path reproduced the earlier in-memory
candidate result: `trigram_or_idf` at threshold `0.15` retrieved all 16
answerable cases and all four Japanese cases, but it also returned evidence for
2 of 4 no-answer cases. The predeclared gate allows at most 1 of 4. Do not
weaken that gate or tune the candidate from this result.

## Reproduction Identity

- Contract: `rag2-hosted-retrieval-eval-contract-v1`
- Fixture: `rag1-seed-v1`
- Metric policy: `v1`, K = 5
- Corpus SHA-256:
  `4adb4bc8013b8893f67295305ac451aa00c54f1eaa4732fff2fd4199d119f57b`
- Clean implementation commit:
  `c6a36ae97f38e5e9268a45c70c9bf2d7765f9e85`
- Candidate: `trigram_or_idf`
- Threshold: `0.15`
- AppDatabase schema version: `5`
- Generated reports:
  `build/integration_test_reports/rag2_hosted_retrieval_eval/`
  (ignored build artifacts)

The snapshot uses the canonical RAG1 fixture loader before creating one
Knowledge Object and one Chunk per fixture document. This matters for the JSON
fixture: decoded JSON string values, not raw Unicode escape sequences, are the
RAG1 corpus content.

## Measured Result

| Gate | Result | Required | Decision |
| --- | ---: | ---: | --- |
| Answerable hits | 16/16 | at least 15/16 | pass |
| Japanese hits | 4/4 | 4/4 | pass |
| No-answer retrieved | 2/4 | at most 1/4 | **fail** |
| Provenance validation | true | true | pass |
| Empty negative control | true | true | pass |
| Existing host preserved | true | true | pass |

Additional retrieval measurements:

- object MRR@5: `0.8958333333333333`
- object nDCG@5: `0.8992653583060998`
- estimated retrieved context: `5,424` tokens across 20 cases
- RAG1 `FULL` reference: 14/16 answerable, 4/4 no-answer, 10,520 context
  tokens

The candidate improves answerable retrieval and context size over `FULL`, but
the independent no-answer gate is conjunctive and remains unmet. Answer and
citation quality were not measured in this slice and must not be inferred from
retrieval metrics.

## Boundary Evidence

- The evaluator creates the RAG2 generation through
  `Rag2DriftDaoGenerationStore.apply(..., indexSearch: true)`.
- Ranked OR queries execute against the hosted `rag2_chunk_search` table and
  bind project identity, declaration identity, generation, and snapshot hash.
- Retained rows are checked against the same committed generation payload.
  Unknown, duplicate, object-mismatched, term-mismatched, or cross-identity
  evidence fails closed.
- Reports contain aggregate results, case IDs, and the committed RAG1
  repository-relative qrel identities, but no source text, stored terms,
  absolute roots, or query text.
- Existing conversation-search and LL5 embedding rows remain present, and the
  AppDatabase schema version remains 5.

## Verification

```bash
fvm flutter test test/tool/rag2_hosted_retrieval_eval_test.dart
fvm dart analyze tool/rag2_hosted_retrieval_eval.dart \
  test/tool/rag2_hosted_retrieval_eval_test.dart
fvm dart run tool/rag2_hosted_retrieval_eval.dart \
  --fixture tool/fixtures/rag_retrieval_eval/fixture.json \
  --out-dir build/integration_test_reports/rag2_hosted_retrieval_eval
```

The focused evaluator suite passes five tests. The clean evaluation command
completed successfully and recorded `candidateDecision: no_go`.

## Next Entry Condition

Freeze this candidate and result. Do not add another lexical threshold or
intent-keyword patch from the two no-answer failures. Any resumed RAG2
retrieval work must predeclare a different answerability hypothesis and a new
untouched holdout, while keeping retrieval relevance and semantic
answerability separate. Storage, settings, tools, prompts, and RAG3 wiring must
remain unchanged until that independent gate passes.
