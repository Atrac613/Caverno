# Final-Answer Tool Request Recovery

## Task

- Goal: Prevent a coding goal from stopping when a tool-result final-answer
  request emits a structured command request instead of a terminal answer.
- User-visible behavior: A malformed or non-executable final-answer tool
  request remains explicit incomplete evidence and receives one bounded coding
  continuation instead of being treated as a completed turn.
- Non-goals: Raising tool-loop budgets, bypassing tool approval, changing MVP
  fixture state isolation, or executing arbitrary text as a command.

## Context

- Affected components: `ContentParser`, final-answer tool-result streaming,
  coding continuation recovery, unexecuted action evidence, and turn-exit
  telemetry.
- Related docs: `docs/tool_loop_pending_batch_exit_codex_task.md` and
  `docs/goal_auto_continue_default_on_codex_task.md`.
- Reference pattern: Existing bracketed coding-tool recovery and
  `unexecuted_command_action` evidence.
- Known failure: Session `92646a52-efab-48f8-a3d6-bcb17290aad6` executed the
  final native batch, then emitted a complete `<tool_use>` block using
  `<arg_name>` fields. The final-answer stream stripped the block, did not
  execute or recover it, and persisted `pending_batch_executed` without an
  incomplete-evidence transform.

## Implementation Notes

- Add a deterministic notifier regression using the exact response shape from
  the session log before changing behavior.
- Recognize `<arg_name>` as a compatibility alias for `<arg_key>`, including
  multiple argument pairs and a tool name immediately followed by the first
  argument tag.
- Tool-result final-answer requests intentionally stream without direct tool
  execution. Route a detected structured coding request through the existing
  bounded coding continuation recovery so the recovered native call still uses
  normal approval, dispatch, and audit paths.
- If recovery cannot produce a native tool call, retain an unexecuted action
  result so Goal Auto-Continue sees incomplete evidence.
- Do not add a parallel execution loop.

## Similar-Pattern Search

- Search terms: `scanForTools: false`, `_looksLikeStructuredToolRequest`,
  `_requestCodingContinuationRecovery`, `pendingBatchExecuted`, `<arg_key>`,
  and `unexecuted_command_action`.
- Files inspected: content parser, final-answer stream, turn-finalization
  recovery, final-answer claim detector, turn-exit classifier, and session-log
  triage scorer.
- Follow-up: Memory extraction incorrectly summarized one failed scaffold
  command in the motivating session. Keep that separate unless the new
  unexecuted evidence is sufficient to correct it automatically.

## Acceptance Criteria

- The exact `<arg_name>` response shape parses into one command call with both
  `command` and `reason` arguments.
- A structured coding-tool request from a tool-result final answer is not saved
  as a successful terminal answer.
- Recovery issues at most one bounded follow-up and any native tool call uses
  the normal tool dispatcher and approval path.
- Japanese future actions equivalent to "I will confirm" and "I will verify"
  produce unexecuted command evidence when no matching execution result exists.
- An unresolved final tool request does not retain the healthy
  `pending_batch_executed` exit classification.
- Existing pending-batch execution, final-answer stripping, and content-tool
  deduplication behavior remains green.

## Verification

```bash
tool/codex_verify.sh --test test/core/utils/content_parser_test.dart
tool/codex_verify.sh --test test/features/chat/domain/services/final_answer_claim_detector_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart
tool/codex_verify.sh
```

After local verification, rerun the exact short TODO prompt with
`qwen3.6-27b-vision` and confirm the unknown-id validation executes before the
goal completes.

## Handoff Notes

- Preserve approval and audit semantics by recovering to native tool calls.
- Treat complete but unparseable tool markup as incomplete evidence, not as a
  successful tool result.
