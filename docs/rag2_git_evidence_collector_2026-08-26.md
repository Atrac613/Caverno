# RAG2 Git Evidence Collector — 2026-08-26

## Task

- Goal: collect the frozen provenance contract's minimum Git evidence through
  one bounded, fail-closed, typed adapter before any live source manifest is
  allowed.
- User-visible behavior: none; the collector is not connected to the app.
- Non-goals: project selection UI, automatic workspace enumeration, manifest
  persistence, SQLite/FTS5, embeddings, prompting, routing, tools, and model
  calls.

## Context

- Collector: `tool/rag2_git_evidence_collector.dart`
- Attestation consumer: `tool/rag2_provenance_attestation_replay.dart`
- Discovery provider boundary: `tool/rag2_source_discovery_replay.dart`
- Tests: `test/tool/rag2_git_evidence_collector_test.dart` and
  `test/tool/rag2_source_discovery_replay_test.dart`
- Predecessor: `docs/rag2_source_discovery_chunking_replay_2026-08-26.md`

The previous source-discovery replay accepted caller-supplied raw Git evidence.
That was sufficient for an offline fixture, but not for a live shadow. The
existing `GitChangedPathsService` also degrades Git failures to an empty path
list, which would make unavailable evidence indistinguishable from a clean
repository. This slice adds a separate RAG2 boundary and leaves the existing
service unchanged.

## Contract

`rag2-git-evidence-collector-contract-v1` is Go for the bounded collector and
temporary-repository test surface only. A live project manifest, storage, and
production RAG remain No-Go.

The collector is constructed for one explicit `CodingProject` and:

1. canonicalizes the configured root;
2. runs `git --literal-pathspecs rev-parse --show-toplevel` and requires the
   canonical repository root to equal the canonical project root;
3. rejects invalid or control-character-bearing repository-relative paths
   before invoking Git;
4. reads one path with NUL-delimited `status --porcelain=v1` and `ls-files`
   probes using exact argument arrays and no shell;
5. obtains `HEAD:<path>` only for a clean tracked source;
6. converts valid output into `cleanTracked`, `modifiedTracked`, or `untracked`
   rather than forwarding raw porcelain to the attestation policy; and
7. rejects command startup failure, timeout, output overflow, non-zero probe
   failures, malformed UTF-8, unexpected paths, and inconsistent states.

Each command has a five-second wall-clock limit and a shared 64 KiB stdout plus
stderr retention limit. The repository preflight is cached per collector.
Failures remain typed reasons on `Rag2GitEvidenceCollection`; they are never
converted to clean evidence.

The source-discovery evaluator now accepts an asynchronous
`Rag2GitEvidenceProvider`. The frozen fixture wrapper adapts its existing map to
that provider, preserving all v1 fixture output. A future manifest shadow can
therefore collect evidence after bounded candidate enumeration without a
second filesystem walk.

## Evidence

Temporary Git repositories prove:

- clean tracked sources use a validated Git blob revision;
- modified tracked, untracked, space-bearing, Unicode, and renamed paths map to
  typed working-tree states;
- a project subdirectory is rejected as `project_not_repository_root`;
- timeout, output overflow, ambiguous status, and control-character paths fail
  closed; and
- discovery requests evidence lazily in deterministic candidate-path order.

The collector result has no serialization surface and does not expose the
configured root, command stdout, command stderr, or source text. Existing
metadata-only discovery reports remain unchanged.

## Similar-Pattern Search

- Search terms: `Process.run`, `GitCommandRunner`, `status --porcelain`,
  `runProcessBounded`, and `RepoMapService`.
- Files inspected:
  `lib/features/chat/data/datasources/git_changed_paths_service.dart`,
  `lib/core/utils/bounded_process.dart`,
  `lib/features/chat/domain/services/repo_map_service.dart`, and the RAG2
  provenance/discovery tools.
- Follow-up found: the general changed-paths service still intentionally fails
  open for Best-of-N verification and must not be reused as RAG2 attestation.
  The active-project repo map remains a prompt-oriented scanner, not a source
  manifest authority.

## Verification

```bash
tool/codex_verify.sh \
  --test test/tool/rag2_git_evidence_collector_test.dart \
  --test test/tool/rag2_source_discovery_replay_test.dart
```

The focused run passes 13 tests. The final
`fvm flutter test test/tool/rag2_*_test.dart` run passes all 77 RAG2 tests, and
project/package static analysis is clean.

## Decision and Next Entry Condition

Freeze the typed collector boundary and the fixture-map compatibility adapter.
The next slice may add one opt-in, manifest-only live-shadow adapter for an
explicitly selected `CodingProject`. It must use this collector, keep source
text and absolute roots out of reports, write no index or application storage,
and preserve generated, symlink, file-count, per-file, and corpus-limit
exclusions. No retrieval or model-facing path is authorized.
