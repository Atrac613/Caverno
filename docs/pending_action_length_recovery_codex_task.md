# Pending-Action Length Recovery

## Task

- Goal: Keep incomplete coding work executable when a tool-result response hits
  the output-token limit before issuing its next tool call.
- User-visible behavior: Caverno makes one compact, tool-aware action retry in
  the same turn instead of converting an unfinished repair into a prose-only
  final answer.
- Non-goals: Increasing model or goal token budgets, adding a persisted state
  machine, suppressing legitimate file reads, or retrying indefinitely.

## Context

- Affected components: Final-answer recovery, coding continuation recovery,
  tool-loop finalization, execution budget telemetry, and Live LLM canaries.
- Related docs: `docs/evidence_driven_execution_orchestrator_plan.md` and
  `docs/ordered_verifier_replay_guard_codex_task.md`.
- Reference pattern: Existing coding continuation recovery already re-enters
  the tool loop with the current tool definitions.
- Known failure: Two exact-short Markdown TOC runs emitted seven
  `finish_reason=length` responses while diagnostics remained. The current
  final-answer recovery removes all tools and asks for a concise final answer,
  so the recovery cannot perform the pending repair.

## Implementation Notes

- Add a pure routing policy that distinguishes completed-answer recovery from
  pending-action recovery.
- Select pending-action recovery only for coding work with incomplete evidence,
  an output-length finish reason, available coding tools, and no prior
  pending-action length retry in the current interaction generation.
- Reuse the current tool definitions so validation and repair capability gates
  remain authoritative.
- Ask for exactly one tool call without analysis or a final answer. Preserve
  current diagnostics and previously gathered context.
- Execute a returned tool call in the same interaction. A prose response or a
  second truncation must not create another action-only retry.
- Preserve the current concise final-answer retry for completed work and
  excessive-repetition recovery.

## Similar-Pattern Search

- Search terms: `FinalAnswerRecoveryPolicy`,
  `_requestCodingContinuationRecovery`, `finish_reason=length`,
  `ExecutionBudgetPolicy`, and `allowedToolNames`.
- Files inspected: Final-answer recovery, coding continuation recovery,
  turn-finalization recovery, Goal Auto-Continue capability selection, and
  tool-loop batch execution.
- Follow-up task found: Reuse a successful identical `read_file` result within
  one mutation generation if repeated reads remain significant after this
  action-only recovery lands.

## Acceptance Criteria

- A length-truncated coding answer with incomplete evidence receives one
  tool-aware action retry.
- The retry uses the same restricted tool definitions as the active tool loop.
- A returned tool call executes in the same interaction.
- A second truncation or prose-only retry does not recurse.
- Completed read-only work retains the concise no-tool final-answer retry.
- Excessive-repetition recovery retains its existing behavior.
- Non-coding conversations do not receive action-only recovery.

## Verification

```bash
tool/codex_verify.sh --no-codegen --test test/features/chat/domain/services/pending_action_length_recovery_policy_test.dart
tool/codex_verify.sh --no-codegen --test test/features/chat/presentation/providers/chat_notifier_test.dart
tool/codex_verify.sh --no-codegen
```

After local verification, run the exact-short Markdown TOC Live LLM canary
three times sequentially. If it reaches 3/3, run one structurally different
MVP canary as a genericity check.

## Live Validation

All runs used `qwen3.6-27b-vision` at
`http://192.168.100.241:1234/v1`. The model endpoint reported a loaded 65,536
token context instance.

| Canary | Result | Duration | First verifier turn | Diagnostics |
|--------|--------|---------:|--------------------:|------------:|
| Markdown TOC exact-short run 1 | passed | 146,246 ms | 1 | 2 |
| Markdown TOC exact-short run 2 | passed | 90,579 ms | 1 | 0 |
| Markdown TOC exact-short run 3 | passed | 181,242 ms | 1 | 1 |
| Expense tracker genericity check | passed | 237,104 ms | 1 | 10 |

Every run reported main readiness `ready`, terminal verifier success, zero
warnings, zero transport disconnects, and no blocked state after success. The
exact-short promotion slice reached 3/3, and the structurally different expense
tracker fixture reached 1/1.

Report directories:

- `build/integration_test_reports/coding_markdown_toc_exact_short_live_canary_1783993464`
- `build/integration_test_reports/coding_markdown_toc_exact_short_live_canary_1783993621`
- `build/integration_test_reports/coding_markdown_toc_exact_short_live_canary_1783993726`
- `build/integration_test_reports/coding_expense_tracker_live_canary_1783993957`

## Handoff Notes

- Summary: Added a pure pending-action routing policy, preserved the active
  capability-filtered tool definitions for one action-only retry, and re-entered
  the existing tool loop when that retry returns a tool call. Extracted streamed
  final-answer recovery into a dedicated notifier part to satisfy the large-file
  ratchet without raising its budget.
- Tests run: The policy tests, all ChatNotifier tests, the file-size ratchet,
  the TODO live-canary wrapper contract tests, and
  `tool/codex_verify.sh --no-codegen --coverage` pass.
- Coverage or low-coverage notes: The final full coverage run completed with
  3,134 passing tests. The new pure policy covers the positive route plus
  completed, non-coding, missing-tool, already-retried, and normal-stop
  boundaries. The notifier boundary test covers tool-loop re-entry and the
  second-truncation bound.
- Risks or follow-ups: These successful runs did not emit a length-truncated
  final stream, so deterministic notifier coverage remains the direct evidence
  for the new recovery branch. If repeated reads remain significant in a future
  truncated run, add mutation-generation-scoped successful read-result reuse as
  a separate slice.
