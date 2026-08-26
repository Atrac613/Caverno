# RAG2 Batch Manifest Shadow Integration

Date: 2026-08-26
Status: integration contract Go; Caverno manifest and production No-Go
Contracts: `rag2-source-manifest-shadow-contract-v1`,
`rag2-batch-git-inventory-contract-v1`

## Outcome

The opt-in source manifest shadow now reuses one bounded source inventory and
collects Git evidence with the frozen three-command batch protocol. Its full
JSON output matches the preceding per-path implementation on a real temporary
repository. The report schema, discovery limits, candidate and exclusion
decisions, source text handling, storage decision, and production decision are
unchanged.

This integration resolves the Git process-count risk for an admitted manifest.
It does not select which source roles belong in Caverno RAG2, increase a limit,
construct chunks, persist an index, or enter an application path.

## Integration Boundary

`runRag2SourceManifestShadow` now performs these steps:

1. inventory candidates once with `inventoryRag2SourceCandidates`;
2. evaluate file-count and corpus-byte violations before Git;
3. for one non-empty in-bound inventory, collect all Git evidence with exactly
   one root preflight, one NUL status inventory, and one NUL stage inventory;
4. resume discovery from the existing inventory and an in-memory evidence map;
5. emit the unchanged metadata-only manifest report.

An empty inventory invokes zero Git commands. A policy violation also invokes
zero Git commands and returns the same fail-closed discovery result as before.
A batch transport, parsing, root, or evidence failure is mapped to every
affected candidate and remains a manifest No-Go.

`discoverRag2SourcesFromInventory` is the shared resumption boundary. The
existing `discoverRag2Sources` entrypoint delegates to it after inventory, so
fixture callers and the frozen per-path collector oracle retain their behavior.

## Reproducible Evidence

The manifest tests prove:

- an in-bound real repository invokes exactly three Git commands;
- the batch-backed report's complete `toJson()` value equals a report produced
  by the frozen per-path `Rag2GitEvidenceCollector`;
- clean tracked, modified tracked, and untracked source metadata is preserved;
- generated, unsupported, oversized, and symlink exclusions are preserved;
- file-count overflow invokes zero Git commands;
- root mismatch remains a typed fail-closed result; and
- report JSON contains no source text, absolute root, or Git command payload.

The oracle comparison intentionally covers the complete report instead of a
subset of fields. This detects schema drift as well as candidate, exclusion,
revision, trust, worktree-state, and decision drift.

## Caverno Live Preflight

The explicit read-only preflight command is:

```bash
fvm dart run tool/rag2_source_manifest_shadow.dart \
  --enable-live-shadow \
  --project-id caverno-live-batch-manifest-2026-08-26 \
  --project-root "$PWD" \
  --max-files 16 \
  --max-file-bytes 524288 \
  --max-corpus-bytes 33554432
```

The final snapshot measured 2,823 candidate files and 28,450,866 candidate
bytes. It returned `file_count_exceeded`, selected zero sources, and stopped
before Git because the inventory is above both the selected 16-file limit and
the 2,048-file hard ceiling. This is a fail-closed boundary check, not evidence
to raise either ceiling. Exact counts may drift as repository files change.

No smaller Caverno profile is run through the batch path. Doing so would select
a source scope before its answer-bearing coverage is measured.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/tool/rag2_source_manifest_shadow_test.dart \
  --test test/tool/rag2_source_discovery_replay_test.dart \
  --test test/tool/rag2_batch_git_inventory_replay_test.dart

fvm flutter test test/tool/rag2_*_test.dart
```

The focused integration subset passes all 18 tests. Project and package static
analysis, package tests, notification-relay tests, and all 91 focused RAG2
tests pass.

## Decision and Next Entry Condition

Freeze the single-inventory resumption boundary, pre-Git limit check,
three-command in-bound behavior, zero-Git out-of-bound behavior, full-report
per-path oracle parity, and unchanged manifest schema.

The next narrow slice should compare source-role coverage using fixed,
answer-bearing active-project questions across the already measured profiles:
runtime only, runtime plus top-level documentation, and runtime plus tests plus
top-level documentation. Keep the replay offline and aggregate-only. It must
measure whether each profile retains the evidence needed to answer each frozen
question before selecting a source scope or revising limits.

Do not add storage, FTS5, embeddings, prompting, routing, tools, model calls, or
an application path from this integration result.
