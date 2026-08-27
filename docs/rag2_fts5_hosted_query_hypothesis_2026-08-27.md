# RAG2 FTS5 Hosted Query

Date: 2026-08-27
Status: FTS5 hosted query Go; retrieval not evaluated; production No-Go
Hypothesis: `rag2-fts5-hosted-query-contract-v1`

## Decision

A hosted `rag2_chunk_search` slot can answer an identity-scoped MATCH
without bumping `AppDatabase` schema version 5. `querySearchIndex`
tokenizes the query with Dart `trigram_or_idf` terms, MATCH-queries one
project/declaration slot bound to the committed generation envelope, and
returns an ordered `List` of chunk ids. It does not rank BM25, score
abstention, or create `rag2_chunk_search` when the table is absent.

A query built from generation-2 chunk text hits a non-empty subset of
that slot, ordered by `chunk_id`. The same query against a neighbor
identity hits that neighbor's own ids and does not leak either way.
Clear hides hits. Rebuild restores them. A mismatched `snapshot_hash`
fails closed. Drop and an unindexed generation both return no ids.
Empty terms and a non-positive limit return no ids. Conversation-search
rows stay untouched.

This selects hosted MATCH reads only. It does not evaluate retrieval
quality, no-answer policy, or add settings, tools, prompting, or
chat/runtime wiring. Production remains No-Go.

## Why This Hypothesis

Rebuild/reopen proved the slot can be repaired from the generation
payload. Write, patch, clear, drop, and rebuild are recorded. The
remaining storage-adjacent question is whether that slot can be read
through MATCH without becoming a quality gate or a production retriever.
Generation apply already stores Dart trigram terms. This slice queries
those terms through one identity and refuses a stale envelope.

## Frozen V1 Policy

The implementation must preserve all of these rules:

1. Do not bump `AppDatabase` `schemaVersion`. Keep the rebuild/reopen
   API, the visibility-drop API, the incremental FTS5 index, the
   AppDatabase-hosted FTS5 API, the isolated FTS5 instrument, the Drift
   DAO write path, the additive schema, and the sqlite3 instrument
   frozen. A generation apply without `indexSearch` must still leave
   RAG2 FTS5 absent.
2. Query through `AppDatabase.queryRag2ChunkSearchChunkIds` and
   `Rag2DriftDaoGenerationStore.querySearchIndex`. Tokenize with Dart
   trigram terms. Bind the committed `generation` and `snapshot_hash`.
   Do not create `rag2_chunk_search` when it is absent. Return a
   `List<String>` ordered by `chunk_id`, not BM25 rank. Cap the result
   set. A non-positive limit returns no ids.
3. A query from generation-2 chunk text must return a non-empty subset
   of that slot's chunk ids. Empty terms must return no ids. Clear must
   hide hits. Rebuild must restore hits. Drop and an unindexed
   generation must return no ids and must not create the table. A slot
   whose envelope does not match the committed generation must return
   no ids.
4. Two projects that share a file must keep separate MATCH results.
   Querying one identity must return a non-empty subset of that
   identity's chunk ids and must not return the other's chunk ids.
   Conversation-search contents and the seeded LL5 embedding row must
   remain identical.
5. Reports omit source text, paths, declared roots, Git payloads,
   questions, evidence markers, MATCH terms, stored tokens, chunk ids,
   rowids, and stale envelope values. Record only aggregate booleans
   and hit counts.
6. Keep retrieval quality, no-answer policy, settings, tools,
   prompting, and production at No-Go. A MATCH hit count is not a
   quality gate.

## Rejected Alternatives

- Do not `ORDER BY rank` or report BM25. Ranking is a retrieval
  measurement, not this contract.
- Do not query `conversation_search` or rewrite LL5 embedding rows.
- Do not bump `AppDatabase` to version 6 or add RAG2 FTS5 to `onCreate`
  / `onUpgrade`.
- Do not treat hosted MATCH as authorization to retrieve, change
  prompts, or expose `search_knowledge`.
- Do not MATCH without the committed generation envelope. A stale
  index must fail closed.

## Synthetic Replay Contract

`tool/rag2_fts5_hosted_query_replay.dart` implements the frozen policy
against the existing storage fixture:

1. index generation 1 and generation 2 through AppDatabase-hosted apply;
2. query with generation-2 chunk text and prove a non-empty subset of
   host chunk ids ordered by `chunk_id`;
3. prove empty terms return no ids;
4. clear, prove no hits, rebuild, and prove hits return;
5. rewrite `snapshot_hash` out of band, prove the query is empty, and
   rebuild the slot;
6. query both project identities in one file and prove each result is
   a non-empty subset of that identity with no cross-leak;
7. query a generation that was never indexed and prove RAG2 FTS5 stays
   absent;
8. drop the declaration and prove the query stays empty;
9. recreate replay files so the same output path can run twice; and
10. emit aggregate-only reports with retrieval left unevaluated.

## Result

The focused replay passes. `querySearchIndex` hits the indexed slot,
hides after clear, restores after rebuild, rejects a mismatched
envelope, and keeps host and neighbor hits inside their own ids.
Querying an unindexed generation does not create `rag2_chunk_search`.
Conversation-search contents and the seeded LL5 embedding row remain
identical. `AppDatabase` stays at schema version 5.

## Next Entry Condition

Keep this hosted query API, the rebuild/reopen API, the visibility-drop
API, the incremental FTS5 index, the AppDatabase-hosted FTS5 API, the
isolated FTS5 instrument, the Drift DAO write path, the additive schema,
and the sqlite3 instrument frozen. Retrieval quality and no-answer
policy remain independent. Do not add settings, tools, prompting, or
chat/runtime wiring.

## Verification

```bash
fvm flutter analyze
fvm dart format lib/features/chat/data/datasources/app_database.dart \
  tool/rag2_drift_dao_generation_store.dart \
  tool/rag2_fts5_hosted_query_replay.dart \
  test/tool/rag2_fts5_hosted_query_replay_test.dart
fvm flutter test test/tool/rag2_fts5_hosted_query_replay_test.dart
fvm flutter test test/tool/rag2_fts5_rebuild_reopen_replay_test.dart
```
