# Caverno Roadmap

This roadmap is the cross-track index for Caverno implementation work. It keeps
milestone identifiers stable so planning notes, test reports, and release
handoffs can refer to the same unit of work over time.

## Milestone Conventions

- Use `PM<number>` for Plan Mode milestones.
- Keep `M<number>` for the existing macOS Computer Use milestones documented in
  `docs/macos_computer_use_helper_architecture.md`.
- Use `F<number>` for Foundation (refactoring, dependency currency, storage)
  milestones and `LL<number>` for Local LLM Agent milestones, both documented
  in `docs/local_llm_agent_roadmap.md`.
- Use one of these statuses: `done`, `current`, `next`, `blocked`, `later`.
- Every active milestone should record scope, acceptance criteria, verification
  evidence, and the next action.
- Prefer small follow-up commits that complete one milestone slice at a time.

## Active Focus

| Track | Milestone | Status | Goal | Next action |
|-------|-----------|--------|------|-------------|
| Plan Mode | PM3 | done | Finish scenario harness decomposition and keep deterministic smoke coverage stable. | Keep the extracted support modules covered while working on report quality. |
| Plan Mode | PM4 | done | Make deterministic Plan Mode reports easy to review and fail for actionable warnings. | Keep warning reasons and quality blockers aligned across suite report formats. |
| Plan Mode | PM5 | done | Stabilize live Plan Mode smoke runs against OpenAI-compatible endpoints. | Keep the PM5 live gate in the release checklist while preparing the MVP handoff. |
| Plan Mode | PM6 | done | Convert Plan Mode deterministic and live evidence into an MVP handoff. | Use the MVP handoff during release review and choose the next Plan Mode milestone before new implementation. |
| Plan Mode | PM7 | done | Turn the MVP handoff into a product release readiness gate. | Use the release checklist for Plan Mode release review. |
| Plan Mode | PM8 | done | Make live gate failures operationally easy to triage. | Use the PM5 gate artifact index and failure triage order during release review. |
| Plan Mode | PM9 | done | Polish product UX for saved plans, approval, execution progress, recovery, and completion. | Keep task state guidance visible while expanding scenario coverage. |
| Plan Mode | PM10 | done | Expand Plan Mode scenario coverage beyond the MVP smoke and ping canary gate. | Use the scenario coverage rules before promoting canaries into smoke. |
| Plan Mode | PM11 | done | Validate model and endpoint compatibility for Plan Mode product use. | Use compatibility notes before classifying live failures as app regressions. |
| Plan Mode | PM12 | done | Define the final release candidate gate. | Use the release candidate gate for final Plan Mode sign-off before opening a new productization track. |
| Plan Mode | PM13 | done | Execute the Plan Mode release candidate gate and record the sign-off decision. | Use the PM14 rerun warning sign-off to drive PM15 manual UX review. |
| Plan Mode | PM14 | done | Burn down release candidate blockers and warnings. | Keep the PM14 evidence attached to the PM13 rerun sign-off. |
| Plan Mode | PM15 | done | Finalize the Plan Mode product UX. | Use the PM15 UX sign-off while starting PM16 settings and compatibility guidance. |
| Plan Mode | PM16 | done | Productize settings and compatibility guidance. | Use the settings preflight copy while starting PM17 supportability. |
| Plan Mode | PM17 | done | Improve supportability for user and reviewer reports. | Use the support snapshot while preparing PM18 release packaging. |
| Plan Mode | PM18 | done | Prepare Plan Mode release packaging. | Use the release package while defining PM19 post-release guardrails. |
| Plan Mode | PM19 | done | Define post-release guardrails. | Use the guardrails for scheduled monitoring and open new PM milestones only when post-release evidence requires it. |
| Plan Mode | PM20 | done | Refresh the release candidate decision with final PM5 gate evidence. | Use the final sign-off as the current Plan Mode productization baseline. |
| Computer Use | M31R | done | Refresh the current Computer Use evidence baseline before element-grounded work. | Run `bash tool/run_macos_computer_use_release_readiness.sh --ci --refresh-safe-inputs`. |
| Computer Use | M52 | done | Ship element-grounded Computer Use through the product release rollout. | Use `bash tool/run_macos_computer_use_m52_product_release_rollout.sh` for final product release evidence. |
| Computer Use | M53 | done | Keep post-release Computer Use operations guarded after product rollout. | Use `bash tool/run_macos_computer_use_m53_post_release_guardrails.sh` for scheduled post-release evidence. |
| Computer Use | M54 | done | Decide whether post-release Computer Use rollout can expand safely. | Use `bash tool/run_macos_computer_use_m54_rollout_expansion_gate.sh` for rollout expansion evidence. |
| Computer Use | M55 | done | Review post-expansion Computer Use evidence and decide whether to continue, hold, pause, or roll back. | Use `bash tool/run_macos_computer_use_m55_post_expansion_monitoring_gate.sh` for post-expansion monitoring evidence. |
| Computer Use | M56 | done | Hand off the approved post-expansion rollout decision to the next user-operated rollout branch. | Use `bash tool/run_macos_computer_use_m56_rollout_decision_handoff_gate.sh` for rollout decision handoff evidence. |
| Remote Coding | RC0 | done | Ship the P0 LAN mobile control safety gate for existing desktop coding projects. | Use `dart run tool/remote_coding_p0_release_gate.dart` before P0 release review. |
| Remote Coding | RC1 | later | Harden Remote Coding for product use with reconnect resilience, support diagnostics, and multi-device evidence. | Keep light manual smoke as sufficient until P1 release evidence becomes a release priority. |
| Foundation | F1 | done | Add a CI-enforced line-count ratchet for oversized files so god-file growth reverses instead of compounding. | Lower budgets in the same PR whenever a refactor slice shrinks a budgeted file. |
| Foundation | F2 | done | Extract the tool-call loop from `ChatNotifier` behind a handler registry shared with routines and subagents. | Use the extracted dispatcher, policies, and routine batch executor as the baseline for F3, LL6, and LL7. |
| Local LLM | LL1 | done | Route secondary LLM calls (memory extraction, subagents, goal suggestions, approval auto-review) to a configurable small model. | Surface the routing settings in user docs when LL9 model guidance lands. |
| Local LLM | LL2 | done | Whole-turn file-change checkpoints with one-action revert. | Keep checkpoint store and UI rollback coverage green while using LL2 as the safety net for later agent changes. |

