# RAG2 Storage Replay Contract

Date: 2026-08-26
Status: storage contract Go; declaration identity aligned; retrieval not evaluated; production No-Go
Contract: `rag2-storage-replay-contract-v1`

## Decision

The backend-neutral offline replay passes. A declaration-scoped in-memory store
atomically applies one complete generation, skips an identical snapshot without
changing its generation or hash, replaces an updated snapshot with exact stale
removals and metadata updates, and preserves the prior generation when an apply
failure is injected.

This is a storage-semantics Go only. It does not select SQLite, FTS5, Drift,
embeddings, retrieval, application wiring, settings, tools, prompting, or model
calls. Retrieval is not evaluated and production remains No-Go.

## Composition

The replay composes the frozen upstream contracts rather than implementing
parallel representations:

- Knowledge Object v2 supplies object/chunk identity, snapshots, and
  `Rag2KnowledgeReplayDelta.compare`.
- Source discovery supplies Markdown heading and Dart symbol chunks.
- Provenance attestation supplies project identity, revision, source trust,
  content hash, and bounded canonical reads. Stored chunk text is taken from
  that attested snapshot, not from a later unfenced file read.
- Explicit complete source roots supply validation and complete in-root
  selection with unchanged policy ceilings and instruction-bearing exclusion.

The only upstream API changes expose existing deterministic object/snapshot
identity helpers, explicit-root validation/membership helpers, and the shared
declaration-identity hasher. Storage no longer hashes
`rag2-storage-replay-contract-v1` plus project id. The same sorted source
roots now produce
`declaration_40a72c56dc081f3170457e4c60666499964ea83a487c0dc414cc7d59a441be14`
in both acquisition and storage. Project identity remains a separate field.

## Fixture Result

The synthetic declaration selects three baseline objects with five chunks.
Initial apply creates generation 1. Replaying the identical snapshot remains at
generation 1 with the same
`31d8769e4f33bab976367e724440209bc5d3da2c3772559522f7ea655f48c95b`
snapshot hash.

The updated snapshot creates generation 2 with
`3d2ef68de7071779c06e45381a761edea6494f4a9207c47463503a759914d610`.
The frozen Knowledge Object delta records four retained chunks, two unchanged
chunks, two metadata-updated chunks, one stale chunk removal, one chunk
addition, one object removal, and one object addition. A source outside the
declared roots is never admitted.

Removing one attestation or exceeding policy limits rejects preparation before
store mutation. Throwing immediately before generation commit returns a
rollback result and leaves generation 2 and its hash unchanged. Repeated
preparation produces byte-identical snapshot JSON.

## Privacy Boundary

JSON and Markdown reports contain only decisions, counts, generations, stable
identities, hashes, and rollback booleans. They omit source text, absolute
paths, declared roots, repository-relative source paths, Git payloads,
questions, and evidence markers.

## Verification

```bash
fvm dart format tool/rag2_storage_replay.dart \
  tool/rag2_knowledge_object_replay.dart \
  tool/rag2_explicit_source_roots_replay.dart \
  test/tool/rag2_storage_replay_test.dart
fvm flutter test test/tool/rag2_storage_replay_test.dart
fvm flutter test \
  test/tool/rag2_knowledge_object_replay_test.dart \
  test/tool/rag2_source_discovery_replay_test.dart \
  test/tool/rag2_provenance_attestation_replay_test.dart \
  test/tool/rag2_explicit_source_roots_replay_test.dart
fvm flutter test test/tool/rag2_*_test.dart
```

## Next Entry Condition

Keep this contract and fixture frozen, including the attested-text binding and
shared declaration identity. Before selecting a production backend, run a
separate migration/reopen/crash-recovery hypothesis. Retrieval remains a later
independent evaluation.
