# RAG2 Post-Answer Claim Verification — 2026-08-25

## Decision

The post-answer verifier is `no_go`. RAG2 remains `later`, and no production
retrieval, generation, prompt, or storage behavior changes.

## Contract

The versioned candidate set contains 36 fixed claims: 12 per corpus and four
each of `supported`, `contradicted`, and `absent` within every corpus.

- candidate set: `rag2-claim-verification-v1`
- candidate-set SHA-256:
  `1c38d410e6222c6a84278dd09b3c865579f71a21f363f6ed61ec7420040b88f9`
- source corpus hashes are embedded in the candidate-set manifest
- retrieval uses the frozen RAG2 trigram sufficiency policy
- verifier inputs are only one fixed claim and its retrieved passages
- answer keys label results after prediction and are not verifier inputs

Nine trigram-coverage policies were evaluated on the original seed. The winner
used support coverage `0.90`, contradiction coverage `0.50`, and numeric
mismatch detection. That exact policy was applied to both holdouts.

## Results

| Dataset | Macro F1 | Supported F1 | Contradicted F1 | Absent F1 | Gate |
| --- | ---: | ---: | ---: | ---: | --- |
| Seed | 0.758 | 0.857 | 0.750 | 0.667 | fail |
| Lexical holdout | 0.675 | 0.667 | 0.500 | 0.857 | fail |
| Runtime adversarial | 0.542 | 0.727 | 0.500 | 0.400 | fail |

Every dataset failed the macro-F1 `0.90` gate.

## Failure audit

The decisive failure is authority loss. The lexical holdout retrieved both
current and superseded configuration passages. Claims that 2048 tokens or port
9090 are current therefore achieved full lexical coverage because those values
exist in historical evidence, even though the claims are contradicted by the
current source. The adversarial safeMode and 30-day rotation claims failed for
the same reason.

Coverage also confused partial topical overlap with contradiction and support:

- an MCP claim at coverage `0.833` was labeled contradicted despite being
  supported;
- an absent configuration-owner claim was labeled contradicted;
- absent password and command claims were labeled contradicted;
- the typo-secret claim reached full coverage and was labeled supported.

This proves that post-answer timing alone does not repair a lexical verifier.
Structured claim verdicts require hit-level provenance and authority rather
than a concatenated evidence bag.

## Reproduction

```bash
fvm dart run tool/rag2_post_answer_claim_eval.dart \
  --claims tool/fixtures/rag2_claim_verification/candidates.json \
  --seed-fixture tool/fixtures/rag_retrieval_eval/fixture.json \
  --holdout-fixture tool/fixtures/rag2_lexical_holdout/fixture.json \
  --audit-fixture tool/fixtures/rag2_runtime_adversarial/fixture.json \
  --out-dir build/integration_test_reports/rag2_post_answer_claim
```

## Next entry condition

Do not tune more lexical thresholds. The next offline experiment must preserve
each retrieved passage as a separate evidence item with source identity,
current/historical authority, and revision order. Apply the same 36 claims and
score whether an authority-aware verifier can distinguish supported,
contradicted, and absent without reading fixture answer keys. The experiment
must remain storage-independent and must not add a production router,
embeddings, prompt injection, or agent-kb federation.

Authority follow-up: `docs/rag2_authority_claim_verification_2026-08-25.md`
preserves hit-level source authority and revision. It improves both holdouts but
fails the gate and regresses seed because claim scope cannot be inferred
reliably from prose.
