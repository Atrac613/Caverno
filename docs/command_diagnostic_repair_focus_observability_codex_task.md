# Command Diagnostic Repair Focus Observability

## Task

- Goal: Measure when command-diagnostic repair focus activates before changing
  its activation threshold.
- User-visible behavior: Live LLM canary summaries distinguish Goal
  Auto-Continue repair contracts from per-request command-diagnostic repair
  focus.
- Non-goals: Changing repair-focus activation behavior, changing tool-loop
  budgets, or changing the session-log schema.

## Context

- Affected components: command-diagnostic focus logging and the generic live
  LLM canary summary parser.
- Related docs: `docs/repeated_command_diagnostic_repair_focus_codex_task.md`
  and `docs/session_logs.md`.
- Reference pattern: Existing Goal Auto-Continue and command-diagnostic signals
  in `tool/live_llm_canary_summary.dart`.
- Known evidence: Three TODO minimal-prompt runs passed, but every run repeated
  the same verifier diagnostic once before repair focus activated at streak 2.

## Implementation Notes

- Emit one explicit, redacted activation marker when focus changes from
  inactive to active.
- Parse the explicit marker in new logs and use the existing redacted
  `ExecutionShadow` marker as a compatibility fallback for historical logs.
- Keep the existing summary schema version because the JSON change is additive.
- Keep the legacy Goal Auto-Continue repair-contract metric and relabel it in
  Markdown so it cannot be confused with command-diagnostic repair focus.

## Similar-Pattern Search

- Search terms: `repairContractActivationCount`, `CommandDiagnostic`,
  `ExecutionShadow`, and `maxIdenticalDiagnosticSignatureStreak`.
- Files inspected: `chat_notifier_goal_auto_continue.dart`,
  `execution_snapshot_projector.dart`, `llm_session_log_store.dart`, and
  `live_llm_canary_summary.dart`.
- Follow-up found: A separate behavior slice can activate a soft repair focus
  at streak 1 after these metrics establish the baseline.

## Acceptance Criteria

- Summaries report command-diagnostic repair-focus activation count and streaks.
- Summaries report the number of unchanged verifier replays implied before
  focus activation.
- Explicit activation markers are not double-counted with ExecutionShadow.
- Historical logs without the explicit marker still produce the metrics.
- Goal repair-contract metrics remain backward compatible and clearly labeled.
- Runtime repair behavior remains unchanged.

## Verification

```bash
tool/codex_verify.sh --no-codegen --test test/tool/live_llm_canary_summary_test.dart
tool/codex_verify.sh --no-codegen
```

## Handoff Notes

- Summary: Added an explicit repair-focus activation marker and additive live
  canary summary metrics with ExecutionShadow compatibility fallback.
- Tests run: Focused summary tests, focused notifier integration test, one
  historical canary-log replay, and the full repository verification suite.
- Risks: ExecutionShadow fallback is intended only for logs created before the
  explicit activation marker existed.
- Follow-up: Implement and compare a streak-1 soft repair focus in a separate
  commit.
