# RAG3 Offline Hybrid Evaluation Contract

## Task

- Goal: freeze the storage-independent quality, degradation, determinism, and
  context-budget contract for RAG3 hybrid retrieval before creating a promotion
  fixture or adding production code.
- User-visible behavior: none in this slice.
- Non-goals: vector persistence, schema migration, `search_knowledge`, tool
  catalog changes, prompt injection, automatic routing, model calls, chat
  wiring, runtime passage-role classification, agent-kb federation, reranking,
  and ANN search.

## Decision

Contract `rag3-offline-hybrid-eval-contract-v2` is frozen on 2026-08-31.
It supersedes v1 because v1 incorrectly placed candidate rankings beside the
promotion oracle, which could make the holdout self-fulfilling. This correction
changes only input ownership and commit order; the candidate, constants, gates,
and production exclusions remain unchanged.
The frozen candidate is `rrf-k60-l1-v1-budget6000-v1`:

- lexical input: the unchanged RAG2 AppDatabase-hosted
  `trigram_or_idf` candidate at threshold `0.15`;
- vector input: bounded brute-force cosine chunk rankings carrying a complete
  model, endpoint, and dimension fingerprint;
- RRF constant: `60`;
- lexical weight: `1.0`;
- vector weight: `1.0`;
- maximum lexical input depth: `32` chunks;
- maximum vector input depth: `32` chunks;
- hard rendered-context budget: `6,000` estimated tokens;
- maximum selected groups from one Knowledge Object: `2`.

These values must not be tuned from the promotion holdout. A different weight,
threshold, fusion constant, input depth, diversity cap, or token budget requires
a new contract version and a new untouched promotion fixture.

## Why This Slice Comes First

RAG1 proves that the embedding endpoint, cosine ranking, and an RRF-shaped
baseline can be measured, but its vector baseline ranks whole documents, uses
equal untyped inputs, and has only focused cosine and deterministic-fusion unit
coverage. It does not implement RAG3 chunk selection, diversity, merging,
budgeting, or degraded reasons.

RAG2 supplies provenance-bearing chunks and a promoted lexical candidate, but
its Knowledge Object types remain evaluation artifacts and its hosted query is
explicitly not a ranking or quality gate. Production retrieval is still absent.

The LL5 `Embeddings` table stores model and dimension but not an endpoint
fingerprint. `DriftEmbeddingStore.search` filters only by source type and treats
mismatched dimensions as zero-scored rows instead of refusing an incompatible
corpus. Reusing it directly would make the production design precede the RAG3
fingerprint and failure contract.

## Frozen Fixture Contract

The evaluator consumes immutable fixture truth and a separately produced
candidate run. It has no database, HTTP, provider, settings, or tool dependency.
The fixture is committed before the evaluator or ranking producer and contains
no candidate rankings, scores, selected groups, exclusions, latency, or results.

Each case declares:

- a stable case ID and whether retrieval is expected;
- query text in the private fixture input, never in the normal report;
- Knowledge Object and chunk metadata, content, content hashes, passage roles,
  and provenance;
- object-level and chunk-level relevance judgments;
- expected answer-support, abstention-support, topical-only, and irrelevant
  roles for post-retrieval scoring;
- Japanese and authority strata;
- the expected behavior of the empty negative control.

The fixture identity includes its schema version, fixture ID, and deterministic
corpus hash. The oracle is complete for every case and references only IDs in
the fixture corpus.

## Frozen Candidate Run Contract

The ranking producer reads the committed fixture and emits a separate run. Each
run binds its schema version, run ID, contract ID, candidate ID, fixture ID, and
corpus hash. Each submitted case declares:

- lexical and vector ranked chunk IDs;
- vector availability plus an explicit degraded reason when unavailable;
- a vector-validation receipt covering finite values, non-zero magnitude,
  uniform dimensions, and query/corpus fingerprint equality;
- the complete vector fingerprint identity below;
- bounded latency and resource measurements required by the evaluator.

No-search cases must be present as unsubmitted cases with empty rankings. A run
that does not bind the exact fixture, corpus, contract, and candidate identities
is invalid before scoring.

Every vector arm carries this fingerprint as one indivisible identity:

- normalized embeddings endpoint identity;
- requested model ID;
- response model ID;
- vector dimension;
- fingerprint schema version.

The ranking producer validates raw vectors and emits the receipt; the evaluator
does not persist or render those vectors. Missing embeddings are
`not_available`, never a zero score. A query/corpus model, endpoint, response
model, or dimension fingerprint mismatch, a non-finite value, a zero-magnitude
vector, or unequal dimensions invalidates the vector arm before fusion and
records a stable degraded reason. It must not leave incompatible rows at the
bottom of an otherwise available ranking.

## Frozen Fusion Contract

Rank positions are one-based. For chunk `d`, weighted reciprocal-rank fusion is
defined as:

```text
score(d) = 1.0 / (60 + lexicalRank(d))
         + 1.0 / (60 + vectorRank(d))
```

An absent arm contributes nothing. Duplicate chunk IDs within an arm collapse
to their best rank before scoring. The deterministic order is:

1. descending fused score;
2. ascending best rank observed in either arm;
3. ascending chunk ID.

When vectors are unavailable, the candidate returns the bounded lexical order
with status `degraded` and the exact vector reason. The lexical-only result is
still scored, but it cannot be reported as an available hybrid measurement.

## Frozen Context Selection Contract

Fusion ranks chunks. Context selection then applies these rules without
changing the recorded fused order:

1. Merge only chunks from the same object, revision, object content hash,
   source trust, and contiguous or overlapping one-based line spans.
2. Render merged content in ascending line order and retain the best fused rank
   as the group rank.
3. Select groups in fused order while allowing at most two groups from one
   Knowledge Object.
