# macOS Computer Use MVP Checklist

MVP scope is a release macOS Computer Use flow that can launch the hidden
helper, show the permission overlay, use user-granted TCC permissions, observe
the desktop, perform one user-prepared click, observe again, and aggregate the
evidence into a release readiness report.

Automation must not grant TCC permissions, edit TCC, operate System Settings,
or run the user-operated desktop action on the user's behalf.

## Sign-Off Order

1. Prepare non-TCC release evidence:

   ```bash
   bash tool/run_macos_computer_use_release_readiness.sh --ci
   ```

2. Validate overlay foreground behavior without granting TCC:

   ```bash
   bash tool/run_macos_computer_use_live_canary.sh --overlay
   ```

3. Refresh Computer Use LLM decision evidence when `CAVERNO_LLM_*` is set:

   ```bash
   bash tool/run_macos_computer_use_llm_decision_canary.sh
   ```

   The Computer Use LLM canaries use the same live LLM setting contract as the
   coding-agent canary: `CAVERNO_LLM_BASE_URL`, `CAVERNO_LLM_API_KEY`, and
   `CAVERNO_LLM_MODEL`.

   To validate the MVP-style fixture scenario without moving the pointer or
   typing, run:

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

   To run both fixture LLM scenarios in one command:

   ```bash
   bash tool/run_macos_computer_use_mvp_fixture_llm_canary.sh
   ```

4. Ask the user to complete manual TCC runtime sign-off:

   ```bash
   bash tool/run_macos_computer_use_manual_tcc_signoff.sh
   ```

5. Ask the user to prepare a safe click target and run the desktop action
   canary:

   ```bash
   bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target
   ```

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
     --desktop-action-canary-summary <desktop-action-canary-summary.json>
   ```

   Running the wrapper without both reports is still useful. It writes
   `macos_computer_use_mvp_handoff.md` with the missing manual inputs and the
   exact user-operated commands to request next.
   `--final-signoff` refreshes only automation-safe evidence plus LLM decision
   evidence when `CAVERNO_LLM_*` is set. It still does not run TCC sign-off or
   the desktop action canary for the user. The handoff is updated with blocked
   gate next actions after the readiness command completes or fails.

   Use `--dry-run` when checking the handoff text without running the final
   release readiness aggregation:

   ```bash
   bash tool/run_macos_computer_use_mvp_signoff.sh --dry-run
   ```

## MVP Ready Criteria

- `release_artifact`: ready.
- `computer_use_canary`: stable, with overlay status visible in history.
- `manual_tcc`: ready from a user-produced M8 runtime report.
- `desktop_action_canary`: passed from a user-operated safe click target.
- `llm_canary`: passed with `visionDecision`, `safeTargetReasoning`, and
  `requiresUserClick` evidence, or explicitly accepted from current readiness
  evidence.

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
- Missing `desktop_action_canary`: ask the user to prepare a safe click target,
  run `bash tool/run_macos_computer_use_desktop_action_canary.sh`, and provide
  `canary_summary.json`.
- Blocked `computer_use_canary`: rerun
  `bash tool/run_macos_computer_use_live_canary.sh --overlay` and inspect
  overlay/helper path diagnostics.
- Blocked `llm_canary`: refresh the LLM canary only when the `CAVERNO_LLM_*`
  environment variables are available by running
  `bash tool/run_macos_computer_use_llm_decision_canary.sh`.
