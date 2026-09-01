# RAG3 Compact Support Filter V3

## Decision

Freeze `rag3-compact-support-filter-v3` as the next non-promotion instrument
contract. It preserves the quality-qualified two-bucket semantic decision while
replacing verbose per-chunk JSON decisions with one ordered binary mask.

Do not pursue another deterministic rank, score, lexical, or intent-rule
candidate in this slice. Existing non-promotion evidence already rejected
lexical thresholds, query-passage intent rules, and exact lexical/vector
consensus because topical evidence remained indistinguishable from answer
support. Those policies lack the semantic support signal that fixed the v2
quality residual.

## Compact Protocol

- Placement under evaluation: after hybrid fusion and before context budgeting
- Maximum chunks: 10
- Calls: one per query
- Input: query, revision, authority, and ordered provenance-bearing chunks
- Output: exact JSON object `{"schemaVersion":1,"mask":"..."}`
- Mask position: the chunk at the same `orderedEvidence` index
- Mask value `1`: `retain_support`
- Mask value `0`: `drop_non_support`
- Maximum output tokens: 32
- Invalid, incomplete, wrapped, or unavailable output: fail closed and No-Go
- Oracle roles, qrels, expected decisions, and answer keys: excluded from input

The model no longer echoes chunk IDs or decision names. The deterministic codec
checks the exact mask length and character set before mapping positions back to
stable chunk IDs. Output order is therefore part of the frozen wire contract,
not an implementation convenience.

## Fixed Gate

The instrument is Go only when all conditions pass:

- false positives: 0
- false negatives: 0
- unavailable batches: 0
- invalid batches: 0
- p95 batch latency: at most 1,200 ms

The quality gate is unchanged from v2. The latency ceiling comes from the
separately frozen `rag3-support-filter-latency-decision-v1` contract and cannot
be tuned against the result.

## Boundary

This contract and codec do not authorize a network run, production wiring, or
promotion. A dedicated HTTP runner must be committed and locally verified
before the existing non-promotion compositional fixture is measured. Any
measurement remains instrument-only because that fixture has already served
other RAG2/RAG3 work.

## Verification

```bash
dart analyze \
  tool/rag3_compact_support_filter_contract.dart \
  test/tool/rag3_compact_support_filter_contract_test.dart
fvm flutter test test/tool/rag3_compact_support_filter_contract_test.dart
tool/codex_verify.sh
git diff --check
```
