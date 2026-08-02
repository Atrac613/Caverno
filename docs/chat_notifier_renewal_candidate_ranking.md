# ChatNotifier Renewal Candidate Ranking

Reviewed 2026-08-02 at synthesis revision
`05a6a25c0237c0b2ce6e93fab3055c36121e45f4`. This report combines three
read-only Phase 1 inventories. It does not authorize a deletion, migration, or
persisted-schema change.

## Decision

The D1 deletion slice is complete: the two orphan proposal-parsing delegates
and their current-source inventory rows have been removed. The clean
matching-build corpus remains the historical evidence for that action.

The highest-confidence implementation candidates are:

1. give execution-task status one owner by joining immutable task intent with
   optional execution progress; and
2. share pure plan-artifact revision mechanics underneath the distinct
   conversation and routine persisted wrappers.

Neither should be folded into the first `TurnRuntime` extraction. Status
ownership should be corrected before task state crosses that boundary, while
plan-artifact persistence remains outside the turn runtime.

I1 is complete. The read-only local persistence audit classified 439 rows: 391
without workflow context, 29 fresh plan-derived workflows, and 19 legacy-
authored workflows. No stale, source-missing, metadata-incomplete, or invalid
record was found. M3 therefore remains blocked.

The compatibility fixture and persisted aggregate audit are complete. Of 19
legacy-authored records, 1 passes the gate and 18 are blocked. All 18 require
preservation of existing provenance in both the current workflow and legacy
checkpoints; 4 also have dangling execution progress and an existing plan
document conflict. The audit covered 33 workflow-bearing checkpoints and found
no invalid records, empty task IDs, open-question drift, projection failures,
or semantic round-trip mismatches.

The provenance-shape audit is complete. All 18 blocked current workflows and
all 33 legacy checkpoints have internally consistent user-message and
specification-file source graphs. No duplicate, empty, orphan, unreferenced,
multi-source, assumption, or clarification condition was observed. Fourteen
records are provenance-only blockers; the other 4 are the plan/progress
conflict subset.

The item-identity reconciliation, provenance-merge audit, conflict-policy
classification, pure preservation envelope, and live read-only rehearsal are
complete. All 14 clean workflows and their 27 checkpoints are mergeable. All 4
conflict records produce lossless envelopes with every execution-progress
object preserved. A two-pass manual decision now cryptographically binds stage
authority to the exact Plan, merged workflow, and progress context, and a
content-free schema-v1 receipt validates replay against current state. A
test-only composed rehearsal now completes the full accepted-decision path for
both authorities while preserving every progress object. A persistence-neutral
confirmation contract now binds immutable requests and results to current
context and emits only manual decisions. The next slice is an adapter ownership
and stale-request lifecycle audit; live authority must not be invented. No
persistence writes or editor removal are authorized.

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

### Completed

| Rank | Candidate | Current evidence | Current size |
| ---: | --- | --- | ---: |
| D1 | Remove `_tryRepairAndDecodeMap` and `_repairJsonCandidate` delegates | Completed; zero production selection roots, no unresolved invocation edge, direct live replacements in `ProposalParsingTextUtils`, and no contradiction in 4 clean matching-build records | 1 file; 6 declaration/body lines, 8 lines including separators |

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
| M4 | Add explicit provenance or a snapshot invariant between goal text and plan/workflow objective text | 6-10 source/test files | Goal lifecycle policy and contract objective text are distinct, but current strings can diverge without provenance | Start with the read-only mismatch diagnostic in I4. Stop if fixtures show divergence is always deliberate or provenance cannot be added compatibly. |

M4 defines a relationship between distinct entities; it does not merge goal
and plan.

## Blocked Migration

| Candidate | Direction confidence | Measured surface | Blocker | Re-entry condition |
| --- | --- | --- | --- | --- |
| Retire workflow as a second authored source while retaining a plan-derived execution projection | High for the direction; blocked for implementation | 25-40 source/test files; 19 persisted legacy-authored workflows: 1 compatible, 14 clean mergeable records, and 4 stage/progress-conflicted blockers | The synthetic path and confirmation contract are complete, but adapter ownership, stale-request lifecycle, persistence, and transformer acceptance gates are undefined | Audit the owner-scoped adapter lifecycle before any UI; keep storage and transformation separate |
| Wire `ChatToolHandlerCatalog` as the production composition boundary | High that all six binding groups can fit an owner-aware catalogue; low that the current composition is ready | 118 static plus 52 private dynamic definitions across 6 binding groups | The registry-last WS6-19 gate remains unmet; all three named modules capture `ChatNotifier`, and Browser/Computer Use still require policy-aware adapters | Reconcile or replace the WS6-19 safety contract, expose typed owner/UI/approval/turn-result ports, and prove branch precedence plus fallback behavior before wiring |

The pinned corpus contained only two records and one normalized submission. It
proves catalogue enumeration and binding joins, not production frequency. No
definition is a deletion candidate based on its zero count.

## Investigation Candidates

### Completed

| Rank | Investigation | Decision unlocked | Measured decision surface | Bounded next action |
| ---: | --- | --- | --- | --- |
| I1 | Audit persisted workflow origins, compatibility, provenance shape, additive merge viability, conflict policy, and lossless preservation | Both cohorts have bounded lossless candidates, the synthetic path is proven, and confirmation fails closed; adapter lifecycle is the next boundary | 439 rows; 14 clean current workflows and 27 checkpoints merge; 4/4 conflicts preserve progress; 2/2 synthetic authorities replay; 9/9 confirmation cases pass | Audit owner-scoped adapter ownership and stale-request disposal |

