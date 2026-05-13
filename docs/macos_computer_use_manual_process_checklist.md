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

## M33 Release Packaging Report

Run this static packaging report before asking for a signed release pass:

```bash
bash tool/run_macos_computer_use_release_packaging.sh
```

Expected outputs:

- `build/integration_test_reports/macos_computer_use_release_packaging.json`
- `build/integration_test_reports/macos_computer_use_release_packaging.md`

The report checks the helper embed phase, LaunchAgent BundleProgram,
MachServices declaration, release entitlements, hardened runtime settings, and
identity-free signing defaults. It does not sign, notarize, staple, grant TCC,
launch System Settings, or perform desktop actions. Signing identity,
notarization ticket, stapler validation, TCC grants, and real desktop evidence
remain user-operated release evidence.

## M34 Permission Recovery UX

Use this review pass when validating permission recovery without granting TCC
from automation:

1. Open `Settings > Advanced > Computer Use`.
2. Confirm the `Recovery guidance` section is visible below `Permission flow`.
3. Confirm first-time missing grants are labeled as `Missing permissions`.
4. Confirm previously granted but now disabled TCC entries are labeled as
   `Revoked permissions`.
5. Confirm stale helper diagnostics or helper path mismatches produce a restart
   action before any permission prompt instruction.
6. Confirm `Main app prompts` says to use the helper-owned permission overlay
   for helper IPC mode.
7. Confirm copied or exported diagnostics contain
   `permissionRecoverySummary`.

Do not automate TCC grants, System Settings toggles, helper foreground checks,
or desktop actions for this pass. Ask the user to perform those steps manually
when fresh runtime evidence is required.

## M13 Review Hardening

Use this review pass before merging Computer Use polish changes:

1. Open Settings and confirm the root list shows `Advanced` with a compact
   Computer Use availability summary, not a top-level Computer Use status panel.
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

## M16 Approval Packet

Use this pass after M15 action-proposal evidence is ready and the next
milestone needs explicit user approvals before any execution step:

1. Select the ready M15 `action_proposal_handoff.json`.
2. Select the ready M15 LLM review `canary_summary.json` when available.
3. Run
   `bash tool/run_macos_computer_use_m16_approval_packet.sh --m15-handoff <action_proposal_handoff.json> --m15-llm-review <canary_summary.json>`.
4. Confirm `m16ApprovalPacketGate.status` is `ready`.
5. Confirm `executionBoundary` is `no_desktop_action_report_only`.
6. Confirm `desktopActionBoundary: no_desktop_action`.
7. Confirm `tccBoundary: no_tcc_operation`.
8. Confirm `llmBoundary: no_llm_call`.
9. Confirm `requiredApprovals` separates `exact_text`, `target_label`,
   `public_action_label`, and `post_action_observation`.
10. If `approvalBlockers` is not empty, ask the user to approve the exact
    text, target, and public action labels before any future execution
    milestone.
11. If all required approvals are supplied with the command flags, confirm
    `approvalStatus: approved`.
12. Review the MVP sign-off handoff or readiness artifact index before final
    aggregation; blocked discovered `m16_approval_packet` evidence stops final
    aggregation until the packet is ready.

Do not use this approval packet to click, type, navigate, submit, post,
purchase, grant TCC, or operate System Settings. It is only the report-only
approval artifact for a future execution milestone.

## M17 Execution Rehearsal

Use this pass after the M16 approval packet is ready and explicitly approved:

1. Select the approved M16 `approval_packet.json`.
2. Run
   `bash tool/run_macos_computer_use_m17_execution_rehearsal.sh --m16-packet <approval_packet.json>`.
3. Confirm `m17ExecutionRehearsalGate.status` is `ready`.
4. Confirm `executionBoundary` is `no_desktop_action_report_only`.
5. Confirm `desktopActionBoundary: no_desktop_action`.
6. Confirm `tccBoundary: no_tcc_operation`.
7. Confirm `llmBoundary: no_llm_call`.
8. Confirm `executionPhases` separates `observe_again`, `focus_target`,
   `type_exact_text`, any `confirm_public_action`, and
   `post_action_observation`.
9. If the rehearsal is blocked, return to M16 and collect explicit user
   approval for the exact text, target label, and public action label before
   preparing the rehearsal again.
10. Review the MVP sign-off handoff or readiness artifact index before final
    aggregation; blocked discovered `m17_execution_rehearsal` evidence stops
    final aggregation until the rehearsal is ready.

Do not use this rehearsal to click, type, navigate, submit, post, purchase,
grant TCC, operate System Settings, or call an LLM. It is only the report-only
execution checklist for a future user-operated milestone.

