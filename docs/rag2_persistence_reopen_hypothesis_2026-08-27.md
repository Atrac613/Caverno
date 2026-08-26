# RAG2 Persistence Reopen Hypothesis

Date: 2026-08-27
Status: persistence reopen Go; no backend selected; retrieval not evaluated;
production No-Go
Hypothesis: `rag2-persistence-reopen-contract-v1`

## Decision

A backend-neutral durable generation store can reopen the last committed
generation after a new process starts, discard a crash partial without
advancing generation, and refuse an unsupported schema without mutating the
committed record.

This is a durability Go only. It does not select SQLite, FTS5, Drift,
embeddings, retrieval, application wiring, settings, tools, prompting, or model
calls. Retrieval is not evaluated and production remains No-Go.

## Why This Hypothesis

The in-memory storage replay proved atomic apply, no-op, replacement, and
rollback. Those semantics disappear when the process exits. Selecting a
production database before reopen, crash recovery, and unknown-schema refusal
would mix backend choice with unanswered durability questions.

File-backed JSON is an instrument, not a backend decision. It exists so the
same generation contract can be reopened without choosing SQLite, FTS5, or
Drift.

## Frozen V1 Policy

The implementation must preserve all of these rules:

1. Reuse `rag2-storage-replay-contract-v1` apply, no-op, replacement, and
   rollback semantics. Do not invent a second generation protocol.
2. Persist attested chunk text inside the durable record. Report JSON and
   Markdown still omit source text, paths, declared roots, Git payloads,
   questions, and evidence markers.
3. Key each slot by project identity and declaration identity. Declaration
   identity remains the shared explicit-root hasher. Project identity remains
   a separate field and a separate hasher. Two projects with the same sorted
   roots must not share a generation slot. Applying or decoding a snapshot
   whose objects, chunks, or provenance belong to a different project fails
   closed.
4. Commit by writing `current.json.partial`. If `current.json` exists, quiesce
   it to `current.json.bak` before installing the partial as `current.json`.
   Reopen discards any leftover partial, restores `current.json.bak` when
   `current.json` is missing, and must not promote a partial to the committed
   generation. Do not delete `current.json` before the replacement is in
   place.
5. Reopen must restore generation number, snapshot hash, object identities,
   chunk identities, and attested chunk text.
6. Unknown `schemaName` or `schemaVersion` other than `1` fails closed. The
   committed file must remain byte-identical. Missing schema is not treated as
   an empty store.
7. A missing `content` field, a content-hash mismatch, a snapshot-hash
   mismatch, or an identity mismatch fails closed.
8. Unsupported schema is not rewritten into v1. Additive migration remains
   unselected until a later schema change exists.
9. Keep retrieval, backend selection, and production at No-Go.

## Synthetic Replay Contract

`tool/rag2_persistence_reopen_replay.dart` implements the frozen policy against
the existing storage fixture:

1. apply generation 1 and generation 2 in one store instance;
2. reopen generation 2 from a second instance;
3. crash before installing a replacement and prove generation 1 remains,
   including when `current.json` was already quiesced to `current.json.bak`;
4. refuse schema version 2 without mutating `current.json`;
5. isolate two project identities that share `docs` and `lib`, using snapshots
   prepared for those projects;
6. reject a snapshot whose project identity does not match the slot;
7. recreate the replay directories so the same output path can run twice; and
8. emit aggregate-only reports.

## Result

The focused replay passes. Generation 2 reopens with snapshot hash
`3d2ef68de7071779c06e45381a761edea6494f4a9207c47463503a759914d610`. A crash
partial leaves generation 1 and
`31d8769e4f33bab976367e724440209bc5d3da2c3772559522f7ea655f48c95b`. Persisted
records keep attested text that reports omit.

## Next Entry Condition

Keep this durable JSON instrument and the storage fixture frozen. A later
backend-selection hypothesis may map these reopen, crash, and fail-closed
schema rules onto SQLite, FTS5, or Drift. Do not add retrieval, settings,
tools, prompting, or application wiring.

## Verification

```bash
fvm dart format tool/rag2_persistence_reopen_replay.dart \
  tool/rag2_storage_replay.dart \
  tool/rag2_explicit_source_roots_replay.dart \
  test/tool/rag2_persistence_reopen_replay_test.dart
fvm flutter test test/tool/rag2_persistence_reopen_replay_test.dart
fvm flutter test test/tool/rag2_*_test.dart
```
