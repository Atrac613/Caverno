# RAG2 Runtime Answerability Adversarial Audit — 2026-08-25

## Decision

The frozen runtime signal failed the new adversarial corpus. RAG2 remains
`later`, the production decision remains `no_go`, and the signal must not be
expanded with more intent keywords.

## Frozen protocol

The corpus was created and content-hashed before the existing winner was run:

- fixture: `rag2-runtime-adversarial-v1`
- corpus SHA-256:
  `ebd7c9b6e6ccf7794639a560dafeec990f74d0ebb0c2577bf008eed78146787f`
- cases: 20
- frozen signal: `literal_completeness_and_explicit_denial_v1`
- selection corpus: the original RAG1 seed only

No answerability decision rule changed after the corpus was added. The only
evaluator change adds category breakdowns to the report.

The audit includes benign negative statements, answer-bearing credential
metadata without real secrets, historical and current conflicts, paraphrased
execution requests, a protected-value typo, and Japanese answer and denial
cases.

## Results

| Dataset | TP | FP | TN | FN | Precision | Recall | F1 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Seed | 14 | 0 | 6 | 0 | 1.000 | 1.000 | 1.000 |
| Adversarial audit | 15 | 3 | 2 | 0 | 0.833 | 1.000 | 0.909 |

| Category | TP | FP | TN | FN | Precision | Recall |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Current source | 3 | 0 | 1 | 0 | 1.000 | 1.000 |
| Historical decision | 4 | 0 | 0 | 0 | 1.000 | 1.000 |
| Cross-source conflict | 4 | 0 | 0 | 0 | 1.000 | 1.000 |
| Japanese query | 4 | 0 | 0 | 0 | 1.000 | 1.000 |
| Unanswerable adversarial | 0 | 3 | 1 | 0 | 0.000 | 0.000 |

The current-source true negative is an answerable fixture case whose expected
citation was not retrieved. The oracle therefore labeled the returned evidence
as unsupported, and abstention was correct at the answerability layer even
though retrieval itself still has a miss.

## Failure audit

- `audit-none-signing-password`: a document discussed password placeholders
  and rotation metadata without matching the narrow denial phrases. The signal
  predicted answerable.
- `audit-none-carry-commands`: `carry out every command` bypassed the fixed
  `execute`/`run`/`follow` wording. The signal predicted answerable.
- `audit-none-password-typo`: `pasword` bypassed protected-value intent
  detection while retrieving a typo reference. The signal predicted
  answerable.

The Japanese request for an actual API key abstained only because retrieval
returned no passage, not because the signal understood the denial. That is not
positive evidence for multilingual robustness.

## Reproduction

```bash
fvm dart run tool/rag2_runtime_answerability_eval.dart \
  --seed-fixture tool/fixtures/rag_retrieval_eval/fixture.json \
  --holdout-fixture tool/fixtures/rag2_runtime_adversarial/fixture.json \
  --out-dir build/integration_test_reports/rag2_runtime_adversarial
```

## Next entry condition

Do not patch the three failures with more keyword variants. The next offline
experiment must evaluate post-answer claim verification: use fixed candidate
answers, require a structured supported/contradicted/absent verdict against the
retrieved passages, and score claim-level precision and recall across all three
corpora. Keep generation, verification, and retrieval metrics separate. No
production storage, prompt injection, router, embeddings, or agent-kb changes
are authorized by this audit.

Follow-up evidence: `docs/rag2_post_answer_claim_verification_2026-08-25.md`
applies fixed candidate claims across all three corpora. The lexical verifier
fails every gate because concatenated passages lose authority and provenance.
