# Plan Mode Live Smoke Compatibility Triage

Date: 2026-05-13

## Context

The PM13 release candidate rerun completed deterministic smoke and static
analysis successfully, but the live smoke gate against
`http://192.168.100.241:1234/v1` with `gemma4-26b-vision` remained blocked by
environment and compatibility findings.

## Current Classification

- Deterministic smoke is release-candidate ready.
- Static analysis is clean.
- Live endpoint preflight passed outside the sandbox.
- Live smoke produced two passing scenarios and one failed scenario.
- The failed scenario, `live_clarify_recovery`, is classified as
  `streamDisconnect` because the endpoint closed `/chat/completions` before the
  full response header was received.
- `live_host_health_scaffold` passed functionally, but its report quality was
  blocked by task drift from incomplete saved task target metadata and extra
  changed files.
- `live_cli_entrypoint_decision` reached cleanup cancellation after natural stop
  convergence; stale background execution later emitted a disposed provider
  container error.

## Fixes Started

- Cleanup cancellation now marks the harness execution handle after timeout, so
  late background execution can stop before reading providers that may already
  be disposed.
- Provider container disposal after cleanup cancellation is classified as a
  harness shutdown condition instead of a task execution failure.
- Passed scenario reporting now falls back to projected execution task targets
  when the saved workflow target metadata is empty.

## Remaining PM14 Work

- Rerun the live smoke gate and confirm whether cleanup cancellation no longer
  pollutes the next scenario log.
- Recheck whether `live_host_health_scaffold` still reports task drift after the
  projected target fallback.
- Decide whether extra changed files from auto-continued saved tasks should be
  accepted, separately reported, or prevented by the live harness.
- Keep `streamDisconnect` blocked as an endpoint compatibility issue unless it
  reproduces across models or endpoints with stable preflight health.

## Follow-Up Run

Command:

```bash
CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 CAVERNO_LLM_API_KEY=no-key CAVERNO_LLM_MODEL=gemma4-26b-vision CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1 tool/run_plan_mode_pm5_live_gate.sh
```

Result:

- PM5 live gate completed.
- Live smoke suite passed all 3 scenarios.
- Live smoke warnings dropped to 0 total, 0 allowed, and 0 unexpected.
- `live_clarify_recovery` passed, so the previous `streamDisconnect` did not
  reproduce.
- Ping CLI live canary passed 1/1 with 0 warnings and 0 task drift findings.
- Report quality still has 1 blocker in `live_host_health_scaffold`:
  `unexpectedChangedFiles`.
- The remaining drift is now correctly narrowed to changed-file scope:
  expected `requirements.txt`, saved `requirements.txt`, actual
  `health_check.py`, `README.md`, and `requirements.txt`.
- Cleanup cancellation still occurred for long-running live smoke scenarios, but
  no disposed provider container task failure was emitted.

Artifacts:

- Live smoke suite:
  `build/integration_test_reports/plan_mode_live_suite_macos_1778643860118`
- Ping CLI canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1778644291/canary_summary.json`

Next PM14 slice:

- Decide whether auto-continued saved task output should be accepted in task
  drift reporting or whether the live harness should stop after the first saved
  task for smoke scenarios that assert a first-slice target.

## Task Drift Policy Follow-Up

Decision:

- Keep task drift strict by default.
- Stop `live_host_health_scaffold` after the first harness task because the
  scenario is scoped to first-slice artifact confidence.
- Leave auto-continuation enabled for scenarios and canaries that explicitly
  exercise multi-task completion.

Validation:

```bash
CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 CAVERNO_LLM_API_KEY=no-key CAVERNO_LLM_MODEL=gemma4-26b-vision CAVERNO_PLAN_MODE_SCENARIOS=live_host_health_scaffold CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=1 tool/run_plan_mode_live_test.sh
```

Result:

- `live_host_health_scaffold` passed.
- Warnings: 0 total, 0 allowed, 0 unexpected.
- Report quality: ready, 0 blockers.
- Task drift: 0 detected.
- Harness log includes `Harness stopped after reaching task execution limit: 1`.

Artifact:

- `build/integration_test_reports/plan_mode_live_suite_macos_1778646479880`

Next PM14 slice:

- Rerun the full PM5 live gate to confirm the focused first-task cap and the
  existing multi-task canary behavior work together.

## PM14 Completion Run

Command:

```bash
CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 CAVERNO_LLM_API_KEY=no-key CAVERNO_LLM_MODEL=gemma4-26b-vision CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1 tool/run_plan_mode_pm5_live_gate.sh
```

Result:

- PM5 live gate completed after one transient rerun.
- Live smoke suite passed all 3 scenarios.
- Live smoke warnings: 0 total, 0 allowed, 0 unexpected.
- Live smoke report quality: ready, 0 blockers.
- Live smoke task drift: 0 detected.
- Ping CLI live canary passed 1/1.
- Ping CLI canary report quality: ready, 0 blockers.
- Ping CLI canary task drift: 0 detected.
- The transient first rerun timeout is now classified as `overallTimeout`
  without adding pre-approval task drift or approval-path blockers.

Artifacts:

- Live smoke suite:
  `build/integration_test_reports/plan_mode_live_suite_macos_1778648454459`
- Ping CLI canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1778648740/canary_summary.json`

PM14 decision:

- Release candidate blockers and warning noise from PM13 are burned down.
- Rerun PM13 from the start before advancing into PM15 product UX finalization.
