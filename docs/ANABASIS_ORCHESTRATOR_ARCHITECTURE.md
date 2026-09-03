# Anabasis Orchestrator Architecture

**Status: design. Nothing here is implemented.** Written 2026-09-02 against
`6434be77e70d92a70de89c1b4527e0e89d2329be`. Every "existing implementation"
cell in §3 was verified by static survey of `lib/`, `packages/`, and `test/` at
that revision. The verification commands are printed alongside the claims so
the mapping can be re-checked rather than trusted — status markers in this repo
have gone stale before.

Anabasis is an orchestration layer, not a second coding agent. Its job is to
hold what the project knows, what it only assumes, and what it has not yet
found out; to refuse to act on unconfirmed material assumptions; to decompose
goals into delegable work; and to accept a child agent's result only on
evidence.

**Related documents**

| Document | Role |
| --- | --- |
| [`anabasis_brand_story.md`](anabasis_brand_story.md) | Concept and naming. The *why*: the cave metaphor, the name, and the design principle it produces. |
| [`anabasis_mvp_plan_superseded.md`](anabasis_mvp_plan_superseded.md) | The first MVP plan, superseded by this document. Kept as the record of why — it is the concrete evidence behind §0. |
| [`roadmap.md`](roadmap.md) | Milestone tracking under "Anabasis Orchestrator Track" (`ANA<number>`). |
| [`chat_notifier_concept_overlap_inventory.md`](chat_notifier_concept_overlap_inventory.md) | The 2026-08-02 finding that the user has three durable concepts, not four or five. §0 exists because of it. |

---

## 0. The rule this document exists to enforce

> **Anabasis reuses existing Caverno state whenever that state already
> expresses the required concept. New authoritative state is introduced only
> when an existing representation is demonstrably insufficient.**

This rule is not abstract hygiene. Three separate design passes each re-derived
a structure Caverno already had:

| Proposed as new | Already existed as |
| --- | --- |
| `AnabasisState` (goal, facts, assumptions, questions, decisions, risks) | `ConversationWorkflowSpec` + `ConversationGoal` + `SessionMemory` |
| `AnabasisProjection` (derived read-only view) | `ExecutionSnapshot` from `ExecutionSnapshotProjector` |
| MVP "generate Acceptance Criteria" | `ConversationWorkflowSpec.acceptanceCriteria`, already emitted by the planning JSON schema |

§3 is the standing answer to that failure mode. Read it before proposing any
new entity.

---

## 1. Vision

Anabasis is deliberately two things at once, and the two do not conflict:

```
User-facing:   Anabasis = the parent bot you tell what you want built
Architecture:  Anabasis = orchestration policy + state projection + authority boundary
```

The progression it manages:

```
User intent
   ↓
Incomplete understanding
   ↓
Identify assumptions       ← epistemic model (§6)
   ↓
Verify what is material    ← confirmation provenance (§7)
   ↓
Build plan, decompose      ← task lifecycle (§8)
   ↓
Delegate to child agents   ← existing subagent/worktree infrastructure
   ↓
Collect evidence
   ↓
Accept only grounded results  ← acceptance model (§9)
   ↓
Understanding
```

Non-goals, stated so they stay non-goals:

- Anabasis does not edit code. It delegates (§5).
- Anabasis does not introduce a fourth authoritative conversation state (§0).
- Anabasis does not replace the Coding workspace. It sits beside it (§2).
- Anabasis does not close a goal on the absence of evidence. `ConversationGoal`
  already refuses to, and the reasoning in its `awaitingConfirmation` doc
  comment is the standard this document adopts.

---

## 2. Product Boundary

| | Coding workspace | Anabasis workspace |
| --- | --- | --- |
| User says | "Fix this." "Implement this function." | "I want to build an RSS reader." |
| Input granularity | operation | outcome |
| Who decomposes | the user | Anabasis |
| Who mutates the workspace | the coding agent, directly | child agents only, via delegation |
| Who decides done | the user, by looking | Anabasis, on evidence, escalating to the user (§9) |
| Surface | existing `WorkspaceMode.coding` | new `WorkspaceMode.anabasis` (MVP 4) |

