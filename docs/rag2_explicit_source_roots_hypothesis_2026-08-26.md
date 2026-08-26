# RAG2 Explicit Source Roots Hypothesis

Date: 2026-08-26
Status: hypothesis frozen; implementation and evaluation not started
Hypothesis: `rag2-explicit-complete-source-roots-v1`

## Decision

The next RAG2 source-scope experiment will evaluate explicit, complete source
roots. A caller must declare one or more repository-relative directories before
discovery. Every eligible `.dart` and `.md` source below those directories is
admitted, or the whole declaration fails closed. There is no sampling within a
declared root.

This is the first candidate after closing `structural_stratified_v1`. It does
not select a Caverno scope, authorize storage, or change production behavior.

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
security-scoped bookmark, and timestamps. V1 must therefore remain an explicit
CLI experiment. Do not add persisted source roots or generated entity changes
before the evaluation gate.

## Evaluation Order

The hypothesis must be evaluated without using the failed structural holdout
as promotion evidence:

1. Implement only an offline/opt-in explicit-root replay and synthetic contract
   tests. Do not connect settings or application state.
2. Prove complete inclusion, overlap rejection, instruction-file exclusion,
   unchanged limits, aggregate-only output, and zero-Git failure behavior.
3. Freeze one realistic source-root declaration from task context before
   writing or inspecting its evaluation questions.
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

Implement the smallest storage-independent replay for this exact frozen policy
using synthetic repositories only. The first implementation commit must not
load the development or failed holdout fixtures and must not select live Caverno
roots.
