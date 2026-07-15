# CLI0 Headless Plan Driver Baseline

## Task

- Goal: Establish the first no-window Plan Mode execution baseline for CLI0.
- User-visible behavior: A developer can run the existing TODO Plan Mode
  scenario from a shell without selecting macOS or foregrounding Caverno.app.
- Non-goals: Shipping the public `caverno` executable, extracting the complete
  frontend-neutral runtime, or replacing the macOS application-path gate.

## Context

- Affected files or components: Plan Mode scenario registration, Live runner
  scripts, CLI contract documentation, and focused runner tests.
- Related docs: `docs/roadmap.md`, `docs/caverno_cli_terminal_contract.md`, and
  `docs/production_path_todo_live_canary_codex_task.md`.
- Reference implementation or pattern: The Coding Live canary runs a
  `ProviderContainer` under `flutter test`, while the Plan Mode application
  canary registers the shared scenario suite under `integration_test`.
- Known failure: Invoking the current Plan Mode integration target without
  `-d macos` still performs device discovery and refuses to run when multiple
  devices are available.

## Implementation Notes

- Preferred approach: Expose reusable Plan Mode suite registration and add a
  test-runner entrypoint outside `integration_test`. Route the Live runner's
  explicit `headless` device mode to that entrypoint without a `-d` argument.
- Constraints: Keep the scenario contract, exact prompt, approval fallback,
  post-validator, session logs, and report vocabulary shared with the macOS
  lane. Do not present the test-runner entrypoint as the final product CLI.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

- Search terms: `CAVERNO_PLAN_MODE_DEVICE`, `run_plan_mode_live_test.sh`,
  `IntegrationTestWidgetsFlutterBinding`, `ProviderContainer`, and
  `live_todo_app_plan_completion`.
- Files or modules inspected: Plan Mode scenario registration and runner
  config, production-path TODO wrapper, Coding TODO Live canary composition,
  and the CLI roadmap tests.
- Follow-up tasks found: Replace the transitional widget-test composition with
  the frontend-neutral runtime facade in CLI1.

## Acceptance Criteria

- Required behavior: `CAVERNO_PLAN_MODE_DEVICE=headless` runs the selected Plan
  Mode scenario without passing a desktop device to Flutter.
- Edge cases: Existing macOS and explicit device selection remain unchanged.
- Failure paths: Endpoint preflight retains its existing exit behavior. The
  reserved `headless` value is the only device value routed away from Flutter
  device selection; other explicit values retain Flutter's device validation.
- Accessibility, localization, or platform expectations: The headless lane
  preserves the scenario language and exact prompt but has no UI assertions or
  screenshots of its own.

## Verification

```bash
tool/codex_verify.sh --test test/tool/run_plan_mode_live_test_test.dart
CAVERNO_PLAN_MODE_SCENARIOS=host_health_scaffold \
  CAVERNO_PLAN_MODE_DEVICE=headless \
  fvm flutter test tool/canaries/plan_mode_headless_scenario_canary_test.dart
```

After deterministic verification, run the TODO Live wrapper once with the
configured local model and inspect the suite report and session log.

## Handoff Notes

- Summary: The shared Plan Mode suite now has a no-window test-runner
  entrypoint, local Hive and SharedPreferences adapters, direct prompt
  submission, headless plan approval, and a dedicated TODO wrapper. Each Live
  run writes `headless_canary_summary.json` with duration, tool-loop, recovery,
  approval-path, drift, quality, and session-log metrics.
- Tests run: CLI contract docs passed 6 tests; runner/config/summary coverage
  passed 14 focused tests; `tool/codex_verify.sh` passed generated-file checks,
  project analysis, and the focused runner tests; deterministic
  `host_health_scaffold` passed without selecting a desktop device. Live run
  `plan_mode_todo_app_headless_live_canary_1784121906` passed 1/1 scenarios and
  its independent TODO post-validator against `qwen3.6-27b-vision`.
- Coverage or low-coverage notes: The Live summary recorded 384288 ms, eight
  tool-loop iterations, nine completed tool calls, two successful saved
  validations, zero tool failures, zero recoveries, one explicit harness plan
  approval path, zero screenshots, zero app-open markers, zero task drift, and
  zero report-quality blockers.
- Risks or follow-ups: This CLI0 lane is intentionally transitional: it runs
  the shared widget scenario suite under `flutter test`, not a released
  `caverno` executable or the CLI1 frontend-neutral runtime. Flutter prints an
  integration-test plugin warning because the wrapper lives outside
  `integration_test`; the scenario and quality reports remain green. Complete
  the three-run headless comparison and one macOS comparison before extracting
  the runtime facade.
