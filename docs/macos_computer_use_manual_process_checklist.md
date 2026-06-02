# macOS Computer Use Manual Process Checklist

Use this checklist only after building a local macOS app. The steps are
user-operated because they inspect Dock state, foreground overlay behavior, and
macOS TCC surfaces.

## Commands

Manual TCC handoff preview command:

```bash
bash tool/run_macos_computer_use_manual_tcc_signoff.sh --handoff-only
```

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
dart run tool/macos_computer_use_manual_tcc_report.dart <user-produced-m8-report-or-summary.json>
```

When the parsed summary is ready, it includes the next automation-safe release
readiness and next-step navigator commands under `nextAutomationSafeCommands`.

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

## macOS Spaces Canary

Use this pass when validating multi-desktop Computer Use behavior for macOS
Spaces:

1. Launch Caverno.app and keep `Caverno Computer Use.app` running.
2. For the baseline observe-only pass, run:

   ```bash
   bash tool/run_macos_computer_use_spaces_canary.sh
   ```

3. For two-Space evidence, manually create or select at least two macOS Spaces.
4. Put a harmless target window on a non-active Space.
5. Run:

   ```bash
   bash tool/run_macos_computer_use_spaces_canary.sh --require-inactive-space-window
   ```

6. Confirm `spacesCanaryGate.status` is `ready`.
7. Confirm `desktopActionBoundary` is `no_desktop_action_observe_only`.
8. Confirm `requiresApprovedInputBeforeSwitching` is true.
9. Do not click, type, focus windows, switch Spaces, grant TCC, or operate
   System Settings from this canary. Any future Space switch must be explicitly
   approved and followed by a fresh `computer_vision_observe`.

For a user-operated focus check:

1. Complete the two-Space setup above with a target window from an app that is
   not visible on the active Space.
2. Confirm Accessibility is granted to the expected helper path.
3. Run:

   ```bash
   bash tool/run_macos_computer_use_spaces_canary.sh --focus-inactive-space-window
   ```

4. Confirm `spacesFocusCanaryGate.status` is `ready`.
5. Confirm `desktopActionBoundary` is
   `user_operated_focus_only_no_pointer_or_text`.
6. Confirm no pointer movement, click, text input, submit, public action, TCC
   grant, or System Settings operation occurred.
7. Run a fresh `computer_vision_observe` before any later pointer or keyboard
   input proposal.

For a user-operated Space switch check:

1. Prepare an adjacent macOS Space with a different harmless window.
2. Confirm the Mission Control Control-Left/Right keyboard shortcuts are
   enabled.
3. Run one direction:

   ```bash
   bash tool/run_macos_computer_use_spaces_canary.sh --switch-space-next
   bash tool/run_macos_computer_use_spaces_canary.sh --switch-space-previous
   ```

4. Confirm `spacesSwitchCanaryGate.status` is `ready`.
5. Confirm `desktopActionBoundary` is
   `user_operated_space_switch_keypress_no_pointer_or_text`.
6. Confirm the report shows `activeWindowInventoryChanged` as true.
7. Confirm no pointer movement, click, text input, submit, public action, TCC
   grant, or System Settings operation occurred.
8. Run a fresh `computer_vision_observe` before any later pointer or keyboard
   input proposal.

For product release readiness, provide the latest
`macos_computer_use_spaces_canary_summary` to the artifact index. It should
come from a handoff preview followed by a run such as
`bash tool/run_macos_computer_use_spaces_canary.sh --require-inactive-space-window --switch-space-next --release-helper-signoff --handoff-only`
and then
`bash tool/run_macos_computer_use_spaces_canary.sh --require-inactive-space-window --switch-space-next --release-helper-signoff`
or the equivalent previous-Space direction, with
`requiresApprovedInputBeforeSwitching` true. Ready summaries include
`nextAutomationSafeCommands` for refreshing the artifact index and M31
next-step navigator after the user-operated run.

## M33 Release Packaging Report

Run this static packaging report before asking for a signed release pass:

```bash
bash tool/run_macos_computer_use_release_packaging.sh
```

Expected outputs:

- `build/integration_test_reports/macos_computer_use_release_packaging.json`
- `build/integration_test_reports/macos_computer_use_release_packaging.md`

The report checks the helper embed phase, LaunchAgent BundleProgram,
MachServices declaration, release entitlements, hardened runtime settings,
identity-free signing defaults, Sparkle update dependency, appcast
configuration, the notarized Sparkle release driver, and the S3 publish helper.
It does not sign, notarize, staple, grant TCC, launch System Settings, upload
appcasts, or perform desktop actions. Signing identity, notarization ticket,
stapler validation, appcast publishing, TCC grants, and real desktop evidence
remain user-operated release evidence.

Before rerunning the M7 release artifact sign-off after a signing blocker:

1. Run `bash tool/run_macos_computer_use_release_signing_preflight.sh`.
2. Confirm `security find-identity -v -p codesigning` lists a valid macOS code
   signing identity.
3. Copy `macos/Runner/Configs/Signing.local.xcconfig.example` to the ignored
   `macos/Runner/Configs/Signing.local.xcconfig`.
4. Include `DEVELOPMENT_TEAM`, `CODE_SIGN_STYLE = Manual`, and a non-ad-hoc
   `CODE_SIGN_IDENTITY`.
5. Rebuild the release app, then rerun
   `bash tool/run_macos_computer_use_smoke_test.sh --m7-signoff`.

For Sparkle distribution after M7/M33 readiness, use the release driver:

```bash
bash tool/run_macos_sparkle_s3_preflight.sh
```

```bash
bash tool/build_macos_sparkle_release.sh \
  --notary-profile caverno-notary \
  --package zip \
  --download-url-prefix https://caverno-macos-releases.s3.amazonaws.com/caverno/macos \
  --s3-uri s3://caverno-macos-releases/caverno/macos
