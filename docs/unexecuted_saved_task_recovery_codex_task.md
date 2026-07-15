# Unexecuted Saved Task Recovery

## Task

- Goal: Recover a saved Coding workflow task when the model claims command or
  file completion without executing any tool.
- User-visible behavior: Caverno corrects the false completion claim and then
  performs one bounded recovery turn instead of leaving the saved task idle.
- Non-goals: Treating real command failures as tool-less turns, changing Goal
  Auto-Continue budgets, or weakening completion evidence requirements.

## Context

- Affected files or components: saved workflow execution in `ChatPage`, Plan
  execution guardrails, and focused product-path regression tests.
- Related docs: `docs/production_path_todo_live_canary_codex_task.md` and
  `docs/evidence_driven_execution_orchestrator_plan.md`.
- Reference implementation or pattern: the Plan Mode live harness retries a
  saved task while its persisted status remains `inProgress`.
- Known failure: Coding session
  `94ac5727-bccc-4ae1-ab72-f1f34c853739` returned a command-success narrative
  with zero tool calls. The false-completion guard emitted
  `unexecuted_command_action`, but the product workflow treated the synthetic
  result as a non-empty tool batch and skipped tool-less recovery.

## Implementation Notes

- Preferred approach:
  1. Classify synthetic non-execution guard results separately from real tool
     execution results.
  2. Allow bounded tool-less saved-task recovery when the result batch is empty
     or contains only those synthetic results.
  3. Preserve existing handling for real failed commands, edits, approvals,
     and diagnostics.
- Constraints: Keep the classification generic and shared. Do not add
  TODO-specific behavior or increase retry budgets.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

- Search terms: `unexecuted_command_action`, `unexecuted_file_save`,
  `unverified_read_only_inspection_claim`, `tool_call_not_executed`,
  `toolResults.isNotEmpty`, and `buildToolLessExecutionRecoveryPrompt`.
- Files or modules inspected: final-answer claim detection, saved workflow
  execution, Goal Auto-Continue, Plan Mode live harness execution, and Plan
  execution guardrails.
- Follow-up tasks found: A future orchestration extraction should make the app
  and headless harness call the same saved-task recovery controller. That is
  outside this focused fix.

## Acceptance Criteria

- Required behavior:
  - A result batch containing only synthetic non-execution results is eligible
    for bounded tool-less recovery.
  - A batch containing any real tool execution or real failure is not
    reclassified as tool-less.
  - A saved task remains incomplete until concrete mutation or verification
    evidence is recorded.
- Edge cases: Empty result batches retain the existing recovery behavior, and
  mixed real/synthetic batches retain the real evidence path.
- Failure paths: Recovery remains bounded and may leave or mark the task
  blocked when the follow-up also produces no concrete progress.
- Accessibility, localization, or platform expectations: No user-facing copy
  or platform behavior changes.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/domain/services/conversation_plan_execution_guardrails_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/pages/chat_page_saved_workflow_recovery_test.dart
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Added a shared synthetic non-execution result classifier, routed
  those saved-task turns into the existing bounded tool-less recovery path,
  and covered the production `Approve and start` execution flow with a widget
  regression test.
- Tests run: Both focused suites passed with 62 tests, and
  `tool/codex_verify.sh` passed code generation checks, static analysis, and
  all 3,232 tests.
- Coverage or low-coverage notes: Coverage was not collected. The focused
  tests cover every recognized synthetic code, bounded loop exhaustion, mixed
  evidence, real command failure, empty input, and the product UI route.
- Risks or follow-ups: Re-run the production-path TODO live canary to confirm
  the local model follows the recovery prompt. A future orchestration
  extraction should remove the remaining recovery-policy duplication between
  the product page and the live harness.
