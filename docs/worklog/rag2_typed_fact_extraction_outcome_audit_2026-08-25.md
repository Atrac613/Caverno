# RAG2 Typed Fact Extraction Outcome Audit — 2026-08-25

## Decision

Withdraw the `typed-fact-extraction-outcome-v1` contract Go. The corrected v2
instrument passes deterministic accounting, but runtime availability remains
`not_evaluated`. The outcome contract, extraction, and production remain
`no_go`, and extraction v3 must not start.

## Audit findings

V1 had two evaluation-integrity failures:

1. Its gate required three datasets, 35 unique outcomes, and zero false
   extractions, but did not require the 19 existing true positives. An extractor
   returning no facts could classify every span as unsupported and still pass.
2. Its availability guard returned `absent` when a claim relation had no mapped
   extractor family. The test for `ownership.owner` encoded this unsafe result
   even though no prose ownership extractor or completeness proof existed.

Two further limits remain explicit rather than silently treated as solved:

- annotated oracle facts identify the offline evaluation spans; runtime
  candidate discovery is not implemented;
- source-file and extractor-family blockers do not prove complete coverage for
  a claim relation or subject.

## Corrections

`typed-fact-extraction-outcome-v2` now:

- pins all three dataset IDs and corpus hashes;
- requires the 19 true positives and their per-dataset and per-family baselines;
- requires the exact 19/1/3/12 outcome distribution;
- renames `errorRate` to `falseExtractionRate`;
- fails a zero-extraction regression;
- makes unknown relations `notAvailable` without an exact relation coverage
  proof;
- permits `absent` only when every cited source has explicit complete coverage
  for that relation.

The current evaluator produces no runtime completeness proofs. Its decisions
are therefore:

- accounting: `go`
- runtime availability: `not_evaluated`
- outcome contract: `no_go`
- extraction: `no_go`
- production: `no_go`

## Preserved measurements

| Family | Spans | Extracted | Availability | False extraction |
| --- | ---: | ---: | ---: | ---: |
| Dart assignment | 11 | 10 | 0.909 | 0.000 |
| Markdown URI | 12 | 9 | 0.750 | 0.000 |
| Prose state | 12 | 0 | 0.000 | 0.000 |
| Overall | 35 | 19 | 0.543 | 0.000 |

These are regression-accounting measurements, not evidence that arbitrary
project code or Markdown has complete typed-fact coverage.

## Next entry condition

Do not implement unary-negative extraction v3. First reconcile the original
RAG2 no-answer retrieval gate with the later requirement to keep retrieval
relevance separate from semantic answerability.

Add a versioned passage-role oracle over the existing answerable and no-answer
cases with four labels: `answer_support`, `abstention_support`, `topical_only`,
and `irrelevant`. Re-score the frozen retrieval arms without changing ranking.
Then record one explicit decision:

- continue typed facts only if they are required by the revised promotion gate;
- otherwise freeze this suite as diagnostic evidence and return to the
  Knowledge Object and bounded retrieval design.