Both remain first-class. The Coding workspace is the faster path when the user
already knows what to change; Anabasis is for when they know the outcome and
not the steps.

---

## 3. Existing Caverno Mapping

The load-bearing section. `Gap` is the only column that authorizes new code.

| Anabasis concept | Existing implementation | Location | Gap |
| --- | --- | --- | --- |
| Goal (lifecycle, budgets, blocking) | `ConversationGoal` — status incl. `awaitingConfirmation`, token/turn budgets, blocker signature | `lib/features/chat/domain/entities/conversation_goal.dart` | none |
| Goal (contract text) | `ConversationWorkflowSpec.goal` | `lib/features/chat/domain/entities/conversation_workflow.dart` | none |
| Constraints | `ConversationWorkflowSpec.constraints` | same | none |
| Acceptance criteria | `ConversationWorkflowSpec.acceptanceCriteria`, emitted by the planning JSON schema | `conversation_planning_prompt_service.dart` | none |
| Open questions | `openQuestions` + `ConversationOpenQuestionProgress` (`unresolved` / `needsUserInput` / `resolved` / `deferred`) | `conversation_workflow.dart` | none |
| Plan document + revisions | `ConversationPlanArtifact` (draft, approved, bounded history) | `conversation_plan_artifact.dart` | none |
| State update (prev state + conversation → new state) | `savedSpec` / `openQuestionDelta` / `executionDelta` fed back into every planning request | `conversation_planning_prompt_service.dart:115-138` | none |
| Structured LLM output | planning request pins a JSON schema and a `kind:"decision"` escape when a user choice would change the plan | `conversation_planning_prompt_service.dart:41` | none |
| Read-only projection | `ExecutionSnapshot` — objective, constraints, acceptance criteria, merged `clarificationQuestions`, `blockingAssumptionCount`, `sourceCount`, `validationStatus`, `contractHash` | `execution_snapshot_projector.dart` | carries **counts, not items**, for assumptions |
| Source provenance | `ConversationContractSourceReference` (`kind`, `locator`, `contentHash`) | `conversation_workflow.dart` | none |
| Item provenance | `ConversationContractItemProvenance` (`assumption`, `material`, `confirmed`, `sourceIds`, `clarificationQuestion`) | `conversation_workflow.dart` | **producer missing** |
| Execution guard on unconfirmed assumptions | `MaterialContractAssumptionGuard`, wired into the tool-loop guard chain | `material_contract_assumption_guard.dart`, `chat_notifier_tool_loop_batch.dart:167` | armed but never fires (no producer) |
| User-confirmed assumption as a source | `ConversationContractSourceKind.userConfirmedAssumption` | `conversation_workflow.dart:35` | **declared, never written anywhere in the repo** |
| Tool effect classification | `ToolCommandEffect` (11 values incl. `workspaceMutation`, `codeGeneration`, `deploymentOrRelease`) | `packages/caverno_tool_contracts/lib/src/tool_capability_classifier.dart:74` | no parent-scoped policy over it |
| Child delegation | `spawn_subagent` / `get_subagent_result`, depth fixed at 1, inherited catalog narrowed to avoid 32768-context overflow | `mcp_tool_service.dart:712`, `subagent_tool_policy.dart` | none |
| Isolated child execution | `WorktreeAgentTask` — own git worktree + branch, `verificationCommand`, `objectiveAcceptanceCriteria`, `verifiedGreen`, `changedFileEvidence`, scheduler, assignment planner | `worktree_agent_task.dart` and siblings | none |
| User entry to delegation | `/agent` (aliases `worktree`, `worktree-agent`) with `--run` / `--verify` / `--accept` | `slash_command_catalog.dart:74`, `worktree_agent_command_args.dart` | none |
| Session facts about the user | `MemoryEntry` (`fact` / `constraint` / `preference` / `persona` / `topic`, confidence, importance, TTL) | `session_memory.dart` | out of scope for v0 (§6) |
| Execution identity (which part of the app issued a request) | `ModelUsageRole` — zone-scoped, already carries `subagent` | `model_usage_role.dart` | no `anabasisParent` value; ambient channel unsuitable for authority (§5) |
| Claim origin | `ConversationContractSourceKind` — `userMessage`, `specificationFile`, `approvedPlan`, `workspaceObservation`, `userConfirmedAssumption`, `legacy` | `conversation_workflow.dart:30` | no `modelDerived` value (§6) |
| **Task preconditions** | — | — | **NEW** |
| **Task readiness calculation** | — | — | **NEW** |
| **Accepted (vs completed) task state** | — | — | **NEW** |
| Anabasis workspace surface | `WorkspaceMode { chat, coding, routines }` | `lib/core/types/workspace_mode.dart` | **NEW** (fourth value) |