## M18 Execution Handoff

Use this pass after the M17 execution rehearsal is ready:

1. Select the ready M17 `execution_rehearsal.json`.
2. Run
   `bash tool/run_macos_computer_use_m18_execution_handoff.sh --m17-rehearsal <execution_rehearsal.json>`.
3. Confirm `m18ExecutionHandoffGate.status` is `ready`.
4. Confirm `executionBoundary` is `user_operated_runtime_handoff`.
5. Confirm `desktopActionBoundary` is `user_operated_only`.
6. Confirm `tccBoundary` is `no_tcc_operation`.
7. Confirm `llmBoundary` is `no_llm_call`.
8. Confirm `actionTimeConfirmations` separates fresh observation, target
   label, exact text, and any public action label.
9. Confirm `executionChecklist` keeps pre-action observation, runtime action,
   and post-action observation as separate user-operated phases.
10. If the handoff is blocked, return to M17 and resolve the rehearsal blocker
    before preparing runtime instructions again.

Do not use this handoff to click, type, navigate, submit, post, purchase,
grant TCC, operate System Settings, or call an LLM. It is only the final
report-only checklist before a separately user-operated runtime step.

## M20 Execution Result Intake

Use this pass after the user has completed the M18-guided runtime step
manually:

1. Select the ready M18 `execution_handoff.json`.
2. Ask the user to confirm whether fresh observation, target confirmation,
   exact-text confirmation, public-action confirmation, runtime action, and
   post-action observation were completed.
3. Run
   `bash tool/run_macos_computer_use_m20_execution_result_intake.sh --m18-handoff <execution_handoff.json> --fresh-observation done --target-confirmed yes --exact-text-confirmed yes --public-action-confirmed <yes-or-not-applicable> --runtime-action succeeded --post-action-observation done`.
4. Confirm `m20ExecutionResultIntakeGate.status` is `ready`.
5. Confirm `executionBoundary` is `manual_result_intake_report_only`.
6. Confirm `desktopActionBoundary` is `user_operated_evidence_only`.
7. Confirm `tccBoundary` is `no_tcc_operation`.
8. Confirm `llmBoundary` is `no_llm_call`.
9. If the intake is blocked, resolve the listed result evidence blocker before
   accepting the runtime result.
10. Review the MVP sign-off handoff or readiness artifact index before final
    aggregation; blocked discovered `m20_execution_result_intake` evidence
    stops final aggregation until the intake is ready.

Do not use this intake to click, type, navigate, submit, post, purchase, grant
TCC, operate System Settings, or call an LLM. It records only user-reported
runtime result evidence. Follow-up actions require a new approval-bound cycle.

## M22 Post-Action Review

Use this pass after the M20 execution result intake is ready:

1. Select the ready M20 `execution_result_intake.json`.
2. Ask the user to review the runtime result and classify the post-action
   state as `stable` or `needs-follow-up`.
3. Ask whether a follow-up action cycle is required. If yes, record a short
   follow-up note.
4. Run
   `bash tool/run_macos_computer_use_m22_post_action_review.sh --m20-intake <execution_result_intake.json> --result-reviewed yes --post-action-state <stable-or-needs-follow-up> --follow-up-required <yes-or-no>`.
5. Confirm `m22PostActionReviewGate.status` is `ready`.
6. Confirm `executionBoundary` is `post_action_review_report_only`.
7. Confirm `desktopActionBoundary` is `no_desktop_action`.
8. Confirm `tccBoundary` is `no_tcc_operation`.
9. Confirm `llmBoundary` is `no_llm_call`.
10. If `nextCycleRecommendation` is `start_new_observe_action_cycle`, return
    to M14 observe-only evidence before proposing any follow-up action.
11. Review the MVP sign-off handoff or readiness artifact index before final
    aggregation; blocked discovered `m22_post_action_review` evidence stops
    final aggregation until the review is ready.

Do not use this review to click, type, navigate, submit, post, purchase, grant
TCC, operate System Settings, or call an LLM. It records only review evidence
for a completed user-operated runtime step.

## M23 Cycle Outcome Handoff

Use this pass after the M22 post-action review is ready:

1. Select the ready M22 `post_action_review.json`.
2. Ask the user to accept the reviewed cycle outcome.
3. If M22 recommends `start_new_observe_action_cycle`, ask for the next
   observe note and confirm `--next-observe-needed yes`.
4. If M22 recommends `no_follow_up`, confirm `--next-observe-needed no`.
5. Run
   `bash tool/run_macos_computer_use_m23_cycle_outcome_handoff.sh --m22-review <post_action_review.json> --outcome-accepted yes --next-observe-needed <yes-or-no>`.
