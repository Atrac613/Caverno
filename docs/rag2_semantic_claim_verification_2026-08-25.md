# RAG2 Semantic Claim Verification — 2026-08-25

## Decision

The deterministic semantic support verifier clears the existing seed and both
holdout gates, but production remains `no_go`. The verifier was designed after
inspecting the four structured-envelope residuals, so the same 36 claims are a
regression closure set rather than independent promotion evidence.

## Frozen inputs and execution order

This experiment keeps the following inputs unchanged:

- 36 claim texts and expected three-class verdicts
- claim scope and cited source IDs
- corpus contents and hashes
- trigram retrieval and sufficiency policy
- lexical support threshold `0.90` and contradiction threshold `0.50`
- authority and revision checks

Citation presence, retrieval, authority, and revision validation run first.
Only citations that pass those checks reach
`deterministic-atomic-facts-v1`. The verifier adds three bounded semantic
normalizations:

- camelCase identifiers and the `initial`/`default`,
  `iteration`/`limit` relations used by terse configuration code
- an explicit `port` relation for numeric ports in HTTP URLs
- boolean polarity for `enabled`, `disabled`, and their direct negations

Relations that are not resolved by these rules retain the frozen lexical
verdict. If the semantic verifier is unavailable, every structurally valid
claim fails closed as `absent`; structural failures remain closed at their
earlier reason.

## Results

| Dataset | Structured macro F1 | Semantic macro F1 | Supported F1 | Contradicted F1 | Absent F1 | Gate |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Seed | 0.838 | 1.000 | 1.000 | 1.000 | 1.000 | pass |
| Lexical holdout | 0.915 | 1.000 | 1.000 | 1.000 | 1.000 | pass |
| Runtime adversarial | 0.915 | 1.000 | 1.000 | 1.000 | 1.000 | pass |

All four prior residuals are corrected:

- code constants support the matching natural-language value and contradict a
  mismatched value;
- an endpoint URL supports its explicit port claim;
- `not disabled` contradicts a `disabled` claim.

The unavailable-verifier regression confirms that 24 structurally valid claims
close as `semantic_verifier_unavailable`. The other 12 claims already close at
the citation boundary, and all 36 predictions remain `absent`.

## Reproduction

```bash
fvm dart run tool/rag2_semantic_claim_eval.dart \
  --claims tool/fixtures/rag2_claim_verification/candidates.json \
  --envelopes tool/fixtures/rag2_claim_verification/claim_envelopes.json \
  --authority tool/fixtures/rag2_claim_verification/evidence_authority.json \
  --seed-fixture tool/fixtures/rag_retrieval_eval/fixture.json \
  --holdout-fixture tool/fixtures/rag2_lexical_holdout/fixture.json \
  --audit-fixture tool/fixtures/rag2_runtime_adversarial/fixture.json \
  --out-dir build/integration_test_reports/rag2_semantic_claim
```

## Next entry condition

Freeze `deterministic-atomic-facts-v1` and the current 36-claim suite. Before
any production migration, evaluate a new blinded semantic holdout that was not
used to design these rules. It must include positive and negative controls for
code-to-prose aliases, URLs with unrelated numbers or no explicit port,
double-negation and modality, and topically similar absent claims. Report the
same three-class metrics and fail-closed availability result. Do not add model
calls, embeddings, production storage, routing, prompt injection, or agent-kb
federation in that slice.

Blinded-holdout follow-up:
`docs/rag2_blinded_semantic_holdout_2026-08-25.md` freezes verifier v1 and adds
12 independent controls. Macro-F1 falls to 0.672 on double negation,
relation-unbound numbers, denied port assignment, and modality. This confirms
the existing 1.000 result is regression closure rather than promotion evidence.
