# RAG2 Investigation Handoff — 2026-08-25

## Purpose

This document is the durable index for the ongoing RAG2 investigation across
`main` and its focused follow-up branches. Update it in every investigation
slice. It preserves the sequence of experiments,
decisions, rejected approaches, frozen evidence, and next entry condition when
the branch is squash-merged.

The committed documents, fixtures, evaluators, and tests are the canonical
evidence. The commit IDs below are historical trace labels only; no gate or
reproduction step depends on those commits remaining reachable after a squash.

## Final decision

RAG2 remains `later`, and production retrieval, prompting, storage, and tool
behavior remain unchanged.

Extraction v2 is the frozen diagnostic precision baseline because a third
untouched holdout measured exact precision `1.000` for both supported families
without a true-positive regression from v1.
Outcome v1's contract Go is withdrawn. Corrected v2 accounting preserves all
19 true positives and the 35-span distribution, but runtime completeness is
`not_evaluated`; the outcome contract remains `no_go`. Availability is `0.909`
for Dart assignments, `0.750` for Markdown URI relations, and `0.000` for
prose. Extraction as a whole remains `no_go`.

The passage-role re-score withdraws `no-answer retrieved` as a promotion gate:
it conflated answer support, abstention support, topical-only evidence, and
irrelevant evidence. Frozen retrieval found answer support for all 27 factual
cases and abstention support for 4/5 bounded-negative cases, but also returned
topical-only passages for 5/8 unavailable cases. No runtime role classifier
exists. Typed facts are therefore closed as diagnostic evidence rather than a
RAG2 prerequisite, and production remains `no_go`.

The initial `rag2-knowledge-object-contract-v1` Go is withdrawn. Its
duplicate-content ordinal could reassign a surviving block's identity, retained
IDs did not expose provenance-only updates, object lifecycle changes were
omitted, and raw source text entered the JSON report. Corrected
`rag2-knowledge-object-contract-v2` uses semantic locators, fails closed on
ambiguous locators, separates 2 fully unchanged from 2 metadata-updated retained
chunks, records 2 removed / 3 added chunks and 1 removed / 1 added object, and
omits raw source text from reports. The offline v2 contract is Go; source
discovery is deferred, storage is not evaluated, and production remains No-Go.

`rag2-provenance-attestation-contract-v1` now closes that entry gate for an
offline representation: persisted `CodingProject.id` owns project identity,
`ProjectReadPathFence` proves canonical containment, raw Git probe evidence
derives clean-tracked / modified-tracked / untracked revision and trust, and
unavailable or inconsistent Git evidence fails closed. Four fixture cases are
attested, one unavailable-Git case is rejected, and the same project moved
between two roots keeps source identity. Source discovery was not implemented;
storage and production remain No-Go.

`rag2-source-discovery-contract-v1` composes the attestation contract with a
fixture-root-only, link-disabled walk. The pinned 276-byte candidate corpus
selects two attested Markdown/Dart sources and five semantic chunks while
excluding one unsupported file, one generated directory, and one generated
Dart file. File-count and corpus-limit violations reject the complete candidate
set; per-file overflow, symlinks, missing Git evidence, unstable Dart
boundaries, and duplicate semantic locators fail closed. Reports contain only
metadata and hashes. The offline discovery contract is Go; no active workspace
is enumerated, storage is not evaluated, and production remains No-Go.

`rag2-git-evidence-collector-contract-v1` closes the execution-boundary gap
found before live shadowing. Exact, shell-free, NUL-delimited Git probes run
under timeout and output limits, require the selected project root to equal the
repository root, and produce typed clean-tracked / modified-tracked / untracked
states. Command failure, malformed or inconsistent output, subdirectory roots,
and resource overflow fail closed. The discovery evaluator now resolves
evidence lazily through a provider while preserving frozen fixture output. No
live manifest or app path existed in that slice; storage and production
remained No-Go.

