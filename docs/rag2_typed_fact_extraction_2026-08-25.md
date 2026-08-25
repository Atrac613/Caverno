# RAG2 Typed Fact Extraction — 2026-08-25

## Decision

Deterministic extraction passes the development fixture for Dart constant
assignments and Markdown URI ports, but fails the complete source-family gate.
Overall exact fact precision is `1.000`, recall is `0.643`, and F1 is `0.783`.
Extraction and production remain `no_go`.

The frozen typed matcher reaches downstream claim macro-F1 `0.915` from the
extracted facts. That downstream pass does not override the extraction failure:
the unsupported prose family misses an asserted preview-state fact and converts
one contradiction into absence.

## Extraction boundary

The extractor reads repository files only. It does not receive candidate IDs,
claim text, expected labels, citation envelopes, or oracle facts. The evaluator
loads those inputs only after extraction to compute exact metrics and feed the
unchanged typed matcher.

Version 1 has two bounded deterministic paths:

- Dart `const` assignments with literal string, integer, or boolean values;
  lower-camel identifier tokens mechanically define subject and relation.
- Markdown HTTP/HTTPS URIs with a bounded adjacent noun phrase; explicit ports
  are preserved and standard scheme ports come from `Uri` semantics.

Other Markdown prose is deliberately unavailable. No polarity, conditional,
modal, or normative prose inference is attempted.

## Results

| Source family | Precision | Recall | F1 | Extracted / Oracle | Gate |
| --- | ---: | ---: | ---: | ---: | --- |
| Dart assignment | 1.000 | 1.000 | 1.000 | 4 / 4 | pass |
| Markdown URI | 1.000 | 1.000 | 1.000 | 5 / 5 | pass |
| Prose state | 0.000 | 0.000 | 0.000 | 0 / 5 | fail |
| **Overall** | **1.000** | **0.643** | **0.783** | **9 / 14** | **fail** |

The downstream matcher class F1 scores are supported `1.000`, contradicted
`0.857`, and absent `0.889`, for macro-F1 `0.915`. Eleven of 12 claim verdicts
are correct. The sole error is the intentionally unavailable preview-state
contradiction.

These are development-fixture results because the existing corpus informed the
bounded extractor. They are not independent promotion evidence.

## Reproduction

```bash
fvm dart run tool/rag2_typed_fact_extraction_eval.dart \
  --claims tool/fixtures/rag2_compositional_holdout/claims.json \
  --claim-atoms tool/fixtures/rag2_compositional_holdout/claim_atoms.json \
  --envelopes tool/fixtures/rag2_compositional_holdout/envelopes.json \
  --oracle-facts tool/fixtures/rag2_compositional_holdout/oracle_facts.json \
  --fixture tool/fixtures/rag2_compositional_holdout/fixture.json \
  --out-dir build/integration_test_reports/rag2_typed_fact_extraction
```

## Next entry condition

Freeze the extractor, typed contract, matcher, and current fixture. The next
offline slice must create a new untouched extraction holdout covering varied
Dart literals and declarations, explicit and default URI ports, line wrapping,
multiple nearby URIs, malformed and unsupported inputs, and prose-state
controls. Apply extraction v1 unchanged and report exact metrics by source
family before designing any prose extractor.

Do not patch URI labels or identifier aliases from holdout failures. Do not add
production storage, embeddings, routing, prompt injection, model calls, or
agent-kb federation.

## Independent holdout follow-up

Frozen extraction v1 fails all source-family gates on a new hashed corpus.
Dart precision/recall is `0.750/1.000`, Markdown URI is `0.667/0.500`, and
prose remains `0.000/0.000`; overall precision/recall/F1 is
`0.714/0.455/0.556`. Interpolated Dart strings and malformed URI ports produce
false facts, while an unsupported URI construction and all prose states are
missed. Extraction and production remain `no_go`. Evidence:
`docs/rag2_typed_fact_extraction_holdout_2026-08-25.md`.

Precision-only v2 follow-up removes the interpolated-string and malformed-port
false facts through analyzer AST literal classification and complete URI-token
validation. Holdout precision improves from `0.714` to `1.000` while recall
stays `0.455`; no relation or prose recall was added. This is informed
diagnostic evidence, so production remains `no_go` pending a third untouched
precision holdout. Evidence: `docs/rag2_typed_fact_extraction_v2_2026-08-25.md`.

The third untouched holdout promotes v2 as the precision baseline with Dart
and Markdown URI precision both `1.000`. Recall remains incomplete and prose
remains unavailable, so extraction and production stay `no_go`. Evidence:
`docs/rag2_typed_fact_extraction_v2_holdout_2026-08-25.md`.