6. Confirm `m23CycleOutcomeHandoffGate.status` is `ready`.
7. Confirm `executionBoundary` is `cycle_outcome_report_only`.
8. Confirm `desktopActionBoundary` is `no_desktop_action`.
9. Confirm `tccBoundary` is `no_tcc_operation`.
10. Confirm `llmBoundary` is `no_llm_call`.
11. If `cycleOutcome` is `restart_observe_action_cycle`, return to M14
    observe-only evidence before proposing or approving the follow-up action.

Do not use this handoff to click, type, navigate, submit, post, purchase, grant
TCC, operate System Settings, or call an LLM. It records only whether the
completed user-operated action cycle is closed or needs a new observe-only
cycle.

## M25 Next-Cycle Seed Handoff

Use this pass after M23 is ready and `cycleOutcome` is
`restart_observe_action_cycle`:

1. Select the ready M23 `cycle_outcome_handoff.json`.
2. Confirm `nextObserveSeed.required` is `true`.
3. Confirm `nextObserveSeed.returnMilestone` is `M14`.
4. Confirm `nextObserveSeed.boundary` is `observe_only_no_desktop_action`.
5. Ask the user to accept the next M14 observe seed.
6. Run
   `bash tool/run_macos_computer_use_m25_next_cycle_seed_handoff.sh --m23-handoff <cycle_outcome_handoff.json> --seed-accepted yes`.
7. Confirm `m25NextCycleSeedHandoffGate.status` is `ready`.
8. Confirm `executionBoundary` is `next_cycle_seed_report_only`.
9. Confirm `desktopActionBoundary` is `no_desktop_action`.
10. Confirm `tccBoundary` is `no_tcc_operation`.
11. Confirm `llmBoundary` is `no_llm_call`.
12. Use `nextCycleSeed.note` as the seed for the next M14 observe-only pass.

Do not use this handoff to start M14, open apps, capture screens, click, type,
navigate, submit, post, purchase, grant TCC, operate System Settings, or call
an LLM. It only freezes the next observe-only seed for a new approval-bound
cycle.

## M26 Observe Restart Packet

Use this pass after M25 is ready and the next M14 observe-only pass needs a
report-only preparation packet:

1. Select the ready M25 `next_cycle_seed_handoff.json`.
2. Confirm `nextCycleSeed.returnMilestone` is `M14`.
3. Confirm `nextCycleSeed.boundary` is `observe_only_no_desktop_action`.
4. Confirm `seedInputs.seedAccepted` is `yes`.
5. Choose the target app for the next observe pass.
6. Use the M25 seed note as the target intent unless a clearer intent is
   needed.
7. Run
   `bash tool/run_macos_computer_use_m26_observe_restart_packet.sh --m25-handoff <next_cycle_seed_handoff.json> --target-app <target-app>`.
8. Confirm `m26ObserveRestartPacketGate.status` is `ready`.
9. Confirm `executionBoundary` is `m14_observe_restart_packet_report_only`.
10. Confirm `desktopActionBoundary` is `no_desktop_action`.
11. Confirm `tccBoundary` is `no_tcc_operation`.
12. Confirm `llmBoundary` is `no_llm_call`.
13. Ask the user to manually prepare the target app state and screenshot before
    running the generated M14 observe-only canary command.

Do not use this packet to start M14, open apps, capture screens, click, type,
navigate, submit, post, purchase, grant TCC, operate System Settings, or call
an LLM. It only prepares the command set and user-operated screenshot
instructions for the next observe-only cycle.

## M27 Screenshot Request Handoff

Use this pass after M26 is ready and the next M14 observe-only pass needs a
frozen manual screenshot request:

1. Select the ready M26 `observe_restart_packet.json`.
2. Confirm `m26ObserveRestartPacketGate.status` is `ready`.
3. Confirm `nextObservePreparation.returnMilestone` is `M14`.
4. Confirm `nextObservePreparation.boundary` is
   `observe_only_no_desktop_action`.
5. Confirm `nextObservePreparation.screenshotRequired` is `true`.
6. Run
   `bash tool/run_macos_computer_use_m27_screenshot_request_handoff.sh --m26-packet <observe_restart_packet.json>`.
7. Confirm `m27ScreenshotRequestHandoffGate.status` is `ready`.
8. Confirm `executionBoundary` is `manual_screenshot_request_report_only`.
9. Confirm `desktopActionBoundary` is `no_desktop_action`.
10. Confirm `tccBoundary` is `no_tcc_operation`.
11. Confirm `llmBoundary` is `no_llm_call`.
12. Ask the user to manually prepare the target app, capture the requested
    screenshot, and run the generated M14 observe-only canary command.