`rag2-source-manifest-shadow-contract-v1` connects discovery and typed Git
evidence only through an explicit CLI opt-in. It emits metadata JSON to stdout,
builds no chunks, writes no application storage, hashes project identity, and
omits roots, source text, and command output. Temporary repositories prove
clean, modified, untracked, generated, symlink, limit, and root-mismatch
behavior. The final Caverno live preflight measured 2,816 candidates and failed
closed on a 16-file limit before Git collection; this also exceeds the v1 hard
ceiling of 2,048. The adapter contract is Go, the current Caverno manifest is
No-Go, and production remains No-Go.

`rag2-source-scope-measurement-contract-v1` reuses the discovery walk before
Git, emits only aggregate top-level/source-role counts, and compares explicit
profiles without selecting one. The final snapshot has 2,819 candidates.
Runtime-only and runtime-plus-top-level-doc profiles exceed the default file
ceiling; retaining tests as well reaches 2,557 files and exceeds the hard
ceiling. The measurement contract is Go and scope selection remains No-Go.

`rag2-batch-git-inventory-contract-v1` obtains exact-root preflight,
repository-wide NUL status, and stage-zero index blobs in three fixed commands.
A real temporary repository matches the frozen per-path state and clean
revision semantics for clean, modified, untracked, staged, renamed, space, and
Unicode cases. Bounded transport and ambiguous inventories fail closed. Batch
parity is Go.

The batch collector is now integrated into the opt-in manifest shadow through
one shared source inventory. In-bound repositories use exactly three Git
commands, discovery-limit failures use zero, and the complete report JSON
matches the frozen per-path oracle. Manifest integration is Go; Caverno source
scope, storage, retrieval, and production remain No-Go. The final live
preflight measured 2,823 candidates and failed closed before Git on a 16-file
limit.

The `rag2-source-role-coverage-contract-v1` Go was withdrawn after audit: it
used an unbounded evidence read, did not block eligibility at the default
ceiling, accepted only one marker per question, and emitted no inventory
identity. `rag2-source-role-coverage-contract-v2` uses all-of required markers,
bounded path-fenced reads with post-read reauthorization, aggregate inventory
and evidence identities, duplicate-path rejection, and default-limit-aware
eligibility. The profiles still cover 2/8, 4/8, and 6/8 development questions;
all exceed the default ceiling. V2 required-source coverage is Go;
source-profile selection, retrieval, storage, and production remain No-Go.

`rag2-structural-profile-candidate-contract-v1` freezes one question-independent
candidate before reading the development fixture. Fixed role quotas and stable
path-hash ranking select 509 files and about 5.34 MiB within default limits,
with instruction-bearing files excluded. The later development replay covers
6/8 questions, missing one runtime and the tooling question at the aggregate
role level. The unchanged candidate then covered 4/8 on one untouched holdout,
missing one documentation, both test, and the tooling question. Close this
stratified stable-hash strategy and do not tune or revive v1.

## Investigation sequence

