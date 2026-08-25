# RAG2 Blinded Semantic Holdout — 2026-08-25

## Decision

The frozen `deterministic-atomic-facts-v1` verifier fails the independent
semantic holdout. Macro-F1 is `0.672`, below the `0.90` gate, so RAG2 and
production claim verification remain `no_go`.

The verifier implementation and the original 36 claims were not changed for
this audit. The new holdout is a separate versioned dataset with 12 balanced
claims and a corpus SHA-256 of
`0314447ba24a5ae2fad63ec65602fee1804f4ea673bfe52d4f2ea38d6d97bac4`.

## Controls

The holdout covers:

- terse camelCase configuration constants with matching and mismatched values;
- URL ports alongside unrelated numbers and URLs without explicit ports;
- direct and double negation;
- modal statements that do not establish current state;
- topically similar owner claims that remain absent.

Claims, envelopes, authority metadata, and expected labels live under
`tool/fixtures/rag2_semantic_holdout/`. The retrieval question for the endpoint
case was clarified before scoring so the cited document passed the frozen
retrieval gate; claim text, labels, corpus content, and verifier stayed fixed.
This keeps the reported failures at the semantic layer.

## Results

| Macro F1 | Supported F1 | Contradicted F1 | Absent F1 | Gate |
| ---: | ---: | ---: | ---: | --- |
| 0.672 | 0.600 | 0.750 | 0.667 | fail |

Four of 12 claims fail:

- `semantic-supported-double-negative`: `not not enabled` is reduced to the
  wrong boolean polarity.
- `semantic-contradicted-unrelated-number`: dashboard build number `8081` is
  incorrectly attached to the dashboard port relation instead of being
  contradicted by explicit port `7443`.
- `semantic-absent-unassigned-port`: a separately mentioned port `9443` is
  incorrectly attached to a callback URL that has no explicit port, despite an
  explicit denial of that assignment.
- `semantic-absent-modal-state`: `may be disabled` is promoted into an asserted
  current disabled state.

The original 36-claim suite remains at macro-F1 `1.000`; this holdout proves
that result was residual-specific and insufficient for promotion.

## Reproduction

```bash
fvm dart run tool/rag2_semantic_holdout_eval.dart \
  --claims tool/fixtures/rag2_semantic_holdout/claims.json \
  --envelopes tool/fixtures/rag2_semantic_holdout/envelopes.json \
  --authority tool/fixtures/rag2_semantic_holdout/authority.json \
  --fixture tool/fixtures/rag2_semantic_holdout/fixture.json \
  --out-dir build/integration_test_reports/rag2_semantic_holdout
```

## Next entry condition

Freeze this holdout and verifier v1. The next offline experiment may compare
one relation-aware atomic-fact verifier v2 against v1, but must not patch
candidate IDs or individual expected labels. V2 must bind values to subjects
within explicit code assignments and URL components, represent boolean parity,
and treat modality or denied assignment as `absent`. It must run unchanged on
the original 36 claims and this holdout, report per-suite three-class metrics,
and fail closed when unavailable. No production model call, embeddings,
storage migration, router, prompt injection, or agent-kb federation is
authorized.

Relation-aware follow-up:
`docs/rag2_relation_aware_claim_verification_2026-08-25.md` compares one v2
against frozen v1. V2 retains macro-F1 1.000 on the original 36 claims and
raises this holdout from 0.672 to 1.000. Production remains No-Go because this
holdout informed v2; a second independent compositional holdout is required.
