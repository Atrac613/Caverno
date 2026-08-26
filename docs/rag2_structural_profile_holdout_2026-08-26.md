# RAG2 Structural Profile Holdout

Date: 2026-08-26
Status: holdout complete; stratified stable-hash strategy closed
Candidate contract: `rag2-structural-profile-candidate-contract-v1`
Candidate: `structural_stratified_v1`
Evaluation contract: `rag2-source-role-coverage-contract-v2`

## Outcome

The frozen structural profile covered four of eight questions in one untouched
active-project holdout. It retained both runtime questions, one of two
documentation questions, the root-source question, zero of two test questions,
and zero of one tooling question. The candidate fits the default source limits
but fails required-source coverage, so scope eligibility is No-Go.

The informed development fixture previously produced 6/8. The independent
holdout produced 4/8. Close this stratified stable-path-hash sampling strategy.
Do not tune its quotas, byte budgets, role allocation, salt, or hash ranking
from either failure.

## Untouched Evaluation Order

The holdout was evaluated in this order:

1. Select eight active-project questions and evidence sources without invoking
   the structural candidate selector or coverage replay.
2. Preserve the development fixture's role distribution: two runtime, two
   documentation, two tests, one tooling, and one root-source question.
3. Exclude every evidence path used by the informed development fixture.
4. Freeze the fixture and its validation test in commit `ceda09de`.
5. Apply the unchanged v1 candidate exactly once.
6. Record the aggregate stdout result without inspecting or publishing selected
   paths.

The fixture is
`tool/fixtures/rag2_structural_profile_holdout/fixture.json`. Its test pins the
question count, role balance, unique evidence paths, development-fixture
separation, source-role classification, and required-marker availability. The
fixture is JSON, and the validation was added to an existing Dart test path, so
freezing it did not add a new `.dart` or `.md` candidate path.

## One-Time Replay

The candidate was applied once with:

```bash
fvm dart run tool/rag2_source_role_coverage_replay.dart \
  --enable-live-replay \
  --project-id caverno-structural-profile-holdout-2026-08-26 \
  --project-root . \
  --fixture tool/fixtures/rag2_structural_profile_holdout/fixture.json
```

Aggregate identities from that run:

- Project: `project_5c9c4954a443bc43fa6b41535ac4e683e5294b3036ec316d1b5c21094fd50e7e`
- Fixture: `fixture_0a72eed154cff51d72b8f4eb8a079adf7692c3dfd5460d72cd19f4e370d22706`
- Inventory metadata: `inventory_metadata_66ae678ba77f4dbad1059c25963842c3f5fb89ab8ed7fd3ec3ad53a2bbf3250e`
- Validated evidence: `evidence_25813c50d863048c6c6d0447526671e2969b317295c4677fefb350405dd2e14e`

## Aggregate Result

| Profile | Files | Bytes | Covered | Default limit | Hard limit | Eligibility |
| --- | ---: | ---: | ---: | --- | --- | --- |
| All-candidates control | 2,829 | 28,521,378 | 8/8 | No-Go | No-Go | No-Go |
| Runtime only | 1,116 | 9,617,137 | 2/8 | No-Go | Go | No-Go |
| Runtime + top-level docs | 1,576 | 14,069,716 | 4/8 | No-Go | Go | No-Go |
| Runtime + tests + top-level docs | 2,564 | 25,855,955 | 6/8 | No-Go | No-Go | No-Go |
| Structural stratified v1 | 509 | 5,341,287 | 4/8 | Go | Go | No-Go |

Structural candidate role coverage:

| Source role | Covered |
| --- | ---: |
| Runtime source | 2/2 |
| Documentation | 1/2 |
| Tests | 0/2 |
| Tooling | 0/1 |
| Root sources | 1/1 |

The all-candidates oracle control covered 8/8, confirming that the fixture
evidence was present in the bounded inventory. The structural candidate's only
blocker was `question_coverage_incomplete`; its file and corpus totals remained
inside both ceilings.

## Decision and Next Entry Condition

Retain v1 and this failed holdout as immutable evidence. Do not reuse the
holdout as independent promotion evidence for another policy. Source
selection, storage, retrieval, and production remain No-Go.

That entry condition is now satisfied by the frozen explicit source-roots
hypothesis in
`docs/rag2_explicit_source_roots_hypothesis_2026-08-26.md`. It moves omission
authority to an explicit caller declaration, admits every eligible source below
the declared roots, and fails closed at the existing default limits. It has not
been implemented or evaluated. Until its synthetic contract is proven, do not
add SQLite, FTS5, embeddings, prompting, routing, tools, model calls, or
application wiring.