## Plan Mode Track

### PM1: Deterministic Scenario Baseline

Status: `done`

Scope:
- Keep deterministic Plan Mode scenarios runnable on macOS.
- Store suite reports, logs, screenshots, and failure artifacts under
  `build/integration_test_reports`.
- Provide scenario filtering through `CAVERNO_PLAN_MODE_SCENARIOS` and tag
  filtering through `CAVERNO_PLAN_MODE_TAGS`.

Acceptance criteria:
- `host_health_scaffold` runs in fake mode.
- Scenario reports include logs, artifacts, screenshots, and diagnostics.
- Report paths are stable enough for follow-up tooling.

Evidence:
- `integration_test/plan_mode_scenario_test.dart`
- `integration_test/test_support/plan_mode_scenario_config.dart`
- `integration_test/test_support/plan_mode_suite_report.dart`

### PM2: Harness Support Module Decomposition

Status: `done`

Scope:
- Move reusable scenario helpers out of the top-level scenario test.
- Add focused coverage for pure support logic.
- Keep the parent scenario test responsible for orchestration, not low-level
  policy details.

Acceptance criteria:
- Planning decisions, post-scenario settle, failure artifacts, task drift,
  execution progress, workflow execution wait, approval UI, and proposal wait
  have focused support modules.
- Each extracted policy has a focused unit or widget test where practical.
- `flutter analyze` passes after each extraction.

Evidence:
- `integration_test/test_support/plan_mode_planning_decisions.dart`
- `integration_test/test_support/plan_mode_workflow_execution_completion.dart`
- `integration_test/test_support/plan_mode_approval_ui.dart`
- `integration_test/test_support/plan_mode_planning_proposal_wait.dart`

### PM3: Scenario Harness Completion

Status: `done`

Scope:
- Reduce `integration_test/plan_mode_scenario_test.dart` to readable scenario
  orchestration.
