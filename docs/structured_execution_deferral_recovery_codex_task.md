# Structured Execution-Deferral Recovery

## Task

- Goal: Recover an active coding implementation turn when the model returns a
  structured plan for its next tool actions instead of issuing a tool call.
- User-visible behavior: A short coding request continues into one bounded,
  tool-aware recovery in the same turn instead of stopping after headings such
  as `What I need to verify` and `Next Chunk`.
- Non-goals: Broadening Goal Auto-Continue from pending workflow state alone,
  recovering ordinary planning answers, or retrying more than once.

## Context

- Affected files or components: initial no-tool coding continuation detection,
  turn-finalization recovery fallback, and focused ChatNotifier tests.
- Related docs: `docs/pending_action_length_recovery_codex_task.md` and
  `docs/evidence_driven_execution_orchestrator_plan.md`.
- Reference implementation or pattern: Existing prose-only coding continuation
  recovery before assistant-message persistence.
- Known failure: Coding session `57d72b13-8bc7-44b6-a7a1-9e28634bedaa`
  received 60 tools and an execution snapshot with action `execute`, but the
  model returned `What I need to verify` and `Next Chunk` prose with zero tool
  calls. The response finished normally and the pending workflow did not
  auto-continue because no tool-result evidence existed.

## Implementation Notes

- Preferred approach: Add a pure structured-deferral detector and let it pass
  the initial continuation-request gate only when an active auto-continue goal
  has an implementation workflow whose projected next action is `execute`.
- Constraints: Preserve the existing future-tense detector for ordinary coding
  turns. Reuse the one-shot turn-finalization recovery generation guard.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

- Search terms: `prose_only_coding_continuation`, `Next Chunk`,
  `hasIncompleteEvidence`, `no incomplete evidence`, and
  `_recoverBeforeTurnFinalizationIfNeeded`.
- Files or modules inspected: coding continuation recovery, turn-finalization
  recovery, Goal Auto-Continue policy, execution snapshot projection, and
  supplied session-log metadata.
- Follow-up tasks found: Keep adaptive MVP entrypoint verification as a
  separate harness slice after initial execution recovery is proven.

## Acceptance Criteria

- Required behavior: The supplied structured response shape triggers one
  coding continuation recovery while an active implementation workflow still
  requires execution.
- Edge cases: Existing `I will ...` recovery remains unchanged; a structured
  response without an active auto-continue implementation goal is preserved.
- Failure paths: Questions, blockers, and text without both a structured
  planning marker and a concrete coding action do not match.
- Accessibility, localization, or platform expectations: No UI or platform
  behavior changes.

## Verification

```bash
tool/codex_verify.sh --coverage
```

After deterministic verification, run the TODO minimal-prompt Live canary
three times and confirm that a structured initial deferral is either absent or
recovered into a real tool call before the turn is persisted.

## Live Validation

- Build: commit `24af7eb0`, clean worktree.
- Endpoint: `http://192.168.100.241:1234/v1`.
- Model: `qwen3.6-27b-vision` with a 65,536-token context and one parallel
  request slot.
- Result: 3/3 runs passed with `ready` main readiness. Every run reached its
  first successful verifier on turn 1 and observed terminal success.
- Structured deferral result: None of the runs emitted the incident headings
  or required coding-continuation or turn-finalization recovery. All three
  proceeded into real tool execution without persisting a plan-only answer.

| Run | Duration | Repair focus | Read replay | Report |
| --- | ---: | ---: | ---: | --- |
| 1 | 595,775 ms | 4 | 1 | `build/integration_test_reports/coding_todo_app_minimal_prompt_live_canary_1784002411` |
| 2 | 189,438 ms | 2 | 0 | `build/integration_test_reports/coding_todo_app_minimal_prompt_live_canary_1784003021` |
| 3 | 231,391 ms | 3 | 0 | `build/integration_test_reports/coding_todo_app_minimal_prompt_live_canary_1784003223` |

## Handoff Notes

- Summary: Added a pure structured execution-deferral detector and gated its
  recovery path on an active auto-continue goal whose implementation workflow
  still projects an executable pending task without unresolved questions.
- Tests run: `tool/codex_verify.sh --coverage` completed successfully with
  3,148 tests passing and no analyzer findings. The TODO minimal-prompt Live
  canary passed 3/3 times against the configured local model.
- Coverage or low-coverage notes: Repository line coverage is 70.27%
  (48,112/68,472). The new detector has 100% line coverage (12/12).
- Risks or follow-ups: The lexical markers are intentionally narrow to avoid
  converting ordinary plans into execution. The stochastic Live runs did not
  reproduce the structured deferral, so the exact recovery branch is covered
  by the deterministic incident test. Adaptive MVP entrypoint verification
  remains a separate harness slice.
