# RAG2 Knowledge Object Contract Audit — 2026-08-25

## Outcome

The previously recorded v1 Go is withdrawn. The corrected
`rag2-knowledge-object-contract-v2` is Go only for the offline identity,
invalidation, provenance-update, object-lifecycle, and report-safety contract.
Storage remains `not_evaluated`; production remains `no_go`.

The earlier proposed next step, bounded source discovery, is deferred. Project
identity, revision, and source-trust derivation are still fixture assertions
rather than attested facts, so scanning more files would multiply provenance
whose authority has not been defined.

## Audit scope

The review reconciled:

- `docs/rag2_knowledge_object_contract_2026-08-25.md`;
- `tool/rag2_knowledge_object_replay.dart`;
- the two-snapshot fixture and generated JSON/Markdown reports;
- `test/tool/rag2_knowledge_object_replay_test.dart`;
- the current project identity, read-containment, text/binary handling, and SEC1
  perimeter surfaces.

No production filesystem discovery, drift schema, FTS5 table, prompt path,
runtime tool, model call, or application behavior was added.

## Findings and corrections

| Finding | Risk | V2 correction |
| --- | --- | --- |
| V1 used content hash plus duplicate ordinal for chunk identity. | Removing the first of two identical blocks could make the survivor inherit the removed block's ID. | Chunk IDs now include a semantic locator. Identical content at distinct locators receives distinct IDs, and duplicate locators fail closed. |
| V1 treated every retained ID as unchanged except for a separate moved-line list. | A retained chunk could carry a new revision or parent-object hash while downstream code considered its provenance current. | Retained chunks are partitioned into fully unchanged and metadata-updated IDs; moved spans remain an explicit subset. |
| V1 omitted object add/remove events. | Rename and deletion could not drive complete invalidation. | Removed and added object IDs are pinned exactly; a path rename is replayed as remove plus add. |
| V1 serialized raw chunk text into the JSON report. | Source secrets or absolute paths could enter durable build artifacts despite the documented report boundary. | Raw text remains in memory but is omitted from serialized chunks. Adversarial sentinels are asserted absent from JSON and Markdown reports. |

## Corrected replay evidence

| Measurement | Result |
| --- | ---: |
| Deterministic replay | `true` |
| Baseline | 3 objects / 6 chunks |
| Updated | 3 objects / 7 chunks |
| Retained chunks | 4 |
| Fully unchanged retained chunks | 2 |
| Metadata-updated retained chunks | 2 |
| Removed / added chunks | 2 / 3 |
| Moved retained chunks | 1 |
| Changed / unchanged common objects | 1 / 1 |
| Removed / added objects | 1 / 1 |
| Raw sentinel leakage | 0 occurrences |

Every snapshot hash and every delta ID is pinned in fixture schema v2. The
fixture includes identical source text under different repository-relative
paths to exercise object lifecycle and source text containing an absolute-path
sentinel plus a secret-like sentinel to exercise report safety. A separate
regression proves that identical chunk content at two semantic locators produces
two identities. Another regression proves that ambiguous locators stop replay.

## Remaining gap

The corrected evaluator still accepts these fields from the fixture:

- `projectId`;
- `revision`;
- `sourceTrust`.

That is sufficient for a representation replay, but not for production
provenance. It does not define whether a project keeps identity after its root
moves, how a clean Git blob differs from a modified working-tree file, how an
untracked file is represented, or what trust label is allowed when Git evidence
is unavailable.

The current repository already provides boundaries that the next contract can
reuse instead of creating a second policy stack:

- persisted `CodingProject.id` for project identity;
- `ProjectReadPathFence` for canonical root containment and symlink resolution;
- filesystem text handling that rejects malformed UTF-8 and detects binary
  inputs, although its reusable boundary still needs to be extracted;
- SEC1 `readOnlyInspection` classification for a non-mutating acquisition path.

## Decision and next action

- V1 identity/replay decision: `withdrawn`.
- V2 offline contract decision: `go`.
- Source-discovery decision: `deferred`.
- Storage decision: `not_evaluated`.
- Production decision: `no_go`.

The next narrow slice is an offline provenance-attestation contract. It must pin
project identity lifecycle, revision kind and value, trust derivation, missing
Git behavior, canonical-root evidence, and bounded text classification across
clean tracked, modified tracked, untracked, moved-root, symlink-escape, binary,
and unavailable-Git controls. It must not enumerate the real repository or add
storage. Source discovery can resume only after this contract passes.

## Reproduction

```bash
fvm dart run tool/rag2_knowledge_object_replay.dart \
  --fixture tool/fixtures/rag2_knowledge_object_replay/fixture.json \
  --out-dir build/integration_test_reports/rag2_knowledge_object

tool/codex_verify.sh \
  --test test/tool/rag2_knowledge_object_replay_test.dart
```
