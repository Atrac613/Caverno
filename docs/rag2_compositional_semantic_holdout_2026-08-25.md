# RAG2 Compositional Semantic Holdout — 2026-08-25

## Decision

Both frozen semantic verifiers fail the second independent holdout. Verifier
v1 scores macro-F1 `0.154`; relation-aware verifier v2 improves to `0.328` but
remains far below the `0.90` gate. RAG2 and production claim verification stay
`no_go`.

Neither verifier nor the existing 48 claims changed for this audit. The new
holdout contains 12 balanced claims and has corpus SHA-256
`c120cb7970ccd7277618915fca9502b0a70fe154fe75c44e0e2199cbb185a8e4`.

## Controls

The holdout composes relation types that the earlier suites tested separately:

- multiple explicit URIs and ports in one passage;
- standard HTTPS default port without an explicit numeric component;
- proxy and API host-port pairs in one sentence;
- default and fallback non-numeric code assignments;
- two scoped feature states in one sentence;
- conditional, modal, and normative state statements;
- topically related owner text without an owner value.

One retrieval question was clarified before final scoring so its cited endpoint
document passed the frozen retrieval gate. Claim text, expected labels, corpus,
and both verifiers remained unchanged, leaving the final errors at the semantic
layer.

## Results

| Verifier | Macro F1 | Supported F1 | Contradicted F1 | Absent F1 | Gate |
| --- | ---: | ---: | ---: | ---: | --- |
| `deterministic-atomic-facts-v1` | 0.154 | 0.462 | 0.000 | 0.000 | fail |
| `relation-aware-atomic-facts-v2` | 0.328 | 0.400 | 0.250 | 0.333 | fail |

V2 fails eight of 12 claims:

- API port support is bound to the proxy URI in the same sentence.
- Standard HTTPS port `443` is treated as absent because it is implicit.
- Default `json` and fallback `yaml` assignments are collapsed by lexical
  fallback, producing false support for the default-`yaml` claim.
- Preview state is taken from the staging clause in the same sentence.
- A production state qualified by `unless` is promoted to asserted support.
- The normative phrase `must not be disabled` is treated as actual enabled
  state.
- The topically similar admin-owner claim is treated as contradiction instead
  of absence.
- The default worker mode is confused with the fallback mode.

These failures show that sentence-level token overlap is not a sufficient
relation boundary. Adding more aliases or modal keywords is closed.

## Reproduction

```bash
fvm dart run tool/rag2_compositional_holdout_eval.dart \
  --claims tool/fixtures/rag2_compositional_holdout/claims.json \
  --envelopes tool/fixtures/rag2_compositional_holdout/envelopes.json \
  --authority tool/fixtures/rag2_compositional_holdout/authority.json \
  --fixture tool/fixtures/rag2_compositional_holdout/fixture.json \
  --out-dir build/integration_test_reports/rag2_compositional_holdout
```

## Next entry condition

Freeze both verifiers and all 60 claims. Do not implement verifier v3 by adding
regexes or aliases. The next offline slice must define a storage-independent,
versioned evidence-fact contract with explicit subject, relation, typed value,
scope, polarity, modality, source span, and provenance. Populate oracle facts
for this 12-claim holdout and measure matcher upper-bound accuracy separately
from fact extraction. Continue only if the oracle matcher reaches the existing
three-class gate without changing claims or labels. No production model call,
embeddings, storage migration, router, prompt injection, or agent-kb federation
is authorized.

## Typed-fact oracle follow-up

The versioned typed claim and evidence-fact contract was evaluated without
changing this holdout. Its source-bounded oracle matcher scores macro-F1
`1.000`, with all three class F1 scores at `1.000`. This passes the matcher
upper-bound gate but does not change the production decision: extraction is
`not_evaluated`, and RAG2 remains `no_go`. The next slice must freeze this
matcher and measure candidate-independent fact extraction by source family.
Evidence: `docs/rag2_typed_fact_oracle_2026-08-25.md`.
