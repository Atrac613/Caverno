# Path-Backed Verifier Replay Guard

## Task

- Goal: Prevent a weak coding model from rerunning the same failing verifier
  after repair focus without first attempting the sourced corrective mutation.
- User-visible behavior: The model receives an actionable synthetic tool result
  instead of spending time on an unchanged verifier replay.
- Non-goals: Blocking verification after a mutation, blocking a different
  diagnostic command, or requiring file mutation for pathless diagnostics.

## Context

- Affected components: Coding command guardrails, command-diagnostic repair
  focus, tool-loop result handling, and Live LLM canary reporting.
- Related docs:
  `docs/command_diagnostic_streak_one_repair_focus_codex_task.md` and
  `docs/markdown_toc_streak_one_repair_focus_live_validation_codex_task.md`.
- Evidence: The third Markdown TOC cross-fixture run passed but repeated the
  same verifier diagnostic four times. After streak 1, the model performed only
  reads before each of three further verifier calls and delayed its mutation
  until Goal Auto-Continue started another turn.
- Existing pattern:
  `_buildUnexecutedFileMutationBeforeCommandGuardResult` returns an actionable
  synthetic result while leaving the external command unexecuted.

## Implementation Notes

- Match the attempted verification call against the active repair focus using
  the existing normalized tool-failure key.
- Apply the guard only when the active diagnostic is path-backed.
- Allow the verifier when the same batch includes a mutation attempt; this
  preserves the common edit-and-verify batch shape.
- Clear the guard through the existing successful-mutation focus reset.
- Return a successful synthetic tool result so a policy intervention is not
  misclassified as an endpoint or execution failure.
- Handle the synthetic result separately from real command success so it does
  not reset diagnostic state or become completion evidence.
- Emit an explicit blocked-replay log marker and report its count in canary JSON
  and Markdown summaries.

## Similar-Pattern Search

- Search terms: `commandDiagnosticRepairFocus`, `toolFailureKey`,
  `unexecuted_file_save`, `actionableCommandFailure`, and
  `unchangedVerifierReplayBeforeRepairCount`.
- Files inspected: `chat_notifier_command_guardrails.dart`,
  `chat_notifier_tool_loop_batch.dart`, `chat_notifier_goal_auto_continue.dart`,
  `tool_failure_classifier.dart`, and `live_llm_canary_summary.dart`.
- Follow-up: Re-run the Markdown TOC exact-short canary after the focused and
  full test suites pass.

## Acceptance Criteria

- The same path-backed verifier is not dispatched again while repair focus is
  active and no mutation is requested.
- The model receives the diagnostic summary and a concrete mutation-first
  instruction in the synthetic result.
- A mutation plus verifier batch remains allowed.
- Pathless repair focus does not activate the guard.
- Synthetic guard results do not clear diagnostic repair focus or count as real
  verification success.
- Canary summaries report blocked unchanged verifier replays after focus.
- Existing repair prompt, tool-loop, approval, and completion tests remain
  green.

## Verification

```bash
tool/codex_verify.sh --no-codegen --test test/features/chat/presentation/providers/chat_notifier_test.dart
tool/codex_verify.sh --no-codegen --test test/tool/live_llm_canary_summary_test.dart
tool/codex_verify.sh --no-codegen
```

## Handoff Notes

- Summary: The same path-backed verifier is now replaced with an actionable
  synthetic result while repair focus remains active. Pathless, different, and
  mutation-batched commands remain allowed, and canary summaries count blocked
  replays explicitly.
- Tests run: Fifteen focused policy, notifier, and summary tests passed.
  `flutter analyze` passed. The default parallel full suite exposed an unrelated
  Settings diagnostic-export test that passed in isolation; the complete suite
  then passed all 3,127 tests with `fvm flutter test --concurrency=1`.
- Risks: A verifier requested in the same batch as a failed mutation may still
  run once. This is preferable to rejecting valid edit-and-verify batches and
  will reactivate the guard if the path-backed diagnostic remains.
- Live comparison: Three clean-build exact-short Markdown TOC runs passed in
  177.7, 533.5, and 268.6 seconds. The 326.6-second average is effectively the
  same as the older 323.7-second baseline but slower than the immediately prior
  294.3-second sample because one run encountered four distinct diagnostics.
  Maximum identical diagnostic streaks were 0, 1, and 1. The slow run attempted
  one unchanged verifier replay after repair focus; the guard blocked it and
  the next Goal Auto-Continue request performed a corrective edit before later
  successful verification. All runs retained terminal-success evidence, and no
  run blocked after success or mutated after successful verification.