### Re-verifying this table

```bash
grep -rn "assumption: true\|assumption: " --include='*.dart' . | grep -v '/test/\|_test\.dart\|\.freezed\.dart\|\.g\.dart\|/build/'
```

```bash
grep -rn "userConfirmedAssumption" --include='*.dart' . | grep -v '\.freezed\.dart\|\.g\.dart\|/build/'
```

```bash
grep -rn "depends\|dependsOn\|dependencies\|precondition" lib/features/chat/domain/entities/conversation_workflow.dart lib/features/chat/domain/entities/worktree_agent_task.dart lib/features/chat/domain/entities/subagent_task.dart
```

The first two must return nothing outside tests and a single enum declaration
respectively; the third must return nothing. If any of them starts returning
production hits, this document is out of date.

---

## 4. Parent / Child Responsibilities

| Anabasis (parent) | Child agent |
| --- | --- |
| Understand, clarify, plan | Inspect |
| Decompose, order by dependency | Edit |
| Delegate | Run |
| Observe, verify, accept | Fix |
| Integrate, report | Report result + evidence |

The parent runs one loop with a whole-project view. A child runs one task with
a narrow view and full mutation rights inside its worktree. Keeping the parent
out of the editor is what preserves the altitude difference; a parent that
starts editing becomes planner, coder, reviewer and orchestrator in one
context, and stops being able to judge any of them.

---

## 5. Tool Authority

The parent's authority is defined by `ToolCommandEffect`, not by a hand-kept
tool name list.

**Parent allowed**

- `inspection`
- `verification`

**Parent forbidden**

- `workspaceMutation`
- `codeGeneration`
- `formatting`
- `build`
- `dependencyResolution`
- `processLifecycle`
- `deploymentOrRelease`
- `externalSideEffect`
- `unknown` (deny by default; an unclassified tool is not proof of safety)

Delegation is the parent's only route to effect. `spawn_subagent` is itself
allowed — the child inherits mutation rights and escalates to the user's
approval dialog at dispatch exactly as the main loop does.

> **Delegation is an explicit parent capability and is not equivalent to
> workspace mutation.** The parent's authority is therefore
> `inspection | verification | delegation`, not the two effects alone.

`spawn_subagent` may not classify cleanly under the existing
`ToolCommandEffect` values, in which case MVP 0 carries it as a named
exception. That is acceptable as a starting point, but it is the kind of
special case that becomes debt if it spreads. Adding a `delegation` effect is
the eventual tidy-up — and per §0 it is only justified once the implementation
demonstrates the existing classifier cannot express it.

**Attach point.** The same guard chain that already runs
`MaterialContractAssumptionGuard` per tool call in
`chat_notifier_tool_loop_batch.dart`. A parent-authority guard is a sibling
entry returning a structured refusal `McpToolResult`, not a throw — a throw
ends the turn and leaves the call unexecuted, which is the wrong shape for a
policy refusal.

