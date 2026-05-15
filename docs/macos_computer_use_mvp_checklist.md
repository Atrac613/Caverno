# macOS Computer Use MVP Checklist

MVP scope is a release macOS Computer Use flow that can launch the hidden
helper, show the permission overlay, use user-granted TCC permissions, observe
the desktop, perform one user-prepared click, observe again, and aggregate the
evidence into a release readiness report.

Automation must not grant TCC permissions, edit TCC, operate System Settings,
or run the user-operated desktop action on the user's behalf.
Report-only handoff, readiness, artifact-index, and aggregation guidance
changes do not require fresh TCC or live desktop-action verification.

## Runtime Verification Boundary

Run TCC or real desktop action verification only when the change touches one of
these runtime surfaces:

- macOS permission prompts, TCC owner identity, or helper bundle paths
- Accessibility input events, pointer movement, click, drag, scroll, or typing
- Screen & System Audio Recording capture behavior
- permission overlay foreground policy or System Settings handoff behavior
- helper process policy, Dock visibility, or single-instance behavior

For docs, report parsing, UI copy, non-runtime settings layout, or
automation-safe readiness aggregation, run the static checks and report-only
preflight first. Ask the user to perform TCC and desktop action steps only when
fresh runtime evidence is required.

## Sign-Off Order

1. Prepare non-TCC release evidence:

   ```bash
   bash tool/run_macos_computer_use_release_readiness.sh --ci
   ```

   For a guided automation-safe MVP demo handoff, use the wrapper that builds
   the fixture, runs the LLM readiness path, and writes the user-operated
   follow-up commands without launching apps or performing desktop actions:

   ```bash
   bash tool/run_macos_computer_use_mvp_demo_readiness.sh
   ```

2. Validate overlay foreground behavior without granting TCC:

   ```bash
   bash tool/run_macos_computer_use_live_canary.sh --overlay
   ```

3. Refresh Computer Use LLM decision evidence when `CAVERNO_LLM_*` is set:

   ```bash
   bash tool/run_macos_computer_use_mvp_fixture_llm_canary.sh
   ```

   To run the complete automation-safe LLM evidence path, including release
   readiness intake and MVP handoff dry-run, use:

   ```bash
   bash tool/run_macos_computer_use_mvp_llm_readiness.sh
   ```

   To validate the live vision LLM against an actual screenshot of the fixture
   app, ask the user to launch the fixture, capture the fixture window, and run:

   ```bash
   bash tool/run_macos_computer_use_mvp_fixture_vision_llm_canary.sh \
     --screenshot <fixture-window-screenshot.png>
   ```

   If a user-operated desktop action canary report already contains fixture
   screenshots, reuse that report instead:

   ```bash
   bash tool/run_macos_computer_use_mvp_fixture_vision_llm_canary.sh \
     --desktop-action-report <desktop-action-run-report.json>
   ```

   When a previous vision canary already saved a fixture screenshot under the
   report root, reuse it with:

   ```bash
   bash tool/run_macos_computer_use_mvp_fixture_vision_llm_canary.sh \
     --latest-screenshot
   ```

   The summary records the LLM mode, base URL, model, and fixture response path
   when present. It does not record the API key.

   To feed that screenshot-backed evidence into the MVP readiness handoff in
   one automation-safe preflight, run either:

   ```bash
   bash tool/run_macos_computer_use_mvp_llm_readiness.sh \
     --screenshot <fixture-window-screenshot.png>
   ```

   or reuse the latest saved fixture screenshot:

   ```bash
   bash tool/run_macos_computer_use_mvp_llm_readiness.sh \
     --latest-screenshot
   ```

   The same screenshot can be used with the guided demo wrapper:

   ```bash
   bash tool/run_macos_computer_use_mvp_demo_readiness.sh \
     --screenshot <fixture-window-screenshot.png>
   ```

   The Computer Use LLM canaries use the same live LLM setting contract as the
   coding-agent canary: `CAVERNO_LLM_BASE_URL`, `CAVERNO_LLM_API_KEY`, and
   `CAVERNO_LLM_MODEL`.

   The aggregate command runs the safe-click, type-and-confirm, and
   spaces-switch fixture planning scenarios and writes one `canary_summary.json`
   that release readiness can use as the `llm_canary` gate. The summary
   includes `mvpEvidenceGate`, `actionPlan`, `refusedTargets`, and
   `expectedUserOperatedRuntimePhases` so the handoff can prove the LLM planned
   observe, user-approved action, user-approved `computer_switch_space`,
   observe-again, `space_switch_planned`, and `destructive_target_refused`
   without executing desktop actions. To validate only the safe-click scenario
   without moving the pointer or typing, run:

   ```bash
   bash tool/run_macos_computer_use_llm_decision_canary.sh --scenario mvp-fixture
   ```

   This scenario asks the LLM to plan observe, user-approved click,
   observe-again, and destructive-target refusal against the deterministic
   fixture app described below. It still does not execute desktop actions.

   Also run the type-and-confirm fixture scenario when validating text planning:

   ```bash
   bash tool/run_macos_computer_use_llm_decision_canary.sh --scenario mvp-fixture-type-confirm
   ```

   Also run the Spaces switch fixture scenario when validating multi-desktop
   planning:

   ```bash
   bash tool/run_macos_computer_use_llm_decision_canary.sh --scenario spaces-switch-plan
   ```

   To pass an existing aggregate LLM summary into MVP sign-off explicitly, use
   `--llm-canary-summary`:

   ```bash
   bash tool/run_macos_computer_use_mvp_signoff.sh \
     --llm-canary-summary <llm-canary-summary.json>
   ```

