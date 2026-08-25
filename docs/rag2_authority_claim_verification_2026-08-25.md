# RAG2 Authority-Aware Claim Verification — 2026-08-25

## Decision

Hit-level authority metadata improves both holdouts but does not pass the
verification gate and makes the seed worse. RAG2 remains `later`; production
retrieval, generation, prompting, and storage remain unchanged.

## Frozen inputs

- candidate claims: `rag2-claim-verification-v1` (36 claims)
- verifier policy: support `0.90`, contradiction `0.50`
- authority metadata: `rag2-evidence-authority-v1`
- authority metadata SHA-256:
  `4684a0df8021966f93937417e95528024819a972cfe6460c0d828cda79c0f2da`

Every corpus object has storage-independent metadata containing source
identity, `current` or `historical` authority, and an integer revision. The
evaluator keeps retrieved passages separate, infers the requested authority
from query and claim wording, selects the highest matching revision, then runs
the unchanged lexical claim verifier per passage.

## Results

| Dataset | Baseline macro F1 | Authority macro F1 | Delta | Gate |
| --- | ---: | ---: | ---: | --- |
| Seed | 0.758 | 0.667 | -0.091 | fail |
| Lexical holdout | 0.675 | 0.838 | +0.163 | fail |
| Runtime adversarial | 0.542 | 0.672 | +0.130 | fail |

The metadata fixes several stale-value errors by preventing historical values
from supporting claims explicitly scoped as current. No dataset reaches the
macro-F1 `0.90` gate.

## Failure audit

Authority inference from prose is not reliable. The seed question about why
LL5 used brute-force cosine has historical intent but no explicit `former` or
`historical` marker. The evaluator defaults to current evidence and selects the
federation contract instead of the historical decision, turning supported and
contradicted ANN claims into `absent`.

Authority does not solve semantic polarity or topical overlap:

- `safeMode is currently disabled` is lexically supported by a current passage
  stating that it is *not* disabled;
- a supported MCP-port claim remains below the support threshold;
- absent owner, command, and typo-secret claims remain confused with
  contradiction or support;
- a supported historical negative statement is verified against the wrong
  current safety passage when its authority is not explicit.

This establishes two separate requirements: retrieved evidence needs durable
authority metadata, and generated claims need explicit scope and citations.
Inferring either from prose recreates a fragile temporal router.

## Reproduction

```bash
fvm dart run tool/rag2_authority_claim_eval.dart \
  --claims tool/fixtures/rag2_claim_verification/candidates.json \
  --authority tool/fixtures/rag2_claim_verification/evidence_authority.json \
  --seed-fixture tool/fixtures/rag_retrieval_eval/fixture.json \
  --holdout-fixture tool/fixtures/rag2_lexical_holdout/fixture.json \
  --audit-fixture tool/fixtures/rag2_runtime_adversarial/fixture.json \
  --out-dir build/integration_test_reports/rag2_authority_claim
```

## Next entry condition

Do not add temporal keywords. The next offline experiment must wrap every fixed
candidate claim in a structured envelope containing explicit `current`,
`historical`, or `unspecified` scope and cited source IDs. Verification must
fail closed when citations are missing, authority mismatches, or cited
revisions are superseded, then apply semantic support only to the selected
passages. Reuse the same claim text and corpus hashes. No production migration,
router, embeddings, prompt injection, or agent-kb federation is authorized.

Structured-envelope follow-up:
`docs/rag2_structured_claim_envelopes_2026-08-25.md` replaces prose inference
with explicit scope and citations. Both holdouts pass, but seed remains below
gate because passage-level semantic verification is still lexical.
