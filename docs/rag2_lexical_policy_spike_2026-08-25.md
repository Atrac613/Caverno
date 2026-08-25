# RAG2 Lexical Policy Spike — 2026-08-25

## Decision

RAG2 remains `later`. Do not start the production drift migration or expose a
knowledge tool yet.

An in-memory FTS5 bake-off recovered all 16 answerable RAG1 cases, including
all four Japanese queries, but no tested tokenizer/query-coverage threshold met
the candidate gate of at least 15/16 answerable hits and at most 1/4 no-answer
retrievals. The best candidate was trigram OR retrieval with an IDF-weighted
query-coverage threshold of 0.15:

| Policy | Threshold | Answerable hits | No-answer retrieved | MRR@5 |
| --- | ---: | ---: | ---: | ---: |
| trigram OR + IDF coverage | 0.15 | 16/16 | 2/4 | 0.896 |
| bigram OR + IDF coverage | 0.40 | 16/16 | 4/4 | 0.887 |
| word OR + IDF coverage | 0.10 | 11/16 | 3/4 | 0.656 |

The corpus SHA-256 remained
`4adb4bc8013b8893f67295305ac451aa00c54f1eaa4732fff2fd4199d119f57b`.
Generated JSON and Markdown remain ignored build artifacts under
`build/integration_test_reports/rag2_lexical_policy_bakeoff`.

## What the spike proves

- Pre-tokenized trigram terms executed through real in-memory FTS5 remove the
  RAG1 Japanese `unicode61` failure: Japanese retrieval improved from 0/4 to
  4/4.
- The winning candidate retrieved every current, historical, and conflict case.
- A simple global coverage threshold cannot supply the required abstention.
  `none-secret-value` and `none-instruction-injection` scored 0.481 and 0.483,
  while valid conflict cases needed thresholds as low as 0.15.
- Bigram retrieval did not discriminate no-answer cases. Word retrieval lost
  five answerable cases and therefore cannot be the lexical correctness path.

## Limits

This is seed calibration, not a production promotion gate. The runner uses an
in-memory FTS5 table, BM25 ordering, and fixed query-coverage thresholds over
the seven-document RAG1 corpus. It does not prove migration safety, incremental
indexing, project-scale latency, or holdout generalization.

## Next entry condition

The follow-up holdout experiment is complete and remains No-Go. Passage
coverage, segment concentration, and BM25 margin produced 15/16 answerable hits
and 2/4 no-answer retrievals on both seed and frozen holdout. Evidence:
`docs/rag2_evidence_sufficiency_holdout_2026-08-25.md`. The next experiment must
measure semantic answerability or claim support instead of adding thresholds to
the same lexical score.