| Step | Pre-squash commit | Experiment | Result and durable decision | Evidence |
| ---: | --- | --- | --- | --- |
| 1 | `41cc68ca` | Lexical policy bake-off | Trigram recovered 16/16 answerable cases but returned 2/4 no-answer cases. Do not migrate storage. | `docs/rag2_lexical_policy_spike_2026-08-25.md` |
| 2 | `b8bc0a38` | Evidence-sufficiency holdout | Coverage, concentration, and BM25 margin could not safely distinguish topical evidence from answer-bearing evidence. Close lexical threshold tuning. | `docs/rag2_evidence_sufficiency_holdout_2026-08-25.md` |
| 3 | `7a779592` | Claim-support oracle | Oracle citation coverage separated relevance from complete support, but was not available as a runtime policy. | `docs/rag2_claim_support_oracle_2026-08-25.md` |
| 4 | `de69d243` | Runtime answerability signal | A deterministic signal passed the inspected synthetic corpora but lacked independent promotion evidence. | `docs/rag2_runtime_answerability_signal_2026-08-25.md` |
| 5 | `dcd56708` | Adversarial answerability audit | The frozen signal failed a new 20-case corpus. Close intent-keyword expansion. | `docs/rag2_runtime_adversarial_audit_2026-08-25.md` |
| 6 | `75971911` | Post-answer claim verification | The lexical verifier failed the fixed 36-claim, three-verdict contract. | `docs/rag2_post_answer_claim_verification_2026-08-25.md` |
| 7 | `fc713c3d` | Authority-aware verification | Revision and authority metadata improved holdouts but did not clear the gate and regressed the seed. | `docs/rag2_authority_claim_verification_2026-08-25.md` |
| 8 | `fcfa36f0` | Structured claim envelopes | Explicit scope and citations passed both holdouts but still missed the seed gate. | `docs/rag2_structured_claim_envelopes_2026-08-25.md` |
| 9 | `0f8ae970` | Semantic verifier v1 | The regression suite passed, but it had informed the implementation and was not independent evidence. | `docs/rag2_semantic_claim_verification_2026-08-25.md` |
| 10 | `95b78452` | Blinded semantic holdout | Frozen v1 scored macro-F1 `0.672`, below the `0.90` gate. | `docs/rag2_blinded_semantic_holdout_2026-08-25.md` |
| 11 | `654512f3` | Relation-aware verifier v2 | V2 reached macro-F1 `1.000` on known suites, but the first holdout had exposed its relations. | `docs/rag2_relation_aware_claim_verification_2026-08-25.md` |
| 12 | `b0d59ffb` | Compositional holdout | Frozen v1/v2 scored `0.154`/`0.328`; relation heuristics did not generalize. | `docs/rag2_compositional_semantic_holdout_2026-08-25.md` |
| 13 | `c9a98b20` | Typed fact oracle | A source-bounded typed matcher reached macro-F1 `1.000`, proving the representation as an oracle upper bound only. | `docs/rag2_typed_fact_oracle_2026-08-25.md` |
| 14 | `2aea7998` | Candidate-independent extraction v1 | Development precision/recall was `1.000`/`0.643`; unsupported prose kept extraction No-Go. | `docs/rag2_typed_fact_extraction_2026-08-25.md` |
| 15 | `dfa5cc0a` | Independent extraction holdout | V1 precision/recall fell to `0.714`/`0.455`; interpolation and malformed ports produced false facts. | `docs/rag2_typed_fact_extraction_holdout_2026-08-25.md` |
| 16 | `c32155f1` | Precision-only extraction v2 | AST literal checks and complete URI validation restored precision `1.000` on the informed holdout, but this was diagnostic only. | `docs/rag2_typed_fact_extraction_v2_2026-08-25.md` |
| 17 | `ab017c67` | Independent v2 precision holdout | V2 independently passed the supported-family precision gate and became the precision baseline; recall and production remain No-Go. | `docs/rag2_typed_fact_extraction_v2_holdout_2026-08-25.md` |
| 18 | `c73f12af` | Versioned extraction outcomes v1 | All 35 annotated spans received one typed outcome, but the initial contract Go was later withdrawn after review. | `docs/rag2_typed_fact_extraction_outcomes_2026-08-25.md` |
| 19 | `d5701ba3` | Fail-closed outcome v2 | Zero extraction and unknown-relation absence are closed; accounting passes, runtime coverage is not evaluated, and the contract remains No-Go. | `docs/rag2_typed_fact_extraction_outcome_audit_2026-08-25.md` |
| 20 | `6118fba7` | Frozen retrieval role re-score | The old no-answer retrieval gate conflated useful abstention evidence with topical-only retrieval. Typed facts close as diagnostic; no runtime role classifier exists. | `docs/rag2_passage_role_oracle_2026-08-25.md` |
| 21 | `d7c6e5be` | Knowledge Object contract v1 | The initial deterministic replay passed but its Go was later withdrawn by the contract audit. | `docs/rag2_knowledge_object_contract_2026-08-25.md` |
| 22 | `Knowledge Object audit slice` | Identity, invalidation, lifecycle, and report-safety audit | V2 corrects ordinal identity, provenance-only updates, object add/remove accounting, and raw report leakage. The offline contract is Go; discovery, storage, and production remain deferred/No-Go. | `docs/rag2_knowledge_object_contract_audit_2026-08-25.md` |
| 23 | `Provenance attestation slice` | Project, root, revision, trust, and read-capability attestation | Persisted project identity survives a root move; clean/modified/untracked Git states derive exact revisions and trust; unavailable Git, symlink escape, binary, and oversized inputs fail closed. Source discovery remains absent. | `docs/rag2_provenance_attestation_contract_2026-08-25.md` |
| 24 | `Source discovery slice` | Fixture-root source discovery and candidate chunking | Two attested sources produce five deterministic Markdown/Dart chunks under file and corpus limits. Generated content, unsupported extensions, symlinks, missing evidence, and ambiguous locators fail closed. Production discovery and storage remain absent. | `docs/rag2_source_discovery_chunking_replay_2026-08-26.md` |
| 25 | `Git evidence collector slice` | Bounded Git execution and typed evidence collection | Exact NUL-delimited probes classify clean, modified, untracked, Unicode, space-bearing, and renamed paths. Root mismatch, timeout, output overflow, invalid paths, and ambiguous output fail closed. Discovery gains a lazy provider boundary; no live manifest is connected. | `docs/rag2_git_evidence_collector_2026-08-26.md` |
| 26 | `Source manifest shadow slice` | Explicit live project manifest without chunks or storage | An opt-in stdout-only CLI preserves bounded exclusions and typed Git failures without roots or source text. Temporary repositories pass; the Caverno preflight finds 2,816 candidates and fails closed before Git because file count exceeds both the selected limit and v1 hard ceiling. | `docs/rag2_source_manifest_shadow_2026-08-26.md` |
| 27 | `Source scope measurement slice` | Pre-Git aggregate scope and role measurement | Shared discovery inventory reports no individual paths or text. Runtime-only is 1,116 files, runtime plus top-level docs is 1,572, and adding tests reaches 2,557. No scope or limit change is selected. | `docs/rag2_source_scope_measurement_2026-08-26.md` |
| 28 | `Batch Git inventory slice` | Fixed-command state and revision parity | One exact-root preflight, one NUL status inventory, and one NUL stage inventory match the per-path oracle across clean, changed, untracked, staged, renamed, and unusual-name cases. Aggregate reports omit paths and Git payloads; manifest integration remains absent. | `docs/rag2_batch_git_inventory_replay_2026-08-26.md` |
| 29 | `Batch manifest integration slice` | Single-inventory manifest evidence integration | The opt-in shadow checks limits before Git, uses exactly three Git commands in-bound, and matches the frozen per-path manifest JSON. Scope selection, storage, and production remain No-Go. | `docs/rag2_batch_manifest_shadow_integration_2026-08-26.md` |
| 30 | `Source-role coverage slice` | Active-project oracle path coverage by measured profile | V1 reported 2/8, 4/8, and 6/8 question coverage, but its Go was later withdrawn by the contract audit. Path coverage is not retrieval evidence. | `docs/rag2_source_role_coverage_replay_2026-08-26.md` |
| 31 | `Source-role coverage contract audit` | Bounded reads, evidence completeness, identity, and eligibility semantics | V1 Go is withdrawn. V2 requires all markers, rejects post-inventory growth and symlink substitution, fingerprints aggregate inventory/evidence state, and makes the default ceiling an eligibility blocker. The 2/8, 4/8, and 6/8 results remain development diagnostics only. | `docs/rag2_source_role_coverage_replay_2026-08-26.md` |
| 32 | `Structural profile candidate` | Question-independent bounded source-role sampling | Fixed role quotas and stable path hashing select 509 files within default limits. The candidate was frozen before fixture use, then covered 6/8 informed development questions. It remains No-Go and cannot be tuned before an untouched holdout. | `docs/rag2_structural_profile_candidate_2026-08-26.md` |
| 33 | `Structural profile untouched holdout` | Independent required-source coverage for the unchanged candidate | The fixture was frozen before candidate use with no development evidence-path overlap. V1 covered 4/8: runtime 2/2, documentation 1/2, tests 0/2, tooling 0/1, and root sources 1/1. Close stratified stable-hash sampling; scope and production remain No-Go. | `docs/rag2_structural_profile_holdout_2026-08-26.md` |
| 34 | `Explicit source roots hypothesis` | Caller-declared complete directories with no intra-root sampling | Freeze `rag2-explicit-complete-source-roots-v1`: explicit non-overlapping directories, complete eligible inclusion, unchanged default limits, zero admission on failure, and aggregate-only output. The policy was frozen before the synthetic implementation; no Caverno roots are selected. | `docs/rag2_explicit_source_roots_hypothesis_2026-08-26.md` |
| 35 | `Explicit source roots synthetic replay` | Root validation, complete admission, batch Git, and all-or-nothing attestation | Nine synthetic cases prove complete in-root admission, explicit repository root, order-independent identities, invalid/duplicate/overlapping/missing/file/symlink rejection, default file-limit zero-Git failure, Git failure rollback, attestation rollback, and aggregate-only output. Contract Go; active-project evaluation and scope selection remain No-Go. | `docs/rag2_explicit_source_roots_hypothesis_2026-08-26.md` |
| 36 | `Explicit roots development declaration` | Freeze a realistic task context and complete roots before questions | The chat memory and conversation-persistence declaration fixes five layer roots. Active-project preflight admits all 451 eligible sources in 3 Git commands with zero blockers. Questions have not been created; storage, retrieval, and production remain No-Go. | `docs/rag2_explicit_source_roots_development_declaration_2026-08-26.md` |
| 37 | `Explicit roots development evaluation` | Frozen in-scope evidence and out-of-scope availability controls | The unchanged five-root declaration passes 11/11 decisions: 12/12 required in-scope paths admitted, 4/4 out-of-scope paths excluded, and 4/4 controls reported `not_available`. Development Go only; an untouched declaration and holdout are still required. | `docs/rag2_explicit_source_roots_development_eval_2026-08-26.md` |
| 38 | `Explicit roots promotion evaluation` | Untouched routines-lifecycle declaration and holdout | The separately frozen declaration passes 11/11 decisions with 8/8 in-scope paths admitted and 4/4 out-of-scope controls unavailable. Complete explicit roots are promotion scope Go. | `docs/rag2_explicit_source_roots_promotion_eval_2026-08-26.md` |
| 39 | `Backend-neutral storage replay` | Declaration-scoped atomic generation semantics | Initial apply, identical no-op, exact stale replacement, deterministic replay, and attestation/policy/injected-failure rollback pass over composed frozen contracts. Storage semantics are Go; retrieval is not evaluated and production remains No-Go. | `docs/rag2_storage_replay_contract_2026-08-26.md` |