### Authority identity is not surface identity

The guard needs to answer "is this tool call being made by the Anabasis
parent?" — and that question must not be answered by `WorkspaceMode`. The
parent can be reached from the shared chat via `@anabasis`, from its own
workspace (MVP 4), or from background orchestration, and the authority must be
identical in all three.

Caverno already separates these. `ModelUsageRole` records which part of the app
issued a request, and it already carries a `subagent` value:

```
ModelUsageRole { chat, memoryExtraction, planning, proReasoning,
                 goalSuggestion, approvalAutoReview, subagent,
                 routine, eval, unknown }
```

Adding `anabasisParent` to it is a one-value change, and it is the right place
for *accounting*.

**It is the wrong channel for authority.** `ModelUsageRole` is ambient — read
from the current `Zone`, defaulting to `unknown` when no call site claimed it.
For accounting, an unclaimed path showing up as `unknown` is a visible gap;
for authority, a missed `runWith` would silently drop the parent out of its own
restrictions. The entity's own doc comment records a related burn: zone values
propagate into async callbacks, so an `unawaited(...)` call inherits the
enclosing turn's attribution.

So:

- **Accounting:** add `ModelUsageRole.anabasisParent`.
- **Authority:** pass the executing role into the guard as an **explicit
  parameter**, the way `MaterialContractAssumptionGuard.evaluate` already takes
  `workspaceMode` and `blockingAssumptions` rather than reading ambient state.
  Absent or unknown role denies the forbidden effects.

This is needed in **MVP 0**, because MVP 0 enforces the parent boundary. The
dedicated workspace stays in MVP 4; only the execution identity comes early.

**Enforce this from MVP 0.** It costs one guard over machinery that already
exists, and retrofitting a boundary after the parent has learned to edit is
much harder than starting with it closed.

---

## 6. Epistemic Model

Five states, each expressed in structures that already exist.

| State | Representation | Behavior |
| --- | --- | --- |
| **Fact** | contract item with `assumption == false` | usable as a premise — *see the caveat below* |
| **Assumption** | `assumption == true, material == false` | shown, not blocking |
| **Material assumption** | `assumption == true, material == true, confirmed == false` | `blocksExecution == true`; blocks delegation and mutation |
| **User-confirmed assumption** | `confirmed == true` plus a `userConfirmedAssumption` source (§7) | usable as a premise, with its confirmation traceable |
| **Unknown** | `ConversationOpenQuestionProgress` with `unresolved` or `needsUserInput` | drives clarification or a research task |

The scheduler rule this produces — the actual implementation of "do not mistake
shadows for reality":

```
Unknown
   ↓
Assumption
   ↓
Material?
 ├─ No  ──────────────→ proceed
 └─ Yes
      ↓
   Confirmed?
    ├─ Yes ───────────→ proceed
    └─ No  ───────────→ verify first (research/inspection task), do not delegate
```

### `assumption == false` is not the same as "verified"

**`assumption == false` means "currently treated as a premise", not
"externally verified truth".** The distinction matters because the planning
model itself writes this flag. A claim the model asserted from a loose reading
of a user message arrives flagged exactly like a claim read out of a
specification file — and Anabasis would then be mistaking a shadow for the
world in the one place it was built not to.

The long-term fix does not need new state either. `ConversationContractSourceKind`
already distinguishes claim origins:

| Claim origin | Existing source kind |
| --- | --- |
| asserted by the user | `userMessage` |
| written in a specification | `specificationFile` |
| observed in the workspace | `workspaceObservation` |
| confirmed assumption | `userConfirmedAssumption` |
| carried from an approved plan | `approvedPlan` |
| **model-derived** | **missing** |

The enum has a value for every *grounded* origin and none for the *ungrounded*
one. That absence is precisely why a model-asserted claim currently reads as a
fact. Adding `modelDerived` and ranking premises by source kind is the eventual
answer.