Do not use this handoff to start M14, open apps, capture screens, click, type,
navigate, submit, post, purchase, grant TCC, operate System Settings, or call
an LLM. It only freezes the manual screenshot request for the next
observe-only cycle.

## M28 Screenshot Evidence Intake

Use this pass after M27 is ready and the user has manually captured the target
app screenshot for the next M14 observe-only pass:

1. Select the ready M27 `screenshot_request_handoff.json`.
2. Confirm `m27ScreenshotRequestHandoffGate.status` is `ready`.
3. Confirm `userScreenshotRequest.returnMilestone` is `M14`.
4. Confirm `userScreenshotRequest.boundary` is
   `observe_only_no_desktop_action`.
5. Confirm the user-provided screenshot file exists.
6. Run
   `bash tool/run_macos_computer_use_m28_screenshot_evidence_intake.sh --m27-handoff <screenshot_request_handoff.json> --screenshot <user-provided-real-app-screenshot.png>`.
7. Confirm `m28ScreenshotEvidenceIntakeGate.status` is `ready`.
8. Confirm `executionBoundary` is
   `manual_screenshot_evidence_intake_report_only`.
9. Confirm `desktopActionBoundary` is `no_desktop_action`.
10. Confirm `tccBoundary` is `no_tcc_operation`.
11. Confirm `llmBoundary` is `no_llm_call`.
12. Use the generated M14 observe-only canary command when the next observe
    pass is ready to run.

Do not use this intake to start M14, open apps, capture screens, click, type,
navigate, submit, post, purchase, grant TCC, operate System Settings, or call
an LLM. It only binds a user-provided screenshot path to the next
observe-only cycle.

## M29 Observe Canary Run Packet

Use this pass after M28 is ready and before asking the user to run the next M14
observe-only canary:

1. Select the ready M28 `screenshot_evidence_intake.json`.
2. Confirm `m28ScreenshotEvidenceIntakeGate.status` is `ready`.
3. Confirm `nextObserveInput.returnMilestone` is `M14`.
4. Confirm `nextObserveInput.boundary` is `observe_only_no_desktop_action`.
5. Confirm the screenshot path recorded in M28 still exists and is non-empty.
6. Run
   `bash tool/run_macos_computer_use_m29_observe_canary_run_packet.sh --m28-intake <screenshot_evidence_intake.json>`.
7. Confirm `m29ObserveCanaryRunPacketGate.status` is `ready`.
8. Confirm `executionBoundary` is
   `m14_observe_canary_run_packet_report_only`.
9. Confirm `desktopActionBoundary` is `no_desktop_action`.
10. Confirm `tccBoundary` is `no_tcc_operation`.
11. Confirm `llmBoundary` is `no_llm_call`.
12. Ask the user to run the generated M14 observe-only command when they are
    ready to collect the next evidence artifact.

Do not use this packet to run M14, open apps, capture screens, click, type,
navigate, submit, post, purchase, grant TCC, operate System Settings, or call
an LLM. It only freezes the user-operated M14 command and keeps the next step
explicit.

## M30 Observe Result Intake

Use this pass after the user has manually run the M14 observe-only canary from
the ready M29 run packet:

1. Select the ready M29 `observe_canary_run_packet.json`.
2. Select the user-produced M14 real-app observe `canary_summary.json`.
3. Confirm `m29ObserveCanaryRunPacketGate.status` is `ready`.
4. Confirm the M29 run packet returns to `M14` and keeps
   `observe_only_no_desktop_action`.
5. Confirm the M14 summary reports `milestone: M14`.
6. Confirm `m14EvidenceGate.status` is `ready`.
7. Confirm the M14 target app, target intent, and screenshot path match the
   M29 run packet.
8. Run
   `bash tool/run_macos_computer_use_m30_observe_result_intake.sh --m29-packet <observe_canary_run_packet.json> --m14-summary <canary_summary.json>`.
9. Confirm `m30ObserveResultIntakeGate.status` is `ready`.
10. Confirm `executionBoundary` is
    `m14_observe_result_intake_report_only`.
11. Confirm `desktopActionBoundary` is `no_desktop_action`.
12. Confirm `tccBoundary` is `no_tcc_operation`.
13. Confirm `llmBoundary` is `no_llm_call`.
14. Use the generated M15 action proposal command for the next report-only
    approval-bound handoff.

Do not use this intake to rerun M14, call an LLM, open apps, capture screens,
click, type, navigate, submit, post, purchase, grant TCC, or operate System
Settings. It only validates the user-produced M14 result and prepares the next
M15 command.

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
