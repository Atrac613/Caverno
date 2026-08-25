# RAG2 Claim-Support Oracle — 2026-08-25

## Decision

RAG2 remains `later` and production retrieval remains unchanged. The new
oracle-only diagnostic separates retrieval relevance from complete support for
the expected answer claims, but it is not a runtime answerability policy.

## Method

The evaluator applies the previously frozen trigram retrieval policy unchanged:

- minimum document coverage: `0.25`
- minimum best-segment coverage: `0.25`
- minimum BM25 relative margin: `0.10`

For answerable cases, fixture citation qrels define the passages required to
support the answer key. A case is `supported` only when every expected citation
is returned, `partial` when only part of the citation set is returned, and
`absent` when none is returned. No-answer cases have no expected claims; a
returned passage is reported separately as `topicalButInsufficient`.

This is intentionally an oracle metric. The answer keys and qrels do not exist
at runtime, so the result cannot be promoted into a production abstention rule.

## Results

| Dataset | Retrieval relevant | Fully supported | Partial | Absent | Topical but insufficient |
| --- | ---: | ---: | ---: | ---: | ---: |
| Seed | 15/16 | 14/16 | 1 | 1 | 2/4 |
| Frozen holdout | 15/16 | 15/16 | 0 | 1 | 2/4 |

The seed conflict case `conflict-loop-limit` returned only the historical
eight-iteration passage. It counted as retrieval-relevant under qrels but did
not cover the current twelve-iteration citation, so its support verdict is
`partial`. `conflict-storage` and holdout `holdout-conflict-mcp` remained
`absent` because the frozen retrieval policy returned no evidence.

The no-answer password and execute-instructions cases still retrieved topical
safety policy passages in both datasets. The oracle correctly records that
those passages contain no expected answer claim, but this does not solve the
runtime decision because that classification depends on fixture knowledge.

## Reproduction

```bash
fvm dart run tool/rag2_claim_support_eval.dart \
  --seed-fixture tool/fixtures/rag_retrieval_eval/fixture.json \
  --holdout-fixture tool/fixtures/rag2_lexical_holdout/fixture.json \
  --out-dir build/integration_test_reports/rag2_claim_support
```

Generated artifacts:
`build/integration_test_reports/rag2_claim_support/`.

## Next entry condition

Do not treat oracle citation coverage as a runtime classifier. The next RAG2
experiment must evaluate a runtime-available answerability signal against these
oracle labels, report precision and recall for `supported` versus
`topicalButInsufficient`, and keep the frozen retrieval policy and holdout
unchanged. Production storage, prompt injection, embeddings, a second router,
and agent-kb federation remain out of scope.

Follow-up evidence: `docs/rag2_runtime_answerability_signal_2026-08-25.md`
evaluates a query-and-passage-only signal against these oracle labels. Its
synthetic gate passes, but the inspected corpus does not authorize production.
