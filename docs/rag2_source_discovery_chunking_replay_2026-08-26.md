# RAG2 Source Discovery and Chunking Replay — 2026-08-26

## Decision

`rag2-source-discovery-contract-v1` is Go for the offline fixture replay only.
Production source discovery and production RAG remain No-Go. Storage is not
evaluated.

The replay consumes the previously frozen provenance-attestation contract. It
does not execute Git, enumerate the active workspace, write an index, call a
model, alter prompts, register tools, or change routing.

## Contract boundary

The fixture supplies one explicit project root, positive resource limits, and
raw Git probe evidence keyed by repository-relative path. Discovery then:

1. walks only that root with link following disabled;
2. considers Markdown and Dart files only;
3. excludes hidden/generated directories, generated Dart files, unsupported
   extensions, symlinks, and files over the per-file byte limit;
4. fails the complete candidate set closed when the remaining file-count or
   corpus-byte limit is exceeded;
5. consumes provenance attestation for every remaining file and excludes any
   source whose Git state, containment, encoding, or trust cannot be attested;
6. creates metadata-only candidate chunks at Markdown heading or top-level Dart
   symbol boundaries; and
7. fails closed when a file produces no stable Dart boundary or a duplicate
   semantic locator.

The serialized JSON and Markdown reports contain source identity, revision,
trust, byte counts, line spans, semantic locators, and content hashes. They do
not contain source text or an absolute project root.

## Frozen replay

The pinned fixture discovers two sources from five visible fixture entries:

| Result | Count | Detail |
| --- | ---: | --- |
| Candidate files | 2 | `docs/guide.md`, `lib/config.dart` |
| Candidate corpus bytes | 276 | Below the frozen 8,192-byte corpus limit |
| Markdown chunks | 3 | Hierarchical heading locators |
| Dart chunks | 2 | Top-level declaration locators |
| Exclusions | 3 | Unsupported extension, generated directory, generated Dart file |
| Limit violations | 0 | File count, per-file bytes, and corpus bytes all bounded |

The fixture policy is pinned to four files, 4,096 bytes per file, and 8,192
bytes for the candidate corpus. Tests also prove whole-corpus rejection for
file-count and byte-limit violations, individual oversized-file exclusion,
symlink rejection, missing-Git-evidence exclusion, duplicate-locator failure,
deterministic artifacts, and absence of raw source text and absolute roots.

## Reproduction

```bash
out_dir="$(mktemp -d /tmp/rag2-source-discovery.XXXXXX)"
fvm dart run tool/rag2_source_discovery_replay.dart \
  --fixture tool/fixtures/rag2_source_discovery_replay/fixture.json \
  --out-dir "$out_dir"
fvm flutter test test/tool/rag2_source_discovery_replay_test.dart
```

The durable inputs are:

- `tool/fixtures/rag2_source_discovery_replay/fixture.json`
- `tool/fixtures/rag2_source_discovery_replay/repository/`
- `tool/rag2_source_discovery_replay.dart`
- `test/tool/rag2_source_discovery_replay_test.dart`

## What this does not authorize

- Do not treat caller-supplied fixture Git evidence as a production Git adapter.
- Do not enumerate an active project automatically or outside an explicitly
  selected `CodingProject` root.
- Do not persist chunks, add SQLite/FTS5 tables, create embeddings, inject
  retrieved text into prompts, expose a retrieval tool, or change model routing.
- Do not infer that heading and regex symbol boundaries are production-quality
  retrieval chunks. This slice proves deterministic acquisition boundaries,
  not retrieval quality.

## Next entry condition

The bounded typed Git collector prerequisite is now complete and recorded in
`docs/rag2_git_evidence_collector_2026-08-26.md`.

The subsequent opt-in manifest-only adapter is complete and recorded in
`docs/rag2_source_manifest_shadow_2026-08-26.md`. Its Caverno preflight exceeds
the bounded file-count policy before Git collection. Measure metadata-only
candidate counts and bytes by top-level source scope next; do not raise the cap
or consider an index schema from the aggregate count alone.
