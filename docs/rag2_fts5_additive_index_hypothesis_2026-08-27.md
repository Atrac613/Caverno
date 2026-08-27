# RAG2 FTS5 Additive Index

Date: 2026-08-27
Status: isolated FTS5 index Go; retrieval not evaluated; production No-Go
Hypothesis: `rag2-fts5-additive-index-contract-v1`

## Decision

The frozen generation envelope can be indexed as an additive FTS5 virtual
table beside `conversation_search` without bumping `AppDatabase` schema
version 5 and without rewriting LL5 embedding rows, conversation payloads, or
model-usage rows. Generation 2 still reopens through the Drift DAO after the
index is created. Replacement keeps only the last committed generation's chunk
identities. Replacement is transactional and scoped to project plus
declaration identity. The index stores generation and snapshot hash and fails
closed when that envelope disagrees with the generation row. Go requires every
target chunk to MATCH.

This selects FTS5 only as an isolated index instrument. It does not change the
frozen generation-row contract, add retrieval ranking, evaluate no-answer
policy, or add settings, tools, prompting, or chat/runtime wiring. Production
remains No-Go.

## Why This Hypothesis

Drift DAO writes proved apply and reopen through table accessors. The remaining
storage-adjacent question is whether an FTS5 index can sit on that same host
file without becoming conversation-search or a retrieval API.

The lexical bake-off already froze Dart-side trigram terms inserted into
`tokenize=unicode61` FTS5. This slice reuses that SQL shape and policy id. It
does not use SQLite's `trigram` tokenizer, rank BM25, or score abstention.

## Frozen V1 Policy

The implementation must preserve all of these rules:

1. Do not bump `AppDatabase` `schemaVersion`. Do not add RAG2 FTS5 to the
   Drift migration. The frozen additive-schema and DAO instruments still
   require RAG2 FTS5 to be absent on their own files.
2. Create `rag2_chunk_search` through `AppDatabase.customStatement` with
   `project_identity`, `declaration_identity`, `generation`, and
   `snapshot_hash` UNINDEXED, plus `chunk_id`, `object_id`, `content`, and
   `tokenize=unicode61`. Do not open a second sqlite3 connection to write the
   index. Leave `conversation_search` on `unicode61` and do not rewrite its
   rows or SQL.
3. Insert Dart-side `trigram_or_idf` terms from attested chunk text. Stored
   FTS5 `content` must equal those terms, not the raw attested string. Do not
   invent a second chunk format. Replacement deletes only the target
   project/declaration slot inside `BEGIN IMMEDIATE` and `COMMIT`. An injected
   `beforeCommit` failure must `ROLLBACK` to the previous generation's index.
4. Bind the index to project identity, declaration identity, generation, and
   snapshot hash. Reading must fail closed when that envelope disagrees with
   the generation row or when one slot mixes generations. Two projects that
   share a file must keep separate FTS5 rows.
5. Reopen must restore generation 2 and the same chunk ids through a new
   Drift DAO connection after the index exists. Do not rewrite `embeddings`,
   conversation payloads, or model-usage rows.
6. Every target chunk must MATCH. One successful MATCH is not Go. Reports omit
   source text, paths, declared roots, Git payloads, questions, evidence
   markers, MATCH terms, and stored tokens. Record only aggregate booleans and
   counts.
7. Keep retrieval quality, no-answer policy, settings, tools, prompting, and
   production at No-Go. A MATCH that locates chunk ids is not a retrieval
   evaluation.

## Rejected Alternatives

- Do not bump `AppDatabase` to version 6 in this slice. That would change the
  frozen v5 host contract.
- Do not switch conversation-search to trigram terms. LL5 history search stays
  on its existing tokenizer.
- Do not treat this index Go as authorization to retrieve, change prompts, or
  expose `search_knowledge`.

## Synthetic Replay Contract

`tool/rag2_fts5_additive_index_replay.dart` implements the frozen policy
against the existing storage fixture:

1. upgrade a v4 `AppDatabase` file that already has an embedding row, a
   conversation payload, conversation-search FTS5 contents, and a model-usage
   row;
2. apply generation 1 and generation 2 through the Drift DAO;
3. create `rag2_chunk_search` with identity columns and `unicode61` through
   `AppDatabase.customStatement`;
4. index generation 1, then atomically replace with generation 2 and prove
   chunk identities change;
5. inject an apply failure and prove the previous generation index remains;
6. prove stored FTS5 content matches Dart trigram terms, not raw attested
   text, and that every chunk MATCHES;
7. isolate two project identities in one file and fail closed on envelope
   mismatch;
8. reopen generation 2 and the same chunk ids through a new DAO connection;
9. prove conversation-search SQL and contents, embeddings, and schema
   version 5 are unchanged;
10. recreate replay files so the same output path can run twice; and
11. emit aggregate-only reports with retrieval left unevaluated.

## Result

The focused replay passes. Generation 2 reopens after indexing with snapshot
hash
`3d2ef68de7071779c06e45381a761edea6494f4a9207c47463503a759914d610`. Replacement
is a `BEGIN IMMEDIATE` transaction scoped to project and declaration identity.
An injected `beforeCommit` failure rolls back to that generation-2 index.
Every chunk MATCHES. Two projects keep separate FTS5 rows. An envelope that
disagrees with the generation row fails closed. Indexed terms use
`trigram_or_idf`, not raw attested text. Conversation-search contents and the
seeded LL5 embedding row remain identical. `AppDatabase` stays at schema
version 5.

## Next Entry Condition

Keep this isolated FTS5 index, the Drift DAO write path, the additive schema,
and the sqlite3 instrument frozen. A later hypothesis may host the virtual
table in `AppDatabase` only if that does not rewrite conversation-search or
generation rows. Retrieval quality and no-answer policy remain independent.
Do not add settings, tools, prompting, or chat/runtime wiring.

## Verification

```bash
fvm flutter analyze
fvm dart format tool/rag2_fts5_additive_index_replay.dart \
  test/tool/rag2_fts5_additive_index_replay_test.dart
fvm flutter test test/tool/rag2_fts5_additive_index_replay_test.dart
fvm flutter test test/tool/rag2_*_test.dart
```
