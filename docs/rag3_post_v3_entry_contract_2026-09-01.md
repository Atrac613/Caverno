# RAG3 Post-V3 Entry Contract

## Decision

Close the current RAG3 candidate families. No measured candidate is eligible
for vector persistence, `search_knowledge`, prompt injection, routing, or any
other production retrieval wiring.

Do not create a v4 candidate merely by changing thresholds, prompt wording,
output shape, retrieval depth, or fusion weights. Resume RAG3 only when a new
independent support signal or materially different serving capability can be
frozen before measurement.

## Evidence Reconciliation

| Candidate family | Result | Blocking evidence |
| --- | --- | --- |
| Frozen hybrid RRF candidate | No-Go | One unavailable case selected only irrelevant evidence on the untouched promotion fixture. |
| Lexical score and intent policies | Rejected | Topical passages were indistinguishable from answer support. |
| Exact lexical/vector consensus | Rejected | No tested depth removed all irrelevant-only unavailable results. |
| Four-role semantic classifier | No-Go | Macro F1 was 0.842 and topical-only F1 was 0.588. |
| Verbose two-bucket semantic filter | Inline No-Go | Quality passed, but p95 was 6,464 ms against the fixed 1,200 ms ceiling. |
| Compact two-bucket semantic filter | No-Go | It produced 3 false positives and 1 false negative, with p95 1,614 ms. |

The compact protocol proved that output reduction can remove substantial
latency, but it did not preserve the zero-error decision boundary and did not
meet the inline ceiling. The verbose classifier proved that the current model
can express the required semantic boundary in one measured run, but not within
the available latency budget.

These results also rule out a filterless production slice. A read-only,
explicitly invoked `search_knowledge` tool would still place unqualified
retrieval results into the model's evidence path. User or model invocation does
not repair the failed unavailable-evidence gate.

## Closed Paths

Do not:

- tune the frozen RAG3 promotion holdout or the inspected RAG1/RAG2 fixtures;
- repeat v2 or v3 to search for a favorable run;
- add lexical thresholds, intent keywords, or cross-arm agreement variants;
- weaken the zero-error support-filter gate or the 1,200 ms p95 ceiling;
- expose raw hybrid or lexical results as a production workaround;
- add vector persistence, schema migration, settings, tools, prompts, or chat
  wiring while RAG3 is blocked;
- open promotion work before a new candidate and evaluator are committed.

## Resume Conditions

RAG3 may resume only when all of these conditions are met:

1. A new support signal or serving capability is available that is materially
   different from the rejected families. Examples include a dedicated local
   relevance model or an endpoint change that can run the quality-qualified
   semantic decision inside the existing latency budget. Availability alone is
   not evidence of eligibility.
2. A new contract freezes the candidate, input boundary, output protocol,
   failure behavior, quality gates, latency gate, and privacy boundary before
   any candidate-specific fixture measurement.
3. Candidate selection uses new non-promotion development evidence. Existing
   RAG1/RAG2 instrument fixtures may remain diagnostic controls but cannot be
   tuning targets.
4. The selected candidate passes a separately authorized non-promotion
   instrument without oracle fields in classifier input and without persisting
   query or source content.
5. A new untouched promotion fixture is committed only after the candidate,
   evaluator, and gates are frozen. The existing RAG3 promotion holdout remains
   permanently excluded.

The quality boundary remains zero false positives, zero false negatives, zero
unavailable responses, and zero invalid responses for an inline support filter.
The latency boundary remains p95 at or below 1,200 ms. A future contract may add
stricter gates but cannot silently weaken these ones.

## Roadmap Consequence

RAG3 stays `blocked`, and RAG4-RAG6 remain downstream. The next repository work
should come from an independent roadmap item rather than another RAG3
experiment until the first resume condition exists.

This decision changes no runtime behavior and authorizes no network run.

## Evidence

- `docs/rag3_promotion_eval_2026-08-31.md`
- `docs/rag3_abstention_vector_instrument_2026-08-31.md`
- `docs/rag3_evidence_role_classifier_instrument_2026-08-31.md`
- `docs/rag3_support_filter_latency_decision_2026-08-31.md`
- `docs/rag3_compact_support_filter_instrument_2026-09-01.md`
