# RAG2 SQLite Durability Mapping

Date: 2026-08-27
Status: SQLite durability Go; Drift not selected; FTS5 not selected; retrieval
not evaluated; production No-Go
Hypothesis: `rag2-sqlite-durability-contract-v1`

## Decision

The frozen generation, reopen, crash, and unknown-schema rules map onto an
isolated SQLite file through `package:sqlite3`. A new connection reopens
generation 2. A writer process that dies after an uncommitted replacement
leaves generation 1 after SQLite recovers the hot journal. An unsupported store
schema fails closed without mutating committed rows.

This selects SQLite only as the durability substrate for that contract. It does
not select Drift, FTS5, embeddings, retrieval, settings, tools, prompting, or
application wiring. Production remains No-Go.

## Why This Hypothesis

File-backed JSON proved the durability semantics. The remaining backend
question is whether those semantics survive a real database transaction without
mixing in retrieval indexing or the production Drift schema.

SQLite is already in Caverno. FTS5 is a retrieval index, not a generation
store. Drift owns the application database and would require generated tables
in `lib/`. Mapping durability first onto an isolated `sqlite3` file keeps those
choices separate.

## Frozen V1 Policy

The implementation must preserve all of these rules:

1. Reuse `rag2-storage-replay-contract-v1` apply, no-op, replacement, and
   rollback, and reuse the persistence payload encoder/decoder. Do not invent a
   second snapshot format.
2. Persist attested chunk text inside the SQLite payload. Reports still omit
   source text, paths, declared roots, Git payloads, questions, and evidence
   markers.
3. Key each row by project identity and declaration identity. Applying or
   decoding a snapshot whose objects, chunks, or provenance belong to a
   different project fails closed.
4. Read the previous row after `BEGIN IMMEDIATE`, then `COMMIT` the
   replacement. Concurrent writers must serialize onto increasing generations.
   A writer process that dies after the uncommitted replacement write, without
   `COMMIT` or `ROLLBACK`, must leave the previous generation after SQLite
   recovers the hot journal. Do not delete the prior row before the replacement
   commits. Same-process `ROLLBACK` is not crash recovery.
5. Reopen must restore generation number, snapshot hash, object identities,
   chunk identities, and attested chunk text from a new database connection.
6. Store `schema_name` / `schema_version` `1` in a metadata table. Unknown
   names or versions fail closed. Missing metadata on a file that already has
   generation rows is not an empty store. Unsupported schema is not rewritten
   into v1.
7. Use an isolated SQLite file. Do not open or migrate `AppDatabase`, add
   Drift tables, or create FTS5 virtual tables.
8. Keep Drift, FTS5, retrieval, and production at No-Go.
9. SELECT every generation-row column on read. Fail closed when row envelope
   fields disagree with the payload or the store identity. Upsert every
   envelope column on replacement.

## Rejected Alternatives

- Do not add FTS5 in this slice. Retrieval remains unevaluated.
- Do not add RAG2 tables to the production Drift schema. That is application
  wiring and a later additive-migration question.
- Do not treat a SQLite durability Go as authorization to index, retrieve, or
  change prompts.

## Synthetic Replay Contract

`tool/rag2_sqlite_durability_replay.dart` implements the frozen policy against
the existing storage fixture:

1. apply generation 1 and generation 2 through one connection;
2. reopen generation 2 from a second connection;
3. kill a child that wrote generation 2 without `COMMIT` and prove generation 1
   remains;
4. refuse schema version 2 without mutating the committed generation;
5. isolate two project identities that share `docs` and `lib` in one file;
6. reject a snapshot whose project identity does not match the slot;
7. recreate replay files so the same output path can run twice; and
8. emit aggregate-only reports with no FTS5 tables.

## Result

The focused replay passes. Generation 2 reopens with snapshot hash
`3d2ef68de7071779c06e45381a761edea6494f4a9207c47463503a759914d610`. Killing a
writer that left an uncommitted generation-2 replacement recovers generation 1
and `31d8769e4f33bab976367e724440209bc5d3da2c3772559522f7ea655f48c95b`.

## Next Entry Condition

Keep this isolated SQLite instrument frozen. A later Drift additive-schema
hypothesis may map the same row contract onto `AppDatabase` without rewriting
LL5 embedding rows. FTS5 and retrieval remain independent. Do not add
settings, tools, prompting, or application wiring.

## Verification

```bash
fvm dart format tool/rag2_sqlite_durability_replay.dart \
  test/tool/rag2_sqlite_durability_replay_test.dart
fvm flutter test test/tool/rag2_sqlite_durability_replay_test.dart
fvm flutter test test/tool/rag2_*_test.dart
```
