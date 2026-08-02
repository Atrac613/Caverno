# ChatNotifier Concept Overlap Inventory

Reviewed 2026-08-02 at source revision
`8561fedb42471f0e99cd15d897002acb30f5e88b`. This is a read-only
architecture finding. It does not change entities, persistence, or UI.

## Answer

The user has **three durable concepts**, not four or five:

1. a **goal**: an optional objective that controls autonomous continuation,
   budgets, completion, and blocking for one conversation;
2. a **plan with execution tasks**: an editable/approvable document whose
   projected tasks expose progress, validation, and recovery; and
3. a **routine**: a reusable scheduled or manually triggered job with its own
   tool permissions, run history, notifications, and delivery behavior.

`ConversationWorkflowSpec` and `ConversationExecutionTaskProgress` are useful
implementation models, but users do not create or manage them as independent
top-level concepts. The workflow spec is now primarily an execution projection
of the plan document, while execution progress is mutable state joined to that
projection by task ID.

The safe reduction is therefore:

- keep goal, plan/task execution, and routine as distinct user concepts;
- finish making the plan document the sole authored source of workflow intent;
- keep workflow projection separate from mutable execution progress, but make
  task status owned only by execution progress; and
- share plan-artifact mechanics between conversations and routines without
  merging their aggregates or user surfaces.

## Lifecycle Map

| Concept | Domain role | Created or edited through | Persistence and lifetime | Completion authority | User-visible surface |
| --- | --- | --- | --- | --- | --- |
| Goal (`ConversationGoal`) | Optional autonomous objective and continuation budget for one conversation | Goal editor, `/goal`, goal suggestions, and `update_goal` | Embedded in conversation JSON and checkpoints; lives with one conversation | Evidence-aware goal finalization, accepted `update_goal`, repeated blockers, budgets, or explicit user action | Goal editor/status with active, awaiting confirmation, blocked, and completed states plus auto-continue/budget controls |
| Plan (`ConversationPlanArtifact`) | Reviewable authored contract with draft, approved text, and revision history | Plan Mode draft, document editor, review/approval, restore, and replan actions | Embedded in conversation JSON and checkpoints | Approval selects the execution document; a plan itself is not “completed” | Plan document, diff/review sheet, approval state, history, and plan actions |
| Workflow (`ConversationWorkflowSpec`) | Structured execution projection: goal text, constraints, acceptance criteria, questions, tasks, and provenance | Derived from approved Markdown for plan-first conversations; a legacy workflow editor/proposal path still exists | Embedded in conversation JSON with source hash and derived timestamp | No independent terminal state; stage and projected tasks drive execution | Users see task and workflow panels, but plan-first conversations block the legacy workflow editor |
| Execution progress (`ConversationExecutionTaskProgress`) | Mutable per-task outcome, validation, blocker, timestamps, and event history | Tool results, assistant-turn inference, task actions, validation, recovery, and replan flows | Embedded in conversation JSON and checkpoints, retained only for surviving task IDs | Validation/evidence and explicit task actions update status; locked terminal completion prevents accidental regression | Hydrated task rows show progress, validation, blockers, events, and recovery actions |
| Routine (`Routine`) | Reusable scheduled/manual prompt job with capability, workspace, delivery, and history policy | Routines home/editor and `create_routine` tool | Separate SharedPreferences `routines` collection; scheduler advances `nextRunAt`; run records survive individual executions | Each `RoutineRunRecord` completes or fails, but the routine remains enabled for future runs | Dedicated routines home/detail/editor, due/run-now controls, run transcript/history, notifications, and delivery status |

### State ownership

```text
Conversation
├── Goal                         autonomous objective policy
├── PlanArtifact                authored and approved document
├── WorkflowSpec                projection of execution intent
└── ExecutionTaskProgress[]     mutable state keyed by projected task ID

Routine repository
└── Routine
    ├── schedule and permissions
    ├── RoutinePlanArtifact     approved plan bound to routine source hash
    └── RoutineRunRecord[]      independent scheduled/manual executions
```

The current `Conversation.projectedExecutionTasks` getter proves the intended
split: it starts with immutable workflow tasks and overlays each matching
progress entry's status. The problem is not the split itself; it is that
`ConversationWorkflowTask` also persists a status, creating two owners for one
fact.

## Pairwise Decisions

