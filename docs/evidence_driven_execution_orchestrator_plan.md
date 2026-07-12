# Evidence-Driven Execution Orchestrator Plan

## Task

- Goal: let a weak local model turn a short user request into a verified result
  without depending on a task-specific prompt, while preserving Caverno's
  approval and unattended-execution boundaries.
- User-visible behavior: a coding task keeps its approved scope, current task,
  latest diagnostic, and verification state across requests and automatic
  continuations. Caverno asks for clarification only when a requirement-level
  assumption lacks a source.
- Non-goals:
  - Do not add a fourth persisted workflow state machine.
  - Do not weaken tool approval, Routine, Computer Use, or workspace-boundary
    enforcement.
  - Do not encode Dart, TODO applications, fixture file names, or one verifier
    command in the core orchestration layer.
  - Do not require user confirmation for reversible implementation choices
    that remain inside the approved contract.

## Motivation

Short-prompt live canaries show a recurring failure mode in which a model can
inspect or even diagnose the workspace, but later requests lose the actionable
state and return prose, repeat an earlier task, or mutate a previously verified
result. Increasing prompt detail masks this failure without fixing the generic
execution path.

Caverno already has most of the required state, but it is split across several
control surfaces:

- `ConversationWorkflowSpec`, execution progress, and
  `ConversationPlanExecutionCoordinator` drive approved Plan execution.
- goal auto-continue schedules another turn from incomplete evidence and its
  own turn budget.
- `RoutineToolPolicy` enforces unattended tool limits.
- the coding tool loop contains local recovery branches, verification feedback,
  and several direct `maxIterations` extensions.

The implementation must unify these surfaces around one persisted workflow
source of truth rather than placing another controller beside them.

## Architecture

### Persisted source of truth

The existing conversation workflow remains authoritative:

```text
ConversationWorkflowSpec
+ Conversation.executionProgress
+ source provenance
+ mutation and verification generations
```

No separate persisted `ExecutionState` enum is introduced. The next execution
phase is derived from the approved workflow, task status, unresolved questions,
latest diagnostic, and evidence freshness.

### Per-request execution snapshot

`ExecutionSnapshotProjector` derives a compact, deterministic snapshot before
every coding LLM request. The same projection is used for initial requests,
tool-result follow-ups, recovery requests, and goal auto-continue requests.

The snapshot contains only current decision inputs:

- contract version and hash;
- sourced objective, constraints, and acceptance criteria;
- the active task and remaining tasks;
- requirement-level assumptions awaiting confirmation;
- the latest relevant diagnostic;
- mutation and verification generations;
- whether required verification is fresh or stale;
- the next required action;
- current execution budget and verification cadence state.

It must not contain the complete event history. Serialization order, clipping,
and hashing must be deterministic so prompt growth and context compaction do not
change the meaning of the snapshot.

### Derived decisions

An ephemeral `ExecutionDecision` selects one of these actions:

- clarify a requirement-level assumption;
- execute the active task;
- run verification;
- repair the latest failed verification;
- continue in another turn;
- complete with fresh evidence;
- stop at a concrete blocker.

The decision is not another state machine. Existing workflow and progress
updates remain the only persisted transitions.

## Contract Provenance

Every requirement-bearing contract item must reference at least one source:

- a user message ID;
- a specification file path, section locator, and content hash;
- an approved plan artifact and content hash;
- a workspace observation and originating tool call;
- a user-confirmed assumption.

A generated item without a source is an assumption. It blocks autonomous
mutation only when it changes scope, acceptance criteria, language/platform,
external side effects, or another material requirement. Reversible technical
choices within the approved scope remain implementation decisions and do not
require confirmation.

For compatibility, provenance is additive metadata keyed by stable workflow
item IDs. Existing approved plan artifacts migrate to an approved-plan source.
Enforcement initially applies only to newly created or materially updated
contracts; legacy conversations are observed in shadow mode before stricter
handling is enabled.

If a referenced specification hash changes, the affected contract items become
stale and must be rebuilt or confirmed before broad mutations continue.

