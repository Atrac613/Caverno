# RAG2 Source Scope Measurement

Date: 2026-08-26
Status: measurement contract Go; scope selection No-Go
Contract: `rag2-source-scope-measurement-contract-v1`

## Outcome

The metadata-only source-scope measurement is reproducible and preserves the
frozen source-discovery walk. It does not select an allowlist, revise a limit,
run Git, construct chunks, write an index, or authorize production RAG.

The current Caverno corpus has no broad profile that both preserves the main
source roles and fits the existing file limits. Runtime sources alone exceed
the 512-file default. Adding top-level documentation remains under the 2,048
hard ceiling but makes the existing per-path Git collector require thousands of
process launches. Adding tests exceeds the hard ceiling.

## Contract Boundary

`tool/rag2_source_scope_measurement.dart` requires all of:

- `--enable-live-measurement`;
- one non-empty project identity supplied as `--project-id`; and
- one explicit `--project-root`.

It has no implicit current-directory mode. The optional `--max-file-bytes`
value defaults to 512 KiB and cannot exceed the manifest shadow's 1 MiB hard
ceiling.

The measurement reuses `inventoryRag2SourceCandidates` from the frozen source
discovery implementation. This keeps directory, symlink, generated-file,
extension, and per-file byte policies aligned with manifest discovery. The
inventory stops before limit enforcement, attestation, or Git evidence so it
can measure a corpus that exceeds the manifest limits.

The stdout JSON contains only:

- a hashed project identity and explicit selection authority;
- policy limits;
- aggregate counts and bytes by top-level scope and source role;
- three non-authoritative comparison profiles;
- aggregate exclusion counts; and
- the estimated minimum and maximum process count of the current per-path Git
  collector.

It omits individual repository-relative paths, source text, absolute roots,
chunks, Git output, and Git errors. `scopeDecision` remains `not_selected`, and
both storage and production remain No-Go.

Instruction-bearing names are measured separately from ordinary project
sources. Version 1 recognizes `AGENTS.md`, `CLAUDE.md`, `CODEX.md`, and
`FOR_ME.md` at any depth. This classification is measurement metadata only; it
does not make those files retrievable evidence.

## Reproducible Coverage

A synthetic non-Git repository proves:

- shared discovery classifies runtime, test, documentation, tooling,
  instruction-bearing, root, and other sources without invoking Git;
- package `lib/` and `test/` roots join the corresponding source roles;
- top-level counts remain deterministic;
- generated directories/files and unsupported extensions appear only as
  aggregate exclusion counts;
- individual paths, source sentinels, instruction filenames, and absolute roots
  do not appear in the JSON;
- default and hard file-limit decisions remain separate; and
- a 513-file corpus reports the expected 1,027-to-1,540 current-collector
  process range without selecting a scope.

## Caverno Live Measurement

The explicit read-only command was:

```bash
fvm dart run tool/rag2_source_scope_measurement.dart \
  --enable-live-measurement \
  --project-id caverno-live-scope-2026-08-26 \
  --project-root "$PWD"
```

The final snapshot includes this measurement tool, its test, and this report.
Exact bytes may drift when existing code or documentation changes.

| Comparison profile | Files | Bytes | Default limit | Hard limit | Estimated Git processes |
| --- | ---: | ---: | --- | --- | ---: |
| All candidates | 2,819 | 28,407,760 | No-Go | No-Go | 5,639-8,458 |
| Runtime only | 1,116 | 9,617,137 | No-Go | Go | 2,233-3,349 |
| Runtime + top-level docs | 1,572 | 14,039,330 | No-Go | Go | 3,145-4,717 |
| Runtime + tests + top-level docs | 2,557 | 25,791,033 | No-Go | No-Go | 5,115-7,672 |

The relevant top-level and role measurements are:

| Scope or role | Files | Bytes |
| --- | ---: | ---: |
| `lib` | 1,104 | 9,510,984 |
| `test` | 919 | 10,620,742 |
| `docs` | 456 | 4,422,193 |
| `tool` | 244 | 2,487,771 |
| Runtime source, including package `lib/` | 1,116 | 9,617,137 |
| Tests, including integration and package tests | 985 | 11,751,703 |
| Instruction-bearing | 3 | 48,981 |

The 494 policy exclusions comprise one oversized file, 12 generated
directories, 42 generated files, and 439 unsupported files.

## Decision and Next Entry Condition

Freeze the measurement schema, explicit opt-in, aggregate-only output, shared
inventory walk, source-role definitions, and the current scope-selection No-Go.
Do not choose a static allowlist or raise either file ceiling from these counts.

The bounded batch Git inventory entry condition is now satisfied by
`rag2-batch-git-inventory-contract-v1`. Synthetic real-repository parity holds
the process count at three while preserving clean, modified, untracked, staged,
renamed, and unusual-name semantics. The contract and evidence are recorded in
`docs/rag2_batch_git_inventory_replay_2026-08-26.md`.

The batch inventory is now integrated into the opt-in manifest shadow while
preserving its schema, limits, decisions, and zero-Git limit failure. Evidence
is recorded in `docs/rag2_batch_manifest_shadow_integration_2026-08-26.md`.

The next slice should compare answer-bearing coverage across these measured
profiles before selecting one. It must not change manifest limits, select a
source profile, add storage, add retrieval, or enter an application path.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/tool/rag2_source_scope_measurement_test.dart \
  --test test/tool/rag2_source_discovery_replay_test.dart \
  --test test/tool/rag2_source_manifest_shadow_test.dart

fvm flutter test test/tool/rag2_*_test.dart
```

The three source-scope tests and the 15-test focused acquisition subset pass.
The subsequent batch manifest integration passes project/package static
analysis and the complete 91-test focused RAG2 suite.
