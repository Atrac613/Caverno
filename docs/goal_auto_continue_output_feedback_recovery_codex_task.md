# Goal Auto-Continue Output Feedback Recovery

## Task

- Goal: Preserve exit-zero command output failures until Goal Auto-Continue
  dispatches a repair turn and the relevant behavior is verified again.
- User-visible behavior: A validation-only continuation that observes a runtime
  failure does not stop with `no incomplete evidence`; it advances to a bounded
  repair turn with mutation tools.
- Non-goals: Increasing goal budgets, adding TODO-specific orchestration, or
  exposing mutation tools during the validation probe itself.

## Context

- Affected files or components: Coding command output feedback, tool-result
  completion evidence, Goal Auto-Continue capability selection, and hidden-turn
  command guardrails.
- Related docs: `docs/validation_probe_capability_gate_codex_task.md` and
  `docs/session_logs.md`.
- Reference implementation or pattern: Analyzer diagnostics already become
  durable incomplete evidence and drive a later repair continuation.
- Known quirks, compatibility rules, or release gates: A compound shell command
  can exit zero after an earlier runtime failure. The command output guardrail
  detects that failure, but its `issues` payload is not currently projected into
  Goal Auto-Continue evidence.

## Implementation Notes

- Preferred approach:
  1. Project command output feedback issues into authoritative error diagnostics.
  2. Prevent failed output feedback from being classified or settled as a
     successful verification.
  3. Use command-effect classification for local verification evidence.
  4. Reject non-verification shell effects during validation-only continuations.
- Constraints: Preserve the existing validation-turn then repair-turn state
  transition. Keep the change generic across coding tasks and command outputs.
- Generated files needed: None.
- Migration or data compatibility concerns: Added evidence is transient and the
  existing feedback JSON schema remains backward compatible.

## Similar-Pattern Search

- Search terms: `coding_output_feedback`, `completionEvidence`,
  `hasSuccessfulExecutionVerification`, `settleForExecutionGenerations`,
  `allowedToolNames`, and `ToolCommandEffect.verification`.
- Files or modules inspected: Command output guardrail service, tool-result
  prompt builder, Goal Auto-Continue provider extension and policy, tool-loop
  command guardrails, and focused provider tests.
- Follow-up tasks found: Verification identity may need a separate durable key
  if equivalent but non-identical verifier commands must later clear a carried
  runtime failure across turns.

## Acceptance Criteria

- Required behavior:
  - Exit-zero `coding_output_feedback` failures count as incomplete blocking
    evidence.
  - A later successful command in the same turn does not erase that failure.
  - Matching execution generations do not settle current blocking evidence.
  - Goal Auto-Continue dispatches a repair turn after the failed validation.
  - Validation-only continuations reject inspection and mutation shell commands.
- Edge cases: Normal exit-zero verifiers still settle unverified mutation
  evidence, and analyzer/test diagnostics keep their existing behavior.
- Failure paths: Repeatedly ignoring the verifier-only instruction remains
  bounded by the existing validation-miss policy.
- Accessibility, localization, or platform expectations: Existing localized UI
  strings remain unchanged; new tool feedback and repository text are English.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/domain/services/tool_result_prompt_builder_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart
tool/codex_verify.sh
```

After rebuilding the desktop app, repeat the exact short TODO prompt once and
run the independent TODO behavior verifier against the generated project.

## Handoff Notes

- Summary: Exit-zero command output failures now remain blocking Goal
  Auto-Continue evidence, validation-only continuations enforce verification
  command effects, and compound commands cannot hide mutations behind a
  verifier segment. Implemented in `364a5d21`, `9967d15a`, and `082ff611`.
- Tests run:
  - `tool/codex_verify.sh --test test/features/chat/domain/services/tool_result_prompt_builder_test.dart`
    equivalent pinned-SDK run: 49 tests passed.
  - `flutter test test/core/security/tool_capability_classifier_test.dart`:
    18 tests passed.
  - Focused Goal Auto-Continue and saved-validation regressions passed.
  - `flutter test test/features/chat/presentation/providers/chat_notifier_test.dart`:
    303 tests passed.
  - `tool/codex_verify.sh`: code generation clean, analysis clean, and 3,240
    tests passed.
- Coverage or low-coverage notes: Coverage was not collected. The new evidence,
  continuation guard, compound-command, approval-cache, and status-wrapper
  branches have focused regression coverage.
- Risks or follow-ups: Rebuild the desktop app and repeat the exact short TODO
  prompt before treating the production-path canary as complete. Consider a
  durable verifier identity only if equivalent but non-identical commands must
  clear carried output failures in a later task.
