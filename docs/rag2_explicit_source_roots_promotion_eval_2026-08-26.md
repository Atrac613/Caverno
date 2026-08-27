# RAG2 Explicit Source Roots Promotion Evaluation

Date: 2026-08-26
Status: promotion scope Go; storage and production No-Go
Declaration: `caverno-routines-lifecycle-promotion-holdout-v1`
Fixture: `caverno-routines-lifecycle-promotion-eval-v1`
Contract: `rag2-explicit-complete-source-roots-v1`

## Decision

The frozen routines-lifecycle declaration passes its untouched promotion scope
evaluation. All required in-scope evidence is admitted, all declared
out-of-scope evidence is excluded, and every out-of-scope control resolves to
`not_available`.

This promotes only the explicit complete-source-roots scope contract. It does
not authorize storage, retrieval, ranking, answer generation, citation
behavior, application wiring, or production use.

## Frozen Dataset

Commit `04dd40df` froze the task context, three roots, limits, and declaration
identity before any promotion question was created. The separate evaluation
fixture contains:

- seven in-scope questions over routine representation, persistence,
  scheduling, execution, receipt settlement, and provider synchronization;
- four out-of-scope controls over routines widgets and models, settings
  persistence, and a core delivery service; and
- eight required in-scope paths plus four required out-of-scope paths.

No question or required evidence path from a development, source-role, or
structural-profile fixture was reused. The machine-readable fixture is
`tool/fixtures/rag2_explicit_source_roots_holdout_v1/evaluation.json`. Its
identity is
`fixture_e7941a66f7b4accd1366630b706c242a02caa19cbd14f5466f737dd3f808389d`.
The evaluated selected-source metadata identity is
`selected_metadata_1b56cdb02e64a82934e171a02edc3e8dab1cba5ff174bb2d1800a6a96ce01ca2`.

## Evaluator

The holdout reuses
`tool/rag2_explicit_source_roots_development_eval.dart`. It reruns live
acquisition with batch Git evidence and all-source attestation, then
classifies each frozen case from the acquisition-admitted source set. Whole-
project inventory is the existence oracle only. CI now executes that same
runner instead of a prefix-only inventory check.

The evaluator retains its generic `evaluationStage: development` and
`promotionDecision: not_evaluated` report fields. The promotion verdict in this
document is the independent gate interpretation: the declaration was frozen
first, the holdout was created afterward without reuse, and every unchanged
scope gate passed on the one-shot run.

The aggregate report omits questions and evidence paths.

## Result

| Measurement | Result |
| --- | ---: |
| Acquisition decision | Go |
| Git commands | 3 |
| Selected candidates | 15 |
| Cases | 11 |
| In-scope cases | 7 |
| Out-of-scope controls | 4 |
| Correct decisions | 11/11 |
| Required in-scope evidence admitted | 8/8 |
| Required out-of-scope evidence excluded | 4/4 |
| Unavailable oracle evidence | 0 |
| Blockers | 0 |

## Interpretation

The independent result supports complete caller-declared source roots as the
RAG2 source-scope policy. Unlike static sampling, it admits every eligible file
inside the caller's declared scope and explicitly classifies required evidence
outside that scope as unavailable.

The result tests acquisition and oracle path membership only. It does not show
that a storage schema can preserve provenance, that retrieval can find the
right evidence, or that generated answers are complete and correctly cited.

## Next Entry Condition

Live acquisition for this frozen declaration is now a CI gate. See
`docs/rag2_explicit_source_roots_acquisition_ci_2026-08-26.md`. Acquisition
and storage now share declaration identity. Persistence reopen is a
durability Go. Isolated SQLite durability is a separate Go. Drift additive
schema is a separate Go. Do not add RAG2 FTS5 or retrieval yet.
