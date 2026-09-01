# RAG3 Support-Filter Latency Decision

## Decision

Reject `rag3-batched-support-filter-v2` for inline use. Its quality-qualified
loaded-model p95 latency is 6,464 ms against the frozen 1,200 ms maximum, or
5.39 times the budget.

The classifier remains eligible for offline or asynchronous shadow evaluation.
Production remains No-Go and promotion was not run.

## Frozen Decision Identity

- Date: 2026-08-31
- Contract: `rag3-support-filter-latency-decision-v1`
- Contract commit: `37bd45f3`
- Source instrument contract: `rag3-batched-support-filter-v2`
- Source report SHA-256:
  `d638f9f4333f99843ca12a79a641e204b73c79af65a163371016b90e4501e393`
- Fixture: `rag2-compositional-holdout-v1`
- Requested and reported model: `qwen3.8-27b-vision`
- Requests: 20
- Maximum added p95 latency: 1,200 ms
- Measured p50 latency: 6,292 ms
- Measured p95 latency: 6,464 ms
- p95 budget multiple: 5.39x

The evaluator consumed only the ignored, content-free instrument report. It did
not read or retransmit fixture query or document content and did not call an LLM.

## Gate Result

| Gate | Result |
| --- | --- |
| Quality | Go |
| Inline latency | No-Go |
| Shadow eligibility | Go |
| Production | No-Go |
| Promotion | Not run |

The 1,200 ms ceiling was frozen before this decision and reuses the existing
RAG6 maximum for an optional local reranker. The threshold was not fitted to the
observed 6,464 ms result.

Cold/warm repetition is not required to reject this v2 inline candidate. The
measured loaded-model run already misses the upper bound by more than fivefold,
and all 20 query-varied batches were tightly grouped between 6,214 and 6,494 ms.
Repeating the same candidate would add evidence volume without changing the
predeclared decision.

## Boundary And Follow-Up

Do not wire this classifier into retrieval, context budgeting, prompts, or
`search_knowledge`. Do not weaken the latency gate or tune against the existing
compositional fixture.

The next candidate must be frozen under a new contract before measurement and
must take one of these shapes:

- a deterministic post-fusion support filter that stays within the 1,200 ms p95
  ceiling, or
- an optimized LLM v3 whose compact protocol demonstrably stays within the same
  ceiling without losing the zero-error quality gate

The v2 classifier may be used as a shadow teacher on non-promotion data, but its
labels cannot become promotion evidence.

## Reproduction

```bash
fvm dart run tool/rag3_support_filter_latency_decision.dart \
  --report build/integration_test_reports/rag3_batched_support_filter_live_2026-08-31/rag3_batched_support_filter_instrument.json \
  --out-dir build/integration_test_reports/rag3_support_filter_latency_decision_2026-08-31
```

The ignored machine-readable decision is at
`build/integration_test_reports/rag3_support_filter_latency_decision_2026-08-31/rag3_support_filter_latency_decision.json`.