| Pair | Decision | Evidence and reason |
| --- | --- | --- |
| Goal ↔ plan | Keep separate | A goal can auto-continue without a plan and carries budgets/blocking/completion. A plan can be reviewed and approved without enabling autonomous continuation. The plan is a contract; the goal is execution policy. |
| Goal ↔ workflow | Keep separate, remove duplicate authority | `ConversationWorkflowSpec.goal` is contract text while `ConversationGoal` is a lifecycle aggregate. Do not merge their schemas. When both exist, define provenance or one-way seeding so two editable objective strings are not silently treated as co-authoritative. |
| Goal ↔ execution progress | Keep separate | Goal finalization consumes aggregate evidence across turns/tasks. Task progress records one task's mutable status and validation history. Collapsing them would mix objective policy with evidence projection. |
| Goal ↔ routine | Keep separate | Goals are conversation-scoped and terminate; routines are reusable, scheduled, independently permissioned, and continue after successful runs. Users control them in different surfaces. |
| Plan ↔ workflow | Unify authored authority | Approved Markdown is already preferred, hashed, and projected into `ConversationWorkflowSpec`; plan-first conversations block the legacy workflow editor. Retain a typed projection, but stop presenting or persisting it as a second authored source. |
| Plan ↔ execution progress | Keep separate | Editing or restoring a plan changes intent and task identity; progress is mutable execution evidence. The source-hash/task-ID reconciliation is necessary precisely because these lifecycles differ. |
| Plan ↔ routine | Keep user concepts separate; share implementation | Both use draft/approved Markdown and bounded revision history. Routine approval additionally binds to a source hash and timestamp because schedule, permissions, and prompt changes stale the plan. Share mechanics, not storage ownership or UI. |
| Workflow ↔ execution progress | Keep the projection/state split; remove duplicate task status | Projection supplies title, files, validation command, notes, and provenance. Progress supplies run/validation/blocker/event state. Persist status only in progress and treat absence as pending. |
| Workflow ↔ routine | Keep separate | Workflow projection is derived for one conversation plan. A routine owns recurrence, permissions, delivery, and multiple run records. No current code makes routine scheduling part of conversation workflow execution. |
| Execution progress ↔ routine | Keep separate | Both record outcomes, but task progress is one task inside a live conversation contract, whereas run history records complete independent routine invocations with triggers, tool transcripts, and delivery. A shared “status” abstraction would erase useful semantics. |

## Consolidation Candidates and Cost

### C1 — Retire workflow as a second authored source

**Recommendation: blocked pending compatibility backfill.** Keep a renamed
internal projection such as `PlanExecutionProjection`, derived from the
approved plan. The read-only local audit found 19 legacy-authored workflows and
29 fresh plan-derived workflows. Remove the legacy workflow editor/proposal
mutation path only after the legacy records are backfilled and all supported
planning paths emit a plan document.

- Evidence: `Conversation.shouldPreferPlanDocument` switches to the plan as
  soon as an artifact exists; `refreshCurrentWorkflowProjectionFromApprovedPlan`
  hashes the execution document, derives the workflow, stabilizes task IDs, and
  retains matching progress; the workflow-editor contract explicitly says
  plan-first conversations never open the legacy editor.
- Estimated scope: 25-40 source/test files. There are 21 non-generated `lib`
  files referencing `ConversationWorkflowSpec`, with additional proposal,
  editor, prompt, projection, persistence, and compatibility tests.
- Behaviors at risk: legacy conversation loading, plan-less workflow proposals,
  plan approval fallback, task-ID stability, open-question retention, saved
  validation commands, plan canaries, and checkpoint restoration.
- Completed evidence: read-only SQLite audits classify aggregate workflow
  origins and apply the pure compatibility gate without exposing record data.
  Of 19 legacy records, 1 is compatible and 18 require current and checkpoint
  provenance preservation; 4 also have plan/progress conflicts. The next safe
  slice is an aggregate-only provenance-shape audit for those cohorts; do not
  delete the editor or mutate the live database.

### C2 — Give task status one owner

**Recommendation: pursue before moving task state into `TurnRuntime`.** Remove
`status` from authored/projected `ConversationWorkflowTask`; resolve missing
`ConversationExecutionTaskProgress` as pending. Keep task metadata in the
projection and all state transitions/events in progress.

- Evidence: `Conversation.projectedExecutionTasks` already overlays progress
  status, and progress stores validation, blocker, run timestamps, and events.
  The source task's status is therefore a competing default/state channel.
- Estimated scope: 20-30 source/test files, selected from 40 non-generated chat
  files that reference `task.status` or `ConversationWorkflowTaskStatus`.
- Behaviors at risk: JSON compatibility, manually edited legacy task status,
  completion lock semantics, task proposal parsing, goal continuation,
  execution summaries, worktree/subagent task projections, and UI action menus.
- Safe first slice: introduce `ExecutionTaskView` as a pure join of task intent
  and optional progress, migrate read paths, then migrate persisted writes and
  finally remove the source status field with generated serializers updated.

### C3 — Share plan-artifact mechanics

**Recommendation: small, independent cleanup.** Extract common immutable
revision/history normalization and draft-versus-approved comparison while
keeping `ConversationPlanArtifact` and `RoutinePlanArtifact` as compatibility
adapters or distinct wrappers.

- Evidence: both artifacts persist draft Markdown, approved Markdown, update
  time, revision kind/label/history, `hasDraft`, `hasApproved`,
  `hasPendingEdits`, and near-identical bounded `recordRevision` logic.
  Routine adds `approvedSourceHash`, `approvedAt`, and freshness rules that must
  remain routine-owned.
- Estimated scope: 8-16 source/test/generated files. Sixteen non-generated
  files currently reference the shared draft/approval mechanics across chat
  and routines.
