# Anabasis Project Vision

Date: 2026-09-13

Status: independent future vision. The product direction below is agreed;
the delivery sequence and design recommendations are proposals, not committed
implementation milestones.

## Agreed Product Direction

Anabasis should help the user operate and evolve a project continuously across
multiple goals and conversations. It should preserve intent and decisions,
reconcile new evidence, and help choose and complete the next meaningful goal.

ANA4 has a separate, bounded destination: entrust one goal through completion,
with progress, decisions needed, and acceptance evidence visible beside the
conversation. This vision is not part of ANA4's completion criteria.

- [Roadmap](roadmap.md#anabasis-project-vision) owns milestone status and promotion.
- [Architecture](ANABASIS_ORCHESTRATOR_ARCHITECTURE.md) owns current execution
  boundaries, state reuse, and the ANA4 surface.
- [Anabasis roadmap](anabasis_roadmap.md) owns detailed milestone scope and
  evidence, including the limits that remain after an implementation slice.
- [Brand story](anabasis_brand_story.md) explains the conceptual motivation.

No ANA5 or later milestone is reserved by this document. The following sections
recommend how to reach the agreed destination and remain open to revision.

## Product Thesis

The value to test is a reduction in the user's coordination work: reconstructing
context, repeating constraints, composing the next instruction, resolving
conflicts between tasks, and checking whether a completion claim is justified.

More agents, longer unattended runs, and more stored text are implementation
choices. They earn their place only when they improve accepted outcomes without
increasing correction work or cost beyond the user's budget.

Start with a developer maintaining an existing repository. This provides
repeated goals, changing constraints, observable artifacts, and opportunities
to compare with Caverno's existing Coding workflow. Broader research and
operational projects can follow once the same coordination benefit is observed.

## Proposed Delivery Sequence

These are learning stages, not milestone identifiers or calendar commitments.

| Stage | User-visible outcome | Evidence needed before expanding |
| --- | --- | --- |
| One goal: ANA4 | Delegate a bounded outcome, see progress, answer decisions, and inspect accepted results. | Representative work completes with less manual steering than the current Coding workflow, without weaker acceptance evidence. |
| Continuity | Resume the same goal in a later conversation without repeating its contract or repeating accepted work. | Restart and new-conversation scenarios recover the right evidence and detect changed premises; stale state is visible. |
| Decision maintenance | Understand which prior decisions still apply and which need review. | A changed requirement or repository fact identifies affected work and preserves the earlier rationale instead of silently overwriting it. |
| Multiple goals | See competing goals and decide what deserves attention next. | Priority recommendations explain their evidence and tradeoffs; accepted user priorities survive new conversations and competing task updates. |
| Bounded ongoing operation | Advance suitable work between user visits within an agreed scope and budget. | Existing authorization and scheduling mechanisms bound work, interruption and resume remain reliable, and idle polling does not consume disproportionate resources. |

Each stage must remain useful if later stages never ship. Preserve a single
active implementation slice; do not turn this sequence into a prerequisite for
shipping ANA4.

## Responsibility And State

Keep responsibilities explicit:

- The user owns purpose, priority tradeoffs, material assumption confirmations,
  and decisions requiring their authority under the existing approval model.
- The parent interprets the goal, decomposes and delegates work, evaluates
  evidence, and recommends the next action within that authority.
- Children produce bounded artifacts and evidence through existing runners.
- Application code enforces state ownership, readiness, permissions, and
  mechanical checks; model prose does not confer authority.

Project continuity needs a lifetime beyond an individual conversation. First
test a small project view that links to existing goals, decisions, and evidence.
Before persisting shared state, identify the fact that no current owner can
represent, its authorized writer, and its update and conflict rules. Follow the
architecture's reuse rule rather than adding a parallel store of task truth.

Keep project decisions separate from user-profile memory. A personal preference
can inform a proposal, but it does not silently become a project requirement.
Likewise, a retrieved historical decision is evidence to interpret, not a new
instruction or an execution grant.

For each durable decision, the later design should be able to answer: what was
decided, why, by whom, from which source, against which project state, and what
superseded it. Extend existing provenance where sufficient. Do not assume that
timestamps alone can resolve conflicting requirements or branches.

Acceptance records describe a judgment against evidence at a point in time.
Preserve that history when files or requirements change, while showing when
the current state needs revalidation. Historical acceptance must not masquerade
as proof that a later revision still satisfies the goal.

## Proposed User Experience

Use one coherent project view with different emphasis during work and on return:

- During work, prioritize decisions needed, active work, and blocking reasons.
- On return, show what changed, which earlier decisions are affected, and the
  next useful action, with links to the supporting artifacts and evidence.
- For completed work, show what was accepted and why, while leaving unresolved
  or merely unverified requirements visible.

Keep the full plan, agent details, and trace available behind those summaries.
Make questions actionable from the same surface. A long catalog of state fields
does not by itself help the user decide what to do.

Use persisted projections for routine display. Ask a model to interpret a
meaningful change or propose a decision when needed; do not require inference
for every panel refresh. Notify on meaningful changes or required decisions,
and keep unchanged, non-actionable state quiet.

## Cost And Execution Strategy

Local-first operation is an opportunity to give the user control over project
data, inference placement, and resource budgets. It does not make orchestration
free: extra calls still consume context, compute, and time.

- Give the parent a bounded view of current goals, decisions, and evidence;
  retrieve relevant details instead of replaying all project history.
- Give a child a task-specific brief with its premises and acceptance criteria.
- Begin with sequential delegation. Parallelize only independent work where
  measured completion time justifies duplicated context and integration work.
- Reconcile on meaningful changes and user requests before introducing periodic
  polling. Reuse existing routine and execution budgets for later unattended work.
- Test a simpler direct Coding path alongside orchestration. Let a known,
  bounded edit remain inexpensive to request and complete.

Reusing a stronger model or another runner is a capability choice within the
user's configured authority, not a reason to invent another parent policy.

## Evidence And Promotion

Compare against the existing Caverno Coding workflow, including its current
Goal, Plan, and verification features. A plain chatbot is not the relevant
baseline. Begin with a small set of repeatable journeys:

1. Add a feature to an existing repository with one genuine user decision.
2. Fix a defect that crosses component boundaries and requires verification.
3. Interrupt work, change a relevant premise, and resume in a new conversation.

Use the same starting revision, goal, available tools, model configuration, and
resource budget where possible. Record the user decisions separately from
remedial prompts that repair lost context, repeated work, or incorrect claims.
For nondeterministic runs, repeat the comparison rather than selecting one
successful demonstration.

Inspect accepted outcome quality, unnecessary steering, correction work,
reorientation time, repeated work, and total model/tool cost. Set promotion
thresholds before the comparison once a baseline exists. Do not optimize for
agent count or uninterrupted runtime at the expense of a useful result.

Include unfinished child work, rejected acceptance, changed assumptions,
interrupted runs, and conflicting updates. Separate wiring failures from model
judgment failures: first establish that the relevant tool, state, and result
were actually available to the deciding model.

## Relationship To Other Tracks

- Goal, Plan, ANA0-ANA3, and current runners supply the execution foundation.
- Memory continuity and retrieval tracks supply their existing storage and
  evidence-retrieval capabilities. Project continuity must not duplicate them
  or confuse personal memory with project authority.
- Trace work supplies execution evidence; model profiles and evaluations supply
  capability evidence. Reuse available paths without making every future
  observability or model-library feature a prerequisite.
- Routines and remote execution remain the owners of scheduling and execution
  mechanisms when later stages need them.

## Recommended Next Product Slice

Review ANA3 closure against the shipped surfaces and the remaining runner and
acceptance-evidence limit before expanding the execution experience. Then
define ANA4's primary journey using one existing repository goal with a real
decision, a blocked task, a produced result, and an accepted result. Build the smallest workspace that lets the user distinguish
and act on those states, and compare it with the existing Coding experience.

Use the observed friction to select the first later milestone. The leading
hypothesis is continuity across interruption and new conversations, ahead of
multi-goal scheduling or broader unattended autonomy.
