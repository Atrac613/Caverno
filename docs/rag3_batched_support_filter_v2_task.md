# RAG3 Batched Support Filter V2

## Decision

Freeze `rag3-batched-support-filter-v2` as the next non-promotion instrument
contract. It is not a production candidate and does not authorize vector
persistence, `search_knowledge`, prompt injection, automatic routing, or use of
any RAG3 promotion fixture.

The rejected four-role classifier remains rejected. Its frozen 100-pair
development report produced eight role errors, but every error stayed within
one of two operational buckets:

- `retain_support`: `answer_support` or `abstention_support`
- `drop_non_support`: `topical_only` or `irrelevant`

Collapsing the already-recorded predictions into those buckets yields 21 true
positives, 79 true negatives, zero false positives, and zero false negatives.
This is diagnostic evidence for a new contract, not validation and not a reason
to reinterpret the rejected four-role gate.

## Runtime-Shaped Contract

- Placement: after lexical/vector fusion and before context budgeting
- Maximum chunks per batch: 10
- Classifier calls: one batch per query, never one request per chunk
- Input: query, corpus revision, query authority, and provenance-bearing chunks
- Output: one exact decision for every supplied chunk ID
- Decisions: `retain_support` or `drop_non_support`
- Unavailable or invalid classifier: drop every chunk and fail the instrument
- Report content: case IDs, chunk IDs, decisions, metrics, and latency only
- Excluded from classifier input: qrels, oracle roles, expected decisions,
  answer keys, and promotion data

The filter deliberately does not distinguish answer support from abstention
support. The RAG evaluator may retain that distinction in fixture truth for
scoring, but both are safe evidence to keep. It also does not distinguish
topical-only from irrelevant evidence because neither supports the requested
answer and both should be removed before context construction.

## Fixed Instrument Gate

The instrument is Go only when all conditions pass:

- false positives: 0
- false negatives: 0
- unavailable batches: 0
- invalid batches: 0

The strict cross-bucket gate protects both sides: unsupported content cannot be
retained, and answer or bounded-abstention support cannot be discarded. The
report records nearest-rank p50 and p95 batch latency, but latency is
measurement-only in this contract. The repository has no existing RAG3 runtime
SLA from which to derive an absolute threshold. The rejected per-pair run used
126,541 ms for 100 calls, or 1,265.41 ms per pair on average, which proves that
sequential classification is not the intended runtime shape but does not
justify comparing an old mean with a new batched p95. Production activation
therefore remains blocked until repeated cold/warm measurements support a
separately frozen latency contract.

## Next Instrument Dataset

Use `rag2-compositional-holdout-v1` only as non-promotion instrument data. It
contains 20 queries and 5 documents, producing 20 batch calls and 100 scored
pairs. Its existing passage-role oracle collapses to 19 `retain_support` pairs
and 81 `drop_non_support` pairs. The oracle is joined only after responses and
must never appear in a classifier request.

The dataset was not sent to the four-role classifier, but it has already served
other RAG2 instruments and is not an untouched holdout. It can qualify this
instrument and expose all-retain or all-drop shortcuts; it cannot validate or
promote a candidate. The batched HTTP runner is
`tool/rag3_batched_support_filter_instrument.dart`. It fixes the run at 20
requests with five documents per request, persists no query or evidence text,
and refuses promotion paths or a non-empty output directory. The user must
explicitly authorize transmission of the fixture query and document content to
the selected endpoint.

## Promotion Boundary

A passing compositional instrument run may freeze a candidate for a future
contract version. It cannot promote RAG3 or activate the filter. Activation
also requires a separately frozen cold/warm latency gate. Promotion requires a
newly committed, untouched fixture created only after the candidate and
evaluator are frozen.
The existing `rag3-offline-hybrid-holdout-v1` remains permanently excluded from
development, validation, and tuning.

## Instrument Result

The authorized one-shot compositional run on 2026-08-31 is quality Go: 19 true
positives, 81 true negatives, zero false positives, zero false negatives, zero
unavailable batches, and zero invalid batches. The loaded-model run recorded
p50 batch latency of 6,292 ms and p95 of 6,464 ms. The separately frozen
1,200 ms latency gate rejects inline use by 5.39x while retaining shadow
eligibility. Production remains No-Go. Evidence:
`docs/rag3_support_filter_latency_decision_2026-08-31.md`.

## Verification

```bash
dart analyze \
  tool/rag3_batched_support_filter_contract.dart \
  test/tool/rag3_batched_support_filter_contract_test.dart
fvm flutter test test/tool/rag3_batched_support_filter_contract_test.dart
fvm flutter test test/tool/rag3_batched_support_filter_instrument_test.dart
tool/codex_verify.sh
git diff --check
```