## Evidence Freshness

The first implementation uses a conservative conversation-level generation:

- increment `mutationGeneration` after a successful mutating tool result;
- conservatively increment it after a command classified as potentially
  generating or mutating workspace state;
- record the current generation on each verification result;
- treat verification as fresh only when its generation equals the current
  mutation generation.

A mutation after a successful verification makes completion evidence stale.
Normal product execution returns to verification. A live canary separately
records `post_success_mutation` and may fail its readiness gate even when the
model later reconverges.

Artifact-scoped generations are a follow-up only if the conservative global
generation creates unacceptable false invalidation.

## First-Class Budget and Verification Policies

### Execution budget

`ExecutionBudgetPolicy` owns:

- the base tool-loop iteration budget;
- progress-based extensions and their reasons;
- the total extension ceiling;
- bounded recovery request budgets;
- goal turn/token budget interaction;
- length-truncation recovery.

Recovery code requests an extension from this policy instead of changing
`maxIterations` directly. Initial behavior preserves the current base limits
and records shadow decisions before extension thresholds are retuned.

A `finish_reason=length` response with pending executable work receives at most
one compact action-only retry for the same pending action. Repeated truncation
without measurable progress stops rather than consuming the remaining goal
budget.

The initial diagnosed-fix carryover policy permits two automatic diagnostic
repair continuations. If Error-severity diagnostics remain after both repair
turns, goal auto-continue blocks even when the raw diagnostic count decreased.
This prevents changing or partially decreasing diagnostics from resetting the
stall guard indefinitely. Session logs record the consumed diagnostic repair
continuation count alongside the existing evidence summary and no-progress
streak.

### Verification cadence

`VerificationCadencePolicy` returns `notDue`, `due`, or `required` from the
active task, mutation generation, diagnostics, and prior verifier attempts.

Verification is always required:

- before completing a task that declares a verification requirement;
- before final completion of a mutated coding result;
- after any mutation that made a successful verification stale;
- when a diagnosed failure has consumed its allowed fix carryover.

Early verification nudges remain configurable and start in shadow mode so
multi-file scaffolds are not forced to run an unusable verifier after every
edit.

## Capability and Approval Model

`ToolCapabilityClassifier` is extended to classify command effects from tool
arguments instead of treating every local command as one undifferentiated shell
action. Initial effects are:

- inspection;
- dependency resolution;
- build;
- test or verification;
- formatting;
- code generation;
- workspace mutation;
- process lifecycle;
- deployment or release;
- external side effect;
- unknown.

Phase eligibility, approval requirements, and hard security ceilings remain
separate decisions:

- the execution coordinator may narrow tools for the current action;
- the existing approval system still decides whether an eligible action needs
  approval;
- Routine and other unattended policies form a hard ceiling that the
  coordinator cannot widen.

Dependency installation, builds, generators, and tests therefore remain usable
during execution when they are relevant and otherwise permitted. Unknown
commands retain conservative existing approval behavior.

## Existing-System Integration Map

| Existing system | Current responsibility | Target responsibility |
| --- | --- | --- |
| Plan execution | Approved workflow, task progress, execution prompts and guardrails | Remains the persisted source of truth; supplies contract and progress data to the snapshot projector |
| Goal auto-continue | Cross-turn scheduling, safe-boundary vetoes, turn budget, incomplete-evidence prompt | Remains the outer scheduler; consumes the shared snapshot, budget decision, and evidence freshness instead of building independent execution context |
| `RoutineToolPolicy` | Static unattended allowlist, Computer Use restrictions, workspace write boundary | Remains a hard policy ceiling; intersects its allowed capabilities with the coordinator request |
| Coding tool loop | Tool execution, local recovery, verification feedback, direct iteration extensions | Executes shared decisions; reports evidence and requests budget extensions through the central policies |

`ConversationPlanExecutionCoordinator` is evolved rather than duplicated. Its
pure task-selection and prompt helpers can move behind the snapshot/decision
interfaces incrementally, while existing callers remain compatible during the
migration.

## Delivery Phases