```

The release driver re-signs Sparkle's bundled updater app, XPC services, and
Autoupdate helper with the selected Developer ID identity before notarization.
Override the resolved identity with `CAVERNO_MACOS_CODESIGN_IDENTITY` only when
multiple Developer ID certificates are available in the keychain.

For a no-upload rehearsal with dummy S3 and HTTPS coordinates:

```bash
bash tool/run_macos_sparkle_staging_rehearsal.sh
```

The artifact index reads
`build/integration_test_reports/macos_computer_use_release_signing_preflight.json`.
If M7 is blocked by LaunchAgent signing constraints, the next-step navigator
uses the preflight report to distinguish missing local overrides from a release
artifact smoke-test regression.

Treat `ad_hoc_signature` and `team_identifier_missing` as release signing setup
blockers, not as helper IPC or Spaces regressions.

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
6. Confirm `Permission owners` separates Accessibility on the helper from
   Screen & System Audio Recording on `Caverno.app`.
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

## M35 Production Action Policy

Use this static pass before any production desktop action is considered ready:

1. Confirm `computer_vision_observe` returns `productionActionPolicy`.
2. Confirm the policy `phaseOrder` is `observe`, `approval_packet`,
   `action_time_confirmation`, `emergency_stop_available`,
   `execution_result_intake`, and `post_action_review`.
3. Confirm public actions require a separate `public_action_label` approval
   even when `target_label` and exact text have already been approved.
4. Confirm `emergencyStopRequired` and `postActionReviewRequired` are true.
5. Confirm the debug evidence summary shows
   `M35 production action policy: defined`.
6. Confirm production hard blocks include missing fresh observation, missing or
   unapproved approval packet, missing action-time confirmation, unavailable
   emergency stop, missing execution result intake, missing post-action review,
   and missing separate public-action approval.

Do not treat this static policy as runtime permission to click, type, submit,
post, purchase, grant TCC, operate System Settings, or call an LLM. It defines
the mandatory gates that future user-operated production actions must satisfy.

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

## M36 Live LLM Evaluation

Use this pass when the broader Computer Use LLM evidence needs product-readiness
coverage beyond the MVP fixture canary:

1. Prepare a saved MVP fixture screenshot.
2. Prepare a user-captured saved real-app screenshot for the intended public
   action review.
3. Run
   `bash tool/run_macos_computer_use_m36_live_llm_eval.sh --fixture-screenshot <mvp-fixture-screenshot.png> --real-app-screenshot <user-provided-real-app-screenshot.png>`.
4. Confirm `m36LiveLlmEvaluationGate.ok` is `true`.
5. Confirm `requiredCoverage` passes for fixture screenshot, saved real-app
   screenshot, refusal, target ambiguity, exact-text preservation,
   public-action boundary preservation, and stale or blocked evidence recovery.
6. Confirm every scenario keeps `desktopActionBoundary: no_desktop_action`.
7. Confirm every scenario keeps `tccBoundary: no_tcc_operation`.
8. Confirm no scenario emits click, type, keypress, focus, submit, post, or
   other executable desktop action tools.

Do not use M36 to capture screenshots, grant TCC, click, type, navigate, submit,
post, purchase, or operate System Settings. It is only a Live LLM evaluation
artifact for Computer Use decision quality.

## M37 Audit Privacy Controls

Use this pass when Computer Use diagnostics are exported for product sign-off or
support review:

1. Copy or export Computer Use diagnostics from the Computer Use settings or
   debug surface.
2. Confirm `auditPrivacyControls.schemaName` is
   `macos_computer_use_audit_privacy_controls`.
3. Confirm `m37AuditPrivacyGate.status` is `ready`.
4. Confirm `requiredEventTypes` includes observe, approval, execution handoff,
   emergency stop, and result review.
5. Confirm `defaultExportRedacted` is `true`.
6. Confirm `explicitPayloadExportRequired` is `true`.
7. Confirm `redactedFieldIds` includes secrets, screenshots, tokens,
   audio payloads, raw tool payloads, and typed text.
8. Confirm `latestAuditCoverage` is present. It may be partial before a full
   user-operated cycle, but missing coverage should be resolved before
   production launch sign-off.

Do not include raw screenshots, audio payloads, tokens, secrets, typed text, or
raw tool payloads in ordinary diagnostics. Export those artifacts only through a
separate explicit user-approved artifact flow.

## M49 Privacy And Audit Release Pack

Use this pass after M48 has produced a ready user-operated action pilot and
redacted Computer Use diagnostics have been exported:

1. Export redacted Computer Use diagnostics from the Computer Use settings or
   debug surface.
2. Confirm the diagnostics include `auditPrivacyControls.schemaName:
   macos_computer_use_audit_privacy_controls`.
3. Confirm M48 produced a ready
   `macos_computer_use_m48_user_operated_action_pilot`.
4. Run
   `bash tool/run_macos_computer_use_m49_privacy_audit_release_pack.sh --m48-pilot <user_operated_action_pilot.json> --diagnostics <redacted-computer-use-diagnostics.json> --redacted-export-reviewed yes --privacy-copy-reviewed yes --support-diagnostics-reviewed yes --explicit-payload-export-policy-reviewed yes --payload-export-requested no --explicit-payload-export-approved not-requested`.
5. Confirm `schemaName` is
   `macos_computer_use_m49_privacy_audit_release_pack`.
6. Confirm `m49PrivacyAuditReleasePackGate.status` is `ready`.
7. Confirm ordinary diagnostics raw-payload leak checks passed.
8. If raw payload export is requested, confirm it has separate explicit
   approval and is not bundled into ordinary diagnostics.

Do not use M49 to export raw screenshots, audio payloads, tokens, secrets,
typed text, or raw tool payloads. Ordinary support diagnostics remain redacted;
raw payload export requires a separate explicit user-approved artifact flow.

## M50 Signed Beta Gate

Use this pass after M49 is ready and the signed beta build evidence is
available:

1. Write or refresh the signed beta checklist template:
   `bash tool/run_macos_computer_use_m50_signed_beta_gate.sh --write-template`.
2. Write the user-operated handoff:
   `bash tool/run_macos_computer_use_m50_signed_beta_gate.sh --handoff-only`.
3. Attach signed artifact evidence from the M7 release artifact sign-off.
4. Attach M33 release packaging evidence.
5. Attach notarization ticket and stapler validation evidence in the M50 signed
   beta checklist.
6. Ask the user to complete clean install, upgrade, permission grant,
   permission revocation, helper restart, and XPC fallback observability checks
   with the signed beta build.
7. Confirm M46 produced a ready
   `macos_computer_use_m46_element_grounded_llm_eval_summary`.
8. Confirm M48 produced a ready
   `macos_computer_use_m48_user_operated_action_pilot`.
9. Confirm M49 produced a ready
   `macos_computer_use_m49_privacy_audit_release_pack`.
10. Run
   `bash tool/run_macos_computer_use_m50_signed_beta_gate.sh --signed-beta-checklist <m50-signed-beta-checklist.json> --release-artifact-report <release-artifact-signoff.json> --release-packaging-report <macos_computer_use_release_packaging.json> --m46-element-grounded-llm-eval <canary_summary.json> --m48-user-operated-action-pilot <user_operated_action_pilot.json> --m49-privacy-audit-release-pack <privacy_audit_release_pack.json>`.
11. Confirm `schemaName` is `macos_computer_use_m50_signed_beta_gate`.
12. Confirm `signedBetaReviewSummary.status` is `ready_for_signed_beta`.
13. Confirm `m50SignedBetaGate.status` is `ready`.

Do not use M50 to sign, notarize, staple, grant TCC, open System Settings,
capture screens, click, type, navigate, submit, post, purchase, export raw
payloads, or operate desktop apps. M50 only reads signed beta checklist
evidence and existing reports.

## M51 Production Launch Gate

Use this pass after M50 signed beta evidence is ready and the production launch
checklist is ready:

1. Write or refresh the launch checklist template:
   `bash tool/run_macos_computer_use_m51_production_launch_gate.sh --write-template`.
2. Attach signed artifact evidence from the M7 release artifact sign-off.
3. Attach M33 release packaging evidence.
4. Attach notarization ticket and stapler validation evidence in the M51 launch
   checklist.
5. Attach helper identity diagnostics that include M38 install migration
   guardrails.
6. Attach manual TCC runbook evidence.
7. Attach ready M46 element-grounded LLM evaluation evidence.
8. Attach ready M49 privacy/audit release-pack evidence.
9. Attach ready M50 signed beta gate evidence.
10. Attach emergency stop, privacy copy, support diagnostics, default-off
    rollout, rollback, and support escalation sign-off in the M51 launch
    checklist.
11. Run
    `bash tool/run_macos_computer_use_m51_production_launch_gate.sh --launch-checklist <m51-launch-checklist.json> --release-artifact-report <release-artifact-signoff.json> --release-packaging-report <macos_computer_use_release_packaging.json> --manual-tcc-report <manual-tcc-summary.json> --m46-element-grounded-llm-eval <canary_summary.json> --m49-privacy-audit-release-pack <privacy_audit_release_pack.json> --m50-signed-beta-gate <macos_computer_use_m50_signed_beta_gate.json> --diagnostics <computer-use-diagnostics.json>`.
12. Confirm `schemaName` is
    `macos_computer_use_m51_production_launch_gate`.
13. Confirm `launchReviewSummary.status` is
    `ready_for_production_launch`.
14. Confirm `automationBoundary` is `read_reports_only`.

Do not use M51 to sign, notarize, staple, grant TCC, open System Settings,
capture screens, click, type, navigate, submit, post, purchase, export raw
payloads, or operate desktop apps. M51 only reads launch checklist evidence
and existing reports.

## M38 Install And Migration Guardrails

Use this pass before validating an upgraded or newly installed Computer Use
build:

1. Open the Computer Use setup or debug surface.
2. Confirm exported diagnostics include
   `installMigrationGuardrails.schemaName:
   macos_computer_use_install_migration_guardrails`.
3. Confirm `installMigrationGuardrails.milestone` is `M38`.
4. Confirm `installMigrationGuardrails.oldHelperActionRequestsBlocked` is
   `true`.
5. If `helperPathMismatch` or stale helper path diagnostics are present,
   confirm the UI explains that helper Accessibility grants are tied to the
   helper app identity and that regrant may be required only after the user
   restarts from the installed Caverno bundle.
6. Confirm old or mismatched helpers can still report status, show permission
   recovery UI, and accept emergency stop, but do not handle screenshot,
   window, pointer, keyboard, or system-audio action requests.

Expected M38 fields:

- `installMigrationGuardrails.status`: `ready` or `blocked`
- `installMigrationGuardrails.m38InstallMigrationGate.blockers`
- `installMigrationGuardrails.tccRegrantRequired`
- `installMigrationGuardrails.tccRegrantReason`
- `installMigrationGuardrails.oldHelperActionRequestsBlocked`: `true`

## M39 Internal Beta Sign-Off

Use this pass after M36 Live LLM evaluation and at least one complete
user-operated observe-approve-execute-review cycle are available:

1. Write or refresh the manual beta checklist template:
   `bash tool/run_macos_computer_use_m39_beta_signoff.sh --write-template`.
2. Ask the user to complete clean install, upgrade, permission grant,
   permission revocation, helper restart, and XPC fallback observability checks.
3. Save the completed checklist with
   `schemaName: macos_computer_use_m39_manual_beta_checklist`.
4. Confirm M36 produced a ready
   `macos_computer_use_m36_live_llm_eval_summary` with
   `desktopActionBoundary: no_desktop_action`.
5. Confirm M23 produced a ready
   `macos_computer_use_m23_cycle_outcome_handoff` for one reviewed
   user-operated action cycle.
6. Run
   `bash tool/run_macos_computer_use_m39_beta_signoff.sh --manual-beta-checklist <m39-manual-beta-checklist.json> --m36-live-llm-eval <canary_summary.json> --m23-cycle-outcome <cycle_outcome_handoff.json>`.
7. Confirm `schemaName` is `macos_computer_use_m39_beta_signoff`.
8. Confirm `betaReviewSummary.status` is `ready_for_internal_beta`.
9. Confirm `automationBoundary` is `read_reports_only`.

Do not use M39 to grant TCC, open System Settings, capture screens, click,
type, navigate, submit, post, purchase, or operate desktop apps. M39 only reads
existing reports and user-provided beta checklist evidence.

## M40 Production Launch Gate

Use this pass only when the release checklist is ready to decide whether
Computer Use can ship to production:

1. Write or refresh the launch checklist template:
   `bash tool/run_macos_computer_use_m40_production_launch_gate.sh --write-template`.
2. Attach signed artifact evidence from the M7 release artifact sign-off.
3. Attach M33 release packaging evidence.
4. Attach notarization ticket and stapler validation evidence in the M40 launch
   checklist.
5. Attach helper identity diagnostics that include M38 install migration
   guardrails.
6. Attach manual TCC runbook evidence.
7. Attach ready M36 Live LLM evaluation evidence.
8. Attach ready M37 audit/privacy diagnostics and confirm the launch checklist
   records audit export sign-off.
9. Attach emergency stop, privacy copy, and support diagnostics sign-off in the
   M40 launch checklist.
10. Attach ready M39 internal beta sign-off evidence.
11. Run
    `bash tool/run_macos_computer_use_m40_production_launch_gate.sh --launch-checklist <m40-launch-checklist.json> --release-artifact-report <release-artifact-signoff.json> --release-packaging-report <macos_computer_use_release_packaging.json> --manual-tcc-report <manual-tcc-summary.json> --m36-live-llm-eval <canary_summary.json> --m39-beta-signoff <macos_computer_use_m39_beta_signoff.json> --diagnostics <computer-use-diagnostics.json>`.
12. Confirm `schemaName` is
    `macos_computer_use_m40_production_launch_gate`.
13. Confirm `launchReviewSummary.status` is
    `ready_for_production_launch`.
14. Confirm `automationBoundary` is `read_reports_only`.

Do not use M40 to notarize, grant TCC, open System Settings, capture screens,
click, type, navigate, submit, post, purchase, or operate desktop apps. M40 only
reads release checklist evidence and existing reports.

## M52 Product Release Rollout

Use this pass only after M51 is ready to decide whether element-grounded
Computer Use can ship through the product release rollout:

1. Write or refresh the product release checklist template:
   `bash tool/run_macos_computer_use_m52_product_release_rollout.sh --write-template`.
2. Confirm Computer Use remains default off for product release.
3. Confirm the only product enablement path remains Settings > Advanced.
4. Confirm the disable path and emergency stop behavior are reversible and
   ready for support use.
5. Attach rollback runbook and support runbook sign-off notes.
6. Attach privacy copy, release notes, support diagnostics handoff, rollout
   owner, monitoring, and escalation sign-off notes.
7. Attach ready M51 production launch gate evidence.
8. Run
   `bash tool/run_macos_computer_use_m52_product_release_rollout.sh --product-release-checklist <m52-product-release-checklist.json> --m51-production-launch-gate <macos_computer_use_m51_production_launch_gate.json>`.
9. Confirm `schemaName` is
   `macos_computer_use_m52_product_release_rollout`.
10. Confirm `releaseRolloutSummary.status` is
    `ready_for_product_release`.
11. Confirm `automationBoundary` is `read_reports_only`.

Do not use M52 to grant TCC, open System Settings, capture screens, click,
type, navigate, submit, post, purchase, export raw payloads, or operate desktop
apps. M52 only reads M51 launch evidence and user-operated product release
checklist evidence.

## M53 Post-Release Guardrails

Use this pass after M52 is ready and on the scheduled post-release review
cadence:

1. Write or refresh the post-release checklist template:
   `bash tool/run_macos_computer_use_m53_post_release_guardrails.sh --write-template`.
2. Confirm M52 product release rollout evidence is ready.
3. Confirm Computer Use remains default off after release.
4. Confirm the only enablement path remains Settings > Advanced.
5. Review redacted support diagnostics, known issues, incidents, complaints,
   regressions, and user-impacting failures.
6. Confirm rollback, disable path, emergency stop, hotfix triggers, rollout
   pause triggers, and escalation coverage remain ready.
7. Run
   `bash tool/run_macos_computer_use_m53_post_release_guardrails.sh --post-release-checklist <m53-post-release-checklist.json> --m52-product-release-rollout <macos_computer_use_m52_product_release_rollout.json>`.
8. Confirm `schemaName` is
   `macos_computer_use_m53_post_release_guardrails`.
9. Confirm `postReleaseGuardrailsSummary.status` is
   `ready_for_post_release_operations`.
10. Confirm `automationBoundary` is `read_reports_only`.

Do not use M53 to grant TCC, open System Settings, capture screens, click,
type, navigate, submit, post, purchase, export raw payloads, or operate desktop
apps. M53 only reads M52 rollout evidence and user-operated post-release
checklist evidence.

## M54 Rollout Expansion Gate

Use this pass after M53 is ready and before broadening the Computer Use rollout
beyond the currently approved cohort:

1. Write or refresh the rollout expansion checklist template:
   `bash tool/run_macos_computer_use_m54_rollout_expansion_gate.sh --write-template`.
2. Confirm M53 post-release guardrail evidence is ready.
3. Confirm the proposed expansion scope, cohort, channel, or percentage.
4. Review cohort risk, excluded segments, support capacity, escalation
   coverage, safety metrics, incidents, complaints, and regressions.
5. Confirm rollback, rollout pause, disable path, emergency stop, hotfix
   triggers, release notes, support copy, user communication, rollout owner,
   support owner, and escalation handoff remain ready.
6. Schedule the next post-expansion review and evidence owner.
7. Run
   `bash tool/run_macos_computer_use_m54_rollout_expansion_gate.sh --rollout-expansion-checklist <m54-rollout-expansion-checklist.json> --m53-post-release-guardrails <macos_computer_use_m53_post_release_guardrails.json>`.
8. Confirm `schemaName` is
   `macos_computer_use_m54_rollout_expansion_gate`.
9. Confirm `rolloutExpansionSummary.status` is
   `ready_for_rollout_expansion`.
10. Confirm `automationBoundary` is `read_reports_only`.

Do not use M54 to grant TCC, open System Settings, capture screens, click,
type, navigate, submit, post, purchase, export raw payloads, or operate desktop
apps. M54 only reads M53 guardrail evidence and user-operated rollout expansion
checklist evidence.

## M55 Post-Expansion Monitoring Gate

Use this pass after M54 is ready and after the approved rollout expansion has
run for its monitoring window:

1. Write or refresh the post-expansion monitoring checklist template:
   `bash tool/run_macos_computer_use_m55_post_expansion_monitoring_gate.sh --write-template`.
2. Confirm M54 rollout expansion gate evidence is ready.
3. Record the expanded cohort, channel, percentage, and elapsed monitoring
   window.
4. Review safety metrics, support volume, support response time, escalation
   load, incidents, complaints, regressions, and user-impacting failures.
5. Confirm rollback, rollout pause, disable path, hotfix, emergency stop,
   owner follow-up, and escalation handoff remain ready.
6. Approve one continuation decision: `continue_expansion`,
   `hold_current_cohort`, `pause_rollout`, or `rollback_recommended`.
7. Schedule the next monitoring review and evidence owner.
8. Run
   `bash tool/run_macos_computer_use_m55_post_expansion_monitoring_gate.sh --post-expansion-monitoring-checklist <m55-post-expansion-monitoring-checklist.json> --m54-rollout-expansion-gate <macos_computer_use_m54_rollout_expansion_gate.json>`.
9. Confirm `schemaName` is
   `macos_computer_use_m55_post_expansion_monitoring_gate`.
10. Confirm `postExpansionMonitoringSummary.status` is
    `ready_for_post_expansion_decision`.
11. Confirm `automationBoundary` is `read_reports_only`.

Do not use M55 to grant TCC, open System Settings, capture screens, click,
type, navigate, submit, post, purchase, export raw payloads, or operate desktop
apps. M55 only reads M54 rollout expansion evidence and user-operated
post-expansion monitoring checklist evidence.

## M56 Rollout Decision Handoff Gate

Use this pass after M55 is ready and the rollout continuation decision needs a
user-operated branch handoff:

1. Write or refresh the rollout decision handoff checklist template:
   `bash tool/run_macos_computer_use_m56_rollout_decision_handoff_gate.sh --write-template`.
2. Confirm M55 post-expansion monitoring gate evidence is ready.
3. Record the M55 decision scope, affected cohort, and evidence window.
4. Confirm the decision branch handoff matches the M55 decision:
   `continue_expansion` to `next_expansion_cycle_seed`,
   `hold_current_cohort` to `monitoring_cadence_hold`, `pause_rollout` to
   `rollout_pause_handoff`, or `rollback_recommended` to `rollback_handoff`.
5. Confirm the handoff owner, evidence archive, user communication review,
   branch risk controls, and next review are ready.
6. Run
   `bash tool/run_macos_computer_use_m56_rollout_decision_handoff_gate.sh --rollout-decision-handoff-checklist <m56-rollout-decision-handoff-checklist.json> --m55-post-expansion-monitoring-gate <macos_computer_use_m55_post_expansion_monitoring_gate.json>`.
7. Confirm `schemaName` is
   `macos_computer_use_m56_rollout_decision_handoff_gate`.
8. Confirm `rolloutDecisionHandoffSummary.status` is
   `ready_for_rollout_decision_handoff`.
9. Confirm `automationBoundary` is `read_reports_only`.

Do not use M56 to grant TCC, open System Settings, capture screens, click,
type, navigate, submit, post, purchase, export raw payloads, or operate desktop
apps. M56 only reads M55 post-expansion monitoring evidence and
user-operated rollout decision handoff checklist evidence.

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
4. Confirm the Accessibility overlay drags `Caverno Computer Use.app`.
5. Confirm the Screen & System Audio Recording overlay drags `Caverno.app`.
6. Confirm the overlay remains visible while System Settings is active.
7. Use the overlay back button to return to onboarding.

Expected overlay fields:

- `overlaySmoke.status`: `ready`
- `overlayForegroundPolicy`: `accessory_overlay_front`
- `overlayIsFloatingPanel`: `true`
- `overlayHidesOnDeactivate`: `false`
- `overlayCollectionBehavior`: includes `canJoinAllSpaces`,
  `fullScreenAuxiliary`, and `transient`

Do not automate TCC grants. If TCC verification is needed, ask the user to run
the relevant manual smoke command and provide the generated report.
