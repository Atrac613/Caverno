# RAG2 Source-Role Coverage Replay

Date: 2026-08-26
Status: v1 Go withdrawn; v2 required-source coverage contract Go; source-profile selection No-Go
Contract: `rag2-source-role-coverage-contract-v2`

## Outcome

The three measured source profiles do not retain all required evidence sources
in the frozen active-project development question set. Runtime only covers the
two runtime questions. Adding top-level documentation covers four of eight
questions. Adding tests covers six of eight but still omits tooling and
root-source evidence, while that profile also exceeds the hard file ceiling.

This result keeps source-profile selection at No-Go. It does not evaluate
retrieval, ranking, generation, answer correctness, or citation quality, and it
does not authorize storage or an application path.

## Evaluation Boundary

`tool/rag2_source_role_coverage_replay.dart` requires explicit live-replay,
project identity, project root, and fixture arguments. It reuses the bounded
source inventory and the exact profile predicates from
`tool/rag2_source_scope_measurement.dart`. It does not run Git, construct
chunks, write files, or call a model.

The immutable v1 fixture is retained as investigation history. The v2 fixture
contains eight active-project questions:

| Expected source role | Questions |
| --- | ---: |
| Runtime source | 2 |
| Top-level documentation | 2 |
| Tests | 2 |
| Tooling | 1 |
| Root sources | 1 |

Each question freezes one or more evidence sources, one or more required
markers per source, and one expected source role. All sources and markers are
required. Evidence paths must be unique across questions so repeated paths
cannot inflate question coverage.

The v1 Go is withdrawn because it performed an unbounded second read, allowed a
hard-ceiling-only eligibility interpretation, accepted only one marker per
question, and emitted no inventory identity. V2 authorizes every evidence read
through `ProjectReadPathFence`, performs one bounded byte read, rejects NUL and
malformed UTF-8, compares the read size with the inventory, and reauthorizes
the canonical path after the read. File growth and symlink substitution after
inventory fail closed.

V2 emits a metadata inventory identity over sorted candidate and exclusion
metadata and a separate content-derived identity for the validated evidence
set. Both are aggregate hashes; paths and content remain absent from the
report. The inventory identity detects metadata changes but is not an
attestation of every candidate's content.

The stdout report is aggregate-only. It contains hashed project and fixture
identities, profile corpus counts, question totals, role-level coverage, limit
decisions, and typed blockers. It omits question IDs and text, evidence paths
and markers, source text, absolute roots, and exclusion paths.

The evaluation mode is explicitly
`oracle_required_source_coverage_only`. Required source and marker presence
does not prove retrieval, complete semantic support, or answer correctness.

The discovery sampling frame remains code and Markdown (`.dart` and `.md`).
YAML, shell, Swift, Kotlin, and other source families are explicitly deferred
at No-Go rather than silently treated as covered.

Instruction-bearing files are intentionally absent from the question set.
Their source-role classification remains a safety measurement and does not make
them retrievable RAG evidence.

## Caverno Live Replay

The explicit read-only command is:

```bash
fvm dart run tool/rag2_source_role_coverage_replay.dart \
  --enable-live-replay \
  --project-id caverno-live-source-role-coverage-v2-2026-08-26 \
  --project-root "$PWD" \
  --fixture tool/fixtures/rag2_source_role_coverage_v2/fixture.json
```

The final aggregate snapshot is:

| Profile | Files | Bytes | Covered | Default limit | Hard limit | Eligibility |
| --- | ---: | ---: | ---: | --- | --- | --- |
| All-candidates control | 2,826 | 28,496,837 | 8/8 | No-Go | No-Go | No-Go |
| Runtime only | 1,116 | 9,617,137 | 2/8 | No-Go | Go | No-Go |
| Runtime + top-level docs | 1,575 | 14,062,653 | 4/8 | No-Go | Go | No-Go |
| Runtime + tests + top-level docs | 2,562 | 25,841,587 | 6/8 | No-Go | No-Go | No-Go |

All four profiles exceed the default ceiling. The all-candidates control also
exceeds the hard ceiling. Runtime-only and runtime-plus-docs fit the hard
ceiling but fail question coverage. Adding all tests still omits the tooling
and root-source questions and exceeds the hard ceiling. Default-limit overflow
is now an eligibility blocker, so a complete profile cannot become eligible
merely by fitting the hard ceiling.

## Reproducible Coverage

Synthetic tests prove:

- the all-candidates control covers eight of eight questions;
- the three comparison profiles cover two, four, and six questions;
- profile and role coverage are deterministic;
- all evidence sources for a question use all-of semantics;
- all required markers use all-of semantics;
- marker and source-role drift fail closed;
- NUL and malformed UTF-8 evidence fail closed;
- traversal paths, duplicate IDs, and duplicate evidence paths fail closed;
- post-inventory file growth and symlink substitution fail closed;
- inventory metadata changes alter the inventory identity without exposing paths;
- default-limit overflow blocks eligibility;
- explicit opt-in and file-size bounds are required; and
- report JSON omits question, path, marker, source, and root sentinels.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/tool/rag2_source_role_coverage_replay_test.dart \
  --test test/tool/rag2_source_scope_measurement_test.dart

fvm flutter test test/tool/rag2_*_test.dart
```

The source-role replay passes all 11 focused tests. The repository verifier
passes project/package static analysis, three package test suites, the focused
subset, and 10 notification-relay tests. All 102 focused RAG2 tests also pass.

## Decision and Next Entry Condition

Retain v1 as withdrawn history. Freeze the v2 eight-question development
fixture, all-of marker validation, bounded fenced read, aggregate identities,
exact three-profile comparison, default-limit eligibility rule, explicit
`.dart`/`.md` sampling frame, and current source-profile No-Go. Do not treat the
informed fixture as independent profile-promotion evidence.

The next slice should define one structural, question-independent bounded
profile candidate before creating a separate untouched active-project holdout.
The candidate must state how tooling, root sources, and tests are admitted
without using question IDs, marker text, or hand-picked paths, and it must fit
the existing default file and corpus ceilings. Apply it unchanged to the new
holdout before selecting a source scope.

Do not raise limits or add SQLite, FTS5, embeddings, prompting, routing, tools,
model calls, or application wiring from this development replay.