### Phase 0: design and shadow observation

1. Land this design and integration map.
2. Add immutable execution snapshot and projection types.
3. Project current workflow/progress state without changing prompts or tool
   behavior.
4. Log a redacted snapshot summary and shadow decision in coding session logs.
5. Compare shadow decisions with the current Plan, recovery, and goal
   auto-continue decisions.

### Phase 1: contract continuity and provenance

1. Add stable workflow item IDs and source-reference metadata.
2. Add compatibility migration for approved plan artifacts.
3. Inject the compact execution snapshot into every coding LLM request.
4. Route goal auto-continue prompts through the same projection.
5. Block only material, unsourced assumptions and ask one focused question.

### Phase 2: evidence generations and verification cadence

1. Persist mutation and verification generations with execution progress.
2. Feed successful tool results and coding verification feedback into the
   generation state.
3. Prevent completion when required evidence is absent or stale.
4. Introduce shadow cadence decisions, then enable required cadence gates.
5. Add normal-product and live-canary handling for post-success mutations.

### Phase 3: budget and recovery consolidation

1. Introduce `ExecutionBudgetPolicy` with compatibility defaults.
2. Replace direct tool-loop iteration extensions with policy requests.
3. Add bounded action-only recovery for length truncation and prose-only stalls.
4. Reuse the same no-progress evidence across tool-loop and goal continuation
   boundaries.
5. Bound diagnosed-fix carryover independently from diagnostic count changes.

### Phase 4: effect-aware capability selection

1. Extend command classification and tests.
2. Select tools by required effect without banning all command execution during
   implementation.
3. Intersect selection with existing approvals and Routine policy.
4. Record classification and denial reasons in existing security telemetry.

### Phase 5: short-prompt contract builder

1. Build a sourced contract from the short request, referenced specifications,
   approved instructions, and deterministic workspace probes.
2. Separate material assumptions from implementation choices.
3. Ask one targeted clarification only when contract readiness requires it.
4. Let interactive Plan Mode render and edit the same contract rather than
   producing a separate execution representation.

### Phase 6: rollout

1. Enable snapshot injection and policy decisions behind separate feature
   flags.
2. Run replay tests before live canaries.
3. Promote by model profile only after repeated clean evidence.
4. Keep a rollback path to current Plan and tool-loop behavior until the new
   telemetry is stable.

## Acceptance Criteria

- The implementation adds no independent persisted execution phase alongside
  the existing conversation workflow.
- Every coding LLM request can receive the same compact current execution
  snapshot, including tool-result and automatic-continuation requests.
- New material contract requirements are sourced or explicitly confirmed.
- A successful verification cannot remain fresh after a later mutation.
- Completion requires fresh evidence when the contract declares verification.
- Budget extensions have a centralized reason and bounded total.
- Command execution remains available for relevant dependency, build,
  generation, and verification work, subject to existing approval policy.
- Routine execution cannot gain a capability through coordinator selection.
- Existing saved conversations deserialize without data loss.
- The implementation remains language- and fixture-independent.

## Evaluation

Run short and detailed prompt variants across multiple artifact shapes,
languages, workspace states, and local model profiles. Use replay tests for
deterministic transitions and repeated live runs for convergence.

Required metrics:

- artifact acceptance pass rate;
- unsupported completion rate;
- verifier first-invocation iteration;
- diagnosed-fix carryover limit rate;
- `finish_reason=length` runaway count;
- post-success mutation rate;
- repeated identical diagnostic count;
- user clarification and intervention count;
- tool calls, tokens, and elapsed time;
- goal auto-continue no-progress stop rate.

Use the TODO fixture as one regression case, not as the promotion criterion.
Include other CLI, document transformation, persistence, API, and multi-file
tasks before enabling the orchestrator by default.

## Verification

Each implementation slice must run focused tests for the changed service and
the repository gate:

```bash
tool/codex_verify.sh
```

Behavior-changing phases additionally require replay coverage and repeated
Live LLM canary evidence. A narrow fixture pass cannot prove the generic
orchestrator complete.
