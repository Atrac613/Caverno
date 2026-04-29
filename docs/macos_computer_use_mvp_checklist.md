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

3. Ask the user to complete manual TCC runtime sign-off:

   ```bash
   bash tool/run_macos_computer_use_manual_tcc_signoff.sh
   ```

4. Ask the user to prepare a safe click target and run the desktop action
   canary:

   ```bash
   bash tool/run_macos_computer_use_desktop_action_canary.sh
   ```

5. Aggregate MVP readiness with the user-produced reports:

   ```bash
   bash tool/run_macos_computer_use_mvp_signoff.sh \
     --manual-tcc-report <manual-tcc-report-or-summary.json> \
     --desktop-action-canary-summary <desktop-action-canary-summary.json>
   ```

   Running the wrapper without both reports is still useful. It writes
   `macos_computer_use_mvp_handoff.md` with the missing manual inputs and the
   exact user-operated commands to request next.

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
- `llm_canary`: passed or explicitly accepted from current readiness evidence.

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
  environment variables are available.
