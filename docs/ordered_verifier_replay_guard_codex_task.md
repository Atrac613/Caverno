# Ordered Verifier Replay Guard

## Task

- Goal: Prevent a path-backed verifier replay from running before the mutation
  that is supposed to justify it in the same tool-call batch.
- User-visible behavior: A verifier-first batch receives the existing
  mutation-first synthetic result, while the later mutation remains eligible
  to execute.
- Non-goals: Requiring a mutation to succeed before verification, blocking a
  different verifier, or changing pathless diagnostic recovery.

## Context

- Affected components: Coding command guardrails, tool-loop batch execution,
  notifier tests, and short-prompt MVP Live LLM canaries.
- Related docs: `docs/path_backed_verifier_replay_guard_codex_task.md`.
- Reference implementation: The existing path-backed verifier replay policy
  and synthetic guard result.
- Known quirk: Serial tool calls execute in model-provided order, but the guard
  currently treats any mutation anywhere in the batch as sufficient. A
  verifier-first batch can therefore execute the unchanged verifier before its
  later mutation.

## Implementation Notes

- Consider only mutation requests that precede the verifier in the pending
  batch.
- Continue to treat a mutation request as sufficient regardless of its result;
  this preserves the existing attempt-based policy.
- Keep the later mutation executable when a preceding verifier is blocked.
- Add a canary-local trace invariant for ordinary short-prompt MVP scenarios.
  Do not apply it to the staged diagnostic plateau scenario, which deliberately
  repeats a verifier diagnostic.
- Keep global canary readiness and duration thresholds unchanged. A non-zero
  blocked-replay count is successful guard activity, not a regression.

## Similar-Pattern Search

- Search terms: `hasPendingMutation`, `pendingToolCalls`,
  `CommandDiagnosticVerifierReplayPolicy`, and `executedCalls`.
- Files inspected: `chat_notifier_command_guardrails.dart`,
  `chat_notifier_tool_loop_batch.dart`, `tool_execution_scheduler.dart`, the
  verifier replay policy tests, and the TODO fixture Live LLM canary.
- Follow-up task found: A separate release gate is unnecessary until the scoped
  trace invariant has proved stable across the existing MVP fixtures.

## Acceptance Criteria

- A `[verifier, mutation]` batch blocks the verifier and still executes the
  mutation.
- A `[mutation, verifier]` batch remains allowed.
- Mutation success is not required to allow a following verifier.
- Pathless diagnostics and different verifier commands retain their current
  behavior.
- Ordinary TODO and derived MVP canaries fail if the same path-backed verifier
  is dispatched again without an intervening mutation attempt.
- The staged diagnostic repair canary retains its intentional repeated
  diagnostic sequence.

## Verification

```bash
tool/codex_verify.sh --no-codegen --test test/features/chat/presentation/providers/chat_notifier_test.dart
tool/codex_verify.sh --no-codegen --test tool/canaries/coding_goal_auto_continue_todo_fixture_live_canary_test.dart
tool/codex_verify.sh --no-codegen
```

After local verification, run the exact-short Markdown TOC Live LLM canary
three times sequentially.

## Handoff Notes

- Summary: The production guard now requires a preceding mutation request in
  the current batch, and ordinary MVP canaries reject unchanged path-backed
  verifier redispatches before a mutation attempt.
- Tests run: The focused policy, notifier, and TODO fixture suite passed 307
  tests with 8 Live tests skipped. `tool/codex_verify.sh --no-codegen` passed
  analysis and all 3,129 tests.
- Coverage or low-coverage notes: Unit coverage includes both tool-call batch
  orders, failed mutation attempts, path-backed replay detection, and pathless
  diagnostic exclusion.
- Live validation: Three sequential exact-short Markdown TOC runs produced one
  pass and two failures. The passing run completed in 716,811 ms with zero
  unchanged verifier replays. Each failed run blocked two unchanged verifier
  replays; one exhausted the 60,000-token budget and the other reached the
  diagnostic repair continuation limit.
- Risks or follow-ups: Preserve the deliberate staged plateau exception. The
  ordered replay guard is Live-validated, but the 1/3 MVP completion rate is
  not release-ready. The next task should address weak-model repair execution,
  especially long reasoning that truncates mutation arguments and repeated
  reads that consume the repair budget.