- Extract report assembly and file writing from `_runScenario`.
- Keep diagnostics and heartbeat completion behavior unchanged.

Acceptance criteria:
- The scenario test stays below roughly 700 lines.
- Scenario report writing is covered by focused tests.
- `host_health_scaffold` still passes on macOS after the extraction.

Evidence:
- `integration_test/plan_mode_scenario_test.dart` is reduced to roughly 680
  lines.
- `integration_test/test_support/plan_mode_scenario_reporting.dart`
- `integration_test/test_support/plan_mode_prompt_submission.dart`
- `test/integration_support/plan_mode_scenario_reporting_test.dart`
- `dart format`
- Focused report writer tests
- `flutter analyze`
- `CAVERNO_PLAN_MODE_SCENARIOS=host_health_scaffold flutter test integration_test/plan_mode_scenario_test.dart -d macos -r compact`

Next action:
- Continue with PM4 deterministic report quality checks.

### PM4: Deterministic Report Quality Gate

Status: `done`

Scope:
- Make deterministic Plan Mode reports suitable for PR review.
- Ensure warnings, task drift, artifact mismatches, and convergence failures are
  visible and actionable.
- Keep the report summary compact enough to scan.

Acceptance criteria:
- Deterministic smoke scenarios pass with expected artifacts.
- Warning policy failures identify the blocking scenario and reason.
- Suite Markdown, JSON, and XML outputs are aligned.

Evidence:
- `integration_test/test_support/plan_mode_warning_policy.dart`
- `integration_test/test_support/plan_mode_report_summary.dart`
- `integration_test/test_support/plan_mode_suite_report.dart`
- `integration_test/test_support/plan_mode_scenario_reporting.dart`
- `test/integration_support/plan_mode_report_summary_test.dart`
- `test/integration_support/plan_mode_suite_report_test.dart`
- `test/integration_support/plan_mode_scenario_reporting_test.dart`
- `fvm flutter test test/integration_support/plan_mode_report_summary_test.dart test/integration_support/plan_mode_suite_report_test.dart test/integration_support/plan_mode_scenario_reporting_test.dart`
- `fvm flutter analyze`
- `CAVERNO_PLAN_MODE_TAGS=smoke fvm flutter test integration_test/plan_mode_scenario_test.dart -d macos -r compact`

Next action:
- Continue with PM5 live LLM smoke stabilization.

### PM5: Live LLM Smoke Stabilization

Status: `done`

Scope:
- Keep live Plan Mode runs stable against OpenAI-compatible endpoints.
- Preserve actionable timeout, stall, and convergence diagnostics.
- Validate the ping CLI convergence path and clarify/recovery paths.

Acceptance criteria:
- `live_host_health_scaffold` passes with no unexpected warnings.
- `live_clarify_recovery` demonstrates decision recovery.
- Ping CLI live canary produces the expected files and final answer.

Evidence:
- `tool/run_plan_mode_live_test.sh`
- `tool/run_plan_mode_ping_cli_live_canary.sh`
- `tool/run_plan_mode_pm5_live_gate.sh`
- `integration_test/test_support/plan_mode_live_harness_execution.dart`
- `integration_test/test_support/plan_mode_canary_summary.dart`
- `test/integration_support/plan_mode_live_harness_execution_test.dart`
- `test/integration_support/plan_mode_canary_summary_test.dart`
- `test/tool/run_plan_mode_pm5_live_gate_test.dart`
- `docs/plan_mode_ping_cli_stabilization_playbook.md`
- `fvm flutter test test/integration_support/plan_mode_canary_summary_test.dart test/integration_support/plan_mode_live_harness_execution_test.dart test/tool/run_plan_mode_pm5_live_gate_test.dart test/tool/run_plan_mode_live_test_test.dart test/integration/plan_mode_scenario_spec_test.dart`
- `fvm flutter analyze`
- `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 CAVERNO_LLM_API_KEY=no-key CAVERNO_LLM_MODEL=gemma-4-26B-A4B-it-Q4_K_M.gguf CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1 tool/run_plan_mode_pm5_live_gate.sh`
- `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 CAVERNO_LLM_API_KEY=no-key CAVERNO_LLM_MODEL=gemma-4-26B-A4B-it-Q4_K_M.gguf CAVERNO_PLAN_MODE_PM5_SKIP_SMOKE=1 CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1 tool/run_plan_mode_pm5_live_gate.sh`
- Latest ping canary report: `build/integration_test_reports/plan_mode_ping_cli_canary_1778555057/canary_summary.json`
- Latest ping canary result: 1 run, 1 passed, 0 failed, 0 warnings, 0 report quality blockers, no task drift.