- Behaviors at risk: persisted enum names, revision ordering/deduplication,
  whitespace normalization, history cap, approval timestamps, routine source
  freshness, and Freezed JSON compatibility.
- Safe first slice: extract pure functions/value primitives underneath both
  persisted wrappers; prove existing JSON round trips are byte-shape
  compatible before considering schema consolidation.

### C4 — Reconcile goal text with plan/workflow objective text

**Recommendation: define an invariant, not a merged entity.** When Plan Mode
creates a goal from workflow text, record source/provenance or an explicit
snapshot relationship. Do not automatically overwrite a user-managed active
goal when a plan is edited.

- Estimated scope: 6-10 source/test files around plan approval, goal creation,
  prompt context, status UI, and persistence.
- Behaviors at risk: user-edited goals, auto-continue budgets, restored plan
  revisions, completion evidence, and legacy conversations where the strings
  intentionally differ.
- Safe first slice: add a read-only mismatch diagnostic and fixtures for
  deliberate versus accidental divergence.

## What Must Stay Outside `TurnRuntime`

- The persisted plan artifact and workflow projection are conversation state.
  A turn runtime should receive an immutable contract/task snapshot and return
  typed progress events; it should not own document approval or projection
  persistence.
- Execution progress transitions are inside the turn boundary, but persistence,
  task-ID reconciliation, and history retention belong behind a conversation
  progress port.
- Goal completion/continuation consumes turn evidence and therefore needs a
  turn-facing policy/port, while the durable goal and budgets remain owned by
  the conversation.
- Routine scheduling, recurrence, run history, notifications, and delivery are
  outside the chat turn boundary. The only relevant bridge is a narrow
  routine-creation port used by `create_routine`.

No current source establishes a reason to put routine scheduling or execution
inside the future chat `TurnRuntime`.

## Measured Surface

These are dependency indicators, not automatic migration sizes:

| Symbol | Files in `lib` + `test` | Non-generated `lib` files |
| --- | ---: | ---: |
| `ConversationGoal` | 50 | 19 |
| `ConversationPlanArtifact` | 31 | 10 |
| `ConversationWorkflowSpec` | 69 | 21 |
| `ConversationWorkflowTask` | 102 | 44 |
| `ConversationExecutionTaskProgress` | 23 | 8 |
| `RoutinePlanArtifact` | 6 | 1 |
| `RoutineRunRecord` | 14 | 5 |

The non-generated routines feature contains 19 Dart files and 7,335 lines.
That size is not evidence for merging it into chat; the lifecycle and UI audit
shows it is a separate user-facing feature.

## Inspection Commands

```bash
rg --files lib/features/chat/presentation | \
  rg '(goal|plan|workflow|execution)' | sort
rg -n "ConversationGoal|ConversationPlanArtifact|ConversationWorkflowSpec|ConversationWorkflowTask|ConversationExecutionTaskProgress" \
  lib/features/chat -g '*.dart' -g '!*.freezed.dart' -g '!*.g.dart'
rg -n "RoutinePlanArtifact|RoutineRunRecord|nextRunAt|runRoutineNow|saveAll" \
  lib/features/routines -g '*.dart' -g '!*.freezed.dart' -g '!*.g.dart'
rg -n "effectiveWorkflowSpec|projectedExecutionTasks|executionProgressForTask|shouldPreferPlanDocument" \
  lib/features/chat/domain/entities/conversation.dart \
  lib/features/chat/presentation/providers/conversations_notifier.dart
git log --oneline --all -S'shouldPreferPlanDocument' -- \
  lib/features/chat/domain/entities/conversation.dart docs
git log --oneline --all -S'ConversationPlanArtifact' -- \
  lib/features/chat/domain/entities/conversation_plan_artifact.dart \
  lib/features/chat/domain/entities/conversation.dart
git log --oneline --all -S'RoutinePlanArtifact' -- \
  lib/features/routines/domain/entities/routine.dart
```

File counts were reproduced with this pattern for each symbol:

```bash
rg -l 'SYMBOL' lib test -g '*.dart' | wc -l
rg -l 'SYMBOL' lib -g '*.dart' -g '!*.freezed.dart' -g '!*.g.dart' | wc -l
```

## Exclusions and Unresolved Items

- A read-only aggregate audit inspected 439 persisted rows without emitting
  paths, identifiers, or record content. It found 19 legacy-authored workflows,
  which blocks deletion of the legacy authoring path.
- No schema migration was prototyped. All file estimates include generated and
  compatibility tests conceptually but are ranges, not implementation plans.
- Plan, workflow, and progress canary behavior was inferred from current code
  and checked-in test/runbook contracts; no live LLM canary was run for this
  documentation-only investigation.
- Routine plan approval and conversation plan approval share mechanics but not
  identical freshness semantics; a single persisted union type is not approved
  by this finding.
- Goal/workflow text divergence has no explicit provenance marker today. The
  report does not assume every mismatch is a bug.
