# RAG2 FTS5 Incremental Index

Date: 2026-08-27
Status: incremental FTS5 index Go; retrieval not evaluated; production No-Go
Hypothesis: `rag2-fts5-incremental-index-contract-v1`

## Decision

A hosted `rag2_chunk_search` slot can follow the frozen Knowledge Object
delta instead of deleting the whole project/declaration slot on every
indexed apply. Unchanged chunks keep their FTS5 `rowid` and `content`.
Metadata-updated chunks rewrite stored terms. Removed chunk ids leave the
index. Added chunk ids are inserted. Envelope columns stay consistent with
the generation row so mixed generations still fail closed.

An empty slot, a missing index, or a slot that does not match the previous
generation still uses full replacement. Generation apply and the index patch
share one `BEGIN IMMEDIATE` transaction. An injected commit failure and a
killed uncommitted writer both leave the previously committed generation and
index, including unchanged rowids.

This selects incremental indexing only. It does not add RAG2 FTS5 to the
Drift migration, evaluate retrieval, or add settings, tools, prompting, or
chat/runtime wiring. Production remains No-Go.

## Why This Hypothesis

AppDatabase-hosted FTS5 proved opt-in indexing in the same apply
transaction. The remaining storage-adjacent question is the roadmap rule
that unchanged content is skipped and delete/disable removes FTS visibility.
The frozen Knowledge Object delta already names unchanged, metadata-updated,
removed, and added chunk ids. This slice applies that delta to the hosted
index without changing the generation-row envelope.

## Frozen V1 Policy

The implementation must preserve all of these rules:

1. Do not bump `AppDatabase` `schemaVersion`. Keep the hosted FTS5 API, the
   isolated FTS5 instrument, the Drift DAO write path, the additive schema,
   and the sqlite3 instrument frozen. A v4-to-v5 upgrade and a generation
   apply without `indexSearch` must still leave RAG2 FTS5 absent.
2. Patch through `AppDatabase.patchRag2ChunkSearchIndex`. Unchanged rows
   update only UNINDEXED `generation` and `snapshot_hash`. Do not rewrite
   their `content`. Metadata-updated rows rewrite `object_id` and `content`.
   Removed ids are deleted in the target project/declaration slot. Added
   rows are inserted. Prove skip with stable FTS5 `rowid` values for
   unchanged chunk ids, using a second indexed project so a slot-wide
   DELETE would reassign ids.
3. An empty slot, a missing index, or a slot whose chunk ids disagree with
   the previous generation must full-replace. Opt-in `indexSearch` still
   writes the generation row and index in one transaction. Injected
   `beforeTxnCommit` failure must roll back both. A writer killed after the
   uncommitted generation and index writes must recover generation 1, its
   chunk ids, and its unchanged rowids.
4. Bind the index to project identity, declaration identity, generation, and
   snapshot hash. Every target chunk must MATCH. Reopen must restore
   generation 2, the same chunk ids, and the same unchanged rowids through a
   new Drift DAO connection.
5. Reports omit source text, paths, declared roots, Git payloads, questions,
   evidence markers, MATCH terms, stored tokens, chunk ids, and rowids.
   Record only aggregate booleans and counts, including unchanged /
   metadata-updated / removed / added counts from the frozen fixture delta.
6. Keep retrieval quality, no-answer policy, settings, tools, prompting, and
   production at No-Go.

## Rejected Alternatives

- Do not keep mixed generations on unchanged rows. The envelope would fail
  closed even when the skip itself succeeded.
- Do not bump `AppDatabase` to version 6 or add RAG2 FTS5 to `onCreate` /
  `onUpgrade`.
- Do not treat incremental indexing as authorization to retrieve, change
  prompts, or expose `search_knowledge`.

## Synthetic Replay Contract

`tool/rag2_fts5_incremental_index_replay.dart` implements the frozen policy
against the existing storage fixture:

1. upgrade a v4 `AppDatabase` file and full-replace generation 1 into an
   empty slot;
2. index a second project in the same file so a slot-wide DELETE would
   reassign FTS5 `rowid` values;
3. apply generation 2 with `indexSearch` and prove unchanged chunk `rowid`
   and `content` values are preserved, removed ids are gone, and added ids
   are present;
4. inject a commit failure and prove generation 2 and its rowids remain;
5. kill an uncommitted generation-2 incremental apply and recover
   generation 1 and its rowids;
6. reopen generation 2, the same chunk ids, and the same rowids through a
   new DAO connection;
7. prove conversation-search SQL and contents, embeddings, and schema
   version 5 are unchanged;
8. recreate replay files so the same output path can run twice; and
9. emit aggregate-only reports with retrieval left unevaluated.

## Result

The focused replay passes. Generation 1 still full-replaces an empty slot.
Generation 2 patches from the frozen Knowledge Object delta: 2 unchanged,
2 metadata-updated, 1 removed, and 1 added. Unchanged FTS5 `rowid` values
and stored terms survive the patch, reopen, injected commit failure, and
process-death recovery. Every chunk MATCHES. Generation 2 reopens with
snapshot hash
`3d2ef68de7071779c06e45381a761edea6494f4a9207c47463503a759914d610`.
Conversation-search contents and the seeded LL5 embedding row remain
identical. `AppDatabase` stays at schema version 5.

## Next Entry Condition

Keep this incremental FTS5 index, the AppDatabase-hosted FTS5 API, the
isolated FTS5 instrument, the Drift DAO write path, the additive schema,
and the sqlite3 instrument frozen. Retrieval quality and no-answer policy
remain independent. Do not add settings, tools, prompting, or chat/runtime
wiring.

## Verification

```bash
fvm flutter analyze
fvm dart format lib/features/chat/data/datasources/app_database.dart \
  tool/rag2_drift_dao_generation_store.dart \
  tool/rag2_fts5_incremental_index_replay.dart \
  test/tool/rag2_fts5_incremental_index_replay_test.dart
fvm flutter test test/tool/rag2_fts5_incremental_index_replay_test.dart
fvm flutter test test/tool/rag2_fts5_appdatabase_host_replay_test.dart
```
