# Coding Verification Feedback Plan (Test/Build)

Status: PR-A is implemented in commit `4f4ddbd` (`feat: Add coding verification
feedback service`). PR-B completion-claim integration is implemented across
`5eab073`, `efcdbed`, `c96c4cf`, and `83f0dee`. PR-D has the default-on
settings entity, Tools settings opt-out UI, and approved-task validation progress
recording in `5880ffd`, `58d97d1`, and `a3f0b4d`. PR-C explicit `run_tests`
tool support is implemented in the current branch. Advanced verification policy
settings for trigger policy, timeout, and failure capping are implemented in the
current branch. PR-E live canary, release gate, release-gate documentation, and
reference-report enforcement are implemented in the current branch. Remaining
follow-up is running and recording live evidence for the configured model before
release promotion. This is the direction "B" follow-up to the analyzer
diagnostic feedback loop shipped in commit
`0d05739` (`feat: Add diagnostic feedback release gate`).

## 1. Why

The analyzer feedback loop (`CodingDiagnosticFeedbackService`) closes the
*static* gap: after Dart edits in Coding Mode it runs `dart/flutter analyze`
and re-injects diagnostics so the model fixes compile/lint errors before
claiming completion.

It does not close the *behavioral* gap. Code can analyze cleanly and still be
wrong. The next rung on the same ladder is harness-initiated verification:
proactively run the relevant tests after meaningful edits, and especially
before the model is allowed to claim the task is done, then feed failures back.

This mirrors the upstream `tmp/cc` philosophy (the TaskUpdate prompt explicitly
forbids marking work complete while tests fail).

## 2. Goal and non-goals

Goal:

- After meaningful Dart edits in Coding Mode (non-planning), and at the
  completion-claim boundary, run a scoped test pass and re-inject failures as a
  structured tool result so the model repairs before finishing.

Non-goals:

- Not a CI replacement and not coverage enforcement.
- Not running the full suite after every file mutation.
- Not behavioral testing of non-Dart files in this phase.

## 3. Relationship to existing components

| Existing | Role | This plan |
|---|---|---|
| `CodingDiagnosticFeedbackService` | static analyzer feedback | template for the new service (service + injection + canary + gate) |
| `ConversationValidationToolResultInference` | infers pass/fail from incidental `*_execute_command` results | verification becomes a *first-class, harness-initiated* validation event mapped onto the same `ConversationExecutionValidationStatus` vocabulary |
| chat_notifier tool loop (`_buildCodingDiagnosticFeedbackToolResult`, completion-claim detection near `chat_notifier.dart:6782`) | post-batch analyzer hook + "complete" detection | add a verification hook gated by trigger policy, fired at the completion boundary |
| canary + release-gate tooling (`tool/canaries/...`, `tool/coding_diagnostic_feedback_release_gate.dart`) | repeatable live evidence | mirror for verification feedback |

Key principle: do not invent a second "did it pass" notion. Reuse
`ConversationExecutionValidationStatus` so plan-mode execution progress and the
verification loop stay coherent.

## 4. The central design problem: trigger policy

Tests are expensive (seconds to minutes) where analyze is cheap. The trigger
policy is the make-or-break decision.

Rules:

- Do NOT run after every file mutation (unlike the analyzer loop).
- Fire at most once per turn, debounced by a verification signature
  (changed-files set + resolved targets hash), and never within N seconds of a
  previous run.
- Triggers:
  1. Completion-claim (primary, default): when the drafted final answer signals
     done and edits occurred this session and verification has not yet passed
     for the current signature, run verification before accepting the answer.
     Reuse the existing completion detection (`normalized.contains('complete')`
     / `hasTextResponse` boundary).
  2. Explicit model request: `run_tests` lets the model call scoped Dart or
     Flutter validation mid-task, analogous to how `LSPTool` is explicit.
  3. Quiet-period (deferred): after an edit batch with no further planned tool
     calls.

Scope selection (cost control):

- Map each changed `lib/**/foo.dart` to its nearest test target
  (`test/**/foo_test.dart`) when it exists.
- If no direct target, fall back to the changed file's package `test/` dir.
- If the package has no tests, skip the test pass (analyzer already covers
  "does it compile"); record `no_test_target` rather than a false pass.
- Per-run timeout (default 90s), max failing tests, max stack chars.

## 5. Service: `CodingVerificationFeedbackService`

Mirror `CodingDiagnosticFeedbackService` structure and defensiveness.

- Injectable `CodingVerificationCommandRunner` typedef (default `Process.start`)
  for deterministic unit tests.
- `buildVerificationToolResult({ projectRoot, changedPaths, trigger, now })`:
  - desktop-only guard (`Platform.isMacOS || isLinux || isWindows`).
  - resolve nearest package root(s) and map changed files to test targets.
  - build a fvm-aware command candidate list (reuse the fvm-metadata detection
    already in the diagnostic service): `fvm flutter test --machine <targets>`,
    `flutter test --machine <targets>`, then `fvm dart test --reporter=json`,
    `dart test --reporter=json` fallbacks.
  - parse machine output (newline-delimited JSON: `testStart` / `testDone` /
    `error` / `print` events). Collect failures: test name, file, line,
    message, first stack frame. (Confirm exact event schema during PR-A.)
  - return a structured payload `caverno_dart_test_feedback`:
    `{ schema, instruction: "Fix failing tests before claiming the coding task
    is complete.", project_root, targets, command, counts: { passed, failed,
    skipped }, failing_tests: [...capped], truncated_count? }`.
  - return `null` when every target passes (positive path). The injection layer
    still emits a single positive signal so the model does not re-run tests.
