# RAG2 Explicit Source Roots Acquisition CI Gate

Date: 2026-08-26
Status: acquisition CI Go; identity aligned; persistence reopen Go; sqlite durability Go; drift additive schema Go
Contract: `rag2-explicit-complete-source-roots-v1`

## Decision

Both frozen explicit-root declarations now rerun live acquisition in CI: whole-
project inventory, complete in-root selection, three-command batch Git
evidence, and all-source attestation. Question scoring uses the admitted
source set from that acquisition, not a second filesystem walk or a duplicated
path-prefix oracle.

This encodes the existing acquisition contract in the focused test suite. It
does not freeze a checkout-specific selected-metadata hash, change production
behavior, select a persistence backend, or evaluate retrieval.

## Why This Gate

The development and promotion evaluators already called
`runRag2ExplicitSourceRootsReplay` from the CLI. The committed tests did not.
They inventoried eligible files and classified required paths with an
independent `_pathIsWithinRoots` helper. That helper could mark a file
available even when Git evidence or attestation would have rejected the
declaration. Count-only coupling in the CLI could also hide a mismatched
admitted set.

## Frozen Inputs

The declarations, roots, and question fixtures remain the previously frozen
snapshots. CI pins declaration identity (contract plus sorted roots) and the
question gates. It does not pin selected-metadata identity or admitted-file
counts. Those hashes and counts are checkout observations and may change when
eligible files under the frozen roots are added, removed, or resized.

The CI gate requires:

- live acquisition Go with exactly three Git commands;
- `admittedSourceCount == eligibleCandidateFileCount`;
- admitted count at or below the unchanged default file ceiling;
- every required in-scope evidence path admitted; and
- every required out-of-scope control excluded.

## Evaluator

`tool/rag2_explicit_source_roots_development_eval.dart` shares one runner with
the tests. The runner:

1. executes `runRag2ExplicitSourceRootsReplay` against the checkout root;
2. keeps inventory and admitted paths on the evaluation run envelope, not on
   the metadata acquisition report;
3. scores each frozen case from those admitted paths;
4. uses the whole-project inventory only as the existence oracle; and
5. fails closed when acquisition is not Go, declaration identity diverges,
   admitted count differs from eligible count, an admitted path is absent from
   inventory, in-scope evidence is omitted, or an out-of-scope control is
   admitted.

Acquisition metadata reports omit inventory and admitted paths. Aggregate
evaluation output still omits questions and evidence paths.

## Result

Observed on this checkout; not CI pins:

| Measurement | Development | Promotion |
| --- | ---: | ---: |
| Acquisition decision | Go | Go |
| Git commands | 3 | 3 |
| Admitted sources | 451 | 15 |
| Correct decisions | 11/11 | 11/11 |
| Required in-scope evidence admitted | 12/12 | 8/8 |
| Required out-of-scope evidence excluded | 4/4 | 4/4 |
| Blockers | 0 | 0 |

The focused tests also prove that dropping an attested in-scope path from the
admitted set fails completeness, and that an admitted path missing from
inventory fails closed.

## Decision Boundary

This gate proves that CI reruns Git-backed, attested acquisition for the two
frozen declarations and that scope questions are classified from that admitted
set. It does not freeze the current admitted-file snapshot, prove retrieval,
ranking, answer correctness, citation quality, durable storage, crash
recovery, or production readiness.

Acquisition and storage now share declaration identity for the same sorted
roots. Persistence reopen is a separate Go; see
`docs/rag2_persistence_reopen_hypothesis_2026-08-27.md`. Isolated SQLite
durability is recorded in
`docs/rag2_sqlite_durability_hypothesis_2026-08-27.md`. Drift additive schema
is recorded in `docs/rag2_drift_additive_schema_hypothesis_2026-08-27.md`. Do
not add RAG2 FTS5, retrieval, settings, tools, or chat/runtime wiring.

## Verification

```bash
fvm dart format tool/rag2_explicit_source_roots_replay.dart \
  tool/rag2_explicit_source_roots_development_eval.dart \
  test/tool/rag2_explicit_source_roots_replay_test.dart \
  test/tool/rag2_explicit_source_roots_development_eval_test.dart \
  test/tool/rag2_explicit_source_roots_promotion_eval_test.dart
fvm flutter test \
  test/tool/rag2_explicit_source_roots_replay_test.dart \
  test/tool/rag2_explicit_source_roots_development_eval_test.dart \
  test/tool/rag2_explicit_source_roots_promotion_eval_test.dart
fvm flutter test test/tool/rag2_*_test.dart
```

## Next Entry Condition

Acquisition and storage now share declaration identity for the same sorted
roots. See `docs/rag2_storage_replay_contract_2026-08-26.md`. Persistence
reopen is recorded in
`docs/rag2_persistence_reopen_hypothesis_2026-08-27.md`. Isolated SQLite
durability is recorded in
`docs/rag2_sqlite_durability_hypothesis_2026-08-27.md`. Drift additive schema
is recorded in `docs/rag2_drift_additive_schema_hypothesis_2026-08-27.md`. Do
not add RAG2 FTS5, settings, tools, prompting, or chat/runtime wiring.
