# ChatNotifier Execution Task View Foundation: Codex Task

## Task

- Goal: Introduce a pure `ExecutionTaskView` join between workflow task intent
  and optional execution progress as the first M1 task-status ownership slice.
- User-visible behavior: None. Existing projected task status behavior remains
  compatible while new code gains an explicit progress-owned status view.
- Non-goals: Removing persisted workflow task status, changing status writers,
  migrating all task readers, or moving task state into `TurnRuntime`.

## Context

- Affected files or components:
  - `lib/features/chat/domain/entities/conversation_workflow.dart`
  - `lib/features/chat/domain/entities/conversation.dart`
  - `test/features/chat/domain/entities/conversation_test.dart`
- Related docs:
  - `docs/chat_notifier_concept_overlap_inventory.md`
  - `docs/chat_notifier_renewal_candidate_ranking.md`
  - `docs/chat_notifier_turn_runtime_prototype_verification_codex_task.md`
- Reference implementation or pattern:
  `Conversation.projectedExecutionTasks` already joins workflow task metadata
  with `ConversationExecutionTaskProgress` status.
- Known quirks, compatibility rules, or release gates:
  legacy conversations may encode execution state only in
  `ConversationWorkflowTask.status`. The compatibility projection must keep
  honoring that value until readers and writers have migrated.

## Implementation Notes

- Preferred approach:
  - Add a non-persisted immutable `ExecutionTaskView` value that retains task
    intent and optional progress separately.
  - Derive its execution status from progress, treating missing progress as
    pending.
  - Add `Conversation.executionTaskViews` as the pure join.
  - Delegate `projectedExecutionTasks` through the new view while preserving
    its current legacy fallback exactly.
- Constraints: Do not introduce a second status writer or change JSON shape.
- Generated files needed: No. The view is a plain Dart value, not a persisted
  Freezed entity.
- Migration or data compatibility concerns: A task whose authored status is
  non-pending and has no progress must remain non-pending through
  `projectedExecutionTasks`, even though the new execution view reports pending.

## Similar-Pattern Search

- Search terms: `projectedExecutionTasks`, `ConversationWorkflowTaskStatus`,
  `executionProgressForTask`, and `.status` on workflow tasks.
- Files or modules inspected: conversation entities, planning prompt and
  execution coordinators, workflow task lifecycle code, goal auto-continue,
  conversation persistence, and chat-page task builders.
- Follow-up tasks found: Migrate bounded readers to `ExecutionTaskView`, migrate
  status writers to progress, then remove persisted workflow task status after
  explicit legacy compatibility handling.

## Acceptance Criteria

- Required behavior:
  - A view exposes task metadata without copying it into progress.
  - Progress status is authoritative when progress exists.
  - Missing progress resolves to pending in the new view.
  - The legacy projection keeps its existing source-status fallback.
- Edge cases: A completed authored task without progress remains completed only
  through the compatibility projection.
- Failure paths: No new runtime failure path is introduced by the pure join.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/domain/entities/conversation_test.dart
```

## Handoff Notes

- Summary: Pending implementation.
- Tests run: Pending.
- Coverage or low-coverage notes: Focus on join precedence, missing progress,
  legacy fallback, and unchanged serialization.
- Risks or follow-ups: Production readers continue using the compatibility
  projection until their legacy semantics are audited individually.
