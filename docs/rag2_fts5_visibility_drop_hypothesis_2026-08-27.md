# RAG2 FTS5 Visibility Drop

Date: 2026-08-27
Status: FTS5 visibility drop Go; retrieval not evaluated; production No-Go
Hypothesis: `rag2-fts5-visibility-drop-contract-v1`

## Decision

A hosted `rag2_chunk_search` slot can lose FTS visibility without bumping
`AppDatabase` schema version 5. `clearSearchIndex` deletes that
project/declaration slot and leaves the generation row. This is a visibility
clear, not a durable disable flag; a later indexed apply may restore the
slot. `drop` deletes the generation row and the slot in the same
`BEGIN IMMEDIATE` transaction. MATCH then returns no rows for the target
identity. A neighbor project in the same file keeps its index. An injected
commit failure and a killed uncommitted drop both restore generation 2 and
its envelope, pretokenized terms, and MATCH count.

This selects drop/clear visibility only. It does not add RAG2 FTS5 to
the Drift migration, evaluate retrieval, or add settings, tools, prompting,
or chat/runtime wiring. Production remains No-Go.

## Why This Hypothesis

Incremental indexing proved unchanged content is skipped and removed chunk
ids leave a live slot. The remaining roadmap rule is that drop/clear
removes FTS visibility. Generation apply already knows how to share a
transaction with index writes. This slice adds the inverse: hide or remove
the slot without rewriting conversation-search or LL5 rows.

## Frozen V1 Policy

The implementation must preserve all of these rules:

1. Do not bump `AppDatabase` `schemaVersion`. Keep the incremental FTS5
   index, the AppDatabase-hosted FTS5 API, the isolated FTS5 instrument,
   the Drift DAO write path, the additive schema, and the sqlite3
   instrument frozen. A generation apply without `indexSearch` must still
   leave RAG2 FTS5 absent.
2. Clear through `AppDatabase.clearRag2ChunkSearchIndex`. Do not create
   `rag2_chunk_search` when the table is absent. DELETE is scoped to the
   target project and declaration identities.
3. `clearSearchIndex` must keep generation 2 and make MATCH return zero
   rows. This is not a durable disable flag. A later no-op apply with
   `indexSearch` may restore the slot. `drop` must remove the generation
   row and the slot together. Dropping a generation that was never indexed
   must leave RAG2 FTS5 absent.
4. Injected `beforeTxnCommit` failure must roll back both the generation
   row and the index, including envelope, pretokenized terms, and MATCH
   count. A writer killed after an uncommitted drop must recover generation
   2 and that same index envelope. `--drop-uncommitted` cannot be combined
   with `--index-search`.
5. Two projects that share a file must keep separate FTS5 rows. Dropping
   one identity must not hide the other. Neighbor recovery must match
   envelope, terms, and MATCH count for the neighbor generation. Reopen
   after drop must keep the generation absent. Reports omit source text,
   paths, declared roots, Git payloads, questions, evidence markers, MATCH
   terms, stored tokens, chunk ids, and rowids. Record only aggregate
   booleans and counts.
6. Keep retrieval quality, no-answer policy, settings, tools, prompting,
   and production at No-Go. MATCH returning zero rows is not a quality gate.

## Rejected Alternatives

- Do not drop the virtual table itself. Neighbor slots in the same file
  would lose visibility.
- Do not bump `AppDatabase` to version 6 or add RAG2 FTS5 to `onCreate` /
  `onUpgrade`.
- Do not persist a search-disabled flag. Schema version 5 has no place for
  it, and a later indexed apply may restore the slot.
- Do not treat visibility drop as authorization to retrieve, change
  prompts, or expose `search_knowledge`.

## Synthetic Replay Contract

`tool/rag2_fts5_visibility_drop_replay.dart` implements the frozen policy
against the existing storage fixture:

1. index generation 1 and generation 2 through AppDatabase-hosted apply;
2. clear the slot and prove generation 2 remains while MATCH returns
   zero rows;
3. no-op apply with `indexSearch` and prove the slot is restored,
   including envelope, terms, and MATCH count;
4. inject a drop failure and prove generation 2 and its index envelope
   remain;
5. drop the declaration and prove the generation row and slot are gone
   through a new DAO connection;
6. drop one of two project identities in one file and prove the neighbor
   index envelope remains;
7. drop a generation that was never indexed and prove RAG2 FTS5 stays
   absent;
8. kill an uncommitted drop and recover generation 2 and its index
   envelope;
9. recreate replay files so the same output path can run twice; and
10. emit aggregate-only reports with retrieval left unevaluated.

## Result

The focused replay passes. `clearSearchIndex` hides MATCH while generation 2
remains. A later indexed no-op apply restores the slot. `drop` removes the
generation row and FTS visibility together. Injected commit failure and
process-death recovery keep generation 2 and its envelope, terms, and MATCH
count. A neighbor project stays visible. Dropping an unindexed generation
does not create `rag2_chunk_search`. Conversation-search contents and the
seeded LL5 embedding row remain identical. `AppDatabase` stays at schema
version 5.

## Next Entry Condition

Keep this visibility-drop API, the incremental FTS5 index, the
AppDatabase-hosted FTS5 API, the isolated FTS5 instrument, the Drift DAO
write path, the additive schema, and the sqlite3 instrument frozen.
Rebuild/reopen is recorded in
`docs/rag2_fts5_rebuild_reopen_hypothesis_2026-08-27.md`. Retrieval quality
and no-answer policy remain independent. Do not add settings, tools,
prompting, or chat/runtime wiring.

## Verification

```bash
fvm flutter analyze
fvm dart format lib/features/chat/data/datasources/app_database.dart \
  lib/features/chat/data/datasources/rag2_drift_generation_dao.dart \
  tool/rag2_drift_dao_generation_store.dart \
  tool/rag2_fts5_visibility_drop_replay.dart \
  test/tool/rag2_fts5_visibility_drop_replay_test.dart
fvm flutter test test/tool/rag2_fts5_visibility_drop_replay_test.dart
fvm flutter test test/tool/rag2_fts5_incremental_index_replay_test.dart
```
