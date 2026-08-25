# RAG2 Passage-Role Oracle — 2026-08-25

## Decision

The frozen trigram ranking and sufficiency policy have been re-scored with the
versioned `rag2-passage-role-oracle-v1`. The ranking, thresholds, source
documents, and query cases did not change.

The old `no-answer retrieved` count is withdrawn as a promotion gate. It
conflated four materially different passage roles:

- `answer_support`: evidence that supports a requested answer;
- `abstention_support`: evidence that supports a bounded negative or
  unavailable answer;
- `topical_only`: related evidence that does not support an answer;
- `irrelevant`: evidence unrelated to the requested claim.

The re-score is diagnostic complete, but production remains No-Go. No runtime
component can assign these roles, and topical-only passages are still returned
for unavailable questions. Typed facts are no longer a RAG2 prerequisite:
freeze the extraction suites as diagnostic evidence and do not implement
extraction v3.

## Frozen inputs

- Oracle: `tool/fixtures/rag2_passage_role_oracle/oracle.json`
- Seed: `rag2-semantic-holdout-v1`, corpus
  `0314447ba24a5ae2fad63ec65602fee1804f4ea673bfe52d4f2ea38d6d97bac4`
- Holdout: `rag2-compositional-holdout-v1`, corpus
  `c120cb7970ccd7277618915fca9502b0a70fe154fe75c44e0e2199cbb185a8e4`
- Retrieval: trigram scorer plus the frozen coverage, segment-coverage, and
  BM25-margin policy from `rag2_claim_support_eval.dart`

The oracle explicitly annotates role-bearing case/object pairs and may pin an
`irrelevant` control. Other unlisted objects are `irrelevant`. The evaluator
rejects missing cases, unknown objects, dataset identity drift, and corpus hash
drift.

## Measured result

| Dataset | Answer support | Abstention support | Unavailable with abstention | Unavailable with topical only |
| --- | ---: | ---: | ---: | ---: |
| Semantic holdout | 14/14 | 1/2 | 1/4 | 3/4 |
| Compositional holdout | 13/13 | 3/3 | 0/4 | 2/4 |

Returned-passage roles were:

| Dataset | Answer support | Abstention support | Topical only | Irrelevant |
| --- | ---: | ---: | ---: | ---: |
| Semantic holdout | 17 | 2 | 8 | 1 |
| Compositional holdout | 14 | 3 | 13 | 1 |

The semantic corpus demonstrates why the old gate was invalid: one unavailable
owner query retrieved an explicit non-identification passage. Counting that
retrieval as an unconditional false positive discarded useful abstention
evidence. Conversely, five of the eight unavailable cases still retrieved at
least one topical-only passage, so retrieval alone cannot establish semantic
answerability.

## Consequences

- Keep relevance, passage role, answerability, and claim verification as
  separate measurements.
- Do not require typed-fact extraction before defining the local Knowledge
  Object boundary. Typed facts remain useful oracle and regression evidence,
  but their incomplete runtime coverage does not block a provenance-bearing
  lexical index.
- Do not promote the oracle into runtime code or derive new intent keywords
  from its cases.
- Keep RAG2 `later` until a storage-independent Knowledge Object and bounded
  lexical retrieval contract preserves provenance and exposes role as unknown
  rather than pretending to classify it.

## Reproduction

```bash
fvm dart run tool/rag2_passage_role_eval.dart \
  --oracle tool/fixtures/rag2_passage_role_oracle/oracle.json \
  --fixture tool/fixtures/rag2_semantic_holdout/fixture.json \
  --fixture tool/fixtures/rag2_compositional_holdout/fixture.json \
  --out-dir build/integration_test_reports/rag2_passage_role

fvm flutter test test/tool/rag2_passage_role_eval_test.dart
```

## Next entry condition

Return to the original RAG2 boundary before storage work. Define a versioned,
storage-independent Knowledge Object and Chunk contract with content hash,
revision, repository-relative location, one-based line span, source trust, and
provenance. Add one replay fixture that proves deterministic chunk identity and
incremental invalidation. Passage role must remain `unknown` at runtime. Do not
add drift tables, FTS5, prompting, routing, or model calls in that slice.
