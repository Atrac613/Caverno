# RAG2 Typed Fact Extraction V2 — 2026-08-25

## Decision

Extraction v2 removes both known syntax-boundary false facts without expanding
relation or prose recall. On the frozen v1 holdout, overall exact precision
improves from `0.714` to `1.000`; recall remains `0.455`, and F1 improves from
`0.556` to `0.625`. Extraction and production remain `no_go`.

This is diagnostic evidence, not independent promotion evidence. The v1
holdout exposed the two precision failures that informed v2.

## Precision-only changes

V1 remains unchanged. V2 is a separate extraction path with two bounded
differences:

- Dart top-level `const` declarations are parsed through the analyzer AST, and
  only `SimpleStringLiteral`, `IntegerLiteral`, and `BooleanLiteral` values are
  eligible. Interpolation, computed expressions, and non-constant declarations
  fail closed.
- Markdown HTTP/HTTPS candidates must pass complete token, host, user-info, and
  numeric port validation before entering the unchanged v1 URI relation binder.
  A malformed port cannot be truncated into an implicit scheme port.

V2 does not add the missed `endpoint URI` construction, subject aliases,
candidate data, or prose parsing.

## Results

### Development fixture

| Extractor | Precision | Recall | F1 | Gate |
| --- | ---: | ---: | ---: | --- |
| V1 | 1.000 | 0.643 | 0.783 | fail |
| V2 | 1.000 | 0.643 | 0.783 | fail |

### Frozen v1 holdout

| Extractor | Precision | Recall | F1 | Gate |
| --- | ---: | ---: | ---: | --- |
| V1 | 0.714 | 0.455 | 0.556 | fail |
| V2 | 1.000 | 0.455 | 0.625 | fail |

V2 source-family precision/recall on the holdout is Dart `1.000/1.000`,
Markdown URI `1.000/0.500`, and prose `0.000/0.000`. This confirms the bounded
precision repair while preserving every known recall gap.

## Reproduction

```bash
fvm dart run tool/rag2_typed_fact_extraction_v2_eval.dart \
  --development-fixture tool/fixtures/rag2_compositional_holdout/fixture.json \
  --development-oracle-facts tool/fixtures/rag2_compositional_holdout/oracle_facts.json \
  --holdout-fixture tool/fixtures/rag2_extraction_holdout/fixture.json \
  --holdout-oracle-facts tool/fixtures/rag2_extraction_holdout/oracle_facts.json \
  --out-dir build/integration_test_reports/rag2_typed_fact_extraction_v2
```

## Next entry condition

Freeze v2 and both existing results. Create a third untouched precision
holdout with new simple/interpolated/computed Dart declarations and valid,
default-port, malformed-port, user-info, and punctuation URI controls. Apply
v1 and v2 unchanged. V2 may become the precision baseline only if supported
source-family precision is at least `0.95` without regressing valid facts.

This precision gate cannot authorize production: URI relation recall and prose
extraction remain separate No-Go conditions. Do not add relation phrases,
aliases, prose keywords, storage, embeddings, routing, prompt injection, model
calls, or agent-kb federation.

## Independent precision holdout

Frozen v2 passes a third untouched supported-family precision gate: Dart and
Markdown URI precision are both `1.000`, with recall `0.750` and `0.667`.
Overall precision/recall/F1 is `1.000/0.500/0.667`. V2 is promoted as the
precision baseline, but extraction and production remain `no_go`. The next
slice must represent unsupported extraction explicitly instead of allowing a
missing extractor result to become an absent fact verdict. Evidence:
`docs/rag2_typed_fact_extraction_v2_holdout_2026-08-25.md`.