**This does not block MVP 0.** Ship the simple definition with the caveat
stated, and revisit once the producer exists and there is real data about how
often the model over-asserts.

**`SessionMemory` stays out of the v0 "Known" list.** `MemoryEntry` is
extracted by a separate pipeline with its own confidence, TTL and cost profile,
and it describes the *user*, not the *project contract*. Mixing it into the
same panel puts two different epistemic sources under one checkmark with no
shared confirmation path. Known, for v0, is contract items with
`assumption == false`. Revisit in v1 with an explicit decision, not by drift.

**Scope limit, stated honestly.** `MaterialContractAssumptionGuard` returns
early unless `workspaceMode == WorkspaceMode.coding`. Epistemic execution
control is therefore coding-scoped by construction today. Widening it to the
Anabasis workspace is part of MVP 4 and must be a deliberate change, not an
assumption.

---

## 7. Confirmation Provenance

`ConversationContractSourceKind.userConfirmedAssumption` exists in the enum and
appears nowhere else in the repository — not in `lib/`, not in the local
packages, not in tests. It is a design intention left unimplemented, and it is
a better design than a bare boolean: confirming an assumption **adds a source**,
so the provenance graph can later answer *why* an item was treated as known.

Confirming a material assumption therefore does three things:

1. append a `ConversationContractSourceReference` of kind
   `userConfirmedAssumption` (locator: the confirming message or approval)
2. add its id to the item's `sourceIds`
3. set `confirmed = true`

### The deadlock this ordering prevents

`blocksExecution => assumption && material && !confirmed`, and the guard is
already live on the tool loop. If the producer ships before the confirm path:

- the first material assumption makes `blockingAssumptions` non-empty
- every mutation tool call in that conversation is refused, permanently
- the guard's own `required_action` tells the model to ask the user and wait —
  but nothing can record the answer
- the loop burns on verbatim retries

**The confirm path lands with or before the producer. Not after.** This is the
critical-path constraint of MVP 0.

Secondary detail: `blockingAssumptions` is captured once per tool batch
(`chat_notifier_tool_loop_batch.dart:63`), so a confirmation mid-batch takes
effect from the next batch. Acceptable, but it should be a documented property
rather than a surprise.

---

## 8. Task Lifecycle

```
proposed → ready → running → produced → verified → accepted
```

`ready` is derived, not stored — from the task's preconditions (§12). Storing
it would add a second writer for something the graph already determines.

Against what exists today:

| Lifecycle state | Existing representation | Note |
| --- | --- | --- |
| proposed | `ConversationWorkflowTaskStatus.pending` | |
| ready | — | **NEW** — derived from preconditions (§12) |
| running | `inProgress` / `WorktreeAgentTaskStatus.running` | |
| produced | `WorktreeAgentTaskStatus.completed` | conflated |
| verified | `WorktreeAgentTask.verifiedGreen` + `ConversationExecutionValidationStatus.passed` | partially separated already |
| accepted | — | **NEW** |

Both existing status enums collapse produced, verified and accepted into
`completed`. This is not a hypothetical risk: Caverno has already paid for a
version of it, when tool-result evidence (which counts `dart analyze`) and the
verification generation counter (which does not) disagreed, and goal
auto-continue read only the lenient one.

Separating `produced` from `accepted` is the single most valuable structural
change for multi-agent work. State it as a standing principle, not an
implementation detail:

> **A child saying "done" means `produced`. It never means `accepted`.**
> Only Anabasis writes `accepted`, and only on evidence (§9, §10).

This one rule is what keeps a ten-child run from accumulating unverified
claims, and it costs nothing to adopt before there is a second child.

---

## 9. Acceptance Model

Four levels, cheapest first. A result is accepted when every level that applies
to it has passed.

