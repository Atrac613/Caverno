# Plan Mode Release Readiness Checklist

Use this checklist before shipping Plan Mode changes. It turns the MVP handoff
into a release decision gate and keeps stabilization history separate from the
final product review.

For final release candidate sign-off, use
[`plan_mode_release_candidate_gate.md`](plan_mode_release_candidate_gate.md).
This checklist is one input to that ordered RC gate.

## Required Command Order

Run the checks in this order:

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

Do not replace the PM5 gate with a ping-only run for release review. A
ping-only run is useful for rediscovery after a fresh smoke pass, but it is not
enough for a release decision.

## External Prerequisites

These are not app-side blockers unless the app reports them incorrectly:

Use
[`plan_mode_model_endpoint_compatibility.md`](plan_mode_model_endpoint_compatibility.md)
for the full endpoint and model compatibility boundary.

- `CAVERNO_LLM_BASE_URL` points to a reachable OpenAI-compatible endpoint.
- `CAVERNO_LLM_API_KEY` matches the endpoint's expected authentication token.
- `CAVERNO_LLM_MODEL` names a model available from the endpoint.
- The endpoint exposes `/models`, or `CAVERNO_PLAN_MODE_PREFLIGHT=0` is set
  intentionally because the endpoint does not support that route.
- The macOS test host can launch Flutter integration tests and drive the live
  Plan Mode harness.

If any prerequisite is missing, record the release decision as
`blocked: environment` and do not count it as a Plan Mode workflow regression.

## Release Decision Matrix

| Signal | Pass | Warning | Blocker |
|--------|------|---------|---------|
| Deterministic smoke | All selected scenarios pass | Non-blocking artifact or allowed warning is explained | Any selected scenario fails |
| Static analysis | `flutter analyze` reports no issues | Not applicable | Any analyzer issue |
| Live smoke | PM5 smoke phase passes | Allowed warning has a documented recovery path | Any live smoke scenario fails |
| Ping CLI canary | `failedCount` is `0` | Allowed warning is expected and documented | Any failed canary run |
| Warnings | `warningSummary.unexpectedWarnings` is `0` | Allowed warnings are present and documented | Any unexpected warning |
| Report quality | `reportQualitySummary.blockerCount` is `0` | Informational report note only | Any report quality blocker |
| Task drift | No task drift detected | Soft artifact drift is explained by a canary note | Any unexplained task drift |
| Approval path | UI approval or `liveHarnessApprovalFallback` with a saved plan | Harness fallback used with valid saved-plan evidence | Unknown approval path or missing saved plan |

## Required Artifact Review

Review these artifacts before marking the release gate as passed:

- `build/integration_test_reports/plan_mode_suite_macos_report.json`
- `build/integration_test_reports/plan_mode_suite_macos_report.md`
- `build/integration_test_reports/plan_mode_live_suite_macos_report.json`
- `build/integration_test_reports/plan_mode_live_suite_macos_report.md`
- `build/integration_test_reports/plan_mode_ping_cli_canary_<timestamp>/canary_summary.json`
- `build/integration_test_reports/plan_mode_ping_cli_canary_<timestamp>/canary_summary.md`

The JSON files are the source of truth for release decisions. The Markdown
files are the reviewer-facing summaries.

## Pass Criteria

Mark the Plan Mode release gate as `pass` only when all of these are true:

- Deterministic smoke scenarios pass.
- Static analysis reports no issues.
- PM5 live smoke scenarios pass.
- PM5 ping CLI canary has `failedCount: 0`.
- `warningSummary.unexpectedWarnings` is `0`.
- `reportQualitySummary.blockerCount` is `0`.
- No unexplained task drift is recorded.
- Any `liveHarnessApprovalFallback` path has a reviewable saved plan and
  passing post-run artifact assertions.

## Warning Criteria

Mark the gate as `warning` only when the product behavior is still acceptable
and the warning is documented. Examples:

- A scenario records an allowed warning with a recovery marker.
- The live harness uses `liveHarnessApprovalFallback`, but saved-plan and
  artifact assertions pass.
- A canary records a known soft artifact note that does not affect release
  behavior.

Every warning needs a short release note entry explaining why it is not a
blocker.

## Blocker Criteria

Mark the gate as `blocked` when any of these occur:

- A deterministic smoke scenario fails.
- `flutter analyze` reports any issue.
- A PM5 live smoke scenario fails.
- The ping CLI canary records any failed run.
- Any unexpected warning is recorded.
- Any report quality blocker is recorded.
- Task drift is detected without a documented canary-level allow pattern.
- The live harness records an unknown approval path or cannot prove a saved
  plan was reviewable.

## Failure Triage Order

When the PM5 live gate fails, start with the artifact index printed by
`tool/run_plan_mode_pm5_live_gate.sh`. It lists the latest live suite report,
ping canary summary, run suite report, run log, release checklist, and
stabilization playbook.

Use this order:

1. Check endpoint/model prerequisites if no report artifacts were written.
2. Open the latest `canary_summary.md` for failed run rows and failure classes.
3. Open the matching `canary_summary.json` for warning, quality, and task drift
   fields.
4. Open the `run_*_suite_report.json` linked by the failed row.
5. Open `run_*_run.log` only after the structured report identifies the branch.
6. Use `plan_mode_ping_cli_stabilization_playbook.md` for the matching failure
   family and next repair step.

Classify endpoint or model availability failures as `blocked: environment`.
Classify workflow, warning, report quality, task drift, and approval-path
failures with the release decision matrix above.

## Exception Handling

Use exceptions sparingly. An exception must include:

- the failed signal
- the reason it does not block this release
- the artifact path that supports the decision
- the follow-up milestone or issue that will remove the exception

Do not use an exception to bypass analyzer failures, missing release artifacts,
or unknown approval paths.

## Release Record Template

```markdown
## Plan Mode Release Readiness

- Decision: pass | warning | blocked | blocked: environment
- Reviewer:
- Date:
- Deterministic report:
- Live report:
- Ping canary summary:
- Unexpected warnings:
- Report quality blockers:
- Task drift:
- Exceptions:
- Follow-up:
```
