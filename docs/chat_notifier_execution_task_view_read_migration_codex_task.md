# ChatNotifier Execution Task View Read Migration: Codex Task

## Task

- Goal: Move one production task-presence guard from the legacy projected task
  list to `Conversation.executionTaskViews`.
- User-visible behavior: None. Coding-verification validation progress is still
  recorded only when the owning conversation has at least one workflow task.
- Non-goals: Changing task status decisions, migrating execution focus
  selection, changing progress writes, removing legacy status, or changing
  persistence.

## Context

- Affected files or components:
  - `lib/features/chat/presentation/providers/chat_notifier_coding_verification_feedback.dart`
  - `test/features/chat/presentation/providers/chat_notifier_test.dart`
- Related docs:
  - `docs/chat_notifier_execution_task_view_codex_task.md`
  - `docs/chat_notifier_concept_overlap_inventory.md`
- Reference implementation or pattern:
  `Conversation.executionTaskViews` has the same task cardinality and ordering
  as `effectiveWorkflowSpec.tasks` while keeping status ownership explicit.
- Known quirks, compatibility rules, or release gates: The selected guard reads
  only list emptiness. It does not inspect task status, so legacy source-status
  fallback cannot affect its decision.

## Implementation Notes

- Preferred approach: Replace only the task-presence check in
  `_recordCodingVerificationValidationProgress`; leave the downstream legacy
  focus-task selection and status mapping unchanged.
- Constraints: Do not migrate another consumer in this slice.
- Generated files needed: No.
- Migration or data compatibility concerns: None. Both lists contain one entry
  per effective workflow task, regardless of progress presence or status.

## Similar-Pattern Search

- Search terms: `projectedExecutionTasks`, `.isEmpty`, `.isNotEmpty`, and
  `task.status`.
- Files or modules inspected: coding-verification feedback, workflow
  preservation, execution snapshots, planning prompts, goal auto-continue,
  workflow task lifecycle, task run coordination, and chat-page builders.
- Follow-up tasks found: The other consumers read status or feed persisted and
  control-flow behavior. Audit them separately before migration.

## Acceptance Criteria

- Required behavior:
  - Coding-verification task presence is read from `executionTaskViews`.
  - The existing validation-progress test remains green.
  - No status calculation or progress write changes.
- Edge cases: Conversations with tasks but no progress still pass the presence
  guard because their views are present and report pending.
- Failure paths: Conversations without tasks still return before selecting or
  writing progress.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
fvm flutter test test/features/chat/presentation/providers/chat_notifier_test.dart \
  --plain-name "sendMessage records coding verification snapshots on execution progress"
tool/codex_verify.sh --test test/features/chat/domain/entities/conversation_test.dart
```

## Handoff Notes

- Summary: Pending implementation.
- Tests run: Pending.
- Coverage or low-coverage notes: This slice changes a cardinality-only guard;
  the existing end-to-end notifier test covers the progress write path.
- Risks or follow-ups: Status-reading consumers remain on the legacy projection
  pending explicit fixture-backed compatibility decisions.
