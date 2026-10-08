# RAG2 Hosted Passage-Role Evaluation — 2026-08-30

## Decision

`rag2-hosted-passage-role-eval-contract-v2` is Go, and the unchanged
AppDatabase-hosted `trigram_or_idf` candidate at threshold `0.15` is Go for the
offline lexical retrieval boundary. Production retrieval, prompt injection,
`search_knowledge`, automatic routing, and RAG3 wiring remain No-Go.

The earlier `rag2-hosted-retrieval-eval-contract-v1` No-Go remains an accurate
record of its frozen raw no-answer gate. V2 does not rewrite that result. It
withdraws raw no-answer retrieval count as a promotion gate because that count
conflates abstention-support, topical-only, and irrelevant evidence.

## Reproduction identity

- Contract: `rag2-hosted-passage-role-eval-contract-v2`
- Candidate: `trigram_or_idf`
- Threshold: `0.15`
- Metric K: `5`
- Promotion fixture: `rag2-hosted-passage-role-holdout-v1`
- Promotion oracle: `rag2-hosted-passage-role-holdout-oracle-v1`
- Corpus SHA-256:
  `e9d063df93d935297fe44050073c219f9813acf48d1769ba04642ec9db7e5f07`
- Clean implementation commit:
  `1c6e3ffc527422de85445e7d05c159bc724ae0ab`
- AppDatabase schema version: `5`
- Runtime passage role: `unknown`
- Runtime role classifier: `not_available`
- Generated reports:
  `build/integration_test_reports/rag2_hosted_passage_role_instrument/` and
  `build/integration_test_reports/rag2_hosted_passage_role_promotion/`
  (ignored build artifacts)

The v2 contract was committed before the promotion corpus. The 20-case corpus,
complete oracle, and content hash were then committed before the evaluator was
implemented or applied to the holdout.

## Instrument validation

The committed evaluator first ran through the actual file-backed AppDatabase
path on both inspected passage-role datasets. These results validate the
instrument; they are not promotion evidence.

| Dataset | Answer support | Japanese support | Expected abstention | Only-irrelevant unavailable | Context tokens |
| --- | ---: | ---: | ---: | ---: | ---: |
| Semantic holdout | 14/14 | 4/4 | 2/2 | 0/4 | 2,174 |
| Compositional holdout | 13/13 | 2/2 | 3/3 | 0/4 | 2,986 |

Both datasets preserved provenance, the empty negative control, schema version
5, conversation search, and the seeded LL5 embedding row. Their raw no-answer
retrieval diagnostic was 3/4, demonstrating again why that count cannot
distinguish passage roles.

## Untouched promotion result

Every predeclared v2 gate passed:

| Gate | Result | Required | Decision |
| --- | ---: | ---: | --- |
| Answer-support retrieval | 14/14 | at least 13/14 | pass |
| Japanese answer support | 4/4 | 4/4 | pass |
| Expected abstention support | 2/2 | 2/2 | pass |
| Unavailable with only irrelevant evidence | 0/4 | 0/4 | pass |
| Retrieved context | 3,776 tokens | at most 6,000 | pass |
| Provenance validation | true | true | pass |
| Empty negative control | true | true | pass |
| Existing host preserved | true | true | pass |

Additional measurements:

- support MRR@5: `1.000`
- support nDCG@5: `0.9949825493217618`
- raw no-answer retrieval diagnostic: `3/4`
- returned role counts: 17 answer-support, 4 abstention-support, 6
  topical-only, and 27 irrelevant hits

The four unavailable cases separated as follows:

- signing-token request: abstention-support evidence;
- execute-retrieved-text request: abstention-support evidence;
- release-date request: topical-only evidence plus irrelevant neighbors;
- external-weather request: no evidence.

No unavailable case returned only irrelevant evidence. V1 would fail the same
shape at raw count 3/4, while v2 records the semantic role of each returned
passage without pretending that the oracle exists at runtime.

## Boundary evidence

- Every dataset creates its generation through
  `Rag2DriftDaoGenerationStore.apply(..., indexSearch: true)`.
- Retrieval executes against the hosted `rag2_chunk_search` slot bound to the
  committed project, declaration, generation, and snapshot identities.
- Role annotation occurs only after hosted retrieval and never changes ranking,
  thresholding, or returned context.
- The report retains case IDs and repository-relative object IDs but omits
  source text, query text, lexical terms, absolute roots, and credentials.
- Runtime chunks continue to expose passage role as `unknown`.
- Production and RAG3 decisions are independent and remain No-Go.

## Verification

```bash
fvm dart run tool/rag2_hosted_passage_role_eval.dart \
  --mode instrument \
  --oracle tool/fixtures/rag2_passage_role_oracle/oracle.json \
  --fixture tool/fixtures/rag2_semantic_holdout/fixture.json \
  --fixture tool/fixtures/rag2_compositional_holdout/fixture.json \
  --out-dir build/integration_test_reports/rag2_hosted_passage_role_instrument

fvm dart run tool/rag2_hosted_passage_role_eval.dart \
  --mode promotion \
  --oracle tool/fixtures/rag2_hosted_passage_role_holdout/oracle.json \
  --fixture tool/fixtures/rag2_hosted_passage_role_holdout/fixture.json \
  --out-dir build/integration_test_reports/rag2_hosted_passage_role_promotion

fvm flutter test test/tool/rag2_hosted_passage_role_eval_test.dart
fvm flutter test test/tool/rag2_*_test.dart
```

The focused v2 suite passes five tests, and the complete currently enumerated
RAG2 suite passes 263 tests.

## Next entry condition

Freeze the v2 contract, holdout, oracle, candidate, and result. Do not add a
runtime passage-role classifier or tune the lexical candidate from these cases.
The RAG2 offline acquisition, storage, provenance, and lexical retrieval
boundaries are now Go. The next roadmap slice may define the RAG3 offline
vector/RRF and context-budget evaluation contract. It must remain
storage-independent first and must not add `search_knowledge`, prompt injection,
automatic routing, or chat/runtime wiring until its own gates pass.
