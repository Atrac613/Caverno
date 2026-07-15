# Mixed Verification Evidence

## Task

- Goal: Keep a failed project verifier blocking when another verifier succeeds
  in the same execution generation.
- User-visible behavior: Goal Auto-Continue does not stop with
  `no incomplete evidence` after static analysis succeeds but tests fail.
- Non-goals: Changing goal budgets, weakening validation-only mutation guards,
  or solving equivalent-but-differently-shaped verifier identity across turns.

## Context

- Affected files or components: Tool-result completion evidence, verification
  generation persistence, Goal Auto-Continue decisions, and focused provider
  tests.
- Related docs: `docs/goal_auto_continue_output_feedback_recovery_codex_task.md`
  and `docs/validation_probe_capability_gate_codex_task.md`.
- Reference implementation or pattern: Exit-zero command-output failures are
  already projected as blocking evidence even when a later analyzer succeeds.
- Known quirks, compatibility rules, or release gates: Session
  `e865cb13-7a97-461e-999a-6bff1d3caa7e` contained a successful `dart analyze`
  followed by failing `dart test` and `run_tests` results. Evidence still
  reported `no incomplete evidence` and stopped automatic continuation.

## Implementation Notes

- Preferred approach: Derive dispatched verification success and failure
  independently after the latest successful mutation. Treat a mixed batch as
  failed, and persist the verification generation only for a clean batch.
- Constraints: A later mutation must continue invalidating older verifier
  results. Guard rejections without execution evidence must not count as either
  success or failure. Preserve authoritative analyzer diagnostics behavior.
- Generated files needed: None.
- Migration or data compatibility concerns: Evidence is transient; no persisted
  entity or log schema changes are required.

## Similar-Pattern Search

- Search terms: `hasSuccessfulExecutionVerification`,
  `hasFailedExecutionVerification`, `carryForwardIncompleteFrom`,
  `recordCurrentVerificationGeneration`, and `settleForExecutionGenerations`.
- Files or modules inspected: Tool-result prompt builder, Goal Auto-Continue,
  conversation verification generations, command diagnostic replay, and
  focused domain/provider tests.
- Follow-up tasks found: Verifier identity may later be needed to reconcile a
  failure and an equivalent success expressed through different tool surfaces.
  Command classification gaps from the same session remain a separate slice.

## Acceptance Criteria

- Required behavior:
  - Analyze success plus test failure remains incomplete blocking evidence.
  - Result order does not change the mixed-batch outcome.
  - Mixed evidence does not advance the verification generation.
  - Goal Auto-Continue chooses a repair continuation instead of stopping.
- Edge cases: Analyze-only and test-only success remain successful; guard
  rejections remain non-execution evidence; a mutation after verification keeps
  verification stale.
- Failure paths: Non-zero verifier exits remain visible even when no structured
  diagnostics are present.
- Accessibility, localization, or platform expectations: No UI or localized
  strings change.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/domain/services/tool_result_prompt_builder_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart
tool/codex_verify.sh
```

After rebuilding the desktop app, repeat the exact short TODO prompt once and
confirm that a failed test dispatches repair rather than ending the goal.

## Handoff Notes

- Summary:
  - Commit `b3f87d4a` derives verifier success and failure independently after
    the latest mutation. Any failed verifier keeps the batch blocking, prevents
    verification-generation settlement, and sends Goal Auto-Continue into a
    repair turn.
  - Commit `6dc88780` recognizes direct Dart script checks and a single safe
    `cd <directory>` segment as verification. Cleanup, redirection, command
    substitution, and multiline mutation segments remain workspace mutations.
- Tests run:
  - Focused evidence-builder and Goal Auto-Continue regression tests passed.
  - The complete command-classifier and ChatNotifier test files passed.
  - `tool/codex_verify.sh` passed: generated output was clean, analysis found no
    issues, and all 3,244 tests passed.
- Coverage or low-coverage notes: Both result orderings are covered at the
  domain layer. The provider layer covers repair continuation, stale
  verification generation, validation-only acceptance, and the existing
  mutation rejection path.
- Risks or follow-ups:
  - A live LLM canary was not rerun in this slice. Rebuild the desktop app and
    repeat the short TODO prompt to confirm the production session now repairs
    a failed test instead of stopping.
  - Equivalent verifier identity across different tool surfaces and different
    turns remains intentionally out of scope.
  - The session's `unexecuted_file_save` false positive and auto-review denial
    still need separate evidence-backed tasks.
