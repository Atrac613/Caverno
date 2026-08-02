# ChatNotifier Renewal Candidate Ranking

Reviewed 2026-08-02 at synthesis revision
`05a6a25c0237c0b2ce6e93fab3055c36121e45f4`. This report combines three
read-only Phase 1 inventories. It does not authorize a deletion, migration, or
persisted-schema change.

## Decision

There is one ready deletion slice: remove the two orphan proposal-parsing
delegates. A clean matching-build corpus now completes their static unreachable
proof without a contradictory observation.

The highest-confidence implementation candidates are:

1. give execution-task status one owner by joining immutable task intent with
   optional execution progress; and
2. share pure plan-artifact revision mechanics underneath the distinct
   conversation and routine persisted wrappers.

Neither should be folded into the first `TurnRuntime` extraction. Status
ownership should be corrected before task state crosses that boundary, while
plan-artifact persistence remains outside the turn runtime.

The operational next slice is deleting those two delegates and updating the
finite guard manifest. After that focused deletion, proceed to the persisted
workflow-origin audit.

## Ranking Rules

- Confidence describes the evidence for the proposed action, not confidence
  that the affected code is large.
- Candidates are ordered by estimated affected surface within each confidence
  band. Size never compensates for lower confidence.
- Delete, migrate, blocked migration, and investigate lanes remain separate.
- A zero observation is never treated as static reachability evidence.
- Deletion takes operational precedence over migration once a candidate meets
  the complete `dead` contract, because it avoids another extraction layer.

## Delete Candidates

### Ready

| Rank | Candidate | Current evidence | Current size |
| ---: | --- | --- | ---: |
| D1 | Remove `_tryRepairAndDecodeMap` and `_repairJsonCandidate` delegates | Zero production selection roots, no unresolved invocation edge, direct live replacements in `ProposalParsingTextUtils`, and no contradiction in 4 clean matching-build records | 1 file; 6 declaration/body lines, 8 lines including separators |

## Migration Candidates

### High confidence

| Rank | Candidate | Estimated affected surface | Evidence | Dependencies and stop condition |
| ---: | --- | --- | --- | --- |
| M1 | Make `ConversationExecutionTaskProgress` the only owner of task status | 20-30 source/test files selected from 40 non-generated chat files that reference task status | `Conversation.projectedExecutionTasks` already overlays progress onto task intent; persisted task status is a competing default and state channel | First introduce a pure `ExecutionTaskView` join. Stop if legacy source-status semantics cannot be reproduced without writing two authorities. |
| M2 | Share pure plan-artifact revision mechanics | 8-16 source/test/generated files | Conversation and routine artifacts duplicate draft/approved comparison, bounded revision history, normalization, and revision labels | Keep both persisted wrappers and routine freshness rules. Stop if byte-shape JSON round trips or revision ordering differ. |

M1 ranks before M2 because both actions have high-confidence ownership evidence
and M1 has the larger measured affected surface. M2 remains an independent
cleanup, not a prerequisite for the runtime renewal.

### Medium confidence

| Rank | Candidate | Estimated affected surface | Evidence | Dependencies and stop condition |
| ---: | --- | --- | --- | --- |
| M3 | Retire workflow as a second authored source while retaining a plan-derived execution projection | 25-40 source/test files | Approved plans are already preferred, hashed, and projected; plan-first conversations block the legacy editor | Requires the workflow-origin audit in I2 and a compatibility path for legacy workflow-only conversations. Stop if a supported current path still requires independently authored workflow state. |
| M4 | Add explicit provenance or a snapshot invariant between goal text and plan/workflow objective text | 6-10 source/test files | Goal lifecycle policy and contract objective text are distinct, but current strings can diverge without provenance | Start with the read-only mismatch diagnostic in I4. Stop if fixtures show divergence is always deliberate or provenance cannot be added compatibly. |

M3 is not a schema-deletion task yet. M4 defines a relationship between distinct
entities; it does not merge goal and plan.

## Blocked Migration

| Candidate | Direction confidence | Measured surface | Blocker | Re-entry condition |
| --- | --- | --- | --- | --- |
| Wire `ChatToolHandlerCatalog` as the production composition boundary | High that all six binding groups can fit an owner-aware catalogue; low that the current composition is ready | 118 static plus 52 private dynamic definitions across 6 binding groups | The registry-last WS6-19 gate remains unmet; all three named modules capture `ChatNotifier`, and Browser/Computer Use still require policy-aware adapters | Reconcile or replace the WS6-19 safety contract, expose typed owner/UI/approval/turn-result ports, and prove branch precedence plus fallback behavior before wiring |

The pinned corpus contained only two records and one normalized submission. It
proves catalogue enumeration and binding joins, not production frequency. No
definition is a deletion candidate based on its zero count.

## Investigation Candidates

### High confidence

| Rank | Investigation | Decision unlocked | Measured decision surface | Bounded next action |
| ---: | --- | --- | --- | --- |
| I1 | Audit persisted workflow origins | Whether M3 can remove the legacy authored-workflow path | Potentially unlocks the 25-40-file M3 surface | Add a read-only repository audit or deterministic migration fixture that classifies plan-derived versus legacy workflow-only records. Stop before deletion if any supported legacy population lacks a backfill. |

