# RAG2 FTS5 Hosted Query Projection

Date: 2026-08-27
Status: FTS5 hosted query projection Go; retrieval not evaluated; production No-Go
Hypothesis: `rag2-fts5-hosted-query-projection-contract-v1`

## Decision

A hosted MATCH result can be projected onto committed generation
provenance without bumping `AppDatabase` schema version 5.
`projectSearchIndex` reads the committed generation once, MATCH-queries
that envelope, keeps MATCH order, and returns locator, content hash,
repo-relative path, revision, line span, source trust, generation, and
snapshot hash. It does not rank BM25, include chunk content, or create
`rag2_chunk_search` when the table is absent.

A query built from generation-2 chunk text projects a non-empty subset
of that slot, matching the MATCH id list. Empty terms return no hits.
An FTS row whose chunk id is missing from the payload, or whose
`object_id` or stored terms diverge from that payload, fails closed.
Host and neighbor identities each project their own ids and project
ids. An unindexed generation stays without RAG2 FTS5.
Conversation-search rows stay untouched.

This selects provenance projection only. It does not evaluate retrieval
quality, no-answer policy, or add settings, tools, prompting, or
chat/runtime wiring. Production remains No-Go.

## Why This Hypothesis

Hosted MATCH proved identity-scoped reads can return chunk ids bound to
the committed envelope. FTS rows store pretokenized terms and object
ids, not path, revision, or line spans. Those fields already live on
the generation payload. The remaining storage-adjacent question is
whether MATCH ids can be joined to that payload without becoming a
ranker or a production retriever.

## Frozen V1 Policy

The implementation must preserve all of these rules:

1. Do not bump `AppDatabase` `schemaVersion`. Keep the hosted query API,
   the rebuild/reopen API, the visibility-drop API, the incremental FTS5
   index, the AppDatabase-hosted FTS5 API, the isolated FTS5 instrument,
   the Drift DAO write path, the additive schema, and the sqlite3
   instrument frozen. A generation apply without `indexSearch` must still
   leave RAG2 FTS5 absent.
2. Project through `Rag2DriftDaoGenerationStore.projectSearchIndex`.
   Read the generation once and MATCH that envelope through
   `AppDatabase.queryRag2ChunkSearchMatchedRows`. Do not MATCH first and
   then re-read generation. Do not add ranking, BM25, or a new FTS
   column. Do not create `rag2_chunk_search` when it is absent.
3. Projected hits must preserve MATCH order and match the committed
   generation chunk for each id, including FTS `object_id` and stored
   terms. Hits must omit chunk content and carry generation plus
   snapshot hash. Paths must stay repository-relative. Empty terms must
   return no hits. Duplicate MATCH chunk ids fail closed.
4. If any MATCH id is missing from the generation payload, or an FTS
   row diverges from that payload, return no hits. Two projects that
   share a file must keep separate projected results. Conversation-search
   contents and the seeded LL5 embedding row must remain identical.
5. Reports omit source text, paths, declared roots, Git payloads,
   questions, evidence markers, MATCH terms, stored tokens, chunk ids,
   rowids, and unknown-id sentinels. Record only aggregate booleans and
   hit counts.
6. Keep retrieval quality, no-answer policy, settings, tools,
   prompting, and production at No-Go. A projected hit count is not a
   quality gate.

## Rejected Alternatives

- Do not MATCH, then re-read generation, then join. A later apply could
  attach a new payload to an older MATCH set.
- Do not join on `chunk_id` alone. A divergent `object_id` or stored
  term list must fail closed.
- Do not read path, revision, or line span from FTS. Those fields are
  not stored there.
- Do not include chunk content on the hit. Content is a retrieval and
  prompt concern.
- Do not `ORDER BY rank` or change MATCH ordering.
- Do not treat projection as authorization to retrieve, change prompts,
  or expose `search_knowledge`.

## Synthetic Replay Contract

`tool/rag2_fts5_hosted_query_projection_replay.dart` implements the
frozen policy against the existing storage fixture:

1. index generation 1 and generation 2 through AppDatabase-hosted apply;
2. MATCH and project with generation-2 chunk text and prove payload
   fields, MATCH order, omitted content, repo-relative paths, and the
   generation envelope;
3. prove empty terms return no hits;
4. insert an FTS row with a matching envelope and an unknown chunk id,
   prove MATCH sees it, and prove projection is empty;
5. rewrite `object_id` and stored terms on a MATCH id, prove MATCH still
   sees the id, and prove projection is empty;
6. project both project identities in one file and prove each result is
   a non-empty subset of that identity with matching project ids;
7. project a generation that was never indexed and prove RAG2 FTS5
   stays absent;
8. recreate replay files so the same output path can run twice; and
9. emit aggregate-only reports with retrieval left unevaluated.

## Result

The focused replay passes. `projectSearchIndex` joins MATCH ids to the
same committed generation used for MATCH, omits content, keeps
repo-relative paths, rejects an unknown or divergent FTS row, and keeps
host and neighbor hits inside their own ids. Querying an unindexed
generation does not create `rag2_chunk_search`. Conversation-search
contents and the seeded LL5 embedding row remain identical.
`AppDatabase` stays at schema version 5.

## Next Entry Condition

Keep this projection API, the hosted query API, the rebuild/reopen API,
the visibility-drop API, the incremental FTS5 index, the
AppDatabase-hosted FTS5 API, the isolated FTS5 instrument, the Drift DAO
write path, the additive schema, and the sqlite3 instrument frozen.
Retrieval quality, CJK tokenizer choice, and no-answer policy remain
independent. Do not add settings, tools, prompting, or chat/runtime
wiring.

## Verification

```bash
fvm flutter analyze
fvm dart format lib/features/chat/data/datasources/app_database.dart \
  tool/rag2_drift_dao_generation_store.dart \
  tool/rag2_fts5_hosted_query_projection_replay.dart \
  test/tool/rag2_fts5_hosted_query_projection_replay_test.dart
fvm flutter test test/tool/rag2_fts5_hosted_query_projection_replay_test.dart
fvm flutter test test/tool/rag2_fts5_hosted_query_replay_test.dart
```
