# RAG2 Drift DAO Generation Store

Date: 2026-08-27
Status: Drift DAO generation-store Go; FTS5 not selected; retrieval not
evaluated; production No-Go
Hypothesis: `rag2-drift-dao-generation-store-contract-v1`

## Decision

The frozen generation row contract can be applied and reopened through Drift
table accessors on `AppDatabase`. Generation 2 reopens from a new connection
that selects `rag2_generations` through the DAO. A writer process that dies
after an uncommitted Drift replacement leaves generation 1. Concurrent Drift
writers serialize onto increasing generations.

This selects Drift only as the write path for that frozen envelope. It does not
change the row contract, create RAG2 FTS5, reuse LL5 embedding rows, or add
settings, tools, prompting, or chat/runtime wiring. Production remains No-Go.

## Why This Hypothesis

Additive schema mapping proved the tables can live beside conversations,
embeddings, conversation-search FTS5, and model-usage rows. The remaining host
question is whether apply, reopen, crash recovery, and envelope checking still
hold when writes go through Drift `select` / `insertOnConflictUpdate` instead of
sqlite3 `execute`.

The isolated sqlite3 store stays frozen as the durability instrument. Replacing
its write path is a separate decision from retrieval. File opening stays in
`app_database_open.dart` so the generated schema can be imported from a dart VM
child without Flutter.

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
   replacement through Drift accessors. Concurrent writers must serialize onto
   increasing generations. A writer process that dies after the uncommitted
   replacement write, without `COMMIT` or `ROLLBACK`, must leave the previous
   generation after SQLite recovers the hot journal. Same-process `ROLLBACK` is
   not crash recovery. Injected `beforeCommit` failure must roll back and leave
   the previously committed generation; the persisted replay must measure that
   rollback, not only crash recovery. Concurrent writer serialization must also
   appear in the persisted JSON/Markdown `contractPassed` result.
5. Reopen must restore generation number, snapshot hash, object identities,
   chunk identities, and attested chunk text from a new `AppDatabase`
   connection by selecting through the DAO.
6. Store RAG2 `schema_name` / `schema_version` `1` in `rag2_store_meta`.
   Unknown names or versions fail closed. Missing metadata on a file that
   already has generation rows is not an empty store. Unsupported RAG2 schema
   is not rewritten into v1. AppDatabase schema version 5 is not a RAG2
   generation-store version. The row `contract` column remains
   `rag2-drift-additive-schema-contract-v1`.
7. Add no new tables. Do not create RAG2 FTS5 virtual tables. Leave
   `conversation_search` FTS5 unchanged. Do not rewrite `embeddings` rows,
   conversation payloads, or model-usage rows during generation apply.
8. Keep FTS5-as-retrieval, settings, tools, prompting, and production at
   No-Go.
9. SELECT every generation-row column on read. Fail closed when row envelope
   fields disagree with the payload or the store identity. Upsert every
   envelope column on replacement.

## Rejected Alternatives

- Do not keep sqlite3 `execute` as the AppDatabase write path. That instrument
  remains frozen separately.
- Do not add RAG2 FTS5 in this slice. Retrieval remains unevaluated.
- Do not treat a Drift DAO Go as authorization to index, retrieve, change
  prompts, or expose settings.

## Synthetic Replay Contract

`tool/rag2_drift_dao_generation_store_replay.dart` implements the frozen policy
against the existing storage fixture:

1. upgrade a v4 `AppDatabase` file that already has an embedding row, a
   conversation payload, conversation-search FTS5 contents, and a model-usage
   row;
2. apply generation 1 and generation 2 through Drift table accessors;
3. reopen generation 2 from a second `AppDatabase` connection by selecting
   `rag2_generations` through the DAO;
4. kill a child that wrote generation 2 without `COMMIT` and prove generation 1
   remains;
5. refuse RAG2 schema version 2 without mutating the committed generation or
   embedding rows, including on a store that was already open;
6. isolate two project identities that share `docs` and `lib` in one file;
7. reject a snapshot whose project identity does not match the slot;
8. inject an apply failure after generation 2 and prove the committed
   generation and hash stay generation 2;
9. serialize two concurrent child writers onto generation 2;
10. recreate replay files so the same output path can run twice;
11. emit aggregate-only reports with no RAG2 FTS5 tables; and
12. prove the reopened row is visible to Drift `select`, not only sqlite3.

## Result

The focused replay passes. Generation 2 reopens through the Drift DAO with
snapshot hash
`3d2ef68de7071779c06e45381a761edea6494f4a9207c47463503a759914d610`. Killing a
writer that left an uncommitted generation-2 replacement recovers generation 1
and `31d8769e4f33bab976367e724440209bc5d3da2c3772559522f7ea655f48c95b`. An
injected `beforeCommit` failure after generation 2 rolls back to that same
committed hash. Two concurrent child writers serialize onto generation 2. The
seeded LL5 embedding row, conversation payload, conversation-search FTS5
contents, and model-usage row remain identical. An already-open store refuses a
metadata rewrite to version 2.

## Next Entry Condition

Need this Drift DAO write path, the additive schema, and the isolated sqlite3
instrument frozen. Isolated FTS5 indexing is recorded in
`docs/rag2_fts5_additive_index_hypothesis_2026-08-27.md`. AppDatabase-hosted
FTS5 is recorded in
`docs/rag2_fts5_appdatabase_host_hypothesis_2026-08-27.md`. Retrieval remains
independent. Do not add settings, tools, prompting, or chat/runtime wiring.

## Verification

```bash
fvm flutter analyze
fvm dart format lib/features/chat/data/datasources/app_database.dart \
  lib/features/chat/data/datasources/app_database_open.dart \
  lib/features/chat/data/datasources/rag2_drift_generation_dao.dart \
  tool/rag2_drift_dao_generation_store.dart \
  tool/rag2_drift_dao_generation_store_replay.dart \
  test/tool/rag2_drift_dao_generation_store_replay_test.dart \
  test/features/chat/data/datasources/rag2_drift_generation_dao_test.dart
fvm flutter test test/features/chat/data/datasources/rag2_drift_generation_dao_test.dart
fvm flutter test test/features/chat/data/datasources/app_database_migration_test.dart
fvm flutter test test/tool/rag2_drift_dao_generation_store_replay_test.dart
fvm flutter test test/tool/rag2_*_test.dart
```
