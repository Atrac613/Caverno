# RAG2 Explicit Source Roots Development Declaration

Date: 2026-08-26
Status: declaration frozen; evaluation questions not created
Declaration: `caverno-chat-memory-persistence-development-v1`
Contract: `rag2-explicit-complete-source-roots-v1`

## Decision

Freeze one active-project development declaration for this task context:

> Trace how chat session memory and conversation persistence are represented,
> mutated, stored, and synchronized across the chat feature layers.

The declaration contains these complete repository-relative roots:

1. `lib/features/chat/application/persistence`
2. `lib/features/chat/data/repositories`
3. `lib/features/chat/domain/entities`
4. `lib/features/chat/domain/services`
5. `lib/features/chat/presentation/providers`

The machine-readable declaration is frozen in
`tool/fixtures/rag2_explicit_source_roots_development_v1/declaration.json`.
Its declaration identity is
`declaration_242f507db96fd65363985db1ec4f1b4978bfa33e5263a65dce1ee64bad916c30`.

## Selection Basis

The roots were selected from the repository architecture and aggregate file
counts only. Together they cover domain representation and orchestration,
repository persistence, application mutation coordination, and provider-level
state synchronization. No evaluation question or required evidence path was
used to choose or narrow a root.

The declaration is intentionally complete rather than path-sampled. It does
not include chat data sources, presentation widgets/pages, settings, routines,
or core services. Later questions whose required evidence lives only in those
areas must resolve to `not_available` under this declaration.

After the roots had already been selected, a search intended to locate fixture
filenames printed one unrelated question line from a prior source-role fixture.
That line did not influence the declaration. To preserve evaluation integrity,
all prior source-role and structural-profile fixture questions are forbidden in
the new development set.

## Active-Project Preflight

The opt-in replay was run against the current Caverno checkout before creating
any new evaluation question:

| Measurement | Result |
| --- | ---: |
| Declared roots | 5 |
| Whole-project eligible candidates | 2,833 |
| Declared-root eligible candidates | 451 |
| Declared-root eligible bytes | 3,681,527 |
| Generated files excluded | 28 |
| Git commands | 3 |
| Admitted sources | 451 |
| Blockers | 0 |

The result fits the unchanged defaults of 512 sources, 512 KiB per source, and
32 MiB total. Batch Git evidence and all-source attestation completed without a
partial admission. The live snapshot identities were:

- project: `project_1bc4db4a130877202a3551239f1fc2ad246bb5aabcde7c58d57d323b649d7e6b`
- inventory metadata:
  `inventory_metadata_169c9bea7bb98d366c6d3fba47c2b3c207c4685d5bf081c04dd7b7f4ab9c8ed7`
- selected metadata:
  `selected_metadata_180efdf3f34ba1d4dcbaef0647097bf2673cf173d1035bf94a79eccaf2a6ce60`

Inventory identities are observations of this checkout and may change with
source edits. The declaration identity and roots are frozen.

## Decision Boundary

This preflight proves only that the declaration is valid, complete, and within
the acquisition limits. It does not prove evidence coverage, out-of-scope
classification, retrieval, ranking, answer correctness, or citation quality.
Storage, retrieval, application wiring, and production remain No-Go.

## Verification

The declaration has two focused tests for its immutable roots, default policy,
identity, absence of evaluation content, normalization, uniqueness, and overlap
rules. The repository verifier passes project and package analysis, three
package test suites, 29 focused acquisition tests, and 10 notification-relay
tests. The complete RAG2 suite passes all 119 tests.

## Next Entry Condition

Create a new development fixture after this declaration commit. Include both
in-scope questions and deliberately out-of-scope controls. Require every
in-scope evidence path to fall below a declared root, every undeclared evidence
path to remain excluded, and every out-of-scope control to resolve explicitly
to `not_available`. Do not reuse or inspect prior fixture questions.
