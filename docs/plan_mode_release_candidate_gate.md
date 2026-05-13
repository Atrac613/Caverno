# Plan Mode Release Candidate Gate

Use this gate for the final Plan Mode release candidate sign-off. It combines
the deterministic smoke suite, the PM5 live gate, selected canaries,
compatibility notes, and manual UX review into one repeatable reviewer flow.

## Entry Conditions

- PM7 release readiness rules are current in
  [`plan_mode_release_readiness_checklist.md`](plan_mode_release_readiness_checklist.md).
- Scenario tiers and promotion rules are current in
  [`plan_mode_scenario_coverage.md`](plan_mode_scenario_coverage.md).
- Endpoint and model boundaries are current in
  [`plan_mode_model_endpoint_compatibility.md`](plan_mode_model_endpoint_compatibility.md).
- The reviewer has a reachable OpenAI-compatible endpoint and records the
  `CAVERNO_LLM_BASE_URL`, `CAVERNO_LLM_API_KEY`, and `CAVERNO_LLM_MODEL`
  values used for the live checks.

## Ordered Release Candidate Flow

Run the flow in this order. Do not skip directly to a later live check after an
earlier blocker.

1. Review compatibility boundaries.

   Confirm that the target endpoint and model satisfy
   `plan_mode_model_endpoint_compatibility.md`. If the endpoint does not expose
   `/models`, set `CAVERNO_PLAN_MODE_PREFLIGHT=0` intentionally and record why.

2. Run deterministic smoke.

   ```bash
   CAVERNO_PLAN_MODE_TAGS=smoke \
   flutter test integration_test/plan_mode_scenario_test.dart -d macos -r compact
   ```

3. Run static analysis.

   ```bash
   flutter analyze
   ```

4. Run the PM5 live gate.

   ```bash
   CAVERNO_LLM_BASE_URL=... \
   CAVERNO_LLM_API_KEY=... \
   CAVERNO_LLM_MODEL=... \
   CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1 \
   tool/run_plan_mode_pm5_live_gate.sh
   ```

5. Run selected canaries.

   Choose canaries from `plan_mode_scenario_coverage.md` according to the
   release risk under review. The default release candidate canary is:

   ```bash
   CAVERNO_LLM_BASE_URL=... \
   CAVERNO_LLM_API_KEY=... \
   CAVERNO_LLM_MODEL=... \
   CAVERNO_PLAN_MODE_SCENARIOS=live_readme_first_canary \
   CAVERNO_PLAN_MODE_FAIL_ON_WARNINGS=1 \
   tool/run_plan_mode_live_test.sh
   ```

   For a saved-validation convergence release check, use:

   ```bash
   CAVERNO_LLM_BASE_URL=... \
   CAVERNO_LLM_API_KEY=... \
   CAVERNO_LLM_MODEL=... \
   tool/run_plan_mode_convergence_full_pass.sh
   ```

6. Complete manual UX review.

   Exercise a Plan Mode request from the app UI and record review notes for:

   - plan proposal and approval clarity
   - saved task progress visibility
   - blocked, recovery, and retry behavior
   - final completion state and conversation continuity

7. Record the release candidate decision.

   Use the template below and attach every artifact path used to make the
   decision.

## Required Artifact Bundle

The release candidate record must name these artifacts:

- deterministic JSON report:
  `build/integration_test_reports/plan_mode_suite_macos_report.json`
- deterministic Markdown report:
  `build/integration_test_reports/plan_mode_suite_macos_report.md`
- deterministic JUnit report:
  `build/integration_test_reports/plan_mode_suite_macos_report.xml`
- live JSON report:
  `build/integration_test_reports/plan_mode_live_suite_macos_report.json`
- live Markdown report:
  `build/integration_test_reports/plan_mode_live_suite_macos_report.md`
- live JUnit report:
  `build/integration_test_reports/plan_mode_live_suite_macos_report.xml`
- PM5 ping canary JSON summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_<timestamp>/canary_summary.json`
- PM5 ping canary Markdown summary:
  `build/integration_test_reports/plan_mode_ping_cli_canary_<timestamp>/canary_summary.md`
- selected canary reports printed by `tool/run_plan_mode_live_test.sh` or
  `tool/run_plan_mode_convergence_full_pass.sh`
- the compatibility notes reviewed before live classification
- the manual UX review notes

JSON reports are the source of truth. Markdown reports and manual notes are the
review surface.

## Decision Owners

- The release reviewer owns the final `pass`, `warning`, `blocked`, or
  `blocked: environment` decision.
- The engineering owner owns app-side blockers, unexplained warnings, report
  quality blockers, and follow-up milestones.
- The endpoint owner owns endpoint availability, model availability, API key
  validity, and compatibility exceptions.

## Exception Rules

An exception must include:

- the failed signal
- why it does not block this release candidate
- the artifact path that supports the decision
- the follow-up milestone or issue that will remove the exception

Do not use an exception to bypass analyzer failures, missing release artifacts,
unknown approval paths, or unexplained task drift.

## Release Candidate Sign-Off

```markdown
## Plan Mode Release Candidate Sign-Off

- Decision: pass | warning | blocked | blocked: environment
- Reviewer:
- Date:
- Endpoint:
- Model:
- Deterministic report:
- Analyze result:
- PM5 live report:
- Ping canary summary:
- Selected canaries:
- Compatibility notes reviewed:
- Manual UX review:
  - Plan approval:
  - Task progress:
  - Blocked or recovery behavior:
  - Completion state:
- Exceptions:
- Follow-up:
```

## Repeatability Check

Before sign-off, confirm that a reviewer who did not perform the stabilization
work can repeat the gate using only this document plus the linked readiness,
coverage, and compatibility documents.
