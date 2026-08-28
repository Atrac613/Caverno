# RAG2 Explicit Source Roots Promotion Holdout Declaration

Date: 2026-08-26
Status: declaration frozen; promotion scope Go
Declaration: `caverno-routines-lifecycle-promotion-holdout-v1`
Contract: `rag2-explicit-complete-source-roots-v1`

## Decision

Freeze one promotion holdout declaration for this task context:

> Trace how routines are represented, persisted, scheduled, executed, and
> synchronized across the routines feature layers.

The declaration contains these complete repository-relative roots:

1. `lib/features/routines/data`
2. `lib/features/routines/domain`
3. `lib/features/routines/presentation/providers`

The machine-readable declaration is frozen in
`tool/fixtures/rag2_explicit_source_roots_holdout_v1/declaration.json`. Its
declaration identity is
`declaration_62f029c04183343e2b6e0616e2afc088a59a0f45f2eb360bb3aa99a0e5b65856`.
The declaration contains no questions or evidence paths.

## Selection Basis

The task context and roots were selected from the documented feature
architecture and aggregate file counts before any promotion question was
created. The roots cover the routines data layer, domain representation and
policies, and provider-level scheduling and state synchronization.

The declaration is complete at each selected directory boundary. It excludes
routines pages, widgets, and presentation models, along with chat, settings,
remote coding, and core services. Future holdout questions whose required
evidence lives only in excluded areas must resolve to `not_available`.

No development, source-role, structural-profile, or other prior fixture
question or required evidence path may be reused to create the promotion
holdout. The roots and evaluator must not be changed in response to holdout
results.

## Active-Project Preflight

The opt-in replay was run against the current Caverno checkout before creating
any promotion question:

| Measurement | Result |
| --- | ---: |
| Declared roots | 3 |
| Whole-project eligible candidates | 2,838 |
| Declared-root eligible candidates | 15 |
| Declared-root eligible bytes | 170,156 |
| Generated files excluded | 2 |
| Git commands | 3 |
| Admitted sources | 15 |
| Blockers | 0 |

The result fits the unchanged defaults of 512 sources, 512 KiB per source, and
32 MiB total. Batch Git evidence and all-source attestation completed without a
partial admission. The live snapshot identities were:

- project: `project_564f19ff6aabec625926aa32c65caad9faf0e21394348a61a4495989e9187e75`
- inventory metadata:
  `inventory_metadata_8121e06166ed82cff441bedaa3dd58753cba165d5128c1fb8e39d8b8c987b158`
- selected metadata:
  `selected_metadata_1b56cdb02e64a82934e171a02edc3e8dab1cba5ff174bb2d1800a6a96ce01ca2`

Inventory identities are observations of this checkout and may change with
source edits. The declaration identity and roots are frozen.

## Decision Boundary

This preflight proves only that the declaration is valid, complete, and within
the acquisition limits. It does not prove evidence coverage, out-of-scope
classification, retrieval, ranking, answer correctness, or citation quality.
Storage, retrieval, application wiring, and production remain No-Go.

## Verification

The declaration has focused tests for immutable roots, default policy,
identity, absence of evaluation content, normalization, uniqueness, and
overlap rules. The complete RAG2 suite must remain green.

## Next Entry Condition

The separate promotion fixture passes the unchanged evaluator without modifying
this declaration. See
`docs/rag2_explicit_source_roots_promotion_eval_2026-08-26.md`. Preserve the
declaration and fixture as frozen promotion evidence while the next slice
defines a storage replay using the existing Knowledge Object v2, provenance,
discovery, and source-scope contracts.
