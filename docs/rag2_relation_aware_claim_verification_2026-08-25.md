# RAG2 Relation-Aware Claim Verification — 2026-08-25

## Decision

`relation-aware-atomic-facts-v2` passes the original 36-claim suite and the
12-claim semantic holdout at macro-F1 `1.000`. It improves the semantic holdout
from verifier v1's `0.672` without regressing any original dataset.

Production remains `no_go`. The first semantic holdout exposed the four
relations used to design v2, so its new perfect score is regression closure,
not independent promotion evidence.

## Frozen comparison

The comparison keeps unchanged:

- all 48 claim texts, expected verdicts, envelopes, and corpus hashes;
- retrieval, sufficiency, authority, revision, and structural citation checks;
- lexical thresholds and verifier v1;
- fail-closed behavior when a semantic verifier is unavailable.

V2 adds relation parsing before the unchanged v1 fallback:

- numeric values bind to normalized code assignment identifiers;
- port values bind to the URI component associated with the matching subject;
- boolean state uses negation parity rather than one-token negation matching;
- modal statements such as `may`, `might`, or `could` remain `absent`;
- Markdown line wrapping is normalized before sentence relation parsing.

No candidate ID or expected label is consulted by the verifier.

## Results

| Verifier | Seed | Lexical holdout | Runtime adversarial | Semantic holdout |
| --- | ---: | ---: | ---: | ---: |
| `deterministic-atomic-facts-v1` | 1.000 | 1.000 | 1.000 | 0.672 |
| `relation-aware-atomic-facts-v2` | 1.000 | 1.000 | 1.000 | 1.000 |

V2 corrects all four independent-holdout failures: double-negation parity,
unrelated numeric values near a URL, a URL without an explicitly assigned
port, and modal boolean state. Each dataset clears the macro-F1 `0.90` gate.

## Reproduction

```bash
fvm dart run tool/rag2_relation_aware_claim_eval.dart \
  --claims tool/fixtures/rag2_claim_verification/candidates.json \
  --envelopes tool/fixtures/rag2_claim_verification/claim_envelopes.json \
  --authority tool/fixtures/rag2_claim_verification/evidence_authority.json \
  --seed-fixture tool/fixtures/rag_retrieval_eval/fixture.json \
  --holdout-fixture tool/fixtures/rag2_lexical_holdout/fixture.json \
  --audit-fixture tool/fixtures/rag2_runtime_adversarial/fixture.json \
  --semantic-claims tool/fixtures/rag2_semantic_holdout/claims.json \
  --semantic-envelopes tool/fixtures/rag2_semantic_holdout/envelopes.json \
  --semantic-authority tool/fixtures/rag2_semantic_holdout/authority.json \
  --semantic-fixture tool/fixtures/rag2_semantic_holdout/fixture.json \
  --out-dir build/integration_test_reports/rag2_relation_aware
```

## Next entry condition

Freeze verifier v2 and all 48 claims. Before production work, run one second
independent compositional holdout that was not used to design either verifier.
It must combine multiple same-type relations in one passage, URI default ports
and host-port ambiguity, non-numeric code assignments, nested or scoped
negation, and several modal or conditional clauses. Compare v1 and v2 without
changing either implementation. Report the same three-class metrics and
availability failure behavior. No production model call, embeddings, storage
migration, router, prompt injection, or agent-kb federation is authorized.

Second-holdout follow-up:
`docs/rag2_compositional_semantic_holdout_2026-08-25.md` freezes both verifiers
and adds 12 compositional controls. V1 scores 0.154 macro-F1 and v2 scores
0.328; both fail. Further regex and alias expansion is closed. The next slice
must measure a typed evidence-fact oracle contract before any verifier v3.
