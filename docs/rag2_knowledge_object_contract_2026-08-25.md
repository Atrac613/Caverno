# RAG2 Knowledge Object Contract — 2026-08-25

## Decision

- `rag2-knowledge-object-contract-v1`: withdrawn after audit.
- `rag2-knowledge-object-contract-v2`: Go for the offline identity, provenance,
  invalidation, and report-safety contract only.
- Storage decision: `not_evaluated`.
- Production decision: `no_go`.
- Runtime passage role: `unknown`.

V1 used a duplicate-content ordinal in chunk identity, did not distinguish
retained chunks whose provenance metadata changed, omitted object add/remove
events, and serialized raw source text into its JSON report. The v1 Go must not
be used as authorization for source discovery, storage, retrieval, or runtime
prompting. The corrective audit is recorded in
`docs/rag2_knowledge_object_contract_audit_2026-08-25.md`.

## Task

- Goal: define a versioned, storage-independent Knowledge Object, Chunk, and
  Provenance contract and prove deterministic incremental invalidation.
- User-visible behavior: none; this is an offline contract and replay fixture.
- Non-goals: drift tables, FTS5, filesystem discovery, production chunking,
  prompting, routing, model calls, and runtime passage-role classification.

## Artifacts

- Contract: `rag2-knowledge-object-contract-v2`
- Evaluator: `tool/rag2_knowledge_object_replay.dart`
- Fixture: `tool/fixtures/rag2_knowledge_object_replay/fixture.json`
- Test: `test/tool/rag2_knowledge_object_replay_test.dart`
- Prior decision: `docs/rag2_passage_role_oracle_2026-08-25.md`

## V2 contract

A Knowledge Object records:

- a deterministic ID scoped by contract version, project ID, and
  repository-relative path;
- project ID, repository-relative path, source kind, source trust, revision,
  normalized content SHA-256, and ordered chunk IDs.

A Chunk records:

- a deterministic ID scoped by object ID, semantic locator, and normalized
  chunk SHA-256;
- object ID, semantic locator, normalized content SHA-256, in-memory text,
  runtime passage role `unknown`, and provenance.

The replay derives Markdown locators from heading paths and Dart locators from
top-level symbols. A duplicate semantic locator within one source fails closed.
This makes identical text at distinct semantic locations receive distinct IDs
without assigning identity by document order. Changed content still receives a
new chunk ID.

Provenance records project ID, repository-relative path, revision, parent-object
content SHA-256, one-based inclusive line span, and source trust. Object identity
deliberately excludes revision and content hash, so a path keeps its identity as
its content changes. Chunk identity deliberately excludes revision and line
span, so unchanged evidence keeps its identity when earlier lines move.

Raw chunk text is available only on the in-memory replay object. JSON and
Markdown reports emit hashes, semantic locators, repository-relative paths, and
provenance metadata, but never raw source text or fixture-root absolute paths.

The delta partitions retained chunks into:

- `unchangedChunkIds` when the full serialized identity and provenance record is
  unchanged;
- `metadataUpdatedChunkIds` when the chunk ID survives but revision, parent
  content hash, line span, or other emitted provenance changes.

Moved-line IDs remain a separately reported subset. Object content changes,
unchanged object content, object removal, and object addition are also explicit.
A path rename is intentionally represented as one removed object and one added
object because the repository-relative path is part of object identity.

The replay segmenter exists only to exercise this contract. It is not the
promoted production chunker and does not satisfy the later source-discovery or
general symbol/heading-aware chunking requirements.

## Acceptance criteria

- The same snapshot serializes identically on repeated runs.
- Snapshot hashes and every retained, unchanged, metadata-updated, removed,
  added, moved, changed-object, unchanged-object, removed-object, and
  added-object ID are pinned in the fixture.
- A count-only implementation cannot pass with different identities.
- Identical content at distinct semantic locations receives distinct IDs.
- Ambiguous semantic locators fail closed.
- Repository path escapes fail closed.
- Every line span is one-based and inclusive.
- Every emitted chunk keeps runtime passage role `unknown`.
- Generated reports do not contain the fixture's absolute-path and secret-like
  sentinels, while the in-memory chunks still contain the source text.
- Storage and production remain unevaluated/No-Go.

## Measured result

| Measurement | Result |
| --- | ---: |
| Baseline | 3 objects / 6 chunks |
| Updated | 3 objects / 7 chunks |
| Retained chunks | 4 |
| Retained chunks unchanged | 2 |
| Retained chunks with metadata updates | 2 |
| Removed chunks | 2 |
| Added chunks | 3 |
| Retained chunks with moved line spans | 1 |
| Changed-content objects | 1 |
| Unchanged-content objects | 1 |
| Removed objects | 1 |
| Added objects | 1 |

The Markdown edit changes one endpoint block, inserts one new body block, and
moves an unchanged storage block from lines 6–7 to 8–9. The storage chunk keeps
its ID but is reported as metadata-updated. The retained document heading also
keeps its ID but records the new revision and parent hash. The untouched Dart
object and both of its chunks are fully unchanged. A fixture path rename proves
object removal/addition accounting. Its source contains absolute-path and
secret-like sentinels that are absent from both generated reports.

## Verification

```bash
fvm dart run tool/rag2_knowledge_object_replay.dart \
  --fixture tool/fixtures/rag2_knowledge_object_replay/fixture.json \
  --out-dir build/integration_test_reports/rag2_knowledge_object

tool/codex_verify.sh \
  --test test/tool/rag2_knowledge_object_replay_test.dart
```

## Remaining boundary and next entry condition

The fixture still declares `projectId`, `revision`, and `sourceTrust`; it does
not prove how production derives or attests them. The next slice must define and
replay those semantics before any source-discovery implementation:

- bind project identity to the persisted `CodingProject.id` and canonicalize
  the configured root through `ProjectReadPathFence`;
- distinguish a Git-tracked revision from a modified or untracked working-tree
  revision without treating missing Git evidence as trusted;
- derive source trust from inspected repository state instead of accepting a
  caller-provided label;
- classify the operation as read-only inspection under the SEC1 perimeter;
- extract or add one bounded reusable UTF-8/binary classifier rather than
  duplicating the private filesystem-tool sniff logic.

That entry gate is now satisfied by
`docs/rag2_provenance_attestation_contract_2026-08-25.md`. Its offline contract
is Go, while real source discovery, production Git execution, storage, FTS,
prompt routing, tools, and model calls remain absent.