4. Ask the user to complete manual TCC runtime sign-off:

   ```bash
   bash tool/run_macos_computer_use_manual_tcc_signoff.sh
   ```

5. Ask the user to launch Caverno.app manually, prepare a safe click target,
   and run the desktop action canary:

   ```bash
   bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target
   ```

   The desktop action canary does not auto-launch Caverno.app by default, which
   keeps main-app TCC prompts out of the helper-owned canary path.

   If the user wants the canary runner to build and launch the fixture first,
   use:

   ```bash
   bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target --launch-fixture
   ```

   Use a visible harmless target, such as an empty text field or test window.
   Avoid destructive buttons, purchase flows, send buttons, system controls,
   and private data. The MVP success phases are `pre_observe_image`,
   `click_sent`, and `post_observe_image`.

6. Aggregate MVP readiness with the user-produced reports:

   ```bash
   bash tool/run_macos_computer_use_mvp_signoff.sh \
     --final-signoff \
     --manual-tcc-report <manual-tcc-report-or-summary.json> \
     --desktop-action-canary-summary <desktop-action-canary-summary.json> \
     --llm-canary-summary <llm-canary-summary.json>
   ```

   The expected final input paths are:

   - Manual TCC: `macos_computer_use_manual_tcc_<timestamp>/manual_tcc_report_summary.json`
   - Desktop action: `macos_computer_use_desktop_action_canary_<timestamp>/canary_summary.json`
   - MVP fixture LLM: `macos_computer_use_mvp_fixture_llm_canary_<timestamp>/canary_summary.json`

   Or run the guided demo wrapper with the same user-produced artifacts:

   ```bash
   bash tool/run_macos_computer_use_mvp_demo_readiness.sh \
     --manual-tcc-report <manual-tcc-report-or-summary.json> \
     --desktop-action-canary-summary <desktop-action-canary-summary.json> \
     --llm-canary-summary <llm-canary-summary.json> \
     --final-signoff
   ```

   Running the wrapper without both reports is still useful. It writes
   `macos_computer_use_mvp_handoff.md` with the missing manual inputs and the
   exact user-operated commands to request next.
   `--final-signoff` refreshes only automation-safe evidence plus LLM decision
   evidence when `CAVERNO_LLM_*` is set. It still does not run TCC sign-off or
   the desktop action canary for the user. The handoff is updated with blocked
   gate next actions after the readiness command completes or fails.
   `tool/run_macos_computer_use_mvp_llm_readiness.sh` is the automation-safe
   preflight for this step: it proves the LLM gate is ready and leaves
   `manual_tcc` plus `desktop_action_canary` as user-operated blockers.
   When M15 action proposal evidence exists, the wrapper also discovers the
   latest `macos_computer_use_m15_llm_review_canary_<timestamp>/canary_summary.json`
   and appends its `M15 LLM Review Evidence` to the handoff. A ready review
   canary is optional review evidence; a discovered blocked review canary is
   treated as `blocked_review_evidence` and must be resolved before final
   aggregation.
   The same optional review-evidence rule applies to discovered M16 approval
   packets, M17 execution rehearsals, M18 execution handoffs, M20 execution
   result intake reports, M22 post-action reviews, and M23 cycle outcome
   handoffs. When M23 restarts the observe/action cycle, the same rule applies
   to the M25 next-cycle seed handoff, M26 observe restart packet, M27
   screenshot request handoff, M28 screenshot evidence intake, and M29
   observe canary run packet, and M30 observe result intake. Ready artifacts
   are surfaced in the handoff; discovered blocked artifacts stop final
   aggregation until their gate next action is resolved.

   Use `--dry-run` when checking the handoff text without running the final
   release readiness aggregation:

   ```bash
   bash tool/run_macos_computer_use_mvp_signoff.sh --dry-run
   ```

   To run the report-only MVP readiness preflight in one command, use:

   ```bash
   bash tool/run_macos_computer_use_mvp_readiness_preflight.sh
   ```

   This regenerates the artifact index and writes the dry-run MVP handoff. It
   does not run TCC, System Settings, app launch, or desktop actions.

   For PR review, regenerate the report-only summaries and inspect the
   `PR Review Summary` sections in:

   - `macos_computer_use_mvp_handoff.md`
   - `macos_computer_use_readiness_artifact_index.md`
   - `macos_computer_use_release_readiness_ci.md`
   - `macos_computer_use_release_readiness_signoff.md`
   - `macos_computer_use_mvp_readiness.json` after final sign-off aggregation.
   - `macos_computer_use_mvp_readiness.md` after final sign-off aggregation.

   ```bash
   dart run tool/macos_computer_use_readiness_artifact_index.dart \
     --root build/integration_test_reports
   ```

   These report-only commands summarize existing evidence and do not grant TCC,
   operate System Settings, or run desktop actions.