Next action:
- Continue with PM6 Plan Mode MVP handoff documentation.

### PM6: Plan Mode MVP Handoff

Status: `done`

Scope:
- Convert deterministic and live evidence into a compact MVP handoff.
- Document the shortest path from local smoke to live confidence.
- Keep commands and expected artifacts discoverable from README and docs.

Acceptance criteria:
- README points to the canonical Plan Mode verification path.
- The stabilization playbook reflects the current scenario names and gates.
- MVP handoff includes deterministic status, live status, warnings, and known
  blockers.

Evidence:
- `README.md`
- `docs/plan_mode_mvp_handoff.md`
- `docs/plan_mode_ping_cli_stabilization_playbook.md`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Use the MVP handoff during release review and choose the next Plan Mode
  milestone before new implementation.

### PM7: Plan Mode Release Readiness

Status: `done`

Scope:
- Turn the PM6 MVP handoff into a release readiness checklist.
- Fix the required order for deterministic smoke, static analysis, and the PM5
  live gate.
- Make pass, warning, blocker, and exception decisions explicit enough for a
  release review.
- Keep the checklist focused on product release decisions rather than
  stabilization history.

Acceptance criteria:
- A release checklist names the exact commands to run before shipping Plan Mode.
- The checklist maps report fields to release decisions.
- Known external prerequisites are separated from app-side blockers.
- The README and MVP handoff point to the release checklist.

Evidence:
- `docs/plan_mode_release_readiness_checklist.md`
- `README.md`
- `docs/plan_mode_mvp_handoff.md`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Use the release checklist for Plan Mode release review and continue with PM8
  live gate failure operations.

### PM8: Live Gate Failure Operations

Status: `done`

Scope:
- Make PM5 live gate failures easy to triage without reading every raw log
  first.
- Connect failure classes, report paths, warning summaries, and task drift
  signals to the stabilization playbook.
- Improve scripts or docs so the latest useful artifact paths are easy to find.

Acceptance criteria:
- A failed PM5 gate points reviewers to the latest summary, suite report, and
  run log.
- Failure classes have documented first investigation steps.
- Endpoint/model availability failures are clearly separated from app workflow
  regressions.
- The playbook and release checklist agree on the failure triage order.

Evidence:
- `tool/run_plan_mode_pm5_live_gate.sh`
- `test/tool/run_plan_mode_pm5_live_gate_test.dart`
- `docs/plan_mode_release_readiness_checklist.md`
- `docs/plan_mode_ping_cli_stabilization_playbook.md`
- `README.md`
- `fvm flutter test test/tool/run_plan_mode_pm5_live_gate_test.dart test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Use the PM5 gate artifact index and failure triage order during release
  review, then continue with PM9 product UX polish.

### PM9: Plan Mode Product UX Polish

Status: `done`

Scope:
- Review saved plan, approval, task progress, recovery, blocked, and completion
  states from a product user perspective.
- Improve user-facing copy and state transitions where the workflow is correct
  but hard to understand.
- Keep harness-only fallback behavior separate from product UI expectations.

Acceptance criteria:
- Plan approval and task progress states are understandable without reading
  harness logs.
- Blocked and recovery states explain what happened and what the user can do.
- Completion states do not leave stale or contradictory task status visible.
- Product-facing strings stay aligned with the existing English-only code and
  documentation rules.

Evidence:
- `lib/features/chat/presentation/pages/chat_page.dart`
- `lib/features/chat/presentation/widgets/plan/plan_hydrated_task_row.dart`
- `assets/translations/en.json`
- `assets/translations/ja.json`
- `test/features/chat/presentation/widgets/plan/plan_hydrated_task_row_test.dart`
- `fvm flutter test test/features/chat/presentation/widgets/plan/plan_hydrated_task_row_test.dart test/features/chat/presentation/widgets/plan/compact_plan_footer_card_test.dart test/features/chat/presentation/widgets/plan/timeline_plan_card_test.dart test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Keep task state guidance visible while expanding scenario coverage in PM10.

