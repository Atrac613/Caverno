# RAG2 Runtime Answerability Signal — 2026-08-25

## Decision

The offline experiment passed its synthetic gate, but RAG2 remains `later` and
the production decision remains `no_go`. The selected signal uses only the
query and retrieved text at decision time, yet the two small synthetic corpora
were already inspected while developing the preceding diagnostics.

## Candidate selection

Three deterministic candidates used the frozen trigram retrieval policy:

1. evidence presence only;
2. evidence presence plus completeness for multiple requested numeric literals;
3. literal completeness plus explicit protected-value and instruction-execution
   denial handling.

Candidates were ranked on the seed only by F1, precision, recall, then stable
policy order. The winning
`literal_completeness_and_explicit_denial_v1` policy was applied unchanged to
the existing holdout.

The signal abstains when:

- retrieval returns no passage;
- a query names multiple numeric literals but the evidence omits one;
- a protected-value request retrieves an explicit exclusion or denial;
- a protected-value request retrieves no passage mentioning such a value; or
- an instruction-execution request retrieves text that explicitly says the
  passage is not executable instruction.

These checks are runtime-available. They do not use answer keys, qrels,
authority labels, case IDs, or expected citations when making a prediction.
The oracle claim-support verdict is used only after prediction for scoring.

## Results

| Dataset | TP | FP | TN | FN | Precision | Recall | F1 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Seed | 14 | 0 | 6 | 0 | 1.000 | 1.000 | 1.000 |
| Frozen holdout | 15 | 0 | 5 | 0 | 1.000 | 1.000 | 1.000 |

The literal check rejected the seed conflict case that retrieved only the
historical eight-iteration passage while the query required both eight and
twelve. Protected-value and instruction-denial checks rejected the four
topical safety false positives across seed and holdout.

## Why this is not a production Go

- The total corpus contains only 40 synthetic cases.
- Both corpora were inspected during earlier RAG2 experiments, so the holdout
  is frozen but no longer blind for this new signal family.
- The denial rules cover narrow protected-value and instruction-execution
  intents and have not been tested against benign negative statements.
- No natural project corpus, paraphrase set, typo set, or multilingual denial
  set has measured generalization.

Promoting this policy would therefore convert a useful diagnostic into an
unmeasured router. Production storage, retrieval, and prompting remain
unchanged.

## Reproduction

```bash
fvm dart run tool/rag2_runtime_answerability_eval.dart \
  --seed-fixture tool/fixtures/rag_retrieval_eval/fixture.json \
  --holdout-fixture tool/fixtures/rag2_lexical_holdout/fixture.json \
  --out-dir build/integration_test_reports/rag2_runtime_answerability
```

## Next entry condition

Freeze a new versioned adversarial corpus before changing the signal again. It
must include benign negative statements, answer-bearing secret-management
documentation without real secrets, incomplete conflict evidence, paraphrases,
typos, and Japanese denial cases. Apply the current winner unchanged first and
report per-class precision and recall. Do not connect the signal to production
unless that untouched audit passes and the policy remains reviewable without a
second router, embeddings, prompt injection, or agent-kb federation.

Adversarial follow-up: the winner was applied unchanged to the versioned
`rag2-runtime-adversarial-v1` corpus and failed at precision `0.833` with three
false positives. See `docs/rag2_runtime_adversarial_audit_2026-08-25.md`. Do not
repair those failures by extending the intent keyword list.
