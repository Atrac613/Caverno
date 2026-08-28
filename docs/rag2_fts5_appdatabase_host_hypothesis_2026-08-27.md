# RAG2 FTS5 AppDatabase Host

Date: 2026-08-27
Status: AppDatabase-hosted FTS5 Go; retrieval not evaluated; production No-Go
Hypothesis: `rag2-fts5-appdatabase-host-contract-v1`

## Decision

`rag2_chunk_search` can be hosted by `AppDatabase` the same way
`conversation_search` is hosted: raw SQL methods, not a Drift table, and not a
schema version bump. Schema version 5 still does not create the virtual table.
Generation apply and index replacement share one `BEGIN IMMEDIATE`
transaction. An injected commit failure and a killed uncommitted writer both
leave generation 1 and its index.

This selects AppDatabase only as the FTS5 host API. It does not add RAG2 FTS5
to the Drift migration, evaluate retrieval, or add settings, tools, prompting,
or chat/runtime wiring. Production remains No-Go.

## Why This Hypothesis

The isolated FTS5 instrument proved an identity-bound, transactional index
beside conversation-search. The remaining host question is whether that DDL
and those writes can live on `AppDatabase` and in the same apply transaction
as the generation row without rewriting LL5 rows or bumping schema version 5.

Frozen additive-schema and DAO files must keep RAG2 FTS5 absent unless a
caller opts into indexing.

## Frozen V1 Policy

The implementation must preserve all of these rules:

1. Do not bump `AppDatabase` `schemaVersion`. Do not create `rag2_chunk_search`
   in `onCreate` or `onUpgrade`. A v4-to-v5 upgrade and a generation apply
   without `indexSearch` must leave RAG2 FTS5 absent.
2. Host CREATE and slot replacement on `AppDatabase` methods. The public
   write owns `BEGIN IMMEDIATE` / `COMMIT` unless it is already inside an
   apply transaction. Do not open a second sqlite3 connection to write the
   index.
3. When `indexSearch` is true, replace that project/declaration slot in the
   same transaction as any generation upsert. A no-op apply must still
   backfill the index for the committed generation. Injected
   `beforeTxnCommit` failure must roll back both. A writer killed after the
   uncommitted generation and index writes must recover generation 1 and its
   index.
4. Bind the index to project identity, declaration identity, generation, and
   snapshot hash. Two projects that share a file must keep separate FTS5 rows.
   Every target chunk must MATCH.
5. Reopen must restore generation 2 and the same chunk ids through a new
   Drift DAO connection. Do not rewrite `embeddings`, conversation payloads,
   or model-usage rows. Leave `conversation_search` on `unicode61`.
6. Reports omit source text, paths, declared roots, Git payloads, questions,
   evidence markers, MATCH terms, and stored tokens. Record only aggregate
   booleans and counts.
7. Keep retrieval quality, no-answer policy, settings, tools, prompting, and
   production at No-Go.

## Rejected Alternatives

- Do not bump `AppDatabase` to version 6 in this slice. That would create
  RAG2 FTS5 on frozen additive-schema and DAO files.
- Do not treat this host Go as authorization to retrieve, change prompts, or
  expose `search_knowledge`.

## Synthetic Replay Contract

`tool/rag2_fts5_appdatabase_host_replay.dart` implements the frozen policy
against the existing storage fixture:

1. upgrade a v4 `AppDatabase` file and prove `rag2_chunk_search` is absent;
2. apply generation 1 and generation 2 without indexing and prove FTS5 stays
   absent;
3. no-op apply generation 2 with `indexSearch` and prove the index is
   backfilled through AppDatabase methods;
4. inject a commit failure and prove generation 2 and its index remain;
5. kill an uncommitted generation-2 apply+index and recover generation 1
   and its index;
6. isolate two project identities in one file;
7. reopen generation 2 and the same chunk ids through a new DAO connection;
8. prove conversation-search SQL and contents, embeddings, and schema
   version 5 are unchanged;
9. recreate replay files so the same output path can run twice; and
10. emit aggregate-only reports with retrieval left unevaluated.

## Result

The focused replay passes. Schema version 5 does not create RAG2 FTS5.
Generation apply without indexing leaves it absent. A later no-op apply with
`indexSearch` backfills the committed generation's slot. Opt-in indexing
writes through `AppDatabase.ensureRag2ChunkSearchTable` and
`AppDatabase.writeRag2ChunkSearchIndex`. Injected commit failure and
process-death recovery keep the previously committed generation and index.
An envelope that disagrees with the generation row fails closed. Generation
2 reopens with snapshot hash
`3d2ef68de7071779c06e45381a761edea6494f4a9207c47463503a759914d610`.
Conversation-search contents and the seeded LL5 embedding row remain
identical. `AppDatabase` stays at schema version 5.

## Next Entry Condition

Keep this AppDatabase-hosted FTS5 API, the isolated FTS5 instrument, the Drift
DAO write path, the additive schema, and the sqlite3 instrument frozen.
Incremental FTS5 indexing is recorded in
`docs/rag2_fts5_incremental_index_hypothesis_2026-08-27.md`. Retrieval quality
and no-answer policy remain independent. Do not add settings, tools,
prompting, or chat/runtime wiring.

## Verification

```bash
fvm flutter analyze
fvm dart format lib/features/chat/data/datasources/app_database.dart \
  tool/rag2_drift_dao_generation_store.dart \
  tool/rag2_fts5_additive_index_replay.dart \
  tool/rag2_fts5_appdatabase_host_replay.dart \
  test/tool/rag2_fts5_appdatabase_host_replay_test.dart \
  test/features/chat/data/datasources/app_database_migration_test.dart
fvm flutter test test/tool/rag2_fts5_appdatabase_host_replay_test.dart
fvm flutter test test/tool/rag2_fts5_additive_index_replay_test.dart
fvm flutter test test/features/chat/data/datasources/app_database_migration_test.dart
```
