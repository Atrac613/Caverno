# RAG3 Promotion Evaluation

## Decision

The frozen RAG3 candidate is **No-Go**. The one-shot promotion run passed every
quality, determinism, budget, provenance, no-search, degradation, and negative
control gate except `unavailableIrrelevantOnly`. One of four unavailable cases
returned only irrelevant selected evidence; the contract requires zero.

This result freezes the candidate, holdout, and aggregate report. It does not
authorize vector persistence, `search_knowledge`, prompt injection, automatic
routing, or any other production retrieval wiring.

## Frozen Identity

- Contract: `rag3-offline-hybrid-eval-contract-v2`
- Candidate: `rrf-k60-l1-v1-budget6000-v1`
- Fixture: `rag3-offline-hybrid-holdout-v1`
- Corpus SHA-256:
  `6a126fadf7358fc3209cf0dec71a72d4834b398c7bc16e592769d0c7990e49ad`
- Run: `rag3-promotion-run-v1`
- Build commit: `1127597bf3af4fc4719bba131730509878d00ce8`
- Embedding model: `qwen3-embedding-0.6b`
- Embedding fingerprint digest:
  `279fceba38183b742f0ca2e56c914f32de77fe3b90bae208a50851193b5c4637`
- Full aggregate report SHA-256:
  `6b7d8a41331b3eb28f9ff4bf71cc1cc1194423521ef776d2d18391978304854c`
- Candidate run SHA-256:
  `b94e83a298c7fd3192ed3825188354c395d72b28ada642f1792e32fd477c58f2`
- Privacy-safe pinned aggregate:
  `tool/fixtures/rag3_offline_hybrid_promotion_result.json`

The pinned aggregate omits queries, source content, endpoint URLs, rankings,
selected groups, and raw vectors. The full generated artifacts remain ignored
under `build/integration_test_reports/rag3_promotion/`.

## One-Shot Execution

The first launch exposed a transport defect before an evaluation run existed.
The LAN proxy recorded the request at `2026-08-31T04:19:11Z` with
`content_length: 0` and `model: null`; no holdout body reached the embedding
backend and no output artifact was created. Commit `1127597b` fixed the HTTP
wire contract by setting the encoded UTF-8 content length and added a local
server regression test.

The valid one-shot run then started from clean commit `1127597b`, used the
unchanged committed fixture and candidate, produced all three artifacts, and
exited with code `1` because the evaluator returned the expected machine-level
No-Go status. The run was not repeated and no candidate constant, qrel, passage
role, corpus content, or gate was changed after the result.

## Aggregate Results

| Arm | Recall@10 | Hit@5 | MRR@10 |
| --- | ---: | ---: | ---: |
| Lexical | 0.6786 | 0.7143 | 0.7143 |
| Vector | 0.9643 | 1.0000 | 0.8929 |
| Hybrid | 0.9643 | 1.0000 | 0.9286 |

- Answer support: 14/14
- Japanese answer support: 4/4
- Expected abstention support: 2/2
- Unavailable cases with only irrelevant evidence: 1/4
- Hybrid misses where the better arm passed Hit@5: 0
- Context-budget violations: 0
- No-search retrievals: 0
- Citation or provenance violations: 0
- Deterministic aggregate replay: passed
- Empty-fusion negative control: detected
- Budget-bypass negative control: detected at 7,063 estimated tokens
- Vector validation and degradation gate: passed

The sole failing case is `unavailable-weather`. Its selected passage roles were
all `irrelevant`; no `abstention_support` or `topical_only` evidence was
selected. The other three unavailable cases satisfied their declared passage
role expectations.

## Gate Receipt

| Gate | Result |
| --- | --- |
| Object Recall@10 | pass |
| Object Hit@5 | pass |
| Object MRR@10 | pass |
| Better-arm hybrid misses | pass |
| Answer support | pass |
| Japanese answer support | pass |
| Abstention support | pass |
| Unavailable irrelevant-only | **fail** |
| Context budget | pass |
| No-search behavior | pass |
| Citation and provenance | pass |
| Empty-fusion negative control | pass |
| Budget-bypass negative control | pass |
| Vector degradation | pass |

## Consequences And Next Entry

RAG3 production work is blocked by the offline promotion gate. Do not tune the
frozen holdout or reinterpret the one failing case. A future attempt requires a
new contract version, a candidate frozen from non-promotion instrument evidence,
and a newly committed untouched promotion fixture. The narrow next research
slice is to test an explicit abstention/no-evidence retrieval policy on separate
instrument data before proposing that new contract; it must not reuse this
holdout as a development set.

## Verification

- `dart analyze tool/rag3_promotion_run.dart test/tool/rag3_promotion_run_test.dart`
- `fvm flutter test test/tool/rag3_promotion_run_test.dart test/tool/rag3_offline_hybrid_eval_test.dart`
- `fvm flutter test test/tool/rag3_offline_hybrid_promotion_result_test.dart test/tool/rag3_offline_hybrid_eval_test.dart test/tool/rag3_promotion_run_test.dart`
- `tool/codex_verify.sh`
- `git diff --check`

The first focused set passed 10 tests after the transport fix. The promotion
result set passed 12 tests after pinning the aggregate. The final standard
verification passed all 8,690 Flutter tests, all three internal package suites,
and all 10 notification relay tests.