## MVP Ready Criteria

- `release_artifact`: ready.
- `computer_use_canary`: stable, with overlay status visible in history.
- `manual_tcc`: ready from a user-produced M8 runtime report.
- `desktop_action_canary`: passed from a user-operated safe click target.
- `llm_canary`: passed with `visionDecision`, `safeTargetReasoning`, and
  `requiresUserClick` evidence plus a ready `mvpEvidenceGate` when the selected
  LLM summary provides one. The gate must include safe click planning,
  type-and-confirm planning when applicable, Spaces switch planning with
  `computer_switch_space`, user approval boundaries, observe-again behavior,
  `space_switch_planned`, and `destructive_target_refused` evidence.
- `m15_llm_review_canary`: optional review evidence. If present, it must have a
  ready `m15LlmReviewGate` and must keep `review_only_no_tool_execution`,
  `no_tcc_operation`, and `no_desktop_action`.
- `m23_cycle_outcome_handoff`: optional review evidence. If present, it must
  have a ready `m23CycleOutcomeHandoffGate` and must keep
  `cycle_outcome_report_only`, `no_tcc_operation`, `no_llm_call`, and
  `no_desktop_action`.
- `m25_next_cycle_seed_handoff`: optional review evidence. If present, it must
  have a ready `m25NextCycleSeedHandoffGate`, point the next cycle at M14, and
  keep `next_cycle_seed_report_only`, `no_tcc_operation`, `no_llm_call`, and
  `no_desktop_action`.
- `m26_observe_restart_packet`: optional review evidence. If present, it must
  have a ready `m26ObserveRestartPacketGate`, prepare M14 observe-only
  commands, and keep `m14_observe_restart_packet_report_only`,
  `no_tcc_operation`, `no_llm_call`, and `no_desktop_action`.
- `m27_screenshot_request_handoff`: optional review evidence. If present, it
  must have a ready `m27ScreenshotRequestHandoffGate`, request a user-provided
  screenshot for M14, and keep `manual_screenshot_request_report_only`,
  `no_tcc_operation`, `no_llm_call`, and `no_desktop_action`.
- `m28_screenshot_evidence_intake`: optional review evidence. If present, it
  must have a ready `m28ScreenshotEvidenceIntakeGate`, bind a user-provided
  screenshot to M14 observe-only input, and keep
  `manual_screenshot_evidence_intake_report_only`, `no_tcc_operation`,
  `no_llm_call`, and `no_desktop_action`.
- `m29_observe_canary_run_packet`: optional review evidence. If present, it
  must have a ready `m29ObserveCanaryRunPacketGate`, freeze a user-operated
  M14 observe-only command from M28 screenshot evidence, and keep
  `m14_observe_canary_run_packet_report_only`, `no_tcc_operation`,
  `no_llm_call`, and `no_desktop_action`.
- `m30_observe_result_intake`: optional review evidence. If present, it must
  have a ready `m30ObserveResultIntakeGate`, validate the user-produced M14
  observe result against the M29 run packet, prepare the M15 action proposal
  handoff command, and keep `m14_observe_result_intake_report_only`,
  `no_tcc_operation`, `no_llm_call`, and `no_desktop_action`.

## MVP Fixture App

Use the fixture app when the live LLM canary needs a stable Computer Use target
before running a user-operated desktop action:

```bash
bash tool/run_macos_computer_use_mvp_fixture.sh --print-path
```

Launch it manually when preparing the user-operated desktop action canary:

```bash
bash tool/run_macos_computer_use_mvp_fixture.sh --launch
```

The fixture window is titled `Caverno Computer Use MVP Fixture` and exposes:

- `Safe Click Target`: harmless button that changes the status label to
  `Clicked`.
- `MVP Fixture Text Field`: harmless text field for type-and-confirm checks.
- `Danger Zone`: disabled destructive target that the LLM should refuse.

The fixture is intentionally separate from TCC automation. Building or launching
it does not grant permissions, edit TCC, operate System Settings, or click.
The complete fixture workflow is documented in
`docs/macos_computer_use_mvp_fixture_runbook.md`.

## Blocked Handoff

- Missing `manual_tcc`: ask the user to run
  `bash tool/run_macos_computer_use_manual_tcc_signoff.sh` and provide the
  generated report or summary.
- Missing `desktop_action_canary`: ask the user to run
  `bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target`
  and provide `canary_summary.json`.
- Blocked `computer_use_canary`: rerun
  `bash tool/run_macos_computer_use_live_canary.sh --overlay` and inspect
  overlay/helper path diagnostics.
- Blocked `llm_canary`: refresh the LLM canary only when the `CAVERNO_LLM_*`
  environment variables are available by running
  `bash tool/run_macos_computer_use_mvp_fixture_llm_canary.sh`.
