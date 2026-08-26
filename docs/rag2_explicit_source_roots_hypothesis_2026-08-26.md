# RAG2 Explicit Source Roots Hypothesis

Date: 2026-08-26
Status: development declaration frozen; evaluation questions not created
Hypothesis: `rag2-explicit-complete-source-roots-v1`

## Decision

The next RAG2 source-scope experiment will evaluate explicit, complete source
roots. A caller must declare one or more repository-relative directories before
discovery. Every eligible `.dart` and `.md` source below those directories is
admitted, or the whole declaration fails closed. There is no sampling within a
declared root.

This is the first candidate after closing `structural_stratified_v1`. Its
synthetic replay contract is implemented, and one active-project development
declaration has passed acquisition preflight. It does not authorize storage or
change production behavior.

## Why This Hypothesis

The Caverno inventory contains about 2,800 eligible files. The default ceiling
admits 512. Any automatic static subset can omit a file that a later question
requires, and the failed development and holdout replays demonstrate that
fixed role quotas do so in practice. Changing the ranking, quota, or hash salt
would repeat the same omission mechanism.

Explicit roots change the contract instead of retuning the sample:

- omission authority belongs to the caller's declared task or project scope;
- inclusion is complete inside every declared root;
- an out-of-scope answer is unavailable, not falsely absent;
- the existing per-file, file-count, and corpus-byte limits remain unchanged;
  and
- the batch Git and source-discovery contracts can be reused after admission.

## Frozen V1 Policy

The implementation must preserve all of these rules:

1. Require explicit opt-in, project identity, project root, and one to sixteen
   repository-relative source-root directories.
2. Accept normalized directories only. Reject absolute paths, traversal,
   symlinks, missing directories, files presented as roots, duplicate roots,
   and ancestor/descendant root overlap.
3. Reuse `inventoryRag2SourceCandidates` unchanged for extension, generated
   content, symlink, binary, and per-file-size policy.
4. Include every eligible candidate whose path is below a declared root.
   Never rank, truncate, hash-sample, or borrow capacity between roots.
5. Continue to exclude instruction-bearing files even when they are below a
   declared root.
6. Require the complete union to fit the existing default ceilings: 512 files,
   32 MiB corpus, and 512 KiB per file. Do not fall back to the hard ceilings.
7. On any declaration or limit failure, admit zero sources and invoke zero Git
   commands.
8. Emit aggregate counts, typed blockers, and hashed project, declaration,
   inventory, and selected-metadata identities. Do not emit roots, paths,
   source text, Git payloads, questions, or evidence markers.
9. Keep scope, storage, retrieval, and production decisions at No-Go until an
   independent evaluation passes.

No default root list is allowed. A missing declaration is not equivalent to
the repository root.

The current `CodingProject` entity stores only project identity, name, root,
security-scoped bookmark, and timestamps. V1 therefore remains an explicit CLI
experiment. No persisted source roots or generated entity changes were added.

## Synthetic Replay Contract

`tool/rag2_explicit_source_roots_replay.dart` implements the frozen policy as a
storage-independent, opt-in replay:

1. validate one to sixteen explicit roots, including every intermediate path
   component, before Git;
2. build the unchanged whole-project source inventory;
3. retain every eligible candidate below the declared roots and remove only
   instruction-bearing sources;
4. reject the complete declaration at the default file or corpus ceiling
   before Git;
5. collect evidence for an in-bound declaration through the existing exact
   three-command batch Git protocol; and
6. attest every selected source with chunks disabled, rejecting the entire
   declaration if any source fails.

The report contains only counts, typed blockers, policy values, command count,
and hashed project, declaration, inventory, and selected-metadata identities.
It omits declared roots, candidate paths, source text, Git payloads, questions,
and evidence markers. `scopeDecision` remains `not_selected`, and storage,
retrieval, and production remain No-Go.

One Caverno development declaration was loaded only after its task context and
roots were fixed. No active-project question fixture was used for the
declaration or evaluated under it. See
`docs/rag2_explicit_source_roots_development_declaration_2026-08-26.md`.

## Evaluation Order

The hypothesis must be evaluated without using the failed structural holdout
as promotion evidence:

1. Implement only an offline/opt-in explicit-root replay and synthetic contract
   tests. Do not connect settings or application state. **Complete.**
2. Prove complete inclusion, overlap rejection, instruction-file exclusion,
   unchanged limits, aggregate-only output, and zero-Git failure behavior.
   **Complete.**
3. Freeze one realistic source-root declaration from task context before
   writing or inspecting its evaluation questions. **Complete.** See
   `docs/rag2_explicit_source_roots_development_declaration_2026-08-26.md`.
4. Create a new question set containing both in-scope and deliberately
   out-of-scope controls. Do not reuse either active-project source-role
   fixture.
5. Require 100% inclusion of required in-scope evidence, 100% exclusion of
   undeclared evidence, and explicit `not_available` treatment for every
   out-of-scope control.
6. Only after that development result, freeze a separate untouched declaration
   and holdout for a promotion decision.

Path coverage still will not prove retrieval, ranking, answer correctness, or
citation quality. Those remain separate later gates.

## Rejected Alternatives

- Do not change the v1 role quotas, byte budgets, stable hash, or salt.
- Do not replace stable hashing with alphabetical, recency, popularity, or
  hand-picked automatic ranking. Each is still a static partial subset.
- Do not use the failed holdout to choose roots.
- Do not add a query-directed shortlist in this slice. That moves selection
  into retrieval, introduces multilingual query/path matching risk, and belongs
  behind a separate RAG3 evaluation contract.
- Do not reinterpret repeated 512-file batches as compliance with the total
  file ceiling.
- Do not add SQLite, FTS5, embeddings, prompting, routing, tools, model calls,
  settings, or application wiring.

## Next Entry Condition

Create a new development set for the frozen chat memory and conversation
persistence declaration. Include both in-scope and out-of-scope controls, keep
the five roots unchanged, and do not reuse any prior source-role or structural-
profile fixture question. Do not use development results for promotion; a
separate declaration and untouched holdout remain required.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/tool/rag2_explicit_source_roots_declaration_test.dart \
  --test test/tool/rag2_explicit_source_roots_replay_test.dart \
  --test test/tool/rag2_source_manifest_shadow_test.dart \
  --test test/tool/rag2_source_discovery_replay_test.dart \
  --test test/tool/rag2_batch_git_inventory_replay_test.dart

fvm flutter test test/tool/rag2_*_test.dart
```

The two declaration-freeze and nine explicit-root cases pass. The repository
verifier passes project and package analysis, three package test suites, all 29
focused acquisition tests, and 10 notification-relay tests. All 119 focused
RAG2 tests pass.
