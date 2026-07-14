# Structured Command Failure Classification

## Task

- Goal: Distinguish actionable non-zero command outcomes from approval or
  execution failures before applying consecutive tool-failure aborts.
- User-visible behavior: Validation diagnostics remain available for repair
  without incorrectly telling the user to check server configuration.
- Non-goals: Raising tool-loop budgets, weakening approval decisions, removing
  bounded loop exits, or changing command success-claim guardrails.

## Context

- Affected components: Tool result classification, shared batch execution,
  chat tool-loop failure accounting, and scheduler lifecycle telemetry.
- Related docs:
  `docs/embedded_function_tool_call_recovery_codex_task.md` and
  `docs/tool_loop_pending_batch_exit_codex_task.md`.
- Reference pattern: Structured command results already expose `exit_code`,
  `stdout`, `stderr`, and optional `diagnostics` fields.
- Known failure: TODO Live LLM canary run
  `coding_todo_app_minimal_prompt_live_canary_1783939802` returned actionable
  verifier diagnostics twice. Both were counted as generic tool failures,
  producing a misleading server-configuration message and requiring
  turn-finalization recovery despite a healthy tool endpoint.

## Implementation Notes

- Add one pure domain classifier shared by chat, routines, and scheduler
  telemetry.
- Classify a failed command result as actionable only when it is valid JSON,
  has a non-zero numeric `exit_code`, contains command output or diagnostics,
  and has no timeout or explicit execution-error marker.
- Classify approval denial before inspecting structured command output.
- Actionable command failures remain unsuccessful results, are not added to
  successful-call deduplication, and do not increment the infrastructure
  failure counter.
- Keep approval and execution failures on the existing two-strike abort path.
- Report actionable command outcomes as `command_failure` in lifecycle logs;
  keep `tool_failure` and `exception` for operational failures.
- Generated files are not needed.

## Similar-Pattern Search

- Search terms: `tool_failure_abort`, `toolFailureCounts`,
  `_isApprovalDenialResult`, `resultStatus`, `exit_code`, and
  `ToolCallBatchExecutor`.
- Files or modules inspected: Chat tool-loop batches, Routine tool runner,
  scheduler telemetry, local shell result encoding, MCP command dispatch, and
  TODO canary verifier results.
- Follow-up task found: Consider typed execution-outcome metadata on
  `McpToolResult` only if JSON classification proves insufficient for remote
  MCP command tools.

## Acceptance Criteria

- A failed command result with non-zero `exit_code` and diagnostics is
  classified as an actionable command failure.
- Repeating the same actionable command failure does not trigger
  `tool_failure_abort` or a server-configuration message.
- Actionable failures are still returned to the model and are not recorded as
  successful tool executions.
- Approval denial, timeout, explicit execution errors, malformed payloads, and
  non-command tool failures retain the existing consecutive-failure behavior.
- Scheduler telemetry emits `command_failure` only for actionable structured
  command outcomes.
- Existing iteration caps and diagnostic repair-contract behavior remain
  unchanged.

## Verification

```bash
tool/codex_verify.sh --no-codegen --test test/features/chat/domain/services/tool_failure_classifier_test.dart
tool/codex_verify.sh --no-codegen --test test/features/chat/domain/services/tool_call_batch_executor_test.dart
tool/codex_verify.sh --no-codegen --test test/features/chat/domain/services/tool_execution_scheduler_test.dart
tool/codex_verify.sh --no-codegen --test test/features/chat/presentation/providers/chat_notifier_test.dart
tool/codex_verify.sh
```

After local verification, rerun the short TODO Live LLM canary and inspect
lifecycle labels, turn-finalization recovery, and Goal Auto-Continue counts.

## Handoff Notes

- Preserve fail-closed approval behavior.
- Do not treat arbitrary textual command errors as actionable outcomes.
- Keep typed `McpToolResult` outcome metadata as a separate compatibility
  decision.