| Level | Question | Existing hook |
| --- | --- | --- |
| 1 Mechanical | Did the verification command pass? | `WorktreeAgentTask.verificationCommand`, `verifiedGreen`, `ConversationExecutionValidationStatus` |
| 2 Evidence | Do the artifacts match the claim? | `WorktreeAgentTask.changedFileEvidence` (paths + real content), `resultSummary`, `verificationSummary` |
| 3 Semantic | Does this actually satisfy the goal? | none — this is the parent's own judgment, and the reason Anabasis exists |
| 4 User | Is this a decision only a person can make? | `ConversationOpenQuestionStatus.needsUserInput`, `ConversationGoalStatus.awaitingConfirmation` |

Level 3 is where green tests and an unmet goal are distinguished: a child can
implement a local cache, pass every test, and leave authentication blocking
startup. Level 4 covers UI/product/trade-off/breaking-change/cost/security
calls; Anabasis marks them awaiting confirmation rather than closing them.

---

## 10. Ownership

One writer per state. This table is the reason §8 and §9 are safe to add.

| State | Sole writer |
| --- | --- |
| `produced` | child executor |
| `verified` | verification subsystem (mechanical + evidence) |
| `accepted` | Anabasis parent |
| user approval | the user, via an explicit surface |
| `confirmed` on a contract item | the user, via the §7 confirmation path |
| `assumption` / `material` on a contract item | the planning producer, at plan time |
| task precondition edges | the decomposition step |
| `ready` | nobody — derived, never stored (§12) |

**Precedent for taking this seriously.** `ConversationExecutionValidationStatus`
already has three writers, one of which judges prose; a fourth exit-code writer
was added and reverted, and the investigation found stderr outranking a clean
exit 0. Adding acceptance levels without fixing ownership first reproduces that
problem at a larger scale.

---

## 11. MVP 0 — Complete the epistemic grounding

Gaps only. Nothing in this list is a reimplementation.

1. **Confirmation path first.** Write a `userConfirmedAssumption` source, link
   it, set `confirmed = true`, with a surface to do it. (§7 deadlock.)
2. **Producer.** Emit `assumption` / `material` per contract item from the
   planning JSON schema and parser
   (`conversation_planning_prompt_service.dart` + the proposal parsers). This
   arms `MaterialContractAssumptionGuard`, which is already wired.
3. **Parent execution identity** — `ModelUsageRole.anabasisParent` for
   accounting, plus an explicit executing-role parameter on the dispatch path
   for authority (§5).
4. **Parent tool-authority policy** over `ToolCommandEffect` (§5).
5. **Expose existing state.** Extend `ExecutionSnapshot` to carry assumption
   *items* alongside `blockingAssumptionCount`. Do not add a new projection
   class.
6. **Canaries** (§ below).

Suggested PR split, canary first so the feature is defined by a failing test:

| PR | Content |
| --- | --- |
| 1 | The failing canary: confirming a material assumption unblocks mutation |
| 2 | Confirmation provenance (§7 three steps) + a minimal confirm surface |
| 3 | Assumption producer — the moment `MaterialContractAssumptionGuard` first fires |
| 4 | Parent execution identity + authority policy |
| 5 | `ExecutionSnapshot` extension and the Understanding panel |

Reuse `MemoryExtractionJsonParser` for parsing rather than writing a new one —
`ConversationGoalSuggestionService` already does, and it carries the fixes for
think-block brace handling.

### MVP 0 canaries

Baseline is **current Caverno**, not a plain chat session. Existing canaries
live in `integration_test/` (`plan_mode_scenario_test.dart`,
`multi_thread_plan_live_canary_test.dart`) and are the pattern to follow.

| Scenario | Current Caverno | + Anabasis |
| --- | --- | --- |
| **Confirming a material assumption lifts the block** | n/a (unreachable) | must pass — write this one first |
| A material assumption is detected and marked | no | yes |
| An assumption is not presented as a fact | no | yes |
| An unconfirmed material assumption blocks mutation | guard exists, never fires | end-to-end |
| Contradictory evidence revises an assumption | ? | yes |
| The parent cannot call a mutation tool | no policy | refused |