### PM10: Plan Mode Scenario Coverage Expansion

Status: `done`

Scope:
- Decide which MVP-adjacent live canaries should become regular coverage.
- Keep new scenarios in canary status until they have stable diagnostics and
  clear promotion criteria.
- Evaluate whether `live_readme_first_canary` is ready for smoke promotion.

Acceptance criteria:
- Candidate scenarios are grouped as smoke, canary, or long-run coverage.
- Each new canary has artifact expectations, task drift checks, and warning
  policy expectations.
- Smoke promotion requires stable PM5 gate behavior and no recurring
  unexpected warnings.
- README and roadmap document the scenario classification rules.

Evidence:
- `docs/plan_mode_scenario_coverage.md`
- `README.md`
- `test/integration/plan_mode_scenario_spec_test.dart`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/integration/plan_mode_scenario_spec_test.dart test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Use the scenario coverage rules before promoting canaries into smoke, then
  continue with PM11 model and endpoint compatibility.

### PM11: Model and Endpoint Compatibility

Status: `done`

Scope:
- Document supported and risky OpenAI-compatible endpoint behavior for Plan
  Mode.
- Capture model differences around tool calling, JSON repair, streaming tags,
  and long-running task completion.
- Define recommended settings and known limitations for product use.

Acceptance criteria:
- Compatibility notes distinguish endpoint failures from model behavior
  limitations.
- Recommended live test environment variables and model assumptions are
  discoverable from the release docs.
- Known limitations include a suggested mitigation or a clear unsupported
  boundary.
- Compatibility findings are backed by deterministic tests, live evidence, or
  documented manual validation.

Evidence:
- `docs/plan_mode_model_endpoint_compatibility.md`
- `docs/plan_mode_release_readiness_checklist.md`
- `docs/plan_mode_mvp_handoff.md`
- `README.md`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Use compatibility notes before classifying live failures as app regressions,
  then continue with PM12 release candidate gate definition.

### PM12: Plan Mode Release Candidate Gate

Status: `done`

Scope:
- Define the final release candidate gate for Plan Mode.
- Combine deterministic smoke, PM5 live gate, selected canaries, compatibility
  notes, and manual UX review into one sign-off flow.
- Record the artifact bundle and decision owner expectations for release
  review.

Acceptance criteria:
- The release candidate checklist has one ordered command and review flow.
- Required artifacts and manual review notes are named explicitly.
- Exceptions require a documented reason and follow-up milestone.
- The final gate can be repeated by a reviewer who did not perform the
  stabilization work.

Evidence:
- `docs/plan_mode_release_candidate_gate.md`
- `docs/plan_mode_release_readiness_checklist.md`
- `docs/plan_mode_scenario_coverage.md`
- `docs/plan_mode_model_endpoint_compatibility.md`
- `README.md`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Use the release candidate gate for final Plan Mode sign-off before opening a
  new productization track.

### PM13: Release Candidate Execution

Status: `done`

Scope:
- Execute the PM12 release candidate gate end to end.
- Record the deterministic smoke, static analysis, PM5 live gate, selected
  canary, compatibility, and manual UX review results.
- Produce a release candidate sign-off decision that can drive product release
  or focused follow-up work.

Acceptance criteria:
- The PM12 gate is run in its documented order.
- All required artifact paths are recorded in the sign-off record.
- The decision is one of `pass`, `warning`, `blocked`, or
  `blocked: environment`.
- Any warning or blocker is converted into a PM14 follow-up item or a
  documented exception with an owner.

