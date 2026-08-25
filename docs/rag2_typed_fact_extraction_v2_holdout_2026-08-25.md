# RAG2 Typed Fact Extraction V2 Precision Holdout — 2026-08-25

## Decision

Extraction v2 passes the independent supported-family precision gate and is
promoted as the precision baseline. Dart assignment precision is `1.000` and
Markdown URI precision is `1.000`, both above the `0.95` gate without losing a
true positive relative to v1.

This is not an extraction or production Go. V2 recall is `0.750` for Dart,
`0.667` for Markdown URI, and `0.000` for prose. Overall exact precision is
`1.000`, recall is `0.500`, and F1 is `0.667`. Extraction and production remain
`no_go`.

## Controls

The third hashed holdout was created after v2 was frozen. It contains:

- typed Dart constant declarations with integer, raw string, boolean, negative
  integer, computed, interpolated, and non-constant controls;
- HTTP default-port and explicit HTTPS-port facts;
- an unsupported copular URI relation plus user-info and port-zero negatives;
- positive, negative, and modal prose-state observations.

Corpus SHA-256:
`fca6a80ea7386fc33c95260f9a434376639d81fc57c0ef8d673655c77b86d6b8`.

## Results

| Family | V1 precision | V1 recall | V2 precision | V2 recall | Precision gate |
| --- | ---: | ---: | ---: | ---: | --- |
| Dart assignment | 0.000 | 0.000 | 1.000 | 0.750 | pass |
| Markdown URI | 0.500 | 0.667 | 1.000 | 0.667 | pass |
| Prose state | 0.000 | 0.000 | 0.000 | 0.000 | observational |

Across all 10 oracle facts, v1 precision/recall/F1 is
`0.500/0.200/0.286`; v2 is `1.000/0.500/0.667`. The precision result is
independent, but the remaining misses are now frozen evaluation evidence and
must not be patched with candidate-specific aliases or keywords.

## Reproduction

```bash
fvm dart run tool/rag2_typed_fact_extraction_v2_holdout_eval.dart \
  --fixture tool/fixtures/rag2_extraction_v2_holdout/fixture.json \
  --oracle-facts tool/fixtures/rag2_extraction_v2_holdout/oracle_facts.json \
  --out-dir build/integration_test_reports/rag2_typed_fact_extraction_v2_holdout
```

## Next entry condition

Freeze v2 as the precision baseline and freeze this holdout. Before adding
recall rules, define a versioned extraction-outcome contract that distinguishes
`extracted`, `unsupported_syntax`, `unsupported_relation`, and
`unsupported_prose` for each source span. Downstream matching must not convert
an unavailable extractor into an `absent` fact verdict.

Measure availability and error rates by source family with the existing three
fixtures. Do not add URI relation phrases, negative-number support, prose
keywords, storage, embeddings, routing, prompt injection, model calls, or
agent-kb federation in that slice.

Completed follow-up:
`docs/rag2_typed_fact_extraction_outcomes_2026-08-25.md` freezes the versioned
outcome accounting baseline across all 35 annotated spans. The subsequent audit
withdraws the v1 contract Go and requires explicit relation coverage before an
absent-fact verdict. Evidence:
`docs/rag2_typed_fact_extraction_outcome_audit_2026-08-25.md`.
