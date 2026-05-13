# Plan Mode MVP Handoff

This handoff is the compact review surface for Plan Mode MVP readiness. Use it
with the deeper stabilization notes in
[`plan_mode_ping_cli_stabilization_playbook.md`](plan_mode_ping_cli_stabilization_playbook.md).
For release decisions, use
[`plan_mode_release_readiness_checklist.md`](plan_mode_release_readiness_checklist.md).
For final release candidate sign-off, use
[`plan_mode_release_candidate_gate.md`](plan_mode_release_candidate_gate.md).
For model and endpoint boundaries, use
[`plan_mode_model_endpoint_compatibility.md`](plan_mode_model_endpoint_compatibility.md).

## Status

- Handoff status: ready after PM5 live gate validation
- Deterministic status: smoke scenarios are covered by the macOS integration
  suite and report-quality checks
- Live status: PM5 gate passed with `3/3` smoke scenarios and `1/1` ping CLI
  canary run
- Latest live evidence:
  `build/integration_test_reports/plan_mode_ping_cli_canary_1778555057/canary_summary.json`
- Warnings: `0` unexpected warnings in the latest PM5 gate evidence
- Report quality: `0` canary report quality blockers in the latest PM5 gate
  evidence
- Task drift: no ping canary task drift detected in the latest PM5 gate evidence

## Canonical Verification Path

Run this path for MVP or release handoff review:

```bash
CAVERNO_PLAN_MODE_TAGS=smoke \
flutter test integration_test/plan_mode_scenario_test.dart -d macos -r compact

flutter analyze

CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1 \
tool/run_plan_mode_pm5_live_gate.sh
```

The PM5 gate requires a reachable OpenAI-compatible endpoint. It runs the live
smoke suite first, then the ping CLI live canary. Use
`CAVERNO_PLAN_MODE_PM5_SKIP_SMOKE=1` only for ping-only rediscovery after a
fresh full gate or smoke pass.

Use the release readiness checklist to classify the result as `pass`,
`warning`, `blocked`, or `blocked: environment`.

## Expected Artifacts

- Deterministic suite:
  `build/integration_test_reports/plan_mode_suite_macos_report.json`
- Deterministic Markdown summary:
  `build/integration_test_reports/plan_mode_suite_macos_report.md`
- Deterministic JUnit summary:
  `build/integration_test_reports/plan_mode_suite_macos_report.xml`
- Live suite:
  `build/integration_test_reports/plan_mode_live_suite_macos_report.json`
- Live Markdown summary:
  `build/integration_test_reports/plan_mode_live_suite_macos_report.md`
- Live JUnit summary:
  `build/integration_test_reports/plan_mode_live_suite_macos_report.xml`
- Ping canary summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_<timestamp>/canary_summary.json`
- Ping canary Markdown summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_<timestamp>/canary_summary.md`

## Review Checklist

- Deterministic smoke scenarios pass.
- `outcomeSummary.passedCount` matches `outcomeSummary.scenarioCount`.
- `warningSummary.unexpectedWarnings` is `0`.
- `reportQualitySummary.blockerCount` is `0`.
- The PM5 ping canary has `failedCount: 0`.
- The PM5 ping canary reports no task drift.
- Any `liveHarnessApprovalFallback` path includes a reviewable saved plan and
  passing post-run artifact assertions.

## Known Blockers

There are no known Plan Mode MVP blockers in the latest PM5 evidence.

External prerequisites remain outside the app:

- The configured OpenAI-compatible endpoint must be reachable.
- The configured model must support the Plan Mode tool-calling flow reliably
  enough for live smoke and ping canary runs.
- macOS foreground timing can still route approval through
  `liveHarnessApprovalFallback`; this is acceptable only when the saved-plan
  and artifact assertions pass.

## Follow-Up Watchpoints

- Treat any unexpected warning as a fix target before widening MVP scope.
- Inspect ping canary task drift before reading raw logs.
- Keep `live_readme_first_canary` as a targeted canary, not part of the default
  smoke gate.
