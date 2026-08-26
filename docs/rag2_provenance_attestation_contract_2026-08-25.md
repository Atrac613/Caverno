# RAG2 Provenance Attestation Contract — 2026-08-25

## Task

- Goal: define how a Knowledge Object obtains project identity, canonical-root
  containment, revision, source trust, and read-only capability evidence before
  bounded source discovery.
- User-visible behavior: none; this is an offline fixture replay.
- Non-goals: real workspace enumeration, production Git execution, chunking,
  drift/FTS storage, retrieval, prompting, tool exposure, and model calls.

## Context

- Contract: `rag2-provenance-attestation-contract-v1`
- Evaluator: `tool/rag2_provenance_attestation_replay.dart`
- Fixture: `tool/fixtures/rag2_provenance_attestation_replay/fixture.json`
- Test: `test/tool/rag2_provenance_attestation_replay_test.dart`
- Predecessor: `docs/rag2_knowledge_object_contract_audit_2026-08-25.md`

The Knowledge Object v2 audit deferred source discovery because `projectId`,
`revision`, and `sourceTrust` were caller-declared labels. This contract accepts
raw Git probe evidence and derives the labels through one fail-closed policy.

## Contract

Project identity comes from persisted `CodingProject.id`. The configured
`CodingProject.rootPath` is canonicalized through `ProjectReadPathFence`; only
an existing file resolving inside that canonical root can be attested. Reports
record containment as `inside_project` but never emit the configured or
canonical absolute path.

Source identity is versioned and scoped by persisted project ID plus
repository-relative path. It excludes root path, content, and revision. The same
persisted project moved to a new root therefore keeps source identity, while a
new project ID or repository-relative path does not.

Git evidence is modeled as the bounded outputs required from:

- `git ls-files --error-unmatch -- <repo-relative-path>`;
- `git status --porcelain=v1 -- <repo-relative-path>`;
- the HEAD blob revision for a clean tracked file.

The evaluator derives these states:

| Raw state | Source trust | Worktree state | Revision |
| --- | --- | --- | --- |
| tracked, clean, HEAD blob present | `workspace_tracked` | `clean` | `git_blob:<oid>` |
| tracked, targeted status present | `workspace_tracked` | `modified` | `working_tree_sha256:<content-hash>` |
| untracked and targeted `??` status present | `workspace_untracked` | `untracked` | `working_tree_sha256:<content-hash>` |
| Git unavailable, missing blob, or inconsistent status | none | none | rejected |

Modified tracked content does not claim the HEAD blob revision. Untracked
content is never upgraded to tracked trust. Missing or contradictory Git
evidence rejects attestation instead of silently treating a non-Git project as
trusted.

The acquisition operation is pinned to SEC1 `readOnlyInspection` with `low`
risk. `BoundedTextFileClassifier` is extracted from the existing filesystem
tools and remains their shared prefix classifier. A NUL byte or malformed UTF-8
is rejected, a rune split at the sniff boundary is tolerated, and attestation
also enforces a one-MiB full-read ceiling before hashing normalized UTF-8 text.

## Fixed controls

The deterministic fixture covers:

- one clean tracked source at two different canonical roots with the same
  persisted project ID;
- one modified tracked source;
- one untracked source;
- one source with unavailable Git evidence.

Focused temporary-filesystem tests additionally cover:

- symlink escape outside the canonical root;
- NUL and malformed UTF-8 input;
- an oversized source;
- ambiguous Git evidence;
- missing project identity;
- a multi-byte UTF-8 rune split at the bounded sniff boundary.

## Measured result

| Measurement | Result |
| --- | ---: |
| Attested fixture cases | 4 |
| Rejected fixture cases | 1 |
| Root-move identity pairs stable | 1 / 1 |
| Clean tracked revisions | `git_blob` |
| Modified and untracked revisions | `working_tree_content` |
| Git-unavailable behavior | rejected |
| Capability class / risk | `readOnlyInspection` / `low` |
| Absolute root paths in reports | 0 |

- Contract decision: `go`.
- Source discovery decision: `no_go` in this slice.
- Storage decision: `not_evaluated`.
- Production decision: `no_go`.

## Similar-pattern search

- Search terms: `CodingProject`, `ProjectReadPathFence`, `_looksBinary`,
  `git status --porcelain`, `readOnlyInspection`.
- Inspected surfaces: coding-project persistence, project-read containment,
  filesystem inspection/search, Git changed-path parsing, and the SEC1
  capability classifier.
- Result: reuse the persisted project entity, containment fence, and SEC1
  classification; extract the binary sniff instead of adding a RAG-only copy.
  The production Git command adapter remained a later implementation boundary
  for this fixture contract.

## Verification

```bash
fvm dart run tool/rag2_provenance_attestation_replay.dart \
  --fixture tool/fixtures/rag2_provenance_attestation_replay/fixture.json \
  --out-dir build/integration_test_reports/rag2_provenance_attestation

tool/codex_verify.sh \
  --test test/tool/rag2_provenance_attestation_replay_test.dart \
  --test test/features/chat/data/datasources/filesystem_tools_test.dart
```

## Handoff notes

The fixture-root-only source-discovery and candidate-chunking replay completed
on 2026-08-26. It consumes this attestation contract and freezes file count,
per-file bytes, corpus bytes, symlink rejection, generated-file exclusions,
Markdown heading boundaries, and Dart symbol boundaries. See
`docs/rag2_source_discovery_chunking_replay_2026-08-26.md`.

The bounded typed Git collector prerequisite completed later on 2026-08-26. It
uses exact NUL-delimited probes, requires project-root/repository-root equality,
and fails closed on command and resource failures. See
`docs/rag2_git_evidence_collector_2026-08-26.md`.

The next slice may add only an opt-in, manifest-only live shadow for one
explicitly selected project through that collector. Production indexing, FTS5,
prompting, routing, tools, and model calls remain blocked.
