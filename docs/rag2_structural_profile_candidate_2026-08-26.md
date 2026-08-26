# RAG2 Structural Profile Candidate

Date: 2026-08-26
Status: candidate frozen; development and holdout coverage No-Go; strategy closed
Contract: `rag2-structural-profile-candidate-contract-v1`
Candidate: `structural_stratified_v1`

## Outcome

One question-independent source profile now fits the existing default limits.
It selects 509 files and about 5.34 MiB from the current Caverno inventory,
below the 512-file and 32 MiB ceilings. It excludes instruction-bearing files
and does not use question IDs, marker text, or individual evidence paths.

The frozen candidate covers six of eight questions in the informed development
fixture. It retains both documentation questions, the root-source question,
one of two runtime questions, both test questions, and zero of one tooling
question. The candidate is therefore No-Go and does not select a source scope.
The result was not used to tune v1 before the untouched holdout replay.

The unchanged candidate subsequently covered 4/8 questions in the untouched
holdout: runtime 2/2, documentation 1/2, tests 0/2, tooling 0/1, and root
sources 1/1. The strategy is closed. See
`docs/rag2_structural_profile_holdout_2026-08-26.md`.

## Selection Order

The candidate was defined in this order:

1. Measure only aggregate source-role and top-level counts.
2. Freeze role quotas, byte budgets, the contract version, and stable-hash
   ranking without loading the question fixture.
3. Run the structural candidate measurement and confirm default-limit fit.
4. Apply the already-frozen candidate to the existing development fixture.

This order prevents development question paths and markers from influencing
candidate membership.

## Frozen Policy

Candidates are first grouped by the existing source-role classifier. Within
each admitted role they are ordered by SHA-256 of contract version, role, and
repository-relative path. The lowest stable scores are admitted until either
the role's file or byte budget is reached. The selected output is finally
sorted by repository-relative path.

| Source role | File budget | Byte budget | Current files | Current bytes |
| --- | ---: | ---: | ---: | ---: |
| Runtime source | 256 | 16 MiB | 256 | 2,218,447 |
| Documentation | 96 | 4 MiB | 96 | 1,314,314 |
| Tests | 96 | 6 MiB | 96 | 1,167,291 |
| Tooling | 48 | 4 MiB | 48 | 566,425 |
| Root sources | 8 | 1 MiB | 6 | 56,873 |
| Other `.dart` / `.md` | 8 | 1 MiB | 7 | 17,937 |
| Instruction-bearing | 0 | 0 | 0 | 0 |
| **Total** | **512** | **32 MiB** | **509** | **5,341,287** |

The role caps intentionally do not borrow unused root or `other` capacity.
Borrowing would make one role's membership depend on another role's inventory
and would weaken the frozen comparison. Stable hashing avoids alphabetical
directory-prefix bias while remaining offline and deterministic. It is an
evaluation sampling policy, not a claim that arbitrary omission is suitable
for production indexing.

The report contains only aggregate counts, fixed budgets, hashed project,
inventory-metadata, and selection identities. It omits roots, paths, source
text, questions, markers, and exclusions. The inventory identity covers sorted
path/size/exclusion metadata but does not attest every candidate's content.

## Reproduction

Freeze and measure the candidate without a question fixture:

```bash
fvm dart run tool/rag2_structural_profile_candidate.dart \
  --enable-live-measurement \
  --project-id caverno-structural-profile-v1-2026-08-26 \
  --project-root "$PWD"
```

Then apply the frozen candidate to the development fixture:

```bash
fvm dart run tool/rag2_source_role_coverage_replay.dart \
  --enable-live-replay \
  --project-id caverno-structural-profile-development-replay-2026-08-26 \
  --project-root "$PWD" \
  --fixture tool/fixtures/rag2_source_role_coverage_v2/fixture.json
```

## Verification Contract

Focused tests prove:

- exact per-role file quotas and default-limit fit;
- per-role byte-budget enforcement;
- deterministic selection under reversed inventory order;
- instruction-bearing exclusion;
- aggregate-only report privacy;
- exact 512-file and 32 MiB total budgets;
- explicit opt-in and the default per-file ceiling; and
- integration into the required-source coverage replay.

Run:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/tool/rag2_structural_profile_candidate_test.dart \
  --test test/tool/rag2_source_role_coverage_replay_test.dart \
  --test test/tool/rag2_source_scope_measurement_test.dart

fvm flutter test test/tool/rag2_*_test.dart
```

The repository verifier passes project/package static analysis, three package
test suites, 20 focused tests, and 10 notification-relay tests. All 108 focused
RAG2 tests pass.

## Decision and Next Entry Condition

Freeze `rag2-structural-profile-candidate-contract-v1`, its role budgets,
stable-hash salt, default-limit policy, and instruction-bearing exclusion. The
development 6/8 is diagnostic and cannot promote or tune the candidate.

The separate untouched active-project holdout was frozen before candidate use
and evaluated exactly once. Its 4/8 result closes this stratified stable-hash
sampling strategy. Selection, storage, retrieval, and production remain No-Go.

Do not revise quotas from the development or holdout misses, and do not reuse
the holdout to promote another policy. Any resumed source-scope work needs a
new question-independent hypothesis and a new untouched holdout. Do not add
SQLite, FTS5, embeddings, prompting, routing, tools, model calls, or
application wiring.
