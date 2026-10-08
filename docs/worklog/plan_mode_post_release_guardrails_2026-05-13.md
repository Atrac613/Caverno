# Plan Mode Post-Release Guardrails - 2026-05-13

PM19 defines how Plan Mode is monitored after release and when a follow-up fix
should become a hotfix.

## Ownership

| Area | Owner | Responsibility |
|------|-------|----------------|
| Release health | Plan Mode release owner | Review scheduled gate results and decide pass, warning, blocked, or hotfix. |
| Compatibility triage | Plan Mode compatibility reviewer | Separate endpoint or model availability failures from app regressions. |
| User reports | Support reviewer | Collect the redacted support snapshot, visible product state, and latest report path. |
| Scenario coverage | Plan Mode test owner | Keep smoke, canary, and long-run classifications current. |

If a single person owns release review, they temporarily own all four areas and
record that in the release note or issue.

## Cadence

| Timing | Required check | Command or artifact |
|--------|----------------|---------------------|
| Before every Plan Mode change merges | Focused tests for touched surfaces and `fvm flutter analyze`. | Change-specific tests plus analyzer. |
| Weekly after release | Deterministic smoke and PM5 live gate against the supported endpoint/model. | `CAVERNO_PLAN_MODE_TAGS=smoke fvm flutter test integration_test/plan_mode_scenario_test.dart -d macos -r compact` and `tool/run_plan_mode_pm5_live_gate.sh`. |
| After endpoint or model changes | Product settings preflight and PM5 live gate. | Settings > General preflight plus PM5 gate report. |
| After a user-reported workflow failure | Support snapshot review, latest report review, and targeted reproduction. | `plan_mode_support_snapshot` JSON and latest deterministic or live report. |
| Before the next release candidate | Reuse the PM12 release candidate gate. | `docs/plan_mode_release_candidate_gate.md`. |

Ping-only rediscovery may be used after a fresh smoke pass, but it must not
replace weekly smoke or release-candidate evidence.

## Regression Checks

Keep these checks green unless an explicit release exception is recorded:

- deterministic smoke scenarios pass
- `fvm flutter analyze` reports no issues
- PM5 live smoke scenarios pass
- PM5 Ping CLI canary has no failed runs
- unexpected warnings remain `0`
- report quality blockers remain `0`
- task drift remains absent or explicitly allowed by scenario coverage rules
- approval paths remain known and prove a reviewable saved plan

Use `docs/plan_mode_release_readiness_checklist.md` as the decision matrix for
every scheduled run.

## Hotfix Rules

Open a hotfix when any of these are true and the failure is reproducible on the
supported endpoint/model:

- a deterministic smoke scenario fails on the release branch
- analyzer fails because of Plan Mode code
- PM5 live smoke fails with an app-side workflow, approval, task-state,
  recovery, or completion regression
- the support snapshot shows `ready`, but a user can no longer generate,
  approve, recover, or complete a Plan Mode workflow
- unexpected warnings, report quality blockers, or task drift reappear without
  a documented scenario-level allow pattern
- a support snapshot or export leaks an API key or other secret

Do not open a Plan Mode hotfix for:

- unreachable endpoint or missing `/models` preflight
- selected model missing from the endpoint
- API key/authentication mismatch outside the app
- a model that cannot produce parseable workflow/task output after bounded
  retries
- ping-only canary failure without a fresh smoke pass

Those cases are `blocked: environment` or compatibility follow-up unless the
app misreports the failure or exposes unsafe data.

## Reusing PM12 And PM13

Future release work should reuse the existing release process:

1. Run the PM12 release candidate gate from
   `docs/plan_mode_release_candidate_gate.md`.
2. Record execution evidence in a PM13-style sign-off document.
3. Attach the PM18 release package and PM19 guardrails to the review.
4. If a warning or blocker appears, open a focused follow-up milestone instead
   of rebuilding the release process.

## User Report Intake

Ask for these fields before classifying a report:

- redacted Plan Mode support snapshot from Settings > General
- latest deterministic, live, or canary report path when available
- endpoint preflight classification
- selected model identity
- visible product state at failure time
- whether the failure happened during planning, approval, execution, recovery,
  completion, or support snapshot creation

## Verification

- `fvm flutter test test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

## Decision

PM19 is complete. Plan Mode now has a post-release cadence, owner model,
regression checks, hotfix rules, and a reuse path for PM12/PM13 release work.
