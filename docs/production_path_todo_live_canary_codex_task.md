# Production-Path TODO Live Canary

## Task

- Goal: Add a Live LLM canary that starts from the real Plan Mode surface,
  approves the generated plan, executes the saved task, and independently
  verifies the TODO CLI built from the exact short Japanese prompt.
- User-visible behavior: The short request proceeds through planning and
  implementation without stopping at an unexecuted narration, and the produced
  Dart CLI satisfies the sourced `todo_app.md` behavior contract.
- Non-goals: Changing production orchestration policy, adding TODO-specific
  logic to `ChatNotifier`, exposing the private canary verifier to the model, or
  replacing the focused Coding Mode fixture canaries.

## Context

- Affected files or components: Plan Mode scenario fixtures, Live scenario
  runtime settings, harness command approval, scenario task-drift reporting,
  shared TODO behavior verification, and a focused Live runner.
- Related docs: `docs/coding_mvp_fixtures/todo_app.md`,
  `docs/evidence_driven_execution_orchestrator_plan.md`, and
  `docs/japanese_structured_execution_deferral_recovery_codex_task.md`.
- Reference implementation or pattern: `live_ping_cli_completion` in the Plan
  Mode integration suite and the independent verifier used by the Coding Mode
  TODO fixture canary.
- Known failure: Coding session
  `1972360e-8bac-4904-8911-1ea3077b2f98` had an approved implementation
  workflow and an executable snapshot, but the first execution request returned
  a Japanese plan with no tool call and exited with
  `unexecuted_command_action_notice`.

## Implementation Notes

- Preferred approach:
  1. Extract the existing TODO behavioral verifier into reusable canary support
     without changing its diagnostics or acceptance behavior.
  2. Add generic scenario seed-file support that records the initial bytes,
     verifies immutable inputs after execution, and excludes unchanged seed
     files from generated-file task-drift accounting.
  3. Make scenario language, temperature, and max-token settings explicit so
     the Japanese canary matches the production request profile.
  4. Generalize target-bound CLI help validation from Python to Dart while
     retaining workspace containment and exact saved-command checks.
  5. Run the independent verifier after Plan execution; do not intercept or
     replace the production tool catalog.
- Constraints: Keep all product behavior unchanged. Seed and verifier support
  must remain generic or test-only. Preserve the exact short Japanese prompt
  through an ASCII-only Unicode escape constant in the canary source.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

- Search terms: `live_ping_cli_completion`, `FakePlanModeMcpToolService`,
  `isSafePlanModeHarnessLocalCommand`, `collectPlanModeScenarioChangedFiles`,
  `_TodoToolService`, and `_verifyTodoAppIn`.
- Files or modules inspected: Plan Mode integration app setup, prompt
  submission, live harness execution, task-drift reporting, Live scenario
  configuration, and the Coding Mode TODO fixture canary.
- Follow-up tasks found: Additional production-path MVP fixtures should reuse
  the same seed and post-validation contracts after the TODO scenario proves
  stable; they are outside this slice.

## Acceptance Criteria

- Required behavior:
  - The selected scratch project contains an immutable root-level
    `todo_app.md` copied from the canonical fixture.
  - The Live request uses the exact short Japanese prompt and Japanese response
    language.
  - The test traverses Plan generation, approval, saved-task execution, and
    execution completion through the existing `ChatPage` integration harness.
  - The model receives the normal Plan Mode built-in tool catalog rather than
    the six-tool Coding Mode fixture replacement.
  - A reusable independent verifier confirms add, list, done, delete,
    persistence, help, empty-state, and unknown-id failure behavior.
  - The canonical specification file is unchanged after the run.
- Edge cases: A generated Dart CLI may use any single resolvable Dart
  entrypoint accepted by the existing adaptive entrypoint policy.
- Failure paths: Missing or ambiguous entrypoints, modified seed files,
  rejected saved validation commands, independent verifier diagnostics,
  `unexecuted_command_action_notice`, and post-success mutations fail the
  scenario with report artifacts.
- Localization and platform expectations: Run with Japanese language settings
  on macOS while keeping all test diagnostics and repository text in English.

## Verification

```bash
tool/codex_verify.sh --test test/integration_support/plan_mode_live_harness_execution_test.dart
tool/codex_verify.sh --test test/integration_support/plan_mode_task_drift_test.dart
tool/codex_verify.sh --test test/integration/plan_mode_scenario_spec_test.dart
tool/codex_verify.sh
```

After deterministic verification, run the new scenario once against the
configured local model. Run three consecutive repetitions only after the first
production-path run proves the wiring and report contract.

## Handoff Notes

