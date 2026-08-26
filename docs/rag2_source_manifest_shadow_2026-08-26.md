# RAG2 Source Manifest Live Shadow — 2026-08-26

## Task

- Goal: connect bounded source discovery to the typed Git evidence collector
  through one explicitly enabled, metadata-only live-shadow CLI.
- User-visible behavior: none; the adapter is an offline developer tool and is
  not connected to Caverno settings, project selection, prompts, or retrieval.
- Non-goals: chunk serialization, index storage, SQLite/FTS5, embeddings,
  prompting, routing, tool registration, and model calls.

## Context

- Adapter: `tool/rag2_source_manifest_shadow.dart`
- Discovery: `tool/rag2_source_discovery_replay.dart`
- Git evidence: `tool/rag2_git_evidence_collector.dart`
- Test: `test/tool/rag2_source_manifest_shadow_test.dart`
- Predecessor: `docs/rag2_git_evidence_collector_2026-08-26.md`

## Contract

`rag2-source-manifest-shadow-contract-v1` is Go for the opt-in developer-tool
boundary. The Caverno repository's measured manifest is No-Go under the bounded
policy, and production RAG remains No-Go.

The CLI requires all of:

- `--enable-live-shadow`;
- one non-empty project identity supplied as `--project-id`; and
- one explicit `--project-root`.

It has no implicit current-directory mode. Defaults are 512 candidate files,
512 KiB per file, and 32 MiB for the candidate corpus. Hard ceilings are 2,048
files, 1 MiB per file, and 128 MiB for the corpus. Values outside those ceilings
are rejected before discovery.

The adapter reuses the frozen link-disabled source walk and typed Git collector.
It disables semantic chunk construction, writes JSON only to stdout, and does
not create an output directory or application record. The JSON contains a
hashed project identity, policy limits, repository-relative paths, byte counts,
trust, worktree state, revision, content hashes, policy exclusions, and typed
failure reasons. It omits source text, chunk data, absolute roots, Git stdout,
and Git stderr.

The report labels project selection authority as `explicit_cli_arguments`.
This developer tool does not prove that the ID came from application
persistence and therefore does not authorize an app or production path.

Expected generated, unsupported-extension, oversized-file, and symlink
exclusions may coexist with a manifest Go. Corpus/file-count violations and any
attestation or Git-evidence rejection make the manifest No-Go. Storage remains
`not_evaluated`, and production remains `no_go` in every report.

## Reproducible Coverage

Temporary real Git repositories prove:

- clean tracked, modified tracked, and untracked sources appear in deterministic
  repository-relative order;
- an invalid Dart chunk boundary does not matter because the shadow does not
  construct chunks;
- generated directories/files and unsupported extensions are excluded;
- symlinks are recorded and never followed;
- file-count overflow stops before any Git command;
- repository-root mismatch retains only a typed failure reason; and
- the report contains no source sentinel, absolute root, or `chunks` field.

## Caverno Live Preflight

One explicit read-only run against the current Caverno worktree used a
deliberately low 16-file limit:

```bash
fvm dart run tool/rag2_source_manifest_shadow.dart \
  --enable-live-shadow \
  --project-id caverno-live-shadow-2026-08-26 \
  --project-root "$PWD" \
  --max-files 16 \
  --max-file-bytes 524288 \
  --max-corpus-bytes 33554432
```

The final pre-commit snapshot measured 2,816 Markdown/Dart candidates,
28,383,371 candidate bytes, and 494 policy exclusions. It returned
`file_count_exceeded`, selected zero sources, and performed zero Git probes.
The candidate count also exceeds the v1 hard ceiling of 2,048. The exact count
and bytes may drift as repository documentation and code change; the decision
does not depend on the exact byte total.

This is a successful fail-closed live shadow, not evidence to raise the cap.
Per-path collection would require at least two Git processes for each candidate
and a third for every clean tracked source, so admitting the complete current
repository without a source-scope decision would be both broader and more
expensive than the reviewed contract.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/tool/rag2_source_manifest_shadow_test.dart \
  --test test/tool/rag2_source_discovery_replay_test.dart \
  --test test/tool/rag2_git_evidence_collector_test.dart

fvm flutter test test/tool/rag2_*_test.dart
```

The five manifest-shadow tests and the 18-test focused acquisition group pass.
Project static analysis is clean, and all 82 focused RAG2 tests pass.

## Decision and Next Entry Condition

Freeze the opt-in CLI, report schema, default/hard limits, and current live
No-Go. Do not increase the file cap directly from this one repository count.

The next slice must add one metadata-only source-scope measurement grouped by
top-level repository-relative path. It must run before Git evidence collection,
preserve the same link and extension policy, report count and bytes without
paths or source text, and compare explicit scope candidates such as `lib/`,
`docs/`, and package source roots. Only that evidence may decide whether the
live manifest should use an explicit allowlist, revised cap, or remain No-Go.
Storage and retrieval remain blocked.
