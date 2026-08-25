# RAG2 Typed Fact Extraction Outcomes — 2026-08-25

## Decision

The original `typed-fact-extraction-outcome-v1` contract Go is withdrawn after
review found that zero extraction could still satisfy its gate and an unknown
relation could become `absent`. The corrected
`typed-fact-extraction-outcome-v2` passes only its offline accounting gate.
Runtime availability is `not_evaluated`, so the outcome contract, extraction,
and production decisions are all `no_go`.

Frozen extraction v2 was applied unchanged to all three existing extraction
datasets. Every one of the 35 annotated fact spans has exactly one outcome:
`extracted`, `unsupported_syntax`, `unsupported_relation`, or
`unsupported_prose`.

The accounting baseline requires the exact three dataset IDs and corpus hashes,
all 19 existing true positives, the per-family counts, the complete outcome
distribution, and a false-extraction rate of `0.000`. A zero-extraction
regression is explicitly No-Go.

## Boundary

The committed oracle annotations identify the evaluation spans and source
families. They are not inputs to extraction and do not add runtime candidate
discovery. Extraction v2 still receives only the corpus root and corpus hash.

For each annotated span, the evaluator first checks for an exact v2 typed fact.
When no exact fact exists, it records the frozen boundary that prevented
extraction:

- Dart assignment misses are `unsupported_syntax`;
- valid HTTP/S URI spans that the unchanged relation binder cannot bind are
  `unsupported_relation`;
- invalid HTTP/S URI spans are `unsupported_syntax`;
- prose-state spans are `unsupported_prose`.

The availability guard converts a typed matcher's tentative `absent` result to
`notAvailable` unless every cited source carries an explicit complete-coverage
proof for the exact claim relation. Unsupported outcomes remain blockers, and
unknown relations fail closed. The oracle-backed outcome evaluator does not
produce runtime completeness proofs, so it cannot promote runtime absence.

## Results

| Family | Spans | Extracted | Availability | Unavailable | False extraction |
| --- | ---: | ---: | ---: | ---: | ---: |
| Dart assignment | 11 | 10 | 0.909 | 0.091 | 0.000 |
| Markdown URI | 12 | 9 | 0.750 | 0.250 | 0.000 |
| Prose state | 12 | 0 | 0.000 | 1.000 | 0.000 |
| Overall | 35 | 19 | 0.543 | 0.457 | 0.000 |

Outcome counts:

- `extracted`: 19
- `unsupported_syntax`: 1
- `unsupported_relation`: 3
- `unsupported_prose`: 12

The false-extraction rate counts false extracted facts relative to all v2
extractions. It remains zero across these datasets. This does not measure
parser execution failures or runtime candidate discovery, and it does not
replace the independent precision gate recorded in
`docs/rag2_typed_fact_extraction_v2_holdout_2026-08-25.md`.

## Reproduction

```bash
fvm dart run tool/rag2_typed_fact_extraction_outcome_eval.dart \
  --development-fixture \
    tool/fixtures/rag2_compositional_holdout/fixture.json \
  --development-oracle-facts \
    tool/fixtures/rag2_compositional_holdout/oracle_facts.json \
  --holdout-fixture tool/fixtures/rag2_extraction_holdout/fixture.json \
  --holdout-oracle-facts \
    tool/fixtures/rag2_extraction_holdout/oracle_facts.json \
  --precision-fixture \
    tool/fixtures/rag2_extraction_v2_holdout/fixture.json \
  --precision-oracle-facts \
    tool/fixtures/rag2_extraction_v2_holdout/oracle_facts.json \
  --out-dir \
    build/integration_test_reports/rag2_typed_fact_extraction_outcomes_v2
```

## Next entry condition

Freeze outcome v2, extractor v2, and all three datasets. Do not start extraction
v3. The next slice must realign the RAG2 promotion metric by distinguishing
`answer_support`, `abstention_support`, `topical_only`, and `irrelevant`
retrieved passages on the existing answerable and no-answer cases. It must
decide whether typed-fact extraction remains a prerequisite or closes as a
bounded diagnostic before any recall, storage, retrieval, or runtime work.

Audit evidence:
`docs/rag2_typed_fact_extraction_outcome_audit_2026-08-25.md`.
