# Goal Continuation Log Record Builder Integration

## Task

- Goal: route goal auto-continuation and completion-shadow record assembly
  through the existing pure `GoalContinuationLogRecordBuilder`.
- User-visible behavior: session-log fields, labels, context ownership, and
  omission rules remain compatible.
- Non-goals: changing log enablement, timestamps, storage, redaction, policy,
  or goal continuation behavior.

## Context

- Affected components: goal continuation logging adapters in
  `chat_notifier_goal_auto_continue.dart`.
- Related docs: `docs/chat_notifier_decomposition_workstream_8_codex_tasks.md`
  WS8-6 and `docs/large_file_refactor_plan.md`.
- Existing collaborator:
  `lib/features/chat/domain/services/goal_continuation_log_record_builder.dart`.
- Release gate: delayed writes must retain the exact turn owner and captured
  generation evidence.

## Implementation Notes

- Build auto-continue records from the exact owner conversation, tracker,
  evidence, cadence, generations, and safe boundary.
- Build completion-shadow records before checking log enablement so agreement
  filtering remains pure and testable.
- Keep owner log-context resolution, `DateTime.now()`, and
  `LlmSessionLogStore` writes in the notifier.
- Pass the builder's immutable fields to the existing store methods without
  changing their schema.
- Remove direct notifier dependencies on evidence-marker and shadow-label
  policies after integration.
- Do not modify generated entities.

## Similar-Pattern Search

- Search terms: `_recordGoalAutoContinueSessionLog`,
  `_recordGoalCompletionShadow`, `recordGoalAutoContinue`,
  `recordGoalCompletionShadow`, `GoalAutoContinueEvidenceMarker`, and
  `GoalCompletionShadow`.
- Files inspected: the goal auto-continue notifier part, builder and direct
  tests, log store, turn goal-completion registry, and detached-owner tests.
- Existing owner poison coverage: immutable builder snapshots and detached
  completion-shadow log routing.

## Acceptance Criteria

- Both log record shapes are assembled only by the pure builder.
- Log enablement, owner-context resolution, time injection, and writes remain
  notifier responsibilities.
- Null omission, counters, cadence, generations, evidence markers, decision
  labels, disagreement filtering, shadow labels, and turn IDs are unchanged.
- Direct builder coverage remains 100%.
- Goal continuation logging and detached-owner poison tests pass.
- Structural, file-size, and turn-scope ratchets pass without raising budgets.

## Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/goal_continuation_log_record_builder.dart \
  lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart \
  test/features/chat/domain/services/goal_continuation_log_record_builder_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/goal_continuation_log_record_builder_test.dart
fvm flutter test \
  test/features/chat/presentation/providers/chat_notifier_test.dart \
  test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

## Handoff Notes

- Record builder inputs and outputs, residual notifier responsibilities,
  owner-poison evidence, measured line-count reductions, coverage, and the
  next roadmap slice.
