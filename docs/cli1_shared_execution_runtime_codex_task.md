# CLI1 Shared Application Execution Runtime

## Task

- Goal: Extract a frontend-neutral execution facade that both the Flutter GUI
  and the transitional headless Plan Mode lane instantiate for one-shot turns.
- User-visible behavior: Existing chat, coding, and Plan Mode behavior remains
  unchanged while terminal clients gain a typed runtime contract they can
  consume without importing Flutter UI or desktop plugin code.
- Non-goals: Shipping the public `caverno` executable, changing prompt or tool
  policy, introducing IPC, or duplicating the `ChatNotifier` state machine.

## Context

- Affected files or components: Chat turn startup/finalization, tool lifecycle
  reporting, approval and question publication, runtime provider composition,
  and the headless Plan Mode harness.
- Related docs: `docs/caverno_cli_terminal_contract.md`,
  `docs/cli0_headless_app_parity_codex_task.md`, and `docs/roadmap.md`.
- Reference implementation or pattern: `ChatNotifier` remains the production
  turn driver. `ToolExecutionLifecycleEvent` and the CLI0 comparison report
  provide the existing typed-event and shared-lane patterns.
- Known quirks, compatibility rules, or release gates: A normal chat stream may
  return from `sendMessage` before its terminal callback fires. Runtime
  completion must therefore follow the finalization path, not the method
  return. Hidden prompts and queued turns must retain their existing behavior.

## Implementation Notes

- Preferred approach: Add a pure Dart application-layer runtime with typed
  events, a monotonically sequenced event stream, explicit approval/question
  ports, and a one-shot turn handle. Add a Riverpod adapter that binds existing
  settings, repositories, LLM data source, tool service, logging, lifecycle,
  and `ChatNotifier` orchestration without moving policy into a second state
  machine.
- Constraints: Files imported by the pure runtime test must not import
  `dart:ui`, Flutter widgets, window management, notifications, or platform
  plugins. The same runtime provider must be read by the application and the
  headless harness. Non-interactive approval remains fail-closed.
- Generated files needed: None. Runtime values are immutable plain Dart
  classes so the public terminal contract does not depend on code generation.
- Migration or data compatibility concerns: None. Existing conversation,
  settings, approval, and session-log schemas remain authoritative.

## Similar-Pattern Search

- Search terms: `ProviderContainer`, `chatNotifierProvider`,
  `ToolExecutionLifecycleEvent`, `pendingAskUserQuestion`,
  `pendingLocalCommand`, `_finishStreaming`, and `_handleError`.
- Files or modules inspected: `lib/main.dart`, `ChatNotifier`, the Plan Mode
  application scenario builder, and the headless Plan Mode execution harness.
- Follow-up tasks found: CLI2 will add the terminal presenter, input parsing,
  signal handling, and stable process exit codes on top of this runtime.

## Acceptance Criteria

- Required behavior:
  - The runtime exposes typed events for run start, assistant text, tool
    lifecycle, approval requests, questions, workflow transitions, usage,
    successful completion, and failure.
  - Event sequence numbers are strictly increasing per runtime instance.
  - `ChatNotifier` emits production events through the shared runtime while
    preserving the visible Flutter result.
  - The GUI and headless Plan Mode compositions resolve the same runtime API.
  - The runtime composition names explicit settings, repository, LLM, tool,
    approval, logging, and lifecycle ports.
- Edge cases: Empty assistant chunks are ignored, only one terminal event is
  emitted per turn, queued turns receive distinct turn IDs, and hidden turns
  do not leak visible assistant content.
- Failure paths: Turn failures emit a typed failure event and complete the turn
  handle with the same failure. Closing the runtime closes its event stream and
  rejects new turns.
- Accessibility, localization, or platform expectations: Runtime event payloads
  are structured data. Presentation and localization stay in the frontend.

## Verification

```bash
(cd packages/caverno_execution_runtime && \
  fvm dart test test/caverno_execution_runtime_test.dart)
tool/codex_verify.sh \
  --no-codegen \
  --test test/features/chat/presentation/providers/chat_notifier_test.dart \
  --test test/integration_support/plan_mode_live_harness_execution_test.dart \
  --test test/integration_support/plan_mode_scenario_config_test.dart
```

After deterministic verification, rerun the CLI0 three-headless-plus-one-macOS
comparison to prove behavior parity through the shared composition.

## Handoff Notes

- Summary: Implemented `CavernoExecutionRuntime` as a pure Dart event runtime,
  added explicit frontend-neutral ports, and connected visible, hidden, direct
  Plan Mode, approval, question, usage, workflow, and terminal paths from
  `ChatNotifier` through the shared Riverpod composition. The headless scenario
  builder selects the same runtime API with a headless surface value.
- Tests run:
  - `tool/codex_verify.sh --no-codegen ...` passed Flutter analysis and 347
    runtime, ChatNotifier, harness, and scenario-configuration tests.
  - The deterministic no-window scenario passed at
    `build/integration_test_reports/cli1_deterministic_headless/plan_mode_suite_headless_report.json`.
  - Three consecutive live headless TODO runs passed under
    `build/integration_test_reports/cli1_live/plan_mode_todo_app_cli0_comparison_1784149029/headless/`.
  - The final production-path macOS TODO run passed with 81 complete tool
    lifecycle events, zero incomplete tools, and zero warnings at
    `build/integration_test_reports/cli1_macos_after_harness_fix/plan_mode_todo_app_live_canary_1784152249/plan_mode/plan_mode_live_suite_macos_report.json`.
- Coverage or low-coverage notes: Pure runtime tests cover every event type,
  strict ordering, hidden-content isolation, duplicate active turn IDs,
  failure, and closure. Flutter tests cover production adapter lifecycle,
  approval, question, and shared provider behavior.
- Live findings fixed: A zero-exit saved validation with failed output-guard
  feedback now retains repair tools, and exact saved validations may run
  `dart format --set-exit-if-changed` only when every affected Dart file is an
  active task target. Unsafe flags, escaping paths, unrelated Dart files, and
  links remain denied.
- Risks or follow-ups: A later full-comparison retry recorded a weak-model
  headless convergence failure while rewriting a generated package import; it
  did not expose a shared-runtime exception. CLI1 provides the runtime boundary,
  not the public terminal UX. CLI2 remains responsible for TTY rendering, JSON
  Lines output, SIGINT handling, and process exit codes.