Evidence:
- `docs/plan_mode_release_candidate_signoff_2026-05-13.md`
- `docs/plan_mode_release_candidate_signoff_2026-05-13_rerun.md`
- `docs/plan_mode_release_candidate_signoff_2026-05-13_pm14_rerun.md`
- `docs/plan_mode_live_smoke_compatibility_triage.md`
- `docs/plan_mode_release_candidate_gate.md`
- `docs/plan_mode_model_endpoint_compatibility.md`
- `build/integration_test_reports/plan_mode_suite_macos_report.json`
- `build/integration_test_reports/plan_mode_suite_macos_report.md`
- `build/integration_test_reports/plan_mode_suite_macos_report.xml`
- `build/integration_test_reports/plan_mode_live_suite_macos_report.json`
- `build/integration_test_reports/plan_mode_live_suite_macos_report.md`
- `build/integration_test_reports/plan_mode_live_suite_macos_report.xml`
- `CAVERNO_PLAN_MODE_TAGS=smoke fvm flutter test integration_test/plan_mode_scenario_test.dart -d macos -r compact`
- `fvm flutter analyze`
- `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 CAVERNO_LLM_API_KEY=no-key CAVERNO_LLM_MODEL=gemma-4-26B-A4B-it-Q4_K_M.gguf CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1 tool/run_plan_mode_pm5_live_gate.sh`
- PM5 live gate result: `blocked: environment` because
  `192.168.100.241:1234` was not reachable during endpoint preflight.
- Rerun command:
  `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 CAVERNO_LLM_API_KEY=no-key CAVERNO_LLM_MODEL=gemma4-26b-vision CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1 tool/run_plan_mode_pm5_live_gate.sh`
- Rerun PM5 live gate result: `blocked: environment` because
  `gemma4-26b-vision` reached live smoke but failed `live_clarify_recovery`
  with `streamDisconnect`, 5 unexpected warnings, 7 report quality blockers,
  and 1 task drift finding.
- PM14 rerun command:
  `CAVERNO_LLM_BASE_URL=http://192.168.100.241:1234/v1 CAVERNO_LLM_API_KEY=no-key CAVERNO_LLM_MODEL=gemma4-26b-vision CAVERNO_PLAN_MODE_PM5_PING_REPEAT_COUNT=1 tool/run_plan_mode_pm5_live_gate.sh`
- PM14 rerun PM5 live gate result: passed with live smoke 3/3 and Ping CLI
  canary 1/1.
- PM14 rerun selected canaries: `live_readme_first_canary` passed, and
  `tool/run_plan_mode_convergence_full_pass.sh` passed focused regressions,
  static analysis, and 3 live README convergence iterations.

Next action:
- Use the PM14 rerun warning sign-off to drive PM15 manual UX review before
  promoting the release candidate decision from `warning` to `pass`.

### PM14: Release Blocker Burn-Down

Status: `done`

Scope:
- Resolve warnings and blockers found during PM13 release candidate execution.
- Keep app-side regressions, endpoint limitations, and accepted exceptions
  separate.
- Update release readiness, compatibility, or scenario coverage docs when a
  finding changes the release boundary.

Acceptance criteria:
- Every PM13 warning or blocker has a fix, documented exception, or explicit
  release deferral.
- Fixed issues include focused tests or updated release evidence.
- The release candidate gate can be rerun without the same unexplained
  warning or blocker.

Next action:
- Keep the PM14 completion evidence attached to the PM13 rerun sign-off while
  PM15 closes the remaining manual UX review warning.

### PM15: Product UX Finalization

Status: `done`

Scope:
- Polish the user-facing Plan Mode experience after RC findings are known.
- Review saved plan approval, task progress, blocked states, recovery, retries,
  and completion.
- Keep harness behavior and product behavior visibly separate.

Acceptance criteria:
- Core Plan Mode states are understandable without reading logs.
- Recovery and blocked states explain the user's next available action.
- Completion leaves no stale or contradictory task status visible.
- User-facing strings and tests cover any changed UX behavior.

Evidence:
- `docs/plan_mode_product_ux_finalization_2026-05-13.md`
- `lib/features/chat/presentation/widgets/plan/timeline_plan_card.dart`
- `lib/features/chat/presentation/widgets/plan/plan_hydrated_task_row.dart`
- `test/features/chat/presentation/widgets/plan/timeline_plan_card_test.dart`
- `test/features/chat/presentation/widgets/plan/plan_hydrated_task_row_test.dart`
- `test/features/chat/presentation/widgets/plan/compact_plan_footer_card_test.dart`
- `test/features/chat/presentation/widgets/plan/plan_review_sheet_test.dart`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/features/chat/presentation/widgets/plan/timeline_plan_card_test.dart test/features/chat/presentation/widgets/plan/plan_hydrated_task_row_test.dart test/features/chat/presentation/widgets/plan/compact_plan_footer_card_test.dart test/features/chat/presentation/widgets/plan/plan_review_sheet_test.dart test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Continue with PM16 settings and compatibility UX.

