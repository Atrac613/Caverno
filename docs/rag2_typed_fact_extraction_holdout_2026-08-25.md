# RAG2 Typed Fact Extraction Holdout — 2026-08-25

## Decision

Frozen extraction v1 fails every source-family gate on a new independent
holdout. Overall exact precision is `0.714`, recall is `0.455`, and F1 is
`0.556`. Extraction and production remain `no_go`; downstream claim matching
was intentionally `not_evaluated`.

The holdout corpus and oracle were created after extraction v1 was frozen. The
extractor received only repository files and the corpus hash. Candidate claims,
labels, envelopes, and oracle facts were not provided to extraction.

## Controls

The hashed holdout contains 11 oracle facts across three source families:

- three Dart literal constant assignments, plus computed, interpolated, and
  non-constant negative controls;
- four Markdown URI-port facts with explicit and default ports, line wrapping,
  and multiple nearby URIs;
- malformed and example-only URI negative controls;
- four prose states spanning positive, negative, conditional, and normative
  modality.

Corpus SHA-256:
`365c9f152244a2ee5d87313fbc1af70ccfa03a8a8b25ac18a70edacfe5ff5179`.

## Results

| Source family | Precision | Recall | F1 | Extracted / Oracle | Gate |
| --- | ---: | ---: | ---: | ---: | --- |
| Dart assignment | 0.750 | 1.000 | 0.857 | 4 / 3 | fail |
| Markdown URI | 0.667 | 0.500 | 0.571 | 3 / 4 | fail |
| Prose state | 0.000 | 0.000 | 0.000 | 0 / 4 | fail |
| **Overall** | **0.714** | **0.455** | **0.556** | **7 / 11** | **fail** |

The audit exposes four bounded failure classes:

- a Dart interpolated string is incorrectly accepted as a literal fact;
- a malformed URI port is truncated and incorrectly assigned HTTPS port 443;
- two valid ports using an unsupported `endpoint URI` construction are missed;
- prose remains deliberately unavailable.

The first two are precision failures at syntax boundaries. The last two are
recall gaps. Do not add holdout-specific subject aliases or prose keywords.

## Reproduction

```bash
fvm dart run tool/rag2_typed_fact_extraction_holdout_eval.dart \
  --fixture tool/fixtures/rag2_extraction_holdout/fixture.json \
  --oracle-facts tool/fixtures/rag2_extraction_holdout/oracle_facts.json \
  --out-dir build/integration_test_reports/rag2_typed_fact_extraction_holdout
```

## Next entry condition

Freeze this holdout and its v1 result. The next narrow slice may define
extraction v2 as precision hardening only: classify Dart literals through
syntax-aware parsing and require complete valid URI-token boundaries. Do not
add the missed `endpoint URI` phrasing, subject aliases, or prose extraction.
Re-score the development fixture and this holdout as diagnostic evidence, then
require another untouched holdout before promotion.

No production storage, embeddings, routing, prompt injection, model calls, or
agent-kb federation is authorized.

## Precision-only v2 follow-up

A separate v2 uses syntax-aware Dart literals and complete URI-token validation
without changing v1 or adding recall rules. On this holdout, precision improves
from `0.714` to `1.000`, recall remains `0.455`, and F1 improves from `0.556`
to `0.625`. Because this holdout informed v2, the result is diagnostic rather
than independent promotion evidence. Freeze v2 and require a third untouched
precision holdout. Evidence: `docs/rag2_typed_fact_extraction_v2_2026-08-25.md`.