## Rejected shortcuts

- Do not use more lexical thresholds or intent keywords as an answerability
  policy. Independent controls showed that topical overlap is not support.
- Do not treat oracle citation coverage as a runtime classifier.
- Do not promote a verifier on a dataset that informed its implementation.
- Do not expand relation aliases or prose keywords directly from a failed
  holdout. Preserve the failed dataset as evaluation evidence.
- Do not interpret an unavailable extractor as evidence that a fact is absent.
- Do not start drift migration, embeddings, routing, prompt injection, model
  calls, or agent-kb federation from diagnostic extraction or oracle results;
  none of those results authorizes a production path.
- Do not treat the fixture-root discovery pass as authorization to enumerate an
  active project, execute Git in production, persist chunks, or inject retrieved
  content. Its evidence proves only the bounded offline acquisition contract.
- Do not reuse `GitChangedPathsService` as RAG2 evidence. Its fail-open empty
  result is correct for its current caller but cannot prove a clean repository.
- Do not treat the standalone Git collector as authorization to enumerate a
  project. Project selection and manifest-only report safety remain a separate
  live-shadow gate.
- Do not raise the live-shadow file ceiling from the Caverno aggregate count.
  Measure source scope first; per-path Git collection over the whole repository
  would multiply process cost without deciding which sources belong in RAG2.