### PM16: Settings and Compatibility UX

Status: `done`

Scope:
- Productize endpoint, model, API key, and preflight compatibility guidance.
- Make common environment failures understandable from settings or Plan Mode
  error surfaces.
- Preserve the PM11 compatibility boundary while reducing user confusion.

Acceptance criteria:
- Endpoint and model failures are distinguishable from Plan Mode workflow
  failures.
- Preflight failure messaging explains the configured endpoint, model, and
  next repair action.
- Settings and release docs stay aligned on supported compatibility behavior.

Evidence:
- `docs/plan_mode_settings_compatibility_ux_2026-05-13.md`
- `docs/plan_mode_model_endpoint_compatibility.md`
- `lib/features/settings/presentation/pages/general_settings_page.dart`
- `assets/translations/en.json`
- `assets/translations/ja.json`
- `test/features/settings/presentation/pages/general_settings_page_test.dart`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/features/settings/presentation/pages/general_settings_page_test.dart test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Continue with PM17 supportability.

### PM17: Supportability

Status: `done`

Scope:
- Define the diagnostic information needed for user reports and reviewer
  investigations.
- Improve access to Plan Mode logs, report paths, compatibility context, and
  troubleshooting guidance.
- Keep sensitive endpoint credentials out of exported diagnostics.

Acceptance criteria:
- A Plan Mode issue report can include non-secret settings, model identity,
  relevant artifact paths, and failure classification.
- Troubleshooting guidance maps common failures to the right release or
  compatibility document.
- Diagnostic output avoids API keys and other secrets.

Evidence:
- `docs/plan_mode_supportability_2026-05-13.md`
- `docs/plan_mode_model_endpoint_compatibility.md`
- `lib/features/settings/presentation/pages/general_settings_page.dart`
- `assets/translations/en.json`
- `assets/translations/ja.json`
- `test/features/settings/presentation/pages/general_settings_page_test.dart`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/features/settings/presentation/pages/general_settings_page_test.dart test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Continue with PM18 release packaging.

### PM18: Release Packaging

Status: `done`

Scope:
- Prepare Plan Mode release notes, user-facing documentation, known
  limitations, and screenshot or demo evidence.
- Align product copy with the final compatibility and exception decisions.
- Make the release package understandable without stabilization history.

Acceptance criteria:
- Release notes describe Plan Mode capability, requirements, and limitations.
- User-facing docs point to the supported setup and troubleshooting path.
- Store or demo assets reflect the final product behavior.

Evidence:
- `docs/plan_mode_release_package_2026-05-13.md`
- `README.md`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Continue with PM19 post-release guardrails.

### PM19: Post-Release Guardrails

Status: `done`

Scope:
- Define the post-release regression and canary cadence for Plan Mode.
- Set hotfix criteria for live gate failures, compatibility regressions, and
  user-reported workflow failures.
- Keep the release candidate gate reusable for future releases.

Acceptance criteria:
- Regression checks and selected canaries have an owner and cadence.
- Hotfix decision rules distinguish app regressions from endpoint or model
  availability failures.
- Future release work can reuse PM12 and PM13 artifacts without rebuilding the
  process.

