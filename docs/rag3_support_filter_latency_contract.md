# RAG3 Support-Filter Latency Decision Contract

## Decision Question

Decide whether the quality-qualified `rag3-batched-support-filter-v2`
classifier may run inline between hybrid retrieval and context budgeting. This
contract does not rerun the model, change the classifier, or authorize
production retrieval.

## Frozen Input

The evaluator accepts only the content-free machine report from the authorized
`rag2-compositional-holdout-v1` run. It requires:

- a clean build and the exact v2 instrument identity
- 20 requests and matching requested/reported model IDs
- no persisted query or evidence content
- no classifier failure
- the instrument quality decision already at Go
- the original production decision at No-Go and promotion not run

The evaluator content-addresses the source report and refuses a non-empty output
directory. It does not read or transmit fixture content.

## Gate

Inline eligibility requires both:

- zero false positives, false negatives, unavailable batches, and invalid
  batches
- added p95 latency at most 1,200 ms

The 1,200 ms ceiling reuses the existing RAG6 gate for an optional local
reranker. A support filter is also optional post-retrieval semantic work, so it
must not receive a larger interactive budget than the later reranker it could
replace or complement. This is an upper bound, not a claim that 1,200 ms is
imperceptible.

A quality-qualified classifier that misses the latency gate remains eligible
for offline or asynchronous shadow evaluation. It is not eligible for inline
activation, production, or promotion. A future optimized candidate requires a
new contract version before new measurements; do not tune this threshold to the
observed result.

## Verification

```bash
dart analyze \
  tool/rag3_support_filter_latency_decision.dart \
  test/tool/rag3_support_filter_latency_decision_test.dart
fvm flutter test test/tool/rag3_support_filter_latency_decision_test.dart
tool/codex_verify.sh
git diff --check
```