- Do not treat oracle path membership as retrieval or answer-quality evidence.
  The source-role fixture informed the comparison and cannot promote a profile.
- Do not tune or revive `structural_stratified_v1` from its 6/8 development or
  4/8 untouched-holdout misses. A different policy needs a new predeclared
  hypothesis and a new untouched holdout.

## Durable artifacts

- Decision reports: the versioned `docs/rag2_*_2026-08-*.md` files listed in
  the sequence above.
- Frozen corpora and manifests: `tool/fixtures/rag2_*`.
- Re-runnable evaluators: `tool/rag2_*_eval.dart`, `tool/rag2_*_replay.dart`,
  and `tool/rag2_lexical_policy_bakeoff.dart`.
- Regression coverage: `test/tool/rag2_*_test.dart`.
- Roadmap decision log: the RAG2 section in
  `docs/local_llm_agent_roadmap.md`.

Generated reports under `build/integration_test_reports/` are intentionally not
the durable record. Each evidence document records its exact reproduction
command, and the versioned inputs needed to regenerate reports are committed.

## Squash-merge preservation check

The squash must include this handoff, all linked evidence documents, the
`tool/fixtures/rag2_*` inputs, the `tool/rag2_*` evaluators, and their
`test/tool/rag2_*` tests. Do not retain only the roadmap summary.

