# RAG3 Compact Support-Filter Instrument Result

## Decision

Reject `rag3-compact-support-filter-v3`. The compact ordered-mask protocol
missed both frozen gates on the authorized non-promotion compositional fixture:
it produced three false positives and one false negative, and its 1,614 ms p95
latency exceeded the fixed 1,200 ms maximum by 414 ms.

Production remains No-Go and promotion was not run. Do not repeat or tune this
candidate against the same fixture.

## Frozen Run Identity

- Date: 2026-09-01
- Build commit: `5c5dbdc7b892647494e799e06000b598e9e0170b`
- Build dirty: `false`
- Contract: `rag3-compact-support-filter-v3`
- Fixture: `rag2-compositional-holdout-v1`
- Corpus hash:
  `c120cb7970ccd7277618915fca9502b0a70fe154fe75c44e0e2199cbb185a8e4`
- Oracle: `rag2-passage-role-oracle-v1`
- Endpoint: `http://192.168.100.241:1234/v1/chat/completions`
- Requested and reported model: `qwen3.8-27b-vision`
- Requests: 20, one five-document batch per query
- Query or evidence persisted: `false`
- Classifier failure reason: none
- Source report SHA-256:
  `7d13fdb8cf1760f7ba6da33fd7deef4991726dfc8679e2deb6a5accbfaeb22b6`

The user explicitly authorized sending the fixture query and document content
to this LAN endpoint. The runner sent no oracle roles, expected decisions,
qrels, or answer keys. Expected decisions were joined only after each response.

## Gate Result

| Gate | Result |
| --- | --- |
| Quality | No-Go |
| Inline latency | No-Go |
| Instrument | No-Go |
| Production | No-Go |
| Promotion | Not run |

The quality result was 18 true positives, 78 true negatives, 3 false
positives, and 1 false negative. Precision was 0.857, recall was 0.947, and F1
was 0.900. All 20 responses matched the strict compact schema, so unavailable
and invalid counts were both zero.

Three cases contained the four classification errors:

| Case | Error |
| --- | --- |
| `composition-report-format` | False positive on `docs/history.md#1` |
| `composition-history-preview` | False positive on `docs/feature_scopes.md#1` |
| `composition-history-owner` | False positive on `docs/history.md#1`; false negative on `docs/ownership.md#1` |

The v2 verbose protocol classified the same collapsed oracle perfectly. This
single run does not isolate whether the v3 quality loss came from the output
protocol, model nondeterminism, or another endpoint behavior, but it is enough
to reject v3 under the predeclared zero-error gate.

## Latency And Usage

| Measurement | Result |
| --- | ---: |
| Total end-to-end request latency | 30,240 ms |
| Minimum batch latency | 1,393 ms |
| p50 batch latency | 1,522 ms |
| p95 batch latency | 1,614 ms |
| Maximum batch latency | 1,695 ms |
| p95 maximum | 1,200 ms |
| p95 excess | 414 ms / 1.34x |
| Prompt tokens | 11,739 total; 583-598 per request |
| Completion tokens | 300 total; 15 per request |
| Mean server prompt time | 971 ms |
| Mean server generation time | 486 ms |

Compared with the v2 run, total request latency fell from 126,206 ms to
30,240 ms, a 4.17x improvement. p95 fell from 6,464 ms to 1,614 ms, a 75.0%
reduction. The compact output therefore removed substantial latency, but output
length was not the only inline constraint: prefill alone averaged 971 ms, and
the complete path still missed the frozen ceiling.

The earlier 1,094 ms synthetic check used only two evidence items and one
request. It did not establish the five-evidence 20-case p95 and cannot override
this instrument result.

## Boundary And Follow-Up

Do not wire v3 into retrieval, context budgeting, prompts, or
`search_knowledge`. Do not run promotion and do not weaken the latency or
quality gates. The existing compositional fixture is now diagnostic evidence
only and must not be used to tune another candidate.

Any further inline support-filter attempt requires a separately frozen
candidate and contract before another authorized non-promotion measurement.
The v2 classifier remains offline or asynchronous shadow evidence only; v3 is
rejected rather than promoted to that role.

## Reproduction

```bash
fvm dart run tool/rag3_compact_support_filter_instrument.dart \
  --fixture tool/fixtures/rag2_compositional_holdout/fixture.json \
  --oracle tool/fixtures/rag2_passage_role_oracle/oracle.json \
  --out-dir build/integration_test_reports/rag3_compact_support_filter_live_2026-09-01 \
  --base-url http://192.168.100.241:1234/v1 \
  --model qwen3.8-27b-vision \
  --api-key no-key
```

The ignored machine-readable report is at
`build/integration_test_reports/rag3_compact_support_filter_live_2026-09-01/rag3_compact_support_filter_instrument.json`.
