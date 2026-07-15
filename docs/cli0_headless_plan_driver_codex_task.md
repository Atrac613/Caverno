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
- Failure paths: Unknown runner modes fail before Flutter starts, and endpoint
  preflight retains its existing exit behavior.
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

- Summary: Pending.
- Tests run: Pending.
- Coverage or low-coverage notes: Pending.
- Risks or follow-ups: Pending.