The matching-build guard capture is complete and moved its two closed proofs
into D1. I1 is complete; the adapter lifecycle audit is the next bounded design
slice for this migration lane.

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
- The workflow-origin audit emits aggregate counts only; it excludes database
  paths, record identifiers, titles, messages, plan text, and workflow content.
- No schema migration prototype or live LLM canary was used for the concept
  ranking.

## Evidence Revisions and Dynamic Provenance

| Input | Evidence revision | Notes |
| --- | --- | --- |
| Guard reachability inventory | `55efb18f51e2739f195bca0d5bd7b1669d5c0f9d` | Historical measurement: 65 represented candidates, 2 dead and 63 unresolved; the 2 dead entries are now deleted |
| Tool catalogue residency inventory | `de73f746f16eed1125b0f4f92cb44a11b57ea7de` | 118 static and 52 private dynamic rows linked to 6 bindings |
| Concept overlap inventory | `8561fedb42471f0e99cd15d897002acb30f5e88b` | Read-only lifecycle and ownership review |
| Consolidated synthesis | `05a6a25c0237c0b2ce6e93fab3055c36121e45f4` | Documentation-only task-contract revision; classified production code is unchanged from the input reviews |
| Workflow-origin audit | Current read-only local capture | 439 aggregate rows; 29 fresh plan-derived and 19 legacy-authored workflows; no path, identifier, or content fields emitted |
| Legacy workflow compatibility fixture | Current pure domain fixture | Fail-closed round-trip, provenance, progress-reference, plan-conflict, projection, and checkpoint gates; no persistence wiring |
| Persisted compatibility audit | Current read-only local capture | 19 legacy candidates: 1 compatible, 18 provenance-blocked, 4 also plan/progress-conflicted, 33 workflow checkpoints, zero invalid records; database bytes unchanged |
| Provenance-shape audit | Current read-only local capture | 18 current workflows and 33 legacy checkpoints have consistent user-message and specification-file graphs; 14 provenance-only and 4 conflict records; zero malformed graph or assumption conditions |
| Provenance-preserving merge fixture | Current pure domain fixture | Additive source and item provenance merge with deterministic blockers for malformed, colliding, mismatched, or unmatched graphs; no persistence wiring |
| Provenance-merge audit | Current read-only local capture | 14 eligible current workflows and 27 cohort checkpoints evaluated; all 41 mergeable with zero blockers after bounded identity reconciliation; database bytes unchanged |
| Legacy item-identity reconciliation | Current pure domain fixture | Exact IDs plus documented positional constraint and acceptance IDs only; ambiguous, incomplete, malformed, semantic-drift, and projection-drift cases fail closed |
| Plan/progress conflict policy audit | Current read-only local capture | 4/4 plans parse, 4/4 workflow specs are semantically equivalent and mergeable, 4/4 stages diverge, and 4/4 meaningful dangling progress records are owned by neither plan nor checkpoint task graphs; database bytes unchanged |
| Workflow conflict preservation envelope | Current pure domain fixture | Exact progress ownership, merged provenance, active/orphan separation, immutable inputs and outputs, and explicit workflow-versus-plan stage authority; no persistence wiring |
| Workflow conflict preservation rehearsal | Current read-only local capture | 4/4 envelopes created, 4/4 full execution-progress multisets preserved, 4/4 meaningful orphans retained, zero selected stages, zero mutation, and only stage-authority blockers; database bytes unchanged |
| Workflow stage-authority decision | Current pure domain fixture | Schema-v1 SHA-256 context binds exact Plan text, both stages, merged provenance, active progress, and orphan progress; only manual UTC decisions with exact digests select a stage |
| Workflow stage-decision receipt | Current pure domain fixture | Content-free schema-v1 JSON receipt with SHA-256 integrity; current-state replay rebuilds context, reconstructs the decision, rejects tampering and stale state, and verifies selected stage |
| Workflow stage-decision end-to-end rehearsal | Current synthetic domain fixture | 2/2 explicit authority paths complete the authority-free pass, accepted decision, lossless envelope, content-free JSON receipt, and current-state replay without mutation |
| Workflow stage user-confirmation contract | Current pure domain fixture | Content-free immutable request/result port; exact identity, digest, current-context, UTC ordering, decline, and both authority results validate before a manual decision is emitted |

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
python3 test/python/audit_conversation_workflow_origins_test.py
python3 tool/audit_conversation_workflow_origins.py --database <path>
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
fvm flutter test \
  test/features/chat/domain/services/conversation_legacy_workflow_compatibility_service_test.dart
fvm flutter test test/tool/audit_legacy_workflow_compatibility_test.dart
fvm dart run tool/audit_legacy_workflow_compatibility.dart \
  --database <path>
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

- The 14 provenance-only records and their 27 legacy checkpoints are proven
  mergeable without persistence writes. The other 4 records rehearse losslessly
  and have explicit decision, receipt, and synthetic end-to-end evidence, but
  live stage authority is still absent and must not be inferred. The
  confirmation contract has no owner-scoped adapter or stale-request lifecycle.
- The correct replacement, if any, for the deferred WS6-19 ordering contract is
  not approved.
- Goal/objective divergence has no provenance marker, so mismatches cannot yet
  be classified as intentional or accidental.
- Net line reduction is deliberately not estimated for migrations. File ranges
  describe review and compatibility surface, not promised deletion.
