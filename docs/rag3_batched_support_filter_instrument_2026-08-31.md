# RAG3 Batched Support-Filter Instrument Result

## Decision

The `rag3-batched-support-filter-v2` non-promotion instrument is quality Go.
The fixed compositional run produced zero cross-bucket errors, zero unavailable
batches, and zero invalid batches.

Production activation remains No-Go. The separately frozen latency contract
subsequently rejected inline use at 6,464 ms p95 against a 1,200 ms ceiling.
The classifier remains shadow-only and promotion was not run. Evidence:
`docs/rag3_support_filter_latency_decision_2026-08-31.md`.

## Frozen Run Identity

- Date: 2026-08-31
- Build commit: `58da0eb82fc1252d2ca1d814a16dc4adbd47790e`
- Build dirty: `false`
- Contract: `rag3-batched-support-filter-v2`
- Fixture: `rag2-compositional-holdout-v1`
- Corpus hash:
  `c120cb7970ccd7277618915fca9502b0a70fe154fe75c44e0e2199cbb185a8e4`
- Oracle: `rag2-passage-role-oracle-v1`
- Endpoint: `http://192.168.100.241:1234/v1/chat/completions`
- Requested and reported model: `qwen3.8-27b-vision`
- Requests: 20, one five-document batch per query
- Persisted query or evidence content: false
- Classifier failure reason: none

The user explicitly authorized sending the fixture query and document content
to this LAN endpoint. The runner sent no oracle roles, expected decisions,
qrels, or answer keys. Expected decisions were joined only after each response.

## Quality Result

| Metric | Result |
| --- | ---: |
| True positives | 19 |
| True negatives | 81 |
| False positives | 0 |
| False negatives | 0 |
| Precision | 1.000 |
| Recall | 1.000 |
| F1 | 1.000 |
| Unavailable batches | 0 |
| Invalid batches | 0 |

The result rejects both unsafe shortcuts: retaining every document would have
created 81 false positives, while dropping every document would have created 19
false negatives. The measured model instead reproduced every collapsed oracle
decision exactly.

## Latency Result

- Total request latency: 126,206 ms
- Minimum batch latency: 6,214 ms
- p50 batch latency: 6,292 ms
- p95 batch latency: 6,464 ms
- Maximum batch latency: 6,494 ms

The earlier rejected per-document four-role run used 126,541 ms for 100
requests. Batching reduced the request count from 100 to 20, but total request
latency was effectively unchanged in these two single runs. This comparison is
diagnostic only: the output schemas and run shapes differ, and neither run is a
repeated cold/warm benchmark.

Do not derive an activation threshold from these values. The separately frozen
`rag3-support-filter-latency-decision-v1` contract reuses the existing 1,200 ms
RAG6 optional-reranker ceiling and rejects this inline candidate by 5.39x.

## Boundary

- Instrument quality: Go
- Latency decision: inline No-Go
- Shadow decision: Go
- Activation decision: rejected for v2
- Production decision: No-Go
- Promotion decision: not run

This result can freeze the two-bucket classifier shape for later evaluation. It
cannot validate or promote RAG3 because the compositional fixture has already
served other RAG2 instruments. A future promotion attempt still requires a new
untouched fixture committed only after the candidate and evaluator are frozen.

## Reproduction

```bash
fvm dart run tool/rag3_batched_support_filter_instrument.dart \
  --fixture tool/fixtures/rag2_compositional_holdout/fixture.json \
  --oracle tool/fixtures/rag2_passage_role_oracle/oracle.json \
  --out-dir build/integration_test_reports/rag3_batched_support_filter_live_2026-08-31 \
  --base-url http://192.168.100.241:1234/v1 \
  --model qwen3.8-27b-vision \
  --api-key no-key
```

The ignored machine-readable report is at
`build/integration_test_reports/rag3_batched_support_filter_live_2026-08-31/rag3_batched_support_filter_instrument.json`.
