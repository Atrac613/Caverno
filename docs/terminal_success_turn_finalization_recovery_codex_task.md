# Terminal Success Turn-Finalization Recovery

## Task

- Goal: Prevent Coding Mode from requesting continuation recovery after a tool
  has returned an accepted structured terminal-success result.
- User-visible behavior: A successful verifier can finish the turn without a
  second model request that restarts inspection or attempts another mutation.
- Non-goals: Relaxing post-success mutation blocking, changing ordinary
  prose-only continuation recovery, or treating an unstructured exit code as
  terminal success.

## Context

- Affected files or components: Turn-finalization recovery policy and terminal-
  success provider tests.
- Trigger: The adaptive TODO minimal-prompt Live gate accepted a verifier result
  containing `terminal_success: true`, then turn finalization requested
  `coding_continuation_recovery` and the model repeated `write_file`.
- Root cause: The tool loop recognizes `ToolTerminalSuccessPolicy`, while turn
  finalization only recognized saved-task validation and Git lifecycle success.
- Reference pattern: `ToolTerminalSuccessPolicy` is the canonical structured
  terminal-success parser and must be reused rather than duplicated.

## Implementation Notes

- Extend terminal-goal-result detection to recognize any completed tool result
  accepted by `ToolTerminalSuccessPolicy`.
- Keep the existing saved validation and Git lifecycle checks unchanged.
- Add a regression response that would request a file mutation if finalization
  recovery incorrectly runs, then assert that the response is never consumed.

## Similar-Pattern Search

- Search terms: `coding_continuation_recovery`, `terminal_success`,
  `_latestCompletedToolResults`, `_finishExplicitTerminalSuccess`, and
  `_hasTerminalGoalSuccessToolResults`.
- Files inspected: Tool-loop batch execution, goal auto-continue terminal
  acceptance, turn-finalization recovery, and continuation-recovery tests.
- Adjacent finding: No equivalent gap exists in the in-loop terminal-success
  path; the Live log records `Terminal success accepted for current generation`
  before the erroneous finalization request.

## Acceptance Criteria

- Structured `terminal_success: true` skips turn-finalization continuation
  recovery even when earlier assistant narration looks like pending work.
- The terminal message remains the visible response and goal completion summary.
- A queued recovery-only mutation is not executed.
- Existing continuation recovery still applies when no structured terminal
  success evidence exists.

## Verification

```bash
fvm flutter test test/features/chat/presentation/providers/chat_notifier_test.dart \
  --plain-name "sendMessage records explicit terminal success as the goal summary"
tool/codex_verify.sh --coverage
```

After deterministic verification, repeat the TODO minimal-prompt Live canary
three times and require no `coding_continuation_recovery` after terminal success.

## Handoff Notes

- Summary: Turn finalization now reuses `ToolTerminalSuccessPolicy` when
  inspecting completed results. Structured terminal success stops recovery even
  when prior assistant narration contains future-action language.
- Tests run: The focused terminal-success provider regression passed, including
  assertions that the queued recovery mutation was not executed and no second
  tool-result request was sent. `tool/codex_verify.sh --coverage` also passed
  the full 3,153-test suite and analyzer.
- Coverage or low-coverage notes: Repository line coverage is 70.25%
  (48,102/68,475). Turn-finalization recovery coverage is 90.60% (106/117).
- Live evidence: The pre-fix sample was 2/3 ready; its only failure accepted the
  verifier and then entered the recovery path fixed here. The post-fix sample
  was 3/3 ready on `qwen3.6-27b-vision`, with 0 coding-continuation recovery
  requests, 0 turn-finalization recovery requests, and 0 post-success mutation
  attempts. Summary run ids: `1784009123`, `1784009257`, and `1784009382`.
- Risks or follow-ups: Ordinary prose-only continuation recovery remains active
  when no structured terminal-success evidence exists, as intended.