Evidence:
- `docs/plan_mode_post_release_guardrails_2026-05-13.md`
- `docs/plan_mode_release_package_2026-05-13.md`
- `README.md`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter test test/docs/plan_mode_mvp_handoff_docs_test.dart`
- `fvm flutter analyze`

Next action:
- Use the guardrails for post-release monitoring and create the next PM
  milestone only from scheduled evidence or user reports.

### PM20: Final Release Candidate Evidence Refresh

Status: `done`

Scope:
- Refresh the release candidate decision after PM15 through PM19 completed the
  remaining productization work.
- Attach the latest PM5 live smoke rerun and Ping CLI canary evidence.
- Close the previous manual UX warning and the final
  `missingExpectedSavedTaskTargetFiles` live gate regression.
- Keep future PM work gated by post-release guardrail evidence, compatibility
  changes, or user reports.

Acceptance criteria:
- A final sign-off record upgrades the current Plan Mode release candidate
  decision to `pass`.
- The sign-off records the latest live smoke, Ping CLI canary, and product UX
  evidence paths.
- README and docs tests point reviewers to the final sign-off.
- The roadmap names PM20 as the current productization baseline.

Evidence:
- `docs/plan_mode_release_candidate_final_signoff_2026-05-13.md`
- `docs/plan_mode_product_ux_finalization_2026-05-13.md`
- `docs/plan_mode_release_package_2026-05-13.md`
- `docs/plan_mode_post_release_guardrails_2026-05-13.md`
- `build/integration_test_reports/plan_mode_live_suite_macos_1778676005689/plan_mode_live_suite_macos_report.json`
- `build/integration_test_reports/plan_mode_ping_cli_canary_1778676312/canary_summary.json`
- `test/docs/plan_mode_mvp_handoff_docs_test.dart`

Next action:
- Use the final sign-off as the current Plan Mode productization baseline and
  open new PM milestones only from scheduled guardrail evidence, compatibility
  changes, or user reports.

## macOS Computer Use Track

The Computer Use milestones already use `M<number>` in
`docs/macos_computer_use_helper_architecture.md`. This roadmap keeps those IDs
intact and links them to MVP readiness.

| Milestone | Status | Summary |
|-----------|--------|---------|
| M1 | done | Permission-first onboarding and helper-owned overlay. |
| M2 | done | Capture, input, system-audio readiness, unsafe action hardening, and approval/arming gates for the debug embedded helper. |
| M3 | done | LaunchAgent-backed named XPC production IPC path. |
| M4 | done | Embedded-helper Screen & System Audio Recording, overlay, and onboarding sign-off gate. |
| M5 | done | Vision LLM observation tool surface. |
| M6 | done | Observe-action-observe loop hardening. |
| M7 | done | Release-helper artifact sign-off gate. |
| M8 | done | Release runtime sign-off gate, with manual TCC runtime evidence required. |
| M9 | done | User-operated manual TCC runbook boundary. |
| M10 | later | Helper IPC/runtime diagnostics for timeout headroom, path mismatches, and launch results. |
| M11 | later | Reusable Live LLM fixture evidence discovery and non-secret request metadata. |
| M12 | later | Real-app observe-only canaries for public-action boundary classification. |

MVP ready criteria live in `docs/macos_computer_use_mvp_checklist.md`.

## Foundation And Local LLM Agent Tracks

The `F<number>` and `LL<number>` milestones, their dependency graph, and the
phase ordering live in `docs/local_llm_agent_roadmap.md`. Summary:

- Phase 0: F1 (line-count ratchet), LL1 (per-role model routing).
- Phase 1: F2 (tool loop extraction), LL2 (whole-turn checkpoints).
- Phase 2: F3 (`openai_dart` 6.x and other major upgrades), LL3 (model
  capability profiles), LL9 (local stack manager).
- Phase 3: LL4 (repo map v1), LL6 (KV-cache-friendly mode), LL14 (context
  surgery), LL15 (weak-model edit harness), LL16 (sampler auto-calibration).
- Phase 4: F4 (Hive to drift/SQLite with FTS), then LL5 (local semantic
  search), LL10 (installed-dependency grounding), LL11 (LSP bridge).
- Phase 5: LL7 (Best-of-N verification loop), LL8 (LAN inference mesh),
  LL12 (personal eval harness), F5 (ongoing large-file decomposition per
  `docs/large_file_refactor_plan.md`).
- Phase 6: LL13 (parallel agents in isolated git worktrees over the mesh),
  LL17 (self-improving harness loop gated by the personal eval suite).

## Operating Loop

1. Pick one `current` or `next` milestone.
2. Split the milestone into one atomic implementation slice.
3. Add or update focused tests for the changed policy.
4. Run format, focused tests, analysis, and the relevant smoke gate.
5. Commit with a Conventional Commits message.
6. Move the milestone status only when acceptance criteria and evidence are
   complete.
