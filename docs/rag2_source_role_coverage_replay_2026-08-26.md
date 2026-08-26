# RAG2 Source-Role Coverage Replay

Date: 2026-08-26
Status: oracle coverage contract Go; source-profile selection No-Go
Contract: `rag2-source-role-coverage-contract-v1`

## Outcome

The three measured source profiles do not retain all answer-bearing evidence in
the frozen active-project question set. Runtime only covers the two runtime
questions. Adding top-level documentation covers four of eight questions.
Adding tests covers six of eight but still omits tooling and root-source
evidence, while that profile also exceeds the hard file ceiling.

This result keeps source-profile selection at No-Go. It does not evaluate
retrieval, ranking, generation, answer correctness, or citation quality, and it
does not authorize storage or an application path.

## Evaluation Boundary

`tool/rag2_source_role_coverage_replay.dart` requires explicit live-replay,
project identity, project root, and fixture arguments. It reuses the bounded
source inventory and the exact profile predicates from
`tool/rag2_source_scope_measurement.dart`. It does not run Git, construct
chunks, write files, or call a model.

The versioned fixture contains eight active-project questions:

| Expected source role | Questions |
| --- | ---: |
| Runtime source | 2 |
| Top-level documentation | 2 |
| Tests | 2 |
| Tooling | 1 |
| Root sources | 1 |

Each question freezes one expected repository-relative evidence path, one
bounded content marker, and the expected source role. Replay fails closed when
a path is outside the source inventory, a marker disappears, a role changes,
an ID is duplicated, or fixture input is malformed. This proves that the
oracle path still contains answer-bearing evidence before profile membership
is counted.

The stdout report is aggregate-only. It contains hashed project and fixture
identities, profile corpus counts, question totals, role-level coverage, limit
decisions, and typed blockers. It omits question IDs and text, evidence paths
and markers, source text, absolute roots, and exclusion paths.

The evaluation mode is explicitly `oracle_path_coverage_only`. A path being
present does not prove that a retriever can find it or that a model can answer
from it.

Instruction-bearing files are intentionally absent from the question set.
Their source-role classification remains a safety measurement and does not make
them retrievable RAG evidence.

## Caverno Live Replay

The explicit read-only command is:

```bash
fvm dart run tool/rag2_source_role_coverage_replay.dart \
  --enable-live-replay \
  --project-id caverno-live-source-role-coverage-2026-08-26 \
  --project-root "$PWD" \
  --fixture tool/fixtures/rag2_source_role_coverage/fixture.json
```

The final aggregate snapshot is:

| Profile | Files | Bytes | Covered questions | Hard limit | Eligibility |
| --- | ---: | ---: | ---: | --- | --- |
| All-candidates control | 2,826 | 28,481,506 | 8/8 | No-Go | No-Go |
| Runtime only | 1,116 | 9,617,137 | 2/8 | Go | No-Go |
| Runtime + top-level docs | 1,575 | 14,060,061 | 4/8 | Go | No-Go |
| Runtime + tests + top-level docs | 2,562 | 25,832,072 | 6/8 | No-Go | No-Go |

The all-candidates control proves every frozen evidence path and marker is
present, but it exceeds the hard ceiling. Runtime-only and runtime-plus-docs
fit the hard ceiling but fail question coverage. Adding all tests still omits
the tooling and root-source questions and also exceeds the hard ceiling.

## Reproducible Coverage

Synthetic tests prove:

- the all-candidates control covers eight of eight questions;
- the three comparison profiles cover two, four, and six questions;
- profile and role coverage are deterministic;
- marker and source-role drift fail closed;
- traversal paths and duplicate IDs fail closed;
- explicit opt-in and file-size bounds are required; and
- report JSON omits question, path, marker, source, and root sentinels.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/tool/rag2_source_role_coverage_replay_test.dart \
  --test test/tool/rag2_source_scope_measurement_test.dart

fvm flutter test test/tool/rag2_*_test.dart
```

The focused subset passes all eight tests. Project and package static analysis,
package tests, notification-relay tests, and all 96 focused RAG2 tests pass.

## Decision and Next Entry Condition

Freeze the eight-question development fixture, marker validation,
aggregate-only report, exact three-profile comparison, and current
source-profile No-Go. Do not treat the informed fixture as independent profile
promotion evidence.

The next slice should define one structural, question-independent bounded
profile candidate before creating a separate untouched active-project holdout.
The candidate must state how tooling, root sources, and tests are admitted
without using question IDs, marker text, or hand-picked paths, and it must fit
the existing hard file and corpus ceilings. Apply it unchanged to the new
holdout before selecting a source scope.

Do not raise limits or add SQLite, FTS5, embeddings, prompting, routing, tools,
model calls, or application wiring from this development replay.