4. Render citation metadata as part of the candidate context using
   `rag3-citation-v1` exactly:
   `[source=<sourcePath>; revision=<revision>; lines=<start>-<end>; object_sha256=<objectContentHash>; chunk_sha256=<groupContentHash>]`.
   The group content hash covers the merged content exactly as rendered.
5. Estimate one group as
   `ceil((content runes + rendered citation runes) / 4)` tokens.
6. Never split a group. Skip a group that would exceed the remaining budget and
   continue to the next fused group.
7. Stop after exhausting candidates or reaching the 6,000-token budget.

The report records fused ranks before selection, every exclusion reason,
selected groups, per-group estimated tokens, the total, and only a digest of
the embedding fingerprint. Absolute paths, source text, query text, lexical
terms, vectors, raw endpoints, endpoint credentials, and API keys are omitted
from normal JSON and Markdown reports.

Passage roles are fixture oracle data applied only after retrieval. They never
change vector ranking, RRF, deduplication, merging, diversity, or budgeting, and
they remain `unknown` at runtime.

## Fixture Separation

Existing RAG1 and RAG2 fixtures are instrument data only. They may prove metric
behavior and expose regressions, but they cannot promote the frozen candidate.

After this corrected contract commit, create a content-hashed 20-case promotion
fixture and complete oracle in a separate commit before implementing the
evaluator or producing a candidate run. The promotion corpus must contain:

- 14 answerable cases, including four Japanese cases;
- four unavailable-answer cases: two with expected abstention support, one
  topical-only case, and one no-evidence case;
- two explicit no-search cases that are not submitted to either retriever;
- current, historical, conflict, safety, and source-diversity strata;
- multi-chunk objects that exercise adjacency merging and the two-group cap;
- at least one case where the 6,000-token budget excludes a relevant lower-rank
  group without exceeding the budget.

The no-search flag is fixture-declared caller policy, not a learned router. It
only verifies that the offline orchestration does not retrieve when the caller
has already said retrieval is unnecessary. RAG5 still owns automatic routing.

## Promotion Gates

All gates are conjunctive:

- object metrics are scored on the final budgeted group order, projecting each
  object only at its first selected group;
- hybrid object Recall@10 is at least `0.85`;
- hybrid object Hit@5 is at least `0.85`;
- hybrid object MRR@10 is at least `0.65`;
- hybrid misses Hit@5 on an answerable case where the better lexical/vector arm
  passes Hit@5 on at most one case;
- answer-support retrieval passes at least 13/14 cases;
- Japanese answer-support retrieval passes 4/4 cases;
- expected abstention support passes 2/2 cases;
- unavailable cases returning only irrelevant evidence are 0/4;
- context-budget violations are zero;
- retrievals on the two declared no-search cases are zero;
- citation and provenance validation pass for every selected group;
- deterministic replay produces byte-identical aggregate reports;
- the known-bad empty/shuffled fusion arm fails its required quality gate;
- a budget-bypass negative control fails the zero-violation gate;
- an unavailable or invalid vector arm degrades to lexical with the declared
  reason and never appears as an available zero-scored vector arm.

The initial RAG3 offline decision is Go only when every gate passes. A No-Go is
a valid result and must freeze the candidate and report rather than trigger
promotion-fixture tuning.

## Task Decomposition And Commit Order

1. **Corrected contract**: commit v2 before fixture work; preserve every v1
   candidate constant and promotion gate.
2. **Untouched holdout**: commit the complete promotion fixture, oracle, schema,
   and corpus hash without candidate rankings or evaluator results.
3. **Pure evaluator and run producer**: implement deterministic ranking input,
   fusion, degradation, selection, metrics, reports, and negative controls with
   focused tests.
4. **Instrument run**: validate the evaluator on inspected RAG1/RAG2 data; fix
   instrument defects without opening the promotion fixture.
5. **Promotion run**: apply the committed evaluator once to the untouched
   holdout and pin the aggregate result in tests.
6. **Decision record**: update roadmaps with Go/No-Go evidence. Do not add
   persistence or a tool in this phase.
7. **Later production slices**: only after offline Go, design fingerprinted
   vector persistence, then the read-only tool and local-LLM citation canary as
   separately reversible changes.

## Acceptance Criteria For This Contract Slice

- The contract ID, frozen candidate, fusion formula, ordering, degradation,
  context selection, fixture/run separation, gates, and commit order are
  explicit.
- RAG1/RAG2 fixtures are marked instrument-only.
- Promotion fixture creation is provably later than the contract commit.
- Production and runtime behavior remain unchanged.
- The detailed and summary roadmaps point to this contract and identify RAG3 as
  the next RAG-track milestone.
- The worktree passes `git diff --check` and `tool/codex_verify.sh`.

## Next Entry Condition

The v2 one-shot promotion result is No-Go and is frozen in
`docs/rag3_promotion_eval_2026-08-31.md`. Do not enter vector persistence,
`search_knowledge`, prompting, or runtime wiring from this contract. A future
attempt requires a new contract version, a candidate frozen from separate
instrument evidence, and a newly committed untouched promotion fixture. Do not
use the v2 promotion holdout as a development or tuning set.

## Implementation Status

The corrected contract, untouched holdout, pure evaluator/run producer,
instrument adapter, promotion transport, and privacy-safe aggregate were
committed in order on 2026-08-31. The instrument passed on inspected RAG1 and
RAG2 data without promotion-fixture access. The valid one-shot promotion run
then returned No-Go because one unavailable case selected only irrelevant
evidence. The candidate, holdout, and report are frozen, and no production
retrieval code has been added. Evidence is recorded in
`docs/rag3_instrument_eval_2026-08-31.md` and
`docs/rag3_promotion_eval_2026-08-31.md`.