- Summary: Implemented the production-path TODO Live canary and the generic
  orchestration hardening exposed by its diagnostic runs. The exact short
  Japanese request now reaches the real Plan Mode surface, approves a sourced
  workflow, repairs validation feedback, completes every saved task, and passes
  the independent TODO behavior verifier.
- Live validation:
  - Three consecutive production-path runs produced two passes and one
    inference stall: `plan_mode_todo_app_live_canary_1784084950` and
    `plan_mode_todo_app_live_canary_1784085389` passed, while
    `plan_mode_todo_app_live_canary_1784085778` exceeded the original
    90-second per-request stall budget after a successful local command.
    Successful requests in the same sample reached 76.8 and 64.4 seconds, so
    the scenario now uses a 150-second inference stall budget while retaining
    its 10-minute workflow timeout.
  - `plan_mode_todo_app_live_canary_1784086368` completed the workflow but
    exposed a verifier false negative for the standalone `[x]` completion
    marker. The verifier now accepts standalone `x` markers without confusing
    task text such as `fix x coordinate` for completion.
  - `plan_mode_todo_app_live_canary_1784086941` passed independent
    post-validation, but a redundant edit mismatch forced an unnecessary
    recovery turn even after the exact saved validation passed. Completion now
    compares mutation and validation order: a later saved validation recovers
    earlier file mutation failures, while failures after validation remain
    blocking.
  - `plan_mode_todo_app_live_canary_1784087686` passed against
    `qwen3.6-27b-vision` after the generation-aware completion fix. Its second
    task contained two edit mismatches before the successful saved validation
    and completed immediately with `hasFailure=false`. The run also exposed a
    rejected `cd <scenario-root> && <saved-validation>` wrapper; the harness
    now accepts only an exact scenario-root prefix and continues to reject
    child, external, and lexically escaped directory changes.
  - `plan_mode_todo_app_live_canary_1784117521` completed all three saved tasks
    and passed independent TODO behavior validation. Its wrapper then reported
    `unexpectedChangedFiles` only because the valid runtime artifact
    `todo_state.json` was absent from the scenario drift exclusions. The
    production-path scenario now treats that state file like the other known
    TODO persistence files while continuing to block unexpected source files.
  - `plan_mode_todo_app_live_canary_1784118227` passed after the runtime-state
    exclusion fix. The suite reported one passed scenario, zero failed
    scenarios, zero task-drift detections, and a ready report-quality summary
    with zero blockers.
  - `plan_mode_todo_app_live_canary_1784082510` passed against
    `qwen3.6-27b-vision` at `http://192.168.100.241:1234/v1`. The completion
    diagnostic recorded one successful validation command, no failed
    validation commands, no remaining failure, and `shouldMarkCompleted=true`.
  - `plan_mode_todo_app_live_canary_1784080504` exposed persistent setup
    failures after later matching validation; recovered setup failures now
    yield to the saved validation result.
  - `plan_mode_todo_app_live_canary_1784081140` exposed a synthetic
    `unexecuted_file_save` caused only by the stale original request; file
    mutation claims now require an explicit claim in the current answer.
  - `plan_mode_todo_app_live_canary_1784081950` stopped after a local-model
    request exceeded the 90-second harness timeout. The next run passed without
    a product change specific to that timeout.
- Tests run:
  - `tool/codex_verify.sh` passed analysis, generated-file checks, and all
    3,219 tests after the final harness changes.
  - `tool/codex_verify.sh --test test/features/chat/domain/services/conversation_plan_execution_guardrails_test.dart`
    passed all 57 focused tests.
  - `tool/codex_verify.sh --test test/integration_support/plan_mode_live_harness_execution_test.dart`
    passed all 24 focused tests.
  - `tool/codex_verify.sh --test test/tool/todo_app_behavior_verifier_test.dart`
    passed all 4 focused tests.
  - `tool/codex_verify.sh --test test/integration/plan_mode_scenario_spec_test.dart`
    passed all 18 focused tests.
  - `fvm flutter test test/features/chat/presentation/providers/chat_notifier_test.dart test/quality/file_size_ratchet_test.dart`
    passed all 307 tests after extracting focused part files.
  - Focused completion guardrail, final-answer claim, short-prompt contract,
    Goal Auto-Continue, shell guardrail, harness, and TODO verifier suites
    passed during implementation.
- Coverage or low-coverage notes: The canary covers the real planning and saved
  workflow execution path plus independent CLI behavior. It does not replace
  the deterministic focused canaries or measure model quality across repeated
  samples.
- Risks or follow-ups: Local inference latency can exceed the harness timeout,
  so repeated canary runs should distinguish transport or inference stalls from
  deterministic orchestration failures. Additional MVP fixtures can reuse the
  seed-file and post-validation contracts in a separate slice.