After the squash lands, verify the durable index from `main`:

```bash
git show main:docs/rag2_investigation_handoff_2026-08-25.md >/dev/null
git grep -n "Canonical investigation handoff" main -- \
  docs/local_llm_agent_roadmap.md
git grep -n "rag2_investigation_handoff_2026-08-25.md" main -- \
  docs/roadmap.md
```

The source branch may be deleted after these checks because the investigation
sequence and reproduction inputs do not rely on its individual commits.

## Verification baseline

The squash-merged baseline passed static analysis, package tests, 70 focused
RAG2 tests, and 10 notification-relay tests through `tool/codex_verify.sh`. The
Git collector slice adds seven focused cases. Future changes should run the RAG2
tests listed under `test/tool/` through the same entrypoint and must not rewrite
the frozen fixture versions. The collector baseline has 77 RAG2 tests; the
manifest-shadow slice adds five focused cases, the source-scope measurement
adds three, the batch inventory adds five, and the batch manifest integration
adds one. The source-role coverage replay v2 replaces five focused cases with
11, and the structural-profile candidate adds five. Project/package static
analysis remains the required gate. The current complete suite contains 123
focused RAG2 tests before the promotion slice; the frozen holdout declaration
and promotion evaluation increase it to 129, and the storage replay increases
it to 134.

## Next entry condition

Freeze the extraction suites, `rag2-passage-role-oracle-v1`, corrected
`rag2-knowledge-object-contract-v2`, and
`rag2-provenance-attestation-contract-v1`, and
`rag2-source-discovery-contract-v1`, and
`rag2-git-evidence-collector-contract-v1`, and
`rag2-source-manifest-shadow-contract-v1`, and
`rag2-source-scope-measurement-contract-v1`, and
`rag2-batch-git-inventory-contract-v1`, and
`rag2-source-role-coverage-contract-v2`; retain v1 only as withdrawn history.
Freeze `rag2-structural-profile-candidate-contract-v1` and its failed holdout
unchanged. The batch manifest integration is Go, the per-path collector stays
the frozen parity oracle, and stratified stable-hash sampling is closed. The
synthetic replay for `rag2-explicit-complete-source-roots-v1` is Go. The chat
memory and conversation-persistence development declaration is frozen and
passes active-project acquisition preflight and all development scope gates. A
separately frozen routines-lifecycle declaration passes the unchanged evaluator
on an untouched 11-case promotion holdout: 8/8 in-scope evidence paths are
admitted and 4/4 out-of-scope controls are excluded. Explicit complete source
roots are promotion scope Go. The backend-neutral
`rag2-storage-replay-contract-v1` now composes the frozen Knowledge Object v2,
provenance, discovery, and source-scope contracts and passes atomic generation,
no-op, invalidation, deterministic replay, and rollback gates. Storage semantics
are Go; retrieval is not evaluated and production remains No-Go. Keep this
fixture frozen. A later persistence-backend hypothesis must preserve the replay
contract through migration and reopen testing before SQLite, FTS5, Drift, or
embeddings are selected. Prompting, routing, tools, model calls, settings, and
application wiring remain out of scope.
