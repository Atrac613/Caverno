# RAG2 Evidence Sufficiency Holdout — 2026-08-25

## Decision

RAG2 remains `later`. Passage coverage, segment concentration, and BM25 margin
do not provide a safe no-answer gate, so production drift migration remains
blocked by evidence rather than implementation effort.

The policy grid was selected only on `rag1-seed-v1`. The selected policy was
then applied unchanged to the separate `rag2-lexical-holdout-v1` corpus:

- trigram OR terms through in-memory FTS5;
- minimum document query coverage: 0.25;
- minimum best-segment query coverage: 0.25;
- minimum relative BM25 top-hit margin: 0.10.

| Dataset | Answerable hits | No-answer retrieved | MRR@5 | Gate |
| --- | ---: | ---: | ---: | --- |
| seed | 15/16 | 2/4 | 0.938 | fail |
| holdout | 15/16 | 2/4 | 0.938 | fail |

The required gate was at least 15/16 answerable hits and at most 1/4 no-answer
retrievals on both datasets.

## Failure audit

The seed missed `conflict-storage` and retrieved `none-secret-value` plus
`none-instruction-injection`. The holdout independently reproduced the same
failure shape: it missed `holdout-conflict-mcp` and retrieved
`holdout-none-password` plus `holdout-none-execute`.

The false positives are not weak lexical accidents. On holdout, the password
query had document/segment coverage 0.462/0.257 and a BM25 margin of 1.0. The
instruction query had 0.806/0.785 and a margin of 1.0. The corpus contains
topically relevant safety passages, but those passages explicitly do not
contain the requested secret and prohibit executing retrieved instructions.
A global similarity, concentration, or rank-margin threshold cannot identify
that semantic distinction without also discarding answer-bearing conflict
queries.

## Reproduction

- Seed corpus SHA-256:
  `4adb4bc8013b8893f67295305ac451aa00c54f1eaa4732fff2fd4199d119f57b`
- Holdout corpus SHA-256:
  `e5b9f6a7a9616afb7a8db42d625f3849da33e3a7c24880fd4c53c0c3c7e834c3`
- Seed candidates: 100; the holdout was never used for selection.
- Generated artifacts:
  `build/integration_test_reports/rag2_evidence_sufficiency/`

```bash
fvm dart run tool/rag2_evidence_sufficiency_eval.dart \
  --seed-fixture tool/fixtures/rag_retrieval_eval/fixture.json \
  --holdout-fixture tool/fixtures/rag2_lexical_holdout/fixture.json \
  --out-dir build/integration_test_reports/rag2_evidence_sufficiency
```

## Next entry condition

Do not add more thresholds to the same lexical score. The next experiment must
measure semantic answerability or claim support on the retrieved passage while
keeping retrieval and answerability as separate verdicts. It must use the same
frozen holdout, report topical-but-insufficient evidence explicitly, and remain
offline. Production storage, automatic prompt injection, a second router,
embeddings, and agent-kb federation remain out of scope.

Follow-up evidence: `docs/rag2_claim_support_oracle_2026-08-25.md` separates
retrieval relevance from full expected-citation coverage. It is an oracle-only
diagnostic and does not clear this entry condition.