- Shared refactor (small, recommended): extract `DartPackageLocator` (nearest
  package root) and the fvm command-discovery helper so the diagnostic and
  verification services do not duplicate that logic.

## 6. chat_notifier integration

- Add `codingVerificationFeedbackServiceProvider` (mirror the diagnostic one).
- Add `_buildCodingVerificationFeedbackToolResult(...)` mirroring
  `_buildCodingDiagnosticFeedbackToolResult`, reusing `_changedFileMutationPaths`
  and the gating (coding mode, non-planning, project root present).
- Difference: fire at the completion-claim boundary, not every batch. If
  verification fails, inject the result and continue the tool loop instead of
  accepting the final answer.
- State: `lastVerificationSignature` for debounce; per-turn "ran" flag.
- Convergence guard: if the same failing tests persist across K injections, stop
  re-injecting and surface "could not auto-resolve N failing tests" once, so the
  capped tool loop does not spin on an unfixable failure.

## 7. Validation-status coherence

Map the verification outcome onto `ConversationExecutionValidationStatus`
(passed / failed / inconclusive) and record it as a harness-initiated
validation event. This makes plan-mode execution progress reflect real,
proactive verification rather than only incidental command inference.

Current state:

- Implemented for completion-claim verification snapshots when an approved
  coding plan exposes a validation-capable execution task.
- Failed snapshots record a failed validation event and block the focused task;
  passed snapshots record a passed validation event and complete the task.
- Threads without saved execution tasks still skip progress recording, which is
  intentional until the explicit request/tool path has task-scoping semantics.

## 8. Settings and safety

- Implemented: `AppSettings.enableCodingVerificationFeedback` (default on,
  conservative trigger) with a Tools settings opt-out.
- Implemented: `codingVerificationTriggerPolicy` enum:
  `onCompletionClaim` (default) / `onRequestOnly` / `off`.
- Implemented: `codingVerificationTimeoutSeconds`,
  `codingVerificationMaxFailures`.
- Safety: tests execute arbitrary project code. Treat like the local shell /
  high-risk tools — require existing coding approval (full coding access),
  restrict to the project root, and document that verification runs project
  code. Implemented for the explicit `run_tests` path by translating it through
  the existing local command approval flow and rejecting paths outside the
  selected coding project. Graceful skip when the toolchain is absent at runtime
  remains the same posture as the analyzer loop.

## 9. Testing and release gate (mirror the diagnostic gate)

- Unit (`test/.../coding_verification_feedback_service_test.dart`): passing
  suite, single failing test, compile error inside a test, missing test target,
  timeout, fvm fallback, nested package, payload capping/dedupe. Fixtures from
  real `flutter test --machine` / `dart test --reporter=json` output.
- Notifier tests: completion-claim-only trigger, debounce by signature,
  convergence guard, gating, positive-path no-injection, continue-loop on
  failure.
- Implemented: Live canary
  `tool/canaries/coding_verification_feedback_live_canary_test.dart` +
  `tool/run_coding_verification_feedback_live_canary.sh`. Scenario: the harness
  scripts a broken edit and premature completion claim, the model must observe
  `dart_test_feedback`, repair, and re-verify green. Root + nested package,
  repeats >= 3 for release evidence.
- Implemented: Release gate
  `tool/coding_verification_feedback_release_gate.dart` +
  `tool/run_coding_verification_feedback_release_gate.sh`, mirroring the
  diagnostic gate's required-evidence shape (result `passed`; non-zero
  verification feedback observed; completion-claim failed test feedback; both
  root and nested package; all Live LLM recovery signals zero). Wired into
  `tool/live_llm_canary_reference_report.dart` as gated evidence.
- Implemented: `docs/coding_verification_feedback_release_gate.md` as a sibling
  to the analyzer one.

## 10. Rollout (atomic PRs)

- PR-A: `CodingVerificationFeedbackService` + parser + unit tests. No chat
  wiring. Includes shared Dart package/tooling extraction. Implemented in
  `4f4ddbd`.
- PR-B: chat_notifier completion-claim integration + trigger policy + debounce +
  convergence guard + notifier tests. Flag default-on for Coding Mode.
  Implemented across `5eab073`, `efcdbed`, `c96c4cf`, and `83f0dee`.
- PR-C: explicit `run_tests` tool + approval wiring. Implemented in the current
  branch.
- PR-D: settings entity/UI + `ConversationExecutionValidationStatus` coherence.
  Basic default-on setting, Tools settings opt-out, and approved-task validation
  progress recording are implemented. Advanced trigger/timeout/failure-limit
  controls are implemented in the current branch.
- PR-E: live canary + release gate + reference report enforcement + docs.
  Implemented in the current branch.

## 11. Risks

- Latency: conservative trigger (completion-claim only by default), scoped
  targets, timeout, debounce.
- Flaky/slow suites: on timeout treat as inconclusive (warning, non-blocking),
  never a hard fail that traps the loop.
- Toolchain absence at runtime: desktop-only + command discovery + graceful
  skip, same as the analyzer loop.
- Destructive tests / side effects: gate behind coding approval, restrict to
  project root, document clearly.
- Infinite repair loops: convergence guard + the existing capped tool-loop
  iterations.
- Duplication with the diagnostic service: mitigated by the shared
  `DartPackageLocator` / fvm-discovery extraction in PR-A.

## 12. Verification commands (for the implementer)

```bash
dart run build_runner build --delete-conflicting-outputs   # after entity changes
flutter test test/features/chat/domain/services/coding_verification_feedback_service_test.dart
flutter analyze
git diff --check
```
