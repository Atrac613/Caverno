# CLI0 Headless And App-Path Parity Gate

## Task

- Goal: Measure the transitional headless Plan Mode lane against the existing
  macOS application-path lane before starting CLI1 runtime extraction.
- User-visible behavior: A developer can run three consecutive headless TODO
  canaries and one macOS TODO canary with one command, then inspect a single
  machine-readable comparison report.
- Non-goals: Shipping the public `caverno` executable, changing the TODO
  scenario contract, or treating headless execution as UI coverage.

## Context

- Affected files or components: TODO Live canary wrappers, CLI0 report
  summarizers, focused runner tests, and the CLI roadmap.
- Related docs: `docs/caverno_cli_terminal_contract.md`,
  `docs/cli0_headless_plan_driver_codex_task.md`, and `docs/roadmap.md`.
- Reference implementation or pattern:
  `tool/run_plan_mode_todo_app_headless_live_canary.sh` and
  `tool/run_plan_mode_todo_app_live_canary.sh`.
- Known quirks, compatibility rules, or release gates: The headless lane uses a
  Flutter test-runner composition without selecting a desktop device. The
  macOS lane remains responsible for application bootstrap, proposal UI,
  approval rendering, and screenshot evidence.

## Implementation Notes

- Preferred approach: Keep both existing lane wrappers authoritative. Add a
  small orchestration script that provides isolated report roots and a Dart
  summarizer that reads the emitted JSON rather than parsing console output.
- Constraints: Use the same endpoint, model, scenario, exact prompt, fixture,
  post-validator, and strict report-quality policy for every run. Fail the gate
  if a run is missing, failed, drifted, blocked by report quality, or reports a
  different model or scenario.
- Generated files needed: None.
- Migration or data compatibility concerns: The comparison report is a new
  schema. Existing suite and per-run summary schemas remain readable.

## Similar-Pattern Search

- Search terms: `REPEAT_COUNT`, `plan_mode_live_suite_macos_report`,
  `headless_canary_summary`, and `reportQualitySummary`.
- Files or modules inspected: Existing Plan Mode convergence, PM5, TODO
  application-path, and TODO headless runners plus their focused tests.
- Follow-up tasks found: CLI1 should replace the transitional Flutter
  test-runner composition with a frontend-neutral runtime facade.

## Acceptance Criteria

- Required behavior: The gate runs exactly three headless TODO canaries by
  default, then one macOS TODO canary, and writes one comparison JSON file.
- Edge cases: A positive integer headless repeat override is supported for
  deterministic tests, while the report records the expected and observed
  run counts.
- Failure paths: Stop on the first failed lane. Reject missing reports,
  inconsistent scenarios or models, task drift, and report-quality blockers.
- Accessibility, localization, or platform expectations: The exact Japanese
  prompt remains owned by the shared scenario. UI-specific coverage is
  recorded only for the macOS lane.

## Verification

```bash
tool/codex_verify.sh \
  --test test/tool/plan_mode_cli0_comparison_summary_test.dart \
  --test test/tool/run_plan_mode_todo_app_cli0_comparison_test.dart
```

After deterministic verification, run the gate against the configured local
model with its default three headless runs and one macOS run.

## Handoff Notes

- Summary: Pending implementation and Live evidence.
- Tests run: Pending.
- Coverage or low-coverage notes: The deterministic tests will cover report
  aggregation and orchestration. The Live gate supplies behavioral evidence.
- Risks or follow-ups: A passing parity gate does not prove TTY behavior,
  signal handling, stable terminal exit codes, or a frontend-neutral runtime.
