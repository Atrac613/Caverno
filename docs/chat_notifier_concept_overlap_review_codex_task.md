# ChatNotifier Concept Overlap Review: Codex Task

## Task

- Goal: Determine whether goals, plans, workflows, execution progress, and
  routines represent distinct user concepts or duplicated implementation
  concepts, and cost any defensible unification.
- User-visible behavior: None. This is a read-only architecture investigation.
- Non-goals: Do not migrate entities, alter persistence, merge user surfaces,
  or change execution behavior.

## Context

- Affected files or components: `ConversationGoal`,
  `ConversationPlanArtifact`, `ConversationWorkflowTask`,
  `ConversationExecutionTaskProgress`, `Routine`, their repositories,
  coordinators, providers, prompts, and user-facing surfaces.
- Related docs: `docs/chat_notifier_inventory_codex_task.md` and
  `docs/chat_notifier_architecture_renewal_plan.md`.
- Reference implementation or pattern: Existing separation between immutable
  workflow intent and mutable execution progress; existing conversation and
  routine plan-artifact implementations.
- Known quirks, compatibility rules, or release gates: Persisted Freezed JSON
  is compatibility-sensitive. A distinction visible only in code is a merge
  candidate; a distinction relied on by users must remain explicit.

## Implementation Notes

- Preferred approach: Trace creation, persistence, mutation, completion, and UI
  presentation for each concept, then evaluate every pair using evidence from
  current code.
- Constraints: Label facts and inferences separately. Give each proposed
  unification a files-touched and behaviors-at-risk estimate. Do not treat file
  size alone as evidence that routines belong inside the chat turn boundary.
- Generated files needed: None.
- Migration or data compatibility concerns: Record them in the inventory, but
  do not implement migrations.

## Similar-Pattern Search

- Search terms: `ConversationGoal`, `ConversationPlanArtifact`,
  `ConversationWorkflowTask`, `ConversationExecutionTaskProgress`,
  `RoutinePlanArtifact`, `RoutineRunRecord`, and persistence keys.
- Files or modules inspected: Entities, serializers, repositories, notifier
  mutation sites, planning/execution services, routine scheduler/executor, and
  chat/routine UI entry points.
- Follow-up tasks found: Record separately in the findings document.

## Acceptance Criteria

- Required behavior: Publish `docs/chat_notifier_concept_overlap_inventory.md`
  with a concept lifecycle map and all pairwise decisions among goal, plan,
  workflow, execution progress, and routine.
- User model: State which concepts users experience as separate and cite the
  concrete interaction surfaces that establish each distinction.
- Domain model: State which records are source intent, approved artifact,
  mutable runtime projection, autonomous objective, or scheduled reusable job.
- Costing: Every merge candidate includes approximate files touched,
  persistence/behavior risks, and an incremental safe boundary.
- Negative findings: Give a defensible reason for every pair that should remain
  separate.
- Scope: Flag confirmed dependencies inside the future `TurnRuntime` boundary;
  keep routine scheduling and delivery outside unless current code proves a
  turn-local dependency.

## Verification

```bash
git diff --check
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Pending.
- Tests run: Pending.
- Coverage or low-coverage notes: Documentation-only investigation.
- Risks or follow-ups: Pending.
