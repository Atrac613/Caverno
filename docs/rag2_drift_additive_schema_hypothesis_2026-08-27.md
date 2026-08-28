# RAG2 Drift Additive Schema Mapping

Date: 2026-08-27
Status: Drift additive schema Go; FTS5 not selected; retrieval not evaluated;
production No-Go
Hypothesis: `rag2-drift-additive-schema-contract-v1`

## Decision

The frozen generation row contract maps onto `AppDatabase` as additive Drift
tables. A v4 database with LL5 embedding rows, a conversation payload, FTS5
search contents, and a model-usage row upgrades to schema version 5 without
rewriting those rows. A new `AppDatabase` connection reopens generation 2 by
selecting `rag2_generations` through Drift. A writer process that dies after an
uncommitted replacement leaves generation 1. A v4 file that has generation rows
without metadata stays at version 4.

This selects Drift only as the host schema for that contract. It does not
select RAG2 FTS5, embeddings reuse, retrieval, settings, tools, prompting, or
chat/runtime wiring. Production remains No-Go.

## Why This Hypothesis

Isolated sqlite3 proved reopen, process-death recovery, concurrent
serialization, and envelope checking. The remaining schema question is whether
those rows can live beside the production Drift tables without rewriting LL5
embedding rows or creating a RAG2 FTS5 index.

`AppDatabase` already owns conversations, chat memory, embeddings, model-usage
rows, and conversation-search FTS5. Adding RAG2 tables in a later isolated
file would not prove additive migration. Mapping the frozen row contract onto
schema version 5 keeps FTS5 and retrieval as separate decisions.

## Frozen V1 Policy

The implementation must preserve all of these rules:

1. Reuse `rag2-storage-replay-contract-v1` apply, no-op, replacement, and
   rollback, and reuse the persistence payload encoder/decoder. Do not invent a
   second snapshot format.
2. Persist attested chunk text inside the generation payload. Reports still
   omit source text, paths, declared roots, Git payloads, questions, and
   evidence markers.
3. Key each row by project identity and declaration identity. Applying or
   decoding a snapshot whose objects, chunks, or provenance belong to a
   different project fails closed.
4. Read the previous row after `BEGIN IMMEDIATE`, then `COMMIT` the
   replacement. Concurrent writers must serialize onto increasing generations.
   A writer process that dies after the uncommitted replacement write, without
   `COMMIT` or `ROLLBACK`, must leave the previous generation after SQLite
   recovers the hot journal. Same-process `ROLLBACK` is not crash recovery.
5. Reopen must restore generation number, snapshot hash, object identities,
   chunk identities, and attested chunk text from a new `AppDatabase`
   connection.
6. Store RAG2 `schema_name` / `schema_version` `1` in `rag2_store_meta`.
   Unknown names or versions fail closed. Missing metadata on a file that
   already has generation rows is not an empty store. Unsupported RAG2 schema
   is not rewritten into v1. AppDatabase schema version 5 is not a RAG2
   generation-store version.
7. Add only `rag2_store_meta` and `rag2_generations`. Do not create RAG2 FTS5
   virtual tables. Leave `conversation_search` FTS5 unchanged. Do not rewrite
   `embeddings` rows, conversation payloads, or model-usage rows during the
   v4-to-v5 upgrade or during generation apply.
8. Keep FTS5-as-retrieval, settings, tools, prompting, and production at
   No-Go.
9. SELECT every generation-row column on read. Fail closed when row envelope
   fields disagree with the payload or the store identity. Upsert every
   envelope column on replacement.

## Rejected Alternatives

- Do not add RAG2 FTS5 in this slice. Retrieval remains unevaluated.
- Do not reuse LL5 embedding rows as Knowledge Object vectors. The embeddings
  table stays conversation-search storage.
- Do not treat a Drift additive-schema Go as authorization to index, retrieve,
  change prompts, or expose settings.

## Synthetic Replay Contract

`tool/rag2_drift_additive_schema_replay.dart` implements the frozen policy
against the existing storage fixture:

1. upgrade a v4 `AppDatabase` file that already has an embedding row, a
   conversation payload, conversation-search FTS5 contents, and a model-usage
   row;
2. prove those host rows and schema version 5 survive the upgrade, and that the
   only FTS5 virtual table is `conversation_search`;
3. apply generation 1 and generation 2 through one connection;
4. reopen generation 2 from a second `AppDatabase` connection by selecting and
   decoding `rag2_generations` through Drift, not sqlite3;
5. kill a child that wrote generation 2 without `COMMIT` and prove generation 1
   remains;
6. refuse RAG2 schema version 2 without mutating the committed generation or
   embedding rows, including on a store that was already open;
7. isolate two project identities that share `docs` and `lib` in one file;
8. reject a snapshot whose project identity does not match the slot;
9. recreate replay files so the same output path can run twice;
10. emit aggregate-only reports with no RAG2 FTS5 tables; and
11. refuse a v4 file that has `rag2_generations` without `rag2_store_meta`
    without creating metadata or bumping `user_version`.

## Result

The focused replay passes. Generation 2 reopens through Drift with snapshot hash
`3d2ef68de7071779c06e45381a761edea6494f4a9207c47463503a759914d610`. Killing a
writer that left an uncommitted generation-2 replacement recovers generation 1
and `31d8769e4f33bab976367e724440209bc5d3da2c3772559522f7ea655f48c95b`. The
seeded LL5 embedding row, conversation payload, conversation-search FTS5
contents, and model-usage row remain identical. An already-open store refuses a
metadata rewrite to version 2. A v4 file with generation rows and no metadata
stays at version 4.

## Next Entry Condition

Keep this additive Drift schema and the isolated sqlite3 instrument frozen.
Drift DAO writes are recorded in
`docs/rag2_drift_dao_generation_store_hypothesis_2026-08-27.md`. Isolated FTS5
indexing is recorded in
`docs/rag2_fts5_additive_index_hypothesis_2026-08-27.md`. AppDatabase-hosted
FTS5 is recorded in
`docs/rag2_fts5_appdatabase_host_hypothesis_2026-08-27.md`. Retrieval remains
independent. Do not add settings, tools, prompting, or chat/runtime wiring.

## Verification

```bash
fvm dart format lib/features/chat/data/datasources/app_database.dart \
  lib/features/chat/data/datasources/rag2_drift_schema.dart \
  tool/rag2_drift_additive_schema_replay.dart \
  tool/rag2_drift_generation_store.dart \
  test/tool/rag2_drift_additive_schema_replay_test.dart \
  test/features/chat/data/datasources/app_database_migration_test.dart
fvm flutter test test/tool/rag2_drift_additive_schema_replay_test.dart
fvm flutter test test/features/chat/data/datasources/app_database_migration_test.dart
fvm flutter test test/tool/rag2_*_test.dart
```
