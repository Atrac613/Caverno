# RAG2 Explicit Source Roots Development Evaluation

Date: 2026-08-26
Status: development Go; promotion not evaluated
Declaration: `caverno-chat-memory-persistence-development-v1`
Fixture: `caverno-chat-memory-persistence-development-eval-v1`
Contract: `rag2-explicit-complete-source-roots-v1`

## Decision

The frozen chat memory and conversation-persistence declaration passes its
development scope evaluation. All required in-scope evidence is admitted, all
declared out-of-scope evidence is excluded, and every out-of-scope control
resolves explicitly to `not_available`.

This is a development Go for the explicit-root scope contract only. Promotion,
storage, retrieval, ranking, answer correctness, citation quality, application
wiring, and production remain unevaluated or No-Go.

## Frozen Dataset

The fixture was created only after commit `d1d5b31a` froze the task context,
five roots, limits, and declaration identity. It contains:

- seven in-scope questions over memory representation, prompt-context gating,
  extraction fallback, atomic memory persistence, conversation cache write-
  through, semantic-index synchronization, and legacy migration;
- four out-of-scope controls over remote chat transport, drawer behavior,
  routine execution, and macOS permission handling; and
- 12 required in-scope paths plus four required out-of-scope paths.

No question from a prior source-role or structural-profile fixture was reused.
The machine-readable fixture is
`tool/fixtures/rag2_explicit_source_roots_development_v1/evaluation.json`.
Its identity is
`fixture_f8f7cd34bd7bf07f6a5f1ca187345be4dbc423a589f94771fa612225b6d36134`.
The evaluated selected-source metadata identity is
`selected_metadata_180efdf3f34ba1d4dcbaef0647097bf2673cf173d1035bf94a79eccaf2a6ce60`.

## Evaluator

`tool/rag2_explicit_source_roots_development_eval.dart` first reruns the live
explicit-root acquisition contract, including batch Git evidence and all-source
attestation. It then classifies each frozen case solely from whether every
required eligible path belongs to the complete declared-root set.

The evaluator fails closed when:

- the fixture and declaration identities disagree;
- oracle evidence is missing or ineligible;
- any required in-scope path is absent;
- any out-of-scope control path is admitted;
- an `available` or `not_available` decision differs from the oracle; or
- live acquisition does not admit the same complete candidate count.

Its report contains aggregate counts, decisions, blockers, command count, and a
fixture hash. It does not emit questions or evidence paths.

## Result

| Measurement | Result |
| --- | ---: |
| Acquisition decision | Go |
| Git commands | 3 |
| Selected candidates | 451 |
| Cases | 11 |
| In-scope cases | 7 |
| Out-of-scope controls | 4 |
| Correct decisions | 11/11 |
| Required in-scope evidence admitted | 12/12 |
| Required out-of-scope evidence excluded | 4/4 |
| Unavailable oracle evidence | 0 |
| Blockers | 0 |

The repository verifier passes project and package analysis, three package test
suites, 33 focused acquisition tests, and 10 notification-relay tests. The
complete RAG2 suite passes all 123 tests.

## Interpretation

The result supports the narrow hypothesis that caller-declared complete roots
can represent task scope without silently sampling away required files. It also
shows that evidence outside the declaration can be surfaced as unavailable
rather than treated as absent from the project.

This fixture is development evidence and cannot promote the policy. It tests
oracle path membership, not retrieval or answers. Tuning the roots or evaluator
from these results would contaminate the next promotion decision.

## Next Entry Condition

Freeze a separate realistic task context and source-root declaration before
creating or inspecting its questions. Reserve a new untouched holdout with both
in-scope and out-of-scope controls. Run the unchanged evaluator once; do not
modify this development declaration, fixture, or evaluator from holdout misses.
