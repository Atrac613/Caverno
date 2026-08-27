# RAG2 FTS5 Rebuild Reopen

Date: 2026-08-27
Status: FTS5 rebuild/reopen Go; retrieval not evaluated; production No-Go
Hypothesis: `rag2-fts5-rebuild-reopen-contract-v1`

## Decision

A hosted `rag2_chunk_search` slot can be repaired from the committed
generation payload without bumping `AppDatabase` schema version 5 or the
generation number. `rebuildSearchIndex` full-replaces the target
project/declaration slot from stored chunks. An empty slot after
`clearSearchIndex`, a mismatched envelope, and a generation that was never
indexed all become the same MATCH-visible index. Rebuilding twice and
reopening a new DAO connection keep generation 2 and the same envelope,
terms, and MATCH count.

If no generation exists, rebuild is a no-op and does not invent FTS rows.
An injected commit failure leaves the previous slot, including a stale
envelope. A writer killed after an uncommitted rebuild of a cleared slot
recovers generation 2 with MATCH still returning zero rows. A neighbor
project in the same file keeps its index.

This selects rebuild/reopen determinism only. It does not add RAG2 FTS5 to
the Drift migration, evaluate retrieval, or add settings, tools, prompting,
or chat/runtime wiring. Production remains No-Go.

## Why This Hypothesis

Visibility drop proved a slot can be hidden or removed. Incremental apply
already full-replaces when a later snapshot sees a mismatched slot. The
remaining roadmap rule is that rebuild and reopen are deterministic: repair
must read the committed generation payload, not require a new snapshot
apply, and a new connection must see the repaired slot without mutation.

## Frozen V1 Policy

The implementation must preserve all of these rules:

1. Do not bump `AppDatabase` `schemaVersion`. Keep the visibility-drop API,
   the incremental FTS5 index, the AppDatabase-hosted FTS5 API, the isolated
   FTS5 instrument, the Drift DAO write path, the additive schema, and the
   sqlite3 instrument frozen. A generation apply without `indexSearch` must
   still leave RAG2 FTS5 absent until an explicit rebuild.
2. Rebuild through `Rag2DriftDaoGenerationStore.rebuildSearchIndex`. Full-
   replace from the stored generation payload. Do not bump generation. Do
   not require the caller to pass a snapshot.
3. Rebuild of a cleared or mismatched slot must restore envelope,
   pretokenized terms, and MATCH count for generation 2. Rebuild of an
   unindexed generation may create `rag2_chunk_search`. Rebuild with no
   generation must not create FTS rows for that identity.
4. Rebuild twice must keep the same envelope, terms, and MATCH count.
   Reopen through a new DAO connection must keep generation 2 and that
   slot. Injected `beforeTxnCommit` failure must leave the previous slot.
   A writer killed after an uncommitted rebuild of a cleared slot must
   recover generation 2 with an empty slot. `--rebuild-uncommitted` cannot
   be combined with `--index-search` or `--drop-uncommitted`.
5. Two projects that share a file must keep separate FTS5 rows. Rebuilding
   one identity must not hide the other. Reports omit source text, paths,
   declared roots, Git payloads, questions, evidence markers, MATCH terms,
   stored tokens, chunk ids, rowids, and injected stale hashes. Record only
   aggregate booleans and counts.
6. Keep retrieval quality, no-answer policy, settings, tools, prompting,
   and production at No-Go. MATCH agreement with stored chunks is not a
   quality gate.

## Rejected Alternatives

- Do not treat indexed no-op apply as the rebuild API. Rebuild must read
  the committed payload without a new snapshot argument.
- Do not bump `AppDatabase` to version 6 or add RAG2 FTS5 to `onCreate` /
  `onUpgrade`.
- Do not increment generation on rebuild. Repair is not a new snapshot.
- Do not treat rebuild/reopen as authorization to retrieve, change
  prompts, or expose `search_knowledge`.

## Synthetic Replay Contract

`tool/rag2_fts5_rebuild_reopen_replay.dart` implements the frozen policy
against the existing storage fixture:

1. index generation 1 and generation 2 through AppDatabase-hosted apply;
2. clear the slot and rebuild from the stored payload;
3. mismatch the envelope and rebuild without bumping generation;
4. rebuild again and prove the slot still matches;
5. inject a rebuild failure and prove the previous slot remains;
6. reopen generation 2 and the repaired slot through a new DAO connection;
7. rebuild one of two project identities in one file and prove the neighbor
   index remains;
8. drop the generation and prove rebuild does not invent FTS rows;
9. rebuild a generation that was never indexed and prove the slot is
   created from the payload;
10. kill an uncommitted rebuild of a cleared slot and recover generation 2
    with MATCH still empty;
11. recreate replay files so the same output path can run twice; and
12. emit aggregate-only reports with retrieval left unevaluated.

## Result

The focused replay passes. `rebuildSearchIndex` repairs a cleared or
mismatched slot from generation 2 without a new snapshot. Rebuild twice and
reopen keep the same envelope, terms, and MATCH count. Injected commit
failure and process-death recovery leave the previous slot. A neighbor
project stays visible. Rebuild with no generation does not invent rows.
Rebuild of an unindexed generation creates `rag2_chunk_search` from the
payload. Conversation-search contents and the seeded LL5 embedding row
remain identical. `AppDatabase` stays at schema version 5.

## Next Entry Condition

Keep this rebuild/reopen API, the visibility-drop API, the incremental FTS5
index, the AppDatabase-hosted FTS5 API, the isolated FTS5 instrument, the
Drift DAO write path, the additive schema, and the sqlite3 instrument
frozen. Hosted MATCH query is recorded in
`docs/rag2_fts5_hosted_query_hypothesis_2026-08-27.md`. Retrieval quality
and no-answer policy remain independent. Do not add settings, tools,
prompting, or chat/runtime wiring.

## Verification

```bash
fvm flutter analyze
fvm dart format tool/rag2_drift_dao_generation_store.dart \
  tool/rag2_fts5_rebuild_reopen_replay.dart \
  test/tool/rag2_fts5_rebuild_reopen_replay_test.dart
fvm flutter test test/tool/rag2_fts5_rebuild_reopen_replay_test.dart
fvm flutter test test/tool/rag2_fts5_visibility_drop_replay_test.dart
```
