# Saved Validation Final Evidence

## Task

- Goal: Prevent the final-answer fallback from labeling an exact successful
  saved validation as an unverified file change.
- User-visible behavior: After a saved task writes its target and its exact
  validation command exits successfully, the final answer may report that
  evidence without receiving a contradictory `UNVERIFIED CHANGE` instruction.
- Non-goals: Broadening shell command classification, weakening later-mutation
  guards, or changing saved validation command matching.

## Context

- Affected files or components: `ChatNotifier` tool-loop finalization,
  completion evidence, and saved workflow regression tests.
- Related docs: `docs/production_path_todo_live_canary_codex_task.md` and
  `docs/evidence_driven_execution_orchestrator_plan.md`.
- Reference implementation or pattern:
  `ToolResultCompletionEvidence.settleForExecutionGenerations` and the existing
  natural-stop saved validation test.
- Known failure: Production-path TODO canary
  `plan_mode_todo_app_live_canary_1784118227` passed, but its first two final
  answer fallback prompts included `UNVERIFIED CHANGE` after their exact saved
  validation commands returned exit code zero.

## Implementation Notes

- Preferred approach: Treat an exact successful current saved validation as
  authoritative for the current mutation generation before constructing the
  final-answer prompt. Reapply that settlement if finalization adds evidence.
- Constraints: Preserve unresolved diagnostics, failed verification, pending
  tool calls, unexecuted action claims, and later mutation invalidation.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

- Search terms: `savedValidationSucceededInLoop`, `UNVERIFIED CHANGE`,
  `settleForExecutionGenerations`, and `finalCompletionEvidence`.
- Files or modules inspected: Tool-result prompt construction, ChatNotifier
  tool-loop finalization, goal auto-continue generation settlement, and saved
  validation tests.
- Follow-up tasks found: The headless production-path baseline remains CLI0
  after this focused evidence fix is merged.

## Acceptance Criteria

- Required behavior: A write followed by an exact successful saved validation
  does not inject `UNVERIFIED CHANGE` into the final-answer request.
- Edge cases: Read-only saved validations remain authoritative only when they
  exactly match the current saved task command.
- Failure paths: Failed or modified validation commands, later mutations,
  unresolved diagnostics, and unexecuted pending tools remain blocking.
- Accessibility, localization, or platform expectations: None.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart
tool/codex_verify.sh --test test/features/chat/domain/services/tool_result_prompt_builder_test.dart
```

After deterministic verification, run the production-path TODO Live canary
once against the configured local model and inspect its final-answer prompts.

## Handoff Notes

- Summary: Exact successful saved validation now settles current-generation
  completion evidence before each final-answer prompt is built. The production
  TODO Live canary completed with three final-answer prompts and zero
  `UNVERIFIED CHANGE` markers.
- Tests run:
  `tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart`
  passed all 306 focused tests and analysis;
  `fvm flutter test test/features/chat/domain/services/tool_result_prompt_builder_test.dart`
  passed all 49 tests; production-path TODO Live canary
  `plan_mode_todo_app_live_canary_1784119689` passed 1/1 scenarios with no task
  drift or report-quality blockers.
- Coverage or low-coverage notes: The regression covers the natural-stop path
  with an exact compound saved validation command. Existing prompt-builder
  tests continue to cover blocking evidence, pending tools, and generation
  invalidation.
- Risks or follow-ups: The Live model needed one tool-less recovery before the
  integration-validation task made a concrete tool call. That behavior is
  recovered by the existing harness and is separate from this evidence fix.
  The headless production-path baseline remains the next CLI0 follow-up.
