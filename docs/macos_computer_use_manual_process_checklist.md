# macOS Computer Use Manual Process Checklist

Use this checklist only after building a local macOS app. The steps are
user-operated because they inspect Dock state, foreground overlay behavior, and
macOS TCC surfaces.

## Commands

Manual runtime sign-off command:

```bash
bash tool/run_macos_computer_use_manual_tcc_signoff.sh
```

Underlying smoke command:

```bash
bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --m8-runtime-signoff
```

Report parser command for automation after the user provides the report:

```bash
dart run tool/macos_computer_use_manual_tcc_report.dart <user-produced-m8-report.json>
```

## Post-Merge Main Sanity Check

Run these checks after merging Computer Use changes into `main`. They do not
grant TCC permissions, operate System Settings, launch the helper UI, or perform
desktop actions:

```bash
bash tool/run_macos_computer_use_post_merge_sanity.sh
```

Treat TCC grants, helper foreground checks, smoke sequence execution, and
desktop action canaries as user-operated follow-ups. Ask the user to run the
manual commands and provide the generated report when runtime evidence is
needed.

## M13 Review Hardening

Use this review pass before merging Computer Use polish changes:

1. Open Settings and confirm the root list shows `Advanced`, not a top-level
   Computer Use status panel.
2. Open `Advanced` and confirm `Computer Use` and `Debug` are normal navigation
   rows.
3. Open `Computer Use` and confirm the helper-owned desktop control copy is
   visible before the detailed readiness card.
4. Confirm detailed runtime fields are behind the collapsed `Diagnostics`
   section, while primary actions remain visible.
5. Confirm no TCC grant, System Settings operation, helper foreground check, or
   desktop action is required for the review-only pass.
6. Run the post-merge sanity wrapper or inspect its `--print-commands` output
   before asking for any manual runtime sign-off. The output should name the
   review scope as `Advanced navigation, collapsed Diagnostics, manual runtime
   handoff, M14 observe-only evidence, M15 review/gate consistency`.

Expected static coverage:

- `test/features/settings/presentation/pages/advanced_settings_page_test.dart`
- `test/features/settings/presentation/pages/settings_page_test.dart`
- `test/features/settings/presentation/pages/computer_use_debug_page_test.dart`
- `test/integration_support/macos_computer_use_release_readiness_test.dart`
- `test/tool/run_macos_computer_use_smoke_test_test.dart`

## M14 Observe-Only Evidence

Use this pass after the M13 review hardening checks when the next milestone
needs real-app visual evidence without executing desktop actions:

1. Ask the user to manually prepare the target app state and screenshot. For
   Safari-style workflows, the user opens Safari, navigates to the logged-in
   page, and captures the screenshot.
2. Run the real-app observe canary with the user-provided screenshot or a
   deterministic fixture response.
3. Confirm the summary reports `milestone: M14` and includes `m14EvidenceGate`.
4. Confirm text-entry targets are classified before any future typing task.
5. Confirm public submit or posting controls are classified as
   `public_action`.
6. Confirm confirmation requirements are documented before any future input or
   public action.
7. Confirm the canary remains observe-only and the action plan does not include
   click, type, submit, post, purchase, or other mutating desktop tools.

Expected M14 evidence fields:

- `m14EvidenceGate.status`: `ready`
- `m14EvidenceGate.checks`: includes
  `safari_style_target_context`, `text_field_targets_classified`,
  `public_submit_boundary_classified`,
  `confirmation_requirements_documented`, and `observe_only_no_mutation`
- `confirmationRequirements`: non-empty
- `actionPlan`: observe-only

Do not automate app navigation, clicking, typing, posting, purchases, TCC
grants, or System Settings operations for M14 evidence. If fresh app state is
needed, ask the user to prepare the screenshot manually.

## M15 Action Proposal Handoff

Use this pass after M14 evidence is ready and the next milestone needs an
approval-bound action plan without executing any action:

1. Select the ready M14 `canary_summary.json`.
2. Run
   `bash tool/run_macos_computer_use_m15_action_proposal_handoff.sh --m14-summary <canary_summary.json>`.
3. Confirm `m15ActionProposalGate.status` is `ready`.
4. Confirm the handoff keeps `desktopActionBoundary: no_desktop_action`.
5. Confirm the handoff keeps `tccBoundary: no_tcc_operation`.
6. Confirm the handoff keeps `llmBoundary: no_llm_call`.
7. Confirm exact text, target, and public-action confirmations are separated.
8. Confirm the handoff includes `reviewTargetCounts` and review target tables
   for `exactTextCandidates`, `textEntryTargets`, and `publicActionTargets`.
9. Confirm the handoff includes `PR Review Summary` with
   `blockedReviewEvidence: none` before treating M15 as ready.
10. Confirm the handoff includes `reviewGateConsistency.status: consistent`
    before treating M15 as ready.
11. When live LLM settings are available, run
    `bash tool/run_macos_computer_use_m15_llm_review_canary.sh --handoff <action_proposal_handoff.json>`.
12. Confirm `m15LlmReviewGate.status` is `ready` before using LLM review
    evidence for the next milestone.
13. Confirm MVP sign-off or the artifact index surfaces the review summary as
    `m15_llm_review_canary`. If it appears in `blocked_review_evidence`, resolve
    the review canary before final aggregation.

Do not use this handoff to click, type, navigate, submit, post, purchase, grant
TCC, or operate System Settings. It is only the review artifact for a future
user-approved action step.

## Hidden Helper

1. Launch `Caverno.app`.
2. Open the Computer Use setup or debug surface.
3. Launch `Caverno Computer Use`.
4. Confirm `Caverno Computer Use.app` does not leave a persistent Dock icon.
5. Launch the helper again from Caverno.
6. Confirm only one `Caverno Computer Use` process remains active.

Expected smoke fields:

- `helperProcessPolicyGate.status`: `ready`
- `helperProcessPolicyGate.maxHelperRunningProcessCount`: `1`
- `helperProcessPolicyGate.singleInstanceLockStatus`: `acquired`
- `helperProcessPolicyGate.helperDockPolicy`: `agent_hidden_from_dock`

## Path Mismatch

If a previous Debug or Release helper is still running, relaunch from Caverno.
The app should terminate the mismatched helper path and launch the embedded
helper path before sign-off.

Expected smoke fields:

- `helperProcessPolicyGate.helperPathMismatch`: `false`
- `helperPathMatchesRunningHelper`: `true`
- `replacedMismatchedHelperPath`: present only when a mismatched helper was
  replaced during launch.

## Permission Overlay

1. Open Accessibility or Screen & System Audio Recording from the onboarding UI.
2. Confirm System Settings opens.
3. Confirm the floating permission overlay appears near the permission list.
4. Confirm the overlay remains visible while System Settings is active.
5. Use the overlay back button to return to onboarding.

Expected overlay fields:

- `overlaySmoke.status`: `ready`
- `overlayForegroundPolicy`: `accessory_overlay_front`
- `overlayIsFloatingPanel`: `true`
- `overlayHidesOnDeactivate`: `false`
- `overlayCollectionBehavior`: includes `canJoinAllSpaces`,
  `fullScreenAuxiliary`, and `transient`

Do not automate TCC grants. If TCC verification is needed, ask the user to run
the relevant manual smoke command and provide the generated report.
