# RAG2 Structured Claim Envelopes — 2026-08-25

## Decision

Structured claim envelopes pass both holdouts but miss the seed gate. The
overall result remains `no_go`, RAG2 stays `later`, and production behavior is
unchanged.

## Frozen contract

Each of the existing 36 candidate claims now has exactly one fixed envelope:

- envelope set: `rag2-claim-envelopes-v1`
- envelope SHA-256:
  `f490d55fdd13cfc75315cbd466c1106ca6b36c626c2e16bd434f915bf28d2e46`
- explicit scope: `current`, `historical`, or `unspecified`
- explicit cited source IDs
- unchanged claim text, expected verdict, corpus hashes, retrieval policy, and
  lexical verifier thresholds

Verification fails closed as `absent` before semantic scoring when citations
are missing, a cited source was not retrieved, citation authority conflicts
with claim scope, or a cited revision is superseded by a newer retrieved source
of the same authority. Only cited passages that clear those checks reach the
frozen support `0.90` / contradiction `0.50` verifier.

## Results

| Dataset | Macro F1 | Supported F1 | Contradicted F1 | Absent F1 | Gate |
| --- | ---: | ---: | ---: | ---: | --- |
| Seed | 0.838 | 0.857 | 0.857 | 0.800 | fail |
| Lexical holdout | 0.915 | 0.857 | 0.889 | 1.000 | pass |
| Runtime adversarial | 0.915 | 0.889 | 0.857 | 1.000 | pass |

Compared with prose-inferred authority, structured envelopes remove all absent
false positives and recover historical claims whose scope was implicit. The
two holdouts clear the macro-F1 `0.90` gate.

## Residual errors

- `seed-supported-loop`: terse source code
  `defaultToolLoopIterations = 12` does not reach lexical support for the
  natural-language claim.
- `seed-contradicted-loop`: the same code-to-prose mismatch prevents a numeric
  contradiction verdict.
- `holdout-supported-mcp`: the cited configuration expresses the endpoint as a
  URL, leaving the natural-language port claim below support coverage.
- `audit-contradicted-safe-mode`: lexical overlap treats `not disabled` as
  support for `disabled`, demonstrating unresolved semantic polarity.

Citation, scope, and revision failures are now separated from passage-level
semantic failures. The remaining gap is not another retrieval threshold or
authority selector.

## Reproduction

```bash
fvm dart run tool/rag2_structured_claim_eval.dart \
  --claims tool/fixtures/rag2_claim_verification/candidates.json \
  --envelopes tool/fixtures/rag2_claim_verification/claim_envelopes.json \
  --authority tool/fixtures/rag2_claim_verification/evidence_authority.json \
  --seed-fixture tool/fixtures/rag_retrieval_eval/fixture.json \
  --holdout-fixture tool/fixtures/rag2_lexical_holdout/fixture.json \
  --audit-fixture tool/fixtures/rag2_runtime_adversarial/fixture.json \
  --out-dir build/integration_test_reports/rag2_structured_claim
```

## Next entry condition

Do not change envelopes, retrieval, or lexical thresholds. The next offline
experiment must apply a semantic support verifier only after citation, scope,
and revision checks pass. It must handle code-to-prose facts, URL-to-port
claims, and negation polarity, report the same three-class metrics for the same
36 envelopes, and fail closed when the semantic verifier is unavailable. No
production model call, migration, router, prompt injection, embeddings, or
agent-kb federation is authorized.

Semantic-verifier follow-up:
`docs/rag2_semantic_claim_verification_2026-08-25.md` closes all four residuals
and reaches macro-F1 1.000 on the three existing datasets. Production remains
No-Go because those residuals informed the verifier design; an independent
blinded semantic holdout is required before promotion.