The matching-build guard capture is complete and has moved its two closed
proofs into D1. I1 becomes the next investigation after D1 is deleted.

### Medium confidence

| Rank | Investigation | Decision unlocked | Measured decision surface | Bounded next action |
| ---: | --- | --- | --- | --- |
| I2 | Reconcile the WS6-19 prerequisites against the new runtime boundary | Whether the blocked catalogue migration should retain its old sequence or use a replacement safety contract | 170 definition rows and 6 binding groups | Produce a prerequisite matrix for owner, UI, approval, result-store, Browser, Computer Use, and fallback ports. Do not implement handlers in the reconciliation slice. |
| I3 | Diagnose goal/objective divergence read-only | Whether M4 needs provenance, one-way seeding, or no change | 6-10 source/test files | Add fixtures for deliberate and accidental mismatches plus a diagnostic that performs no mutation. |

### Unranked unresolved guard work

The other 63 guard candidates do not have a closed production call graph and a
matching-build action state. Do not bulk-instrument or migrate them. Select at
most one additional event using the checked-in telemetry selection contract and
keep every unresolved callback, registration, and configuration edge explicit.

## Stable Boundaries and Exclusions

- Keep goal, plan with execution tasks, and routine as three user-facing
  concepts.
- Keep routine scheduling, recurrence, history, notification, and delivery out
  of `TurnRuntime`.
- Keep plan approval, projection persistence, task-ID reconciliation, and
  durable goal budgets behind ports rather than owned by a turn runtime.
- Exclude tool-payload subsetting and KV-cache optimization; the tool inventory
  measures handler residency only.
- Exclude dynamic MCP names, schemas, endpoint details, configuration
  fingerprints, private paths, and session identifiers.
- Exclude runtime-frequency conclusions from the tiny synthetic tool corpus.
- No persisted user corpus, schema migration prototype, or live LLM canary was
  used for the concept ranking.

## Evidence Revisions and Dynamic Provenance

| Input | Evidence revision | Notes |
| --- | --- | --- |
| Guard reachability inventory | `55efb18f51e2739f195bca0d5bd7b1669d5c0f9d` | 65 represented candidates; 2 dead and 63 unresolved after matching-build analysis |
| Tool catalogue residency inventory | `de73f746f16eed1125b0f4f92cb44a11b57ea7de` | 118 static and 52 private dynamic rows linked to 6 bindings |
| Concept overlap inventory | `8561fedb42471f0e99cd15d897002acb30f5e88b` | Read-only lifecycle and ownership review |
| Consolidated synthesis | `05a6a25c0237c0b2ce6e93fab3055c36121e45f4` | Documentation-only task-contract revision; classified production code is unchanged from the input reviews |

The tool measurement used analyser revision
`de73f746f16eed1125b0f4f92cb44a11b57ea7de`, corpus-manifest digest
`b4b24f21d53d237cf80b5c34fb21fb2844cd477948f56286d514dae6666cbe4d`,
one file, two records, one configuration segment, one catalogue snapshot, and
the inclusive logged range `2026-08-02T02:45:00Z` through
`2026-08-02T02:46:00Z`. Its represented build was clean revision
`739957a5ae1958347b3ea118b34e388747f954c4`. The private measurement and
catalogue-snapshot digests remain recorded in the residency inventory; this
report does not duplicate private topology.

## Reproduction Commands

```bash
python3 test/python/analyze_chat_notifier_inventory_test.py
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --check-guard-manifest tool/chat_notifier_guard_inventory.json
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --guard-manifest tool/chat_notifier_guard_inventory.json \
  --check-telemetry-selection \
  tool/chat_notifier_guard_telemetry_selection.json
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --check-tool-manifest tool/chat_notifier_tool_catalog_inventory.json
rg -n "_tryRepairAndDecodeMap|_repairJsonCandidate" lib test docs
rg -l "ConversationWorkflowSpec|ConversationExecutionTaskProgress|ConversationWorkflowTaskStatus|RoutinePlanArtifact|ConversationPlanArtifact" \
  lib test -g '*.dart'
git diff --quiet 4222d74d7598a9ec8d2aa3fe8d31b8e4f8592708 -- \
  lib tool/chat_notifier_guard_inventory.json
git diff --quiet de73f746f16eed1125b0f4f92cb44a11b57ea7de -- \
  lib tool/analyze_chat_notifier_inventory.py \
  tool/chat_notifier_tool_catalog_inventory.json
git diff --check
```

The private dynamic reproduction command remains in the tool-residency
inventory so sensitive paths do not appear here.

## Unresolved Items

- The two `dead` delegates remain present until the focused deletion slice.
- The legacy workflow-only persisted population is unknown.
- The correct replacement, if any, for the deferred WS6-19 ordering contract is
  not approved.
- Goal/objective divergence has no provenance marker, so mismatches cannot yet
  be classified as intentional or accidental.
- Net line reduction is deliberately not estimated for migrations. File ranges
  describe review and compatibility surface, not promised deletion.