The first row is listed first deliberately: without it the others describe a
product that locks itself.

---

## 12. MVP 1 — Decompose

The first substantially new implementation in the roadmap.

### Preconditions, not dependencies

A plain `List<TaskId> dependencies` is too narrow. Real blocking in Anabasis
has three shapes, and only one of them is another task:

```
Build sync engine
  requires  task:       inspect-data-model   state: accepted
  requires  assumption: stable-entity-ids    state: confirmed
  requires  question:   conflict-policy      state: resolved
```

Modelling them as one **precondition** list keeps `ready` fully derived and
keeps the epistemic model (§6) load-bearing rather than decorative:

```
ready =
     all task preconditions        accepted
  && all assumption preconditions  confirmed
  && all question preconditions    resolved
```

Each precondition kind points at state that already exists: task acceptance
(§8), `ConversationContractItemProvenance.confirmed` (§6), and
`ConversationOpenQuestionStatus.resolved`. So the new structure is the edge
list and the predicate — not new state on either end.

Scope for MVP 1:

- precondition edges on `ConversationWorkflowTask`
- readiness predicate
- decomposition output rendered but **not executed**

---

## 13. MVP 2 — Delegate

Map ready tasks onto the existing subagent / worktree infrastructure. No new
execution machinery: `spawn_subagent` for in-conversation children,
`WorktreeAgentTask` for isolated branch work. The new code is the mapping and
the scheduling policy, not the runner.

---

## 14. MVP 3 — Accept

- `produced` / `verified` / `accepted` as distinct states with §10 ownership
- parent semantic judgment (Level 3)
- escalation to `awaitingConfirmation` for Level 4
- integration of accepted work

---

## 15. Future Workspace UX

A fourth `WorkspaceMode`. State on the left, conversation on the right — chat
becomes one interface onto a persistent project state rather than the state
itself.

```
┌──────────────────────────────────────────┐
│ Anabasis · Project Understanding         │
├─────────────────┬────────────────────────┤
│ Goal            │ Conversation           │
│ Plan            │                        │
│ Assumptions     │ User: Make an RSS      │
│ Open Questions  │       reader...        │
│ Tasks           │                        │
│ Agents          │ Anabasis: I need to    │
│                 │       clarify...       │
└─────────────────┴────────────────────────┘

Agents
● Research architecture   Accepted
● Build data layer        Running
○ Build UI                Waiting  (depends on data layer)
○ Review                  Blocked  (unconfirmed: stable entity IDs)
```

The subtitle matters. "Anabasis · Project Understanding" is what makes the name
learnable without the etymology; the Greek is discoverable in the README, not
required at the point of use.

---

## 16. Open questions

Ordered by when an answer is actually needed, so none of them becomes a reason
to keep designing instead of building.

| Needed by | Question |
| --- | --- |
| MVP 1 | Does a child inherit the parent's confirmed assumptions as premises, and if so how are they injected without re-sending the whole contract? |
| MVP 2 | What happens to a running child when an assumption it depended on is contradicted mid-flight — continue, cancel, invalidate the result, or restart? This becomes a policy, not a case-by-case call. |
| MVP 3 | At Level 3, does the parent re-read the child's changed files itself or work from `resultSummary`? §5 permits reading (inspection is allowed); the trade is grounding against cost, and the cost is measurable by then. |
| MVP 3 | Does ranking premises by `ConversationContractSourceKind` (incl. a new `modelDerived`) change acceptance decisions enough to be worth building (§6)? |
| MVP 4 | When does `MaterialContractAssumptionGuard` widen beyond `WorkspaceMode.coding` (§6)? |
| MVP 4 | Does the Anabasis workspace get its own `AssistantMode`, or reuse `plan`? |

Resolved during design: *how the parent is identified for authority purposes* —
answered in §5. It was the only open question that touched MVP 0.

None of the remaining questions block MVP 0.
