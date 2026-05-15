# macOS Computer Use Helper Architecture

## Status

This document defines the target split between `Caverno.app` and a separate
`Caverno Computer Use.app` helper. The helper target is bundled inside
`Caverno.app`, can be launched from the settings smoke-test panel, and now owns
permission status, System Settings shortcuts, reachability checks, emergency
stop requests, visual observation, window focus, input events, and system audio
recording. LaunchAgent-backed named XPC is the preferred production IPC
transport; distributed notifications remain an observable fallback path for
timeouts or named-service startup failures.

## Goals

- Keep chat, model configuration, memory, MCP orchestration, and network access
  in `Caverno.app`.
- Keep Accessibility, screen capture, input events, and system audio capture in
  `Caverno Computer Use.app`.
- Keep `NSSystemAudioUsageDescription` out of `Caverno.app`; the main chat app
  should not appear as the system-audio permission owner.
- Make macOS privacy prompts understandable by showing the helper name next to
  the sensitive permissions it owns.
- Make revocation and emergency stop possible without shutting down the chat
  client.
- Preserve existing built-in tool names so model prompts and settings remain
  compatible during migration.

## Non-Goals

- The helper must not host LLM calls, MCP servers, memory extraction, or chat
  persistence.
- The helper must not automatically toggle macOS privacy permissions. It may
  open System Settings and explain what the user must grant manually.
- The helper must not treat distributed-notification fallback as production IPC
  readiness. Fallback is allowed only as an observable, non-destructive recovery
  path when named XPC is unavailable.

## Roadmap

### M1: Permission-First Onboarding

The main task for M1 is the helper-owned permission overlay. `Caverno.app`
opens the onboarding flow and requests the overlay through helper IPC, but
`Caverno Computer Use.app` owns the foreground guide because it is the bundle
that receives macOS privacy grants.

The overlay is a floating helper window, not injected UI inside System Settings.
It should guide the user after the relevant Privacy & Security pane is opened,
show the exact permission owner, and provide a draggable app tile for
`Caverno Computer Use.app` when macOS requires drag-and-drop into a privacy
list.

M1 acceptance criteria:

- Accessibility and Screen & System Audio Recording actions open the targeted
  System Settings panes and show the helper-owned overlay above them.
- The overlay contains a draggable `Caverno Computer Use.app` tile backed by
  the helper app bundle URL.
- The overlay is borderless, uses a compact permission-list panel, and includes
  a left-side return arrow that animates the user back to Caverno's setup flow.
- The overlay clearly states that macOS permissions are granted to
  `Caverno Computer Use.app`, not to `Caverno.app`.
- The flow never attempts to modify TCC databases or automatically grant
  permissions.
- After the user grants permissions, `bash tool/run_macos_computer_use_smoke_test.sh --require-capture`
  and `bash tool/run_macos_computer_use_smoke_test.sh --unsafe-armed --require-input`
  are the M1 readiness checks.

Current M1 implementation status:

- `showPermissionOverlay` and `startOnboardingPermissionFlow` are available
  over helper IPC and are advertised in the XPC parity command list.
- The helper opens the targeted System Settings pane and presents a floating
  AppKit panel owned by `Caverno Computer Use.app`.
- The overlay contains a draggable helper app bundle tile and a left-side return
  arrow.
- The overlay rechecks the relevant permission locally and reports placement
  diagnostics such as `overlayPlacement`, `overlayShown`, and
  `draggableTileReady`.
- The helper onboarding `Allow` buttons open the matching System Settings pane,
  replace the selected permission row with a `COMPLETE IN SYSTEM SETTINGS`
  placeholder, and animate a snapshot of that row toward the floating overlay's
  draggable helper tile.
- The helper reports the most recent Allow transition as
  `lastOnboardingTransition`, including `transitionSourcePermission`,
  `transitionPlaceholderShown`, `transitionAnimationTarget`, and the source /
  target frames used by the animation.
- When System Settings is visible, the floating overlay prefers the lower
  permission-list area and reports `overlayPlacement` as
  `system_settings_permission_list`.
- Overlay readiness is covered by the live smoke gate. Remaining M1 validation
  is hands-on macOS UX smoke: confirm the tile can be dropped into both privacy
  lists and that the overlay placement feels stable across single-display and
  multi-display setups.

M1 overlay readiness gate:

- Run `bash tool/run_macos_computer_use_smoke_test.sh --overlay-smoke` to
  record non-strict overlay diagnostics in the live smoke report.
- Run `bash tool/run_macos_computer_use_smoke_test.sh --require-overlay` when
  marking M1 overlay readiness; this requires both Accessibility and Screen &
  System Audio Recording overlays to report `overlayShown`,
  `draggableTileReady`, and a matching permission identifier.
- The smoke report's `overlaySmoke` section records `overlayPlacement`,
  `overlayMode`, `helperBundlePath`, and `dragPasteboardTypes` so hands-on drag
  failures can be diagnosed without rerunning the full unsafe input sequence.
- The floating overlay includes an upward drag cue and aligns the onboarding
  transition target with the actual draggable helper tile.
- The floating overlay is borderless so it does not show macOS traffic-light
  window controls. Its left-side arrow animates the overlay back to the main
  onboarding window and refreshes permission rows.
- The overlay uses a wide, short panel with a looping upward pull cue on the
  drag arrow.
- Run `bash tool/run_macos_computer_use_smoke_test.sh --require-onboarding-transition`
  to invoke the helper-owned onboarding permission flow and prove that the row
  placeholder was shown and the animation targeted the permission overlay
  window.
- Main-app helper diagnostics now include `embeddedHelperPath`,
  `runningHelperPath`, and `helperPathMismatch` so debug builds can detect when
  macOS relaunched a different `Caverno Computer Use.app` path than the one
  Caverno is configured to open.
- Hands-on sign-off still requires dragging the tile into both macOS privacy
  lists because macOS does not expose a supported API for granting or fully
  simulating TCC list drops.

M1 sign-off checklist:

- `bash tool/run_macos_computer_use_smoke_test.sh --require-overlay` passes.
- `bash tool/run_macos_computer_use_smoke_test.sh --require-onboarding-transition`
  passes by invoking the helper-owned onboarding permission flow.
- Accessibility overlay drop is accepted by macOS when dragged into the
  privacy list.
- Screen & System Audio Recording overlay drop is accepted by macOS when
  dragged into the privacy list.
- `bash tool/run_macos_computer_use_smoke_test.sh --require-capture` passes
  after Screen & System Audio Recording is granted.
- `bash tool/run_macos_computer_use_smoke_test.sh --unsafe-armed --require-input`
  passes after Accessibility is granted.
- `bash tool/run_macos_computer_use_smoke_test.sh --require-capture` remains
  blocked until Screen Recording is granted to the exact helper bundle path
  reported in the smoke diagnostics.
- `bash tool/run_macos_computer_use_capture_signoff.sh --reveal-helper --open-settings`
  opens the current helper bundle in Finder, opens the Screen Recording privacy
  pane, and prints the expected helper path before the manual grant.
- `bash tool/run_macos_computer_use_existing_helper_probe.sh --require-capture`
  can be used after a successful grant to verify the existing built helper
  without triggering another Flutter rebuild.
- Add `--require-helper-path-match` to the existing-helper probe when the
  sign-off must prove that the currently running helper is the same bundle path
  Caverno will launch.
- Add `--replace-helper` when the probe should terminate a running helper from
  a different path and launch the configured helper path before checking.

Current M1 status:

- Overlay readiness, onboarding transition readiness, Accessibility-backed
  non-destructive input readiness, and screen capture readiness are signed off
  for the current debug embedded helper.
- The current helper path matches the helper bundle embedded in the debug
  `Caverno.app` build.
- M1 is complete for the debug embedded helper after the 2026-04-29 M4 sign-off
  run. Release builds still need their own TCC grant and smoke pass because
  macOS records privacy grants per signed bundle path and identity.

The drag/drop sign-off is intentionally manual. Adding the helper to macOS
privacy lists changes system privacy settings, so it must only happen after an
explicit action-time confirmation from the person operating the Mac.

Manual sign-off notes:

- 2026-04-28: `bash tool/run_macos_computer_use_smoke_test.sh --overlay-smoke`
  passed after the tile-target transition update. Both Accessibility and Screen
  & System Audio Recording overlays reported `overlayShown`,
  `draggableTileReady`, and matching permission identifiers. The current debug
  helper path still needs Screen Recording before capture readiness can pass.
- 2026-04-28: `bash tool/run_macos_computer_use_smoke_test.sh --require-overlay`
  passed with both permission overlays reporting `overlayShown` and
  `draggableTileReady`.
- 2026-04-28: `bash tool/run_macos_computer_use_smoke_test.sh --require-onboarding-transition`
  passed by invoking the helper-owned `startOnboardingPermissionFlow` command.
  The smoke report recorded `transitionPlaceholderShown: true`,
  `transitionAnimationTarget: permission_overlay_window`, and
  `transitionOverlayPlacement: system_settings_permission_list`.
- 2026-04-28: `bash tool/run_macos_computer_use_smoke_test.sh --unsafe-armed --require-input`
  passed the required non-destructive input checks: pointer movement, pointer
  drag, scroll, and key press.
- 2026-04-28: `bash tool/run_macos_computer_use_smoke_test.sh --require-capture`
  failed as expected with `screen_capture_permission_missing`; rerun it after
  granting Screen Recording to the exact `Caverno Computer Use.app` helper path
  shown in the smoke report.
- 2026-04-28: `bash tool/run_macos_computer_use_existing_helper_probe.sh --require-helper-path-match --require-capture`
  confirmed `helperPathMatchesExpected: true`, `inputReady: true`, and
  `captureReady: false`. The probe failed only because the required capture
  gate was blocked by `screenCaptureGranted: false`; it also confirmed
  display screenshots still work while window capture requires Screen
  Recording.
- 2026-04-28: System Settings accepted `Caverno Computer Use.app` through the
  standard Add flow for Accessibility and Screen & System Audio Recording.
  After restarting the helper, the helper onboarding UI reported both
  permissions as `Done`.
- 2026-04-28: The helper onboarding UI **Verify** action completed display and
  window observation checks: display screenshot `3600 x 2338 px` and window
  capture `Codex #203679`.
- 2026-04-29: `bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --register-xpc-agent --strict-xpc`
  passed with `xpcProductionOk: true`, `namedServiceConnected: true`,
  `launchAgentEnabled: true`, and no `xpcRuntimeDiagnostics` blockers.
- 2026-04-29: `bash tool/run_macos_computer_use_capture_signoff.sh --replace-helper --require-capture --verbose-probe`
  passed for the debug embedded helper path after Screen & System Audio
  Recording was granted. The probe reported `helperPathMatchesExpected: true`,
  `captureReady: true`, and `inputReady: true`.
- 2026-04-29: `bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --m4-signoff`
  passed the combined sign-off gate with `m4SignoffGate.status: ready`,
  `blockers: []`, matching embedded and running helper paths, required capture,
  required overlay readiness, required onboarding transition readiness, system
  audio readiness, and LaunchAgent named XPC readiness.
- Drag/drop tile acceptance remains a separate hands-on check. The successful
  permission grant above used the macOS Add flow because the running debug
  helper path must match the exact helper bundle that macOS records in TCC.

Drag/drop sign-off runbook:

- Run `bash tool/run_macos_computer_use_existing_helper_probe.sh --replace-helper --require-helper-path-match`
  and confirm the running helper path is the helper bundle intended for
  sign-off.
- If the path check passes but permissions are missing, grant that exact helper
  bundle in System Settings before continuing.
- For a guided capture grant, run
  `bash tool/run_macos_computer_use_capture_signoff.sh --reveal-helper --open-settings`.
  This does not change macOS privacy settings; it only reveals the helper path,
  opens the Screen Recording pane, and prints the current capture status.
- Use `bash tool/run_macos_computer_use_capture_signoff.sh --replace-helper --require-capture`
  for embedded-helper sign-off. A passing standalone helper result is not a
  valid embedded-helper sign-off, even when the bundle identifier matches.
- Run `bash tool/run_macos_computer_use_smoke_test.sh --require-overlay` to
  show both overlays and confirm `draggableTileReady` is true.
- Drag the overlay tile into Accessibility and Screen & System Audio Recording.
  Record whether macOS accepts the drop, requests Quit & Reopen, or requires the
  standard Add flow fallback.
- If the drag/drop target refuses the overlay tile, use the `+` button in the
  matching privacy list and select the same helper bundle path reported by
  `helper.expectedPath` in the existing-helper probe.
- After either drag/drop or the Add flow, quit and reopen the helper if macOS
  requests it, then rerun
  `bash tool/run_macos_computer_use_capture_signoff.sh --require-capture`
  before marking Screen Recording complete.

Follow-on milestones:

- M2: Complete capture, input, optional system-audio readiness, and unsafe
  action hardening using the live smoke gates and chat approval flow.
- M3: Promote named XPC and LaunchAgent registration to the production IPC
  path.
- M4: Complete embedded-helper Screen & System Audio Recording, overlay, and
  onboarding sign-off with one strict live smoke gate.
- M5: Connect the vision LLM loop to the approved helper tool surface.
- M6: Harden the observe-action-observe loop so multimodal desktop tasks can
  safely propose, approve, execute, and verify one step at a time.
- M7: Complete release-helper sign-off against the release
  `Caverno.app/Contents/Helpers/Caverno Computer Use.app` bundle identity,
  signing chain, LaunchAgent plist, and MachService declaration.
- M8: Complete installed release runtime sign-off by launching the release
  `Caverno.app`, replacing mismatched debug app/helper processes, and verifying
  the running release helper owns Accessibility, Screen & System Audio
  Recording, screenshot capture, window listing, window capture, and system
  audio readiness.
- M9: Lock TCC verification to a user-operated manual runbook. Automation may
  prepare artifacts and parse reports, but it must not perform release runtime
  TCC sign-off on the user's behalf.
- M10: Stabilize helper IPC/runtime diagnostics so XPC timeout headroom, path
  mismatches, and Open Computer Use launch results are visible without
  re-triggering permission prompts.
- M11: Make Live LLM fixture evidence reusable by discovering saved fixture
  screenshots and recording non-secret LLM request metadata.
- M12: Add real-app observe-only canaries for Safari-style workflows. These
  canaries classify visible UI targets and public-action boundaries from
  user-provided screenshots without opening apps, clicking, typing, submitting,
  or posting.
- M13: Complete review and merge hardening after the Computer Use MVP merge.
  Keep Computer Use behind the Advanced settings flow, reduce the default
  settings surface area, verify the post-merge sanity runner, and keep the
  PR-review evidence handoff easy to inspect before merging polish changes.
- M14: Expand real-app observe-only canaries after M13. Use Safari-style
  logged-in workflows only for visual classification of targets, text fields,
  submission boundaries, and confirmation requirements. These canaries must not
  click, type, submit, post, purchase, or otherwise mutate external state.
- M15: Convert ready M14 observe-only evidence into an approval-bound action
  proposal handoff. The handoff may describe the next observe, exact text
  confirmation, target confirmation, and public-action confirmation phases, but
  it must not call an LLM, click, type, navigate, submit, post, purchase, grant
  TCC, or operate System Settings. The generated handoff includes a
  `PR Review Summary` that surfaces `blockedReviewEvidence` before final MVP
  aggregation. After the handoff is ready, the report-only M15 LLM review
  canary can ask the configured live LLM to preserve those approval boundaries
  without executing any desktop action. MVP sign-off and the readiness artifact
  index now surface that review canary as optional review evidence and block
  final aggregation when a discovered review canary is not ready.
- M16: Convert ready M15 action-proposal and review evidence into a
  report-only user approval packet. The packet records the exact text, target,
  public-action, and post-action observation approvals needed by a future
  execution milestone, but it still must not call an LLM, click, type,
  navigate, submit, post, purchase, grant TCC, or operate System Settings.
  Missing approvals are surfaced as `approvalBlockers`, while the packet gate
  remains focused on whether the M15 evidence is ready and boundary-preserving.
  MVP sign-off and the readiness artifact index surface the latest packet as
  optional review evidence and block final aggregation when a discovered packet
  is not ready.
- M17: Convert an approved M16 approval packet into a report-only execution
  rehearsal. The M17 execution rehearsal turns the approved exact text, target,
  public-action label, and post-action observation boundary into a future
  execution checklist while preserving `no_desktop_action`,
  `no_tcc_operation`, and `no_llm_call`. It blocks unless the source M16 packet
  is ready and `approvalStatus` is `approved`, and it still must not click,
  type, navigate, submit, post, purchase, grant TCC, operate System Settings,
  or call an LLM. MVP sign-off and the readiness artifact index surface the
  latest rehearsal as optional review evidence and block final aggregation when
  a discovered rehearsal is not ready.
- M18: Convert a ready M17 execution rehearsal into a user-operated execution
  handoff. The handoff records the fresh observation, target confirmation,
  exact-text confirmation, optional public-action confirmation, runtime action,
  and post-action observation checklist for a future manual execution step. It
  still must not call an LLM, click, type, navigate, submit, post, purchase,
  grant TCC, or operate System Settings; it only prepares the action-time
  confirmations that the user must perform before any runtime action.
- M19: Surface the latest M18 execution handoff in the readiness artifact index
  and MVP sign-off handoff. This keeps the runtime handoff visible to PR review
  and final aggregation without crossing the TCC, LLM, System Settings, or
  desktop-action boundary. A discovered blocked M18 handoff stops final
  aggregation until its gate next action is resolved.
- M20: Record user-operated runtime result evidence after an M18 handoff. The
  result intake is report-only and accepts user-reported fresh observation,
  action-time confirmations, runtime action status, and post-action
  observation. It blocks unless the M18 handoff is ready, the required
  confirmations are present, the runtime action is recorded as succeeded, and
  the post-action observation is recorded. It still must not call an LLM, grant
  TCC, operate System Settings, or perform desktop actions.
- M21: Surface M20 execution result intake in the readiness artifact index and
  MVP sign-off handoff. A discovered blocked M20 intake is treated as blocked
  review evidence and stops final aggregation until the result-intake gate next
  action is resolved. Missing M20 intake remains optional because the runtime
  step is user-operated and may not have happened yet.
- M22: Convert ready M20 result intake into a report-only post-action review.
  The review records that the user reviewed the runtime result, classifies the
  post-action state, and decides whether a new observe/action approval cycle is
  required. It must not call an LLM, grant TCC, operate System Settings, or
  perform desktop actions. MVP sign-off and the readiness artifact index
  surface discovered M22 reviews as optional review evidence and block final
  aggregation when a discovered review is not ready.
- M23: Convert ready M22 post-action review evidence into a report-only cycle
  outcome handoff. The handoff records whether the completed action cycle is
  closed or whether a new observe-only pass is required, keeps any follow-up
  note as the seed for the next M14 observe pass, and preserves the
  `no_desktop_action`, `no_tcc_operation`, and `no_llm_call` boundaries.
- M24: Surface M23 cycle outcome handoffs in MVP sign-off and preflight
  handoffs. Ready handoffs are visible review evidence, and discovered blocked
  handoffs stop final aggregation until the recorded M23 next action is
  resolved.
- M25: Convert a ready M23 `restart_observe_action_cycle` outcome into a
  report-only next-cycle seed handoff. The seed freezes the note, M14 return
  milestone, and `observe_only_no_desktop_action` boundary for the next
  observe pass. It does not start M14, call an LLM, grant TCC, operate System
  Settings, or perform desktop actions.
- M26: Convert a ready M25 next-cycle seed into a report-only M14 observe
  restart packet. The packet prepares the target app, target intent,
  user-operated screenshot preparation steps, and M14 observe-only commands
  without starting M14, calling an LLM, granting TCC, opening apps, operating
  System Settings, capturing screens, or performing desktop actions.
- M27: Convert a ready M26 observe restart packet into a report-only manual
  screenshot request handoff. The handoff freezes the target app, target
  intent, requested screenshot state, and M14 observe-only command so the next
  pass can stay user-operated until screenshot evidence exists.
- M28: Convert a ready M27 screenshot request handoff plus a user-provided
  screenshot file into a report-only screenshot evidence intake. The intake
  binds the screenshot path to the next M14 observe-only command without
  opening apps, capturing screens, calling an LLM, granting TCC, or performing
  desktop actions.
- M29: Convert ready M28 screenshot evidence into a report-only M14 observe
  canary run packet. The packet freezes the exact command the user can run
  next, rechecks the screenshot file, and still avoids LLM calls, TCC,
  System Settings, app launches, screen capture, and desktop actions.
- M30: Convert the ready M29 run packet plus the user-produced M14 observe
  summary into a report-only result intake. The intake validates source
  alignment, the ready M14 evidence gate, observe-only boundaries, and the
  next M15 action proposal command without calling an LLM, granting TCC,
  capturing screens, opening apps, or performing desktop actions.

## Production Roadmap After M30

M1-M30 prove the helper boundary, manual TCC workflow, observe-only evidence,
approval packets, user-operated execution handoffs, post-action review, and
cycle restart path. The product roadmap turns that evidence chain into a
releasable Computer Use feature that remains hidden from the default chat
surface until the user intentionally enables it.

- M31: Add a next-step navigator for Computer Use artifacts. It should inspect
  the latest readiness artifact index, identify the highest-priority blocked or
  ready milestone, and show exactly one recommended next command plus the
  evidence path it consumes. This keeps the M14-M30 cycle usable without asking
  operators to manually remember the milestone graph.
  The initial M31 implementation writes
  `macos_computer_use_next_step_navigator.json` and
  `macos_computer_use_next_step_navigator.md` through
  `dart run tool/macos_computer_use_next_step_navigator.dart --root build/integration_test_reports`.
  The readiness artifact index also embeds the same recommendation under
  `nextStepNavigator` so PR review can see the current command, evidence path,
  priority, and user-operation boundary in one place.
- M32: Move Computer Use from the default settings surface into an Advanced
  Computer Use page. The normal settings page should show only a compact
  enabled/disabled summary, while the dedicated page owns permission status,
  helper launch controls, artifact links, smoke checks, and diagnostic export.
  The initial M32 implementation keeps the root Settings list limited to an
  Advanced row with a compact Computer Use availability summary. The
  full `ComputerUseSettingsPage` lives in its own page module and is reachable
  only from Advanced, where it owns helper permission status, launch controls,
  smoke sequence navigation, artifact links, and diagnostic export.
- M33: Establish the signed release packaging lane. The release build must
  embed the helper, LaunchAgent plist, MachService declaration, entitlements,
  signing identity, hardened runtime settings, and notarization evidence that
  match the helper bundle path used for TCC grants.
  The initial M33 implementation adds the static report command
  `bash tool/run_macos_computer_use_release_packaging.sh`, which writes
  `macos_computer_use_release_packaging.json` and
  `macos_computer_use_release_packaging.md`. The report verifies the helper
  embed phase, LaunchAgent BundleProgram, MachServices declaration, helper
  bundle identity, release entitlements, hardened runtime settings, and
  identity-free repository signing defaults. Release signing identity,
  notarization, stapling, TCC grants, and real desktop actions remain
  user-operated evidence collected by the release pipeline.
- M34: Harden permission recovery and revocation UX. The app should clearly
  distinguish missing permissions, revoked permissions, stale helper paths,
  mismatched debug and release helpers, and the user action needed to recover
  without triggering extra macOS permission prompts from the main app.
  The implementation is tracked through a shared permission recovery summary
  that is rendered in Settings and exported in onboarding diagnostics. It
  separates first-time missing grants from previously granted but now revoked
  TCC permissions, reports stale helper diagnostics and helper path mismatches,
  and keeps recovery instructions on the helper-owned permission overlay path
  so `Caverno.app` does not request screen or accessibility grants itself.
- M35: Define the production action policy. Every desktop action must pass
  through observe, approval packet, action-time confirmation, emergency stop,
  execution result intake, and post-action review boundaries. Public actions
  such as post, send, publish, purchase, or delete require separate approval
  even when text and target approvals are already present.
  The policy is now exposed as `productionActionPolicy` alongside the
  `computer_vision_observe` action proposal policy, in the system prompt, and
  in the Computer Use debug evidence summary. It defines the required phase
  order as observe, approval packet, action-time confirmation, emergency stop
  availability, execution result intake, and post-action review, with separate
  hard blockers for missing public-action approval and missing post-action
  review evidence.
- M36: Expand Live LLM evaluation for Computer Use. The suite should cover
  fixture screenshots, saved real-app screenshots, refusal cases, target
  ambiguity, exact-text preservation, public-action boundary preservation, and
  recovery from stale or blocked evidence without executing desktop actions.
  Implemented as
  `bash tool/run_macos_computer_use_m36_live_llm_eval.sh --fixture-screenshot <mvp-fixture-screenshot.png> --real-app-screenshot <user-provided-real-app-screenshot.png>`.
  The report schema is `macos_computer_use_m36_live_llm_eval_summary`; it
  records `m36LiveLlmEvaluationGate`, per-scenario failures, coverage status,
  `tccBoundary: no_tcc_operation`, and `desktopActionBoundary:
  no_desktop_action`.
- M37: Add product-grade audit and privacy controls. The helper and main app
  should record local, user-exportable audit events for observe, approval,
  execution handoff, emergency stop, and result review while redacting secrets,
  screenshots, tokens, and typed text unless the user explicitly exports them.
  Implemented as `auditPrivacyControls` in exported Computer Use diagnostics
  with schema `macos_computer_use_audit_privacy_controls`. The gate records the
  required event types, bounded local retention, default redaction, explicit
  payload-export requirements, and latest audit coverage without storing raw
  screenshots, audio payloads, tokens, secrets, raw tool payloads, or typed text.
- M38: Build install, update, and migration guardrails. Upgrades must preserve
  the helper identity when possible, detect when TCC must be regranted, explain
  why regranting is needed, and prevent old helper processes from handling new
  action requests. Implemented as `installMigrationGuardrails` in exported
  diagnostics with schema `macos_computer_use_install_migration_guardrails`.
  The M38 gate records helper path match status, stale helper diagnostics,
  whether TCC regrant may be required, and the policy that blocks old helper
  processes from screenshot, window, input, and audio action requests while
  keeping status, permission recovery, helper UI, and emergency stop available.
- M39: Run an internal beta sign-off. The beta gate should include clean
  install, upgrade, permission grant, permission revocation, helper restart,
  XPC fallback observability, Live LLM observe-only canaries, and at least one
  full user-operated observe-approve-execute-review cycle. Implemented as
  `bash tool/run_macos_computer_use_m39_beta_signoff.sh`. The report schema is
  `macos_computer_use_m39_beta_signoff`; it records `betaReviewSummary`,
  user-operated beta gates, M36 observe-only LLM evidence, M23 cycle outcome
  evidence, and `automationBoundary: read_reports_only`.
- M40: Cut the production launch gate. Release is allowed only when the signed
  artifact, notarization, helper identity, manual TCC runbook, Live LLM evidence,
  audit export, emergency stop, privacy copy, and support diagnostics all have
  passing evidence attached to the release checklist. Implemented as
  `bash tool/run_macos_computer_use_m40_production_launch_gate.sh`. The report
  schema is `macos_computer_use_m40_production_launch_gate`; it records
  `launchReviewSummary`, signed artifact evidence, notarization evidence,
  helper identity evidence, manual TCC runbook evidence, M36 Live LLM evidence,
  M37 audit/privacy evidence, emergency stop evidence, privacy copy evidence,
  support diagnostics evidence, M39 beta sign-off evidence, and
  `automationBoundary: read_reports_only`.

## Computer Use Live Canary

The live canary for this milestone is scoped to Computer Use helper readiness,
not to generic coding-agent workflow behavior. It verifies helper launch, IPC
readiness, helper ping, permission-status reporting, and cleanup while
intentionally skipping TCC-gated screenshot, window capture, vision observe,
input, and audio checks.

Run:

```bash
bash tool/run_macos_computer_use_live_canary.sh
```

CI-style run:

```bash
bash tool/run_macos_computer_use_live_canary.sh --ci
```

Local/manual-prep run with repeat count:

```bash
bash tool/run_macos_computer_use_live_canary.sh --manual --repeat 3
```

Stability run:

```bash
bash tool/run_macos_computer_use_live_canary.sh --stability
```

Opt-in overlay foreground run:

```bash
bash tool/run_macos_computer_use_live_canary.sh --overlay
```

The overlay run opens System Settings and validates the helper overlay's
foreground diagnostics without granting TCC. It requires `overlaySmoke.status`
to be `ready`, including `overlayForegroundPolicy:
accessory_overlay_front`, `overlayIsFloatingPanel: true`, and
`overlayHidesOnDeactivate: false`.

The summary is written under
`build/integration_test_reports/macos_computer_use_live_canary_<timestamp>/`.
The summary schema is `macos_computer_use_live_canary_summary`. Each run
contains a `computerUseLiveCanaryGate`, a granular `failureClass`, and the
summary-level `failureClasses` count. Summaries also promote
`helperProcessPolicy` path-mismatch fields such as
`helperPathMismatch`, `helperPathMatchesRunningHelper`,
`replacedMismatchedHelperPath`, and `helperPathMismatchTerminationTimedOut`.
A passing canary means the helper core runtime is available for Computer Use
flows; it does not prove Accessibility, Screen & System Audio Recording,
screenshot capture, or live desktop actions. Those TCC checks remain
user-operated manual sign-off steps after the user grants permissions. Each
summary includes a `manualTccHandoff` object with the command the user should
run and the parser command automation may run against the user-produced report.

## Desktop Action Canary

The desktop action canary is the first live Computer Use canary that proves the
helper can see the desktop, perform one explicit click, and see the desktop
again. It is intentionally separate from the helper-runtime live canary because
it crosses the macOS TCC boundary and can mutate foreground app state.

Scope:

- Read the current desktop through the already-built helper without rebuilding
  `Caverno.app`.
- Run one explicitly armed `computer_click`.
- Capture the target again through the same already-built helper.
- Report the result through `desktopActionCanaryGate`.

Non-goals:

- Automating TCC grants or operating System Settings on behalf of the user.
- Proving arbitrary LLM-chosen click safety.
- Replacing the LLM/tool-loop canary or the manual M8 TCC sign-off.

Manual run after the user grants Accessibility and Screen & System Audio
Recording, launches Caverno.app manually, and prepares a safe click target:

```bash
bash tool/run_macos_computer_use_desktop_action_canary.sh --fixture-target
```

The default runner is no-build because macOS TCC permissions are tied to the
exact helper bundle identity. Rebuilding the Debug app during the canary can
replace `Caverno.app/Contents/Helpers/Caverno Computer Use.app` and make
previously granted permissions appear missing. The runner also does not
auto-launch `Caverno.app` by default; this keeps main-app TCC prompts out of
the canary path. It also preserves the currently running helper by default, so
a TCC-granted standalone Debug helper can be used for local desktop-action
validation without replacing the helper bundle. Use `--launch-caverno` only
when intentionally debugging main-app launch behavior. Use
`--release-helper-signoff` only when intentionally validating that the running
helper path matches the embedded release/debug helper; that mode may require the
user to grant TCC again after helper replacement. The old Flutter
integration-test path remains available only through `--legacy-integration` for
debugging canary code itself.

The runner writes
`macos_computer_use_desktop_action_canary_<timestamp>/canary_summary.json` and
`.md` under `build/integration_test_reports/`. The summary schema is
`macos_computer_use_desktop_action_canary_summary`, and each run classifies
failures such as `target_not_visible`, `click_not_sent`,
`post_observe_unavailable`, and `post_observe_unchanged`.

The user must prepare a visible harmless target, such as an empty text field or
test window, and avoid destructive buttons, purchase flows, send buttons,
system controls, and private data. The current MVP success contract is
`pre_observe_image`, `click_sent`, and `post_observe_image`; visible post-click
change is tracked only when the runtime report includes explicit change
evidence.

## macOS Spaces Canary

The macOS Spaces canary validates the multi-desktop discovery path without
performing desktop actions. It runs the existing helper probe with
`computer_list_windows` using `space_scope=all_spaces`, records the
`spaceSupport` metadata, and verifies that switching Spaces remains behind
explicit user approval plus a fresh observation before any input action.

Observe-only run:

```bash
bash tool/run_macos_computer_use_spaces_canary.sh
```

Manual two-Space run:

```bash
bash tool/run_macos_computer_use_spaces_canary.sh --require-inactive-space-window
```

User-operated focus run:

```bash
bash tool/run_macos_computer_use_spaces_canary.sh --focus-inactive-space-window
```

User-operated Space switch run:

```bash
bash tool/run_macos_computer_use_spaces_canary.sh --switch-space-next
bash tool/run_macos_computer_use_spaces_canary.sh --switch-space-previous
```

Before the two-Space run, the user prepares at least two macOS Spaces and keeps
a harmless target window on a non-active Space. The observe-only runs do not
switch Spaces, focus windows, click, type, grant TCC, or operate System
Settings. The summary schema is `macos_computer_use_spaces_canary_summary`, and
each probe report contains `spacesCanaryGate` with `activeSpaceWindowCount`,
`allSpacesWindowCount`, `inactiveSpaceWindowCount`,
`requiresApprovedInputBeforeSwitching`, and `spaceIdentifiersAvailable`.

The focus run is an explicit user-operated exception to the observe-only
boundary. It sends one `focusWindow` request to the first inactive-Space
candidate, then records `spacesFocusCanaryGate` and a fresh active-Space window
inventory. It must not click, type, submit, capture private content, or treat a
focused window as safe for input until a later `computer_vision_observe` runs.

The Space switch run is a separate user-operated exception. It sends one
Control-Right or Control-Left `pressKey` request, then records
`spacesSwitchCanaryGate` and a fresh active-Space window inventory. It requires
an adjacent macOS Space with a different harmless window plus enabled Mission
Control shortcuts. It does not move the pointer or type text, and any later
pointer or keyboard input still requires a fresh `computer_vision_observe`.

Passing this canary means the helper can expose the best-effort all-Spaces
window inventory and its safety metadata. It does not prove that macOS will
switch to a specific Space by ID because public macOS APIs do not expose stable
Space identifiers or names for this workflow.

The LLM live canaries and the Computer Use live canary cover different risks.
`tool/run_macos_computer_use_llm_decision_canary.sh` validates the live LLM
decision layer for Computer Use by asking the configured `CAVERNO_LLM_*`
endpoint to choose a safe click target from a canned
`computer_vision_observe`-style payload. It does not grant TCC, move the
pointer, click, type, or operate System Settings. Its summary schema is
`macos_computer_use_llm_decision_canary_summary` and promotes
`visionDecision`, `safeTargetReasoning`, and `requiresUserClick` so MVP
readiness can prove the LLM understood the observation while leaving execution
user-approved. `tool/run_plan_mode_ping_cli_live_canary.sh` still validates the
coding-agent LLM, tool-calling, saved-task recovery, and coding workflow
behavior.

The same LLM decision runner also supports a deterministic MVP fixture
scenario:

```bash
bash tool/run_macos_computer_use_llm_decision_canary.sh --scenario mvp-fixture
```

It also supports a fixture text scenario:

```bash
bash tool/run_macos_computer_use_llm_decision_canary.sh --scenario mvp-fixture-type-confirm
```

Use the aggregate runner when both MVP fixture decisions should be refreshed
together:

```bash
bash tool/run_macos_computer_use_mvp_fixture_llm_canary.sh
```

The aggregate fixture summary includes `mvpEvidenceGate`, `actionPlan`,
`refusedTargets`, and `expectedUserOperatedRuntimePhases`. The gate proves the
LLM planned safe click, type-and-confirm, Spaces switch via
`computer_switch_space`, observe-again, user approval boundaries,
`space_switch_planned`, and `destructive_target_refused` before any
user-operated desktop action canary runs.

The screenshot-backed fixture vision runner is the preferred MVP `llm_canary`
artifact when the user has provided an actual fixture screenshot. Release
readiness discovers `macos_computer_use_mvp_fixture_vision_llm_canary_*`
summaries before aggregate fixture summaries, then falls back to
single-scenario decision summaries. The shell wrappers also accept
`--llm-canary-summary` when a specific artifact should be used.
Use `tool/run_macos_computer_use_mvp_llm_readiness.sh` when the whole
automation-safe LLM preflight should run in one command. By default it creates
the aggregate fixture LLM summary; with `--screenshot <path>` it creates
screenshot-backed fixture vision evidence instead. In both modes it feeds the
summary into release readiness, writes an MVP handoff dry-run, and still leaves
capture, TCC, and desktop action evidence user-operated.
Use `tool/run_macos_computer_use_mvp_demo_readiness.sh` when a single guided
entrypoint should prepare the fixture, run the available LLM readiness path,
write a demo handoff, and optionally aggregate final user-produced evidence.
That wrapper still does not launch the fixture, capture the screen, grant TCC,
click, or type.
Use `tool/run_macos_computer_use_mvp_fixture_vision_llm_canary.sh` when the
live vision LLM should inspect an actual screenshot of the fixture app. The
screenshot is provided by the user or extracted from a user-operated desktop
action canary report through `--desktop-action-report <path>`, so the canary
does not capture the screen, grant TCC, operate System Settings, move the
pointer, click, or type.

Use `tool/run_macos_computer_use_m36_live_llm_eval.sh` when the broader
Computer Use LLM evaluation needs refresh before product sign-off. It combines
fixture screenshot target inventory, saved real-app public-action boundary
preservation, refusal without approval, target ambiguity, exact-text
preservation, and stale or blocked evidence recovery into one report-only
gate. The runner accepts `--fixture-suite <path>` for deterministic regression
tests; production runs should provide saved fixture and real-app screenshots
and the configured `CAVERNO_LLM_*` endpoint. It never captures the desktop,
grants TCC, clicks, types, submits, posts, or operates System Settings.

The fixture app is built with:

```bash
bash tool/run_macos_computer_use_mvp_fixture.sh --print-path
```

Its window is titled `Caverno Computer Use MVP Fixture` and exposes a
low-risk `Safe Click Target`, an `MVP Fixture Text Field`, and a disabled
`Danger Zone` target. The LLM canary must select the safe target, keep
`requiresUserClick: true`, include `computer_vision_observe`,
`computer_click`, and a second `computer_vision_observe`, and refuse
`Danger Zone`. This remains a no-desktop-action LLM decision test; the user can
launch the fixture later when running the user-operated desktop action canary.
The user-operated runbook lives in
`docs/macos_computer_use_mvp_fixture_runbook.md`.

`tool/run_macos_computer_use_live_canary.sh` validates the macOS Computer Use
helper runtime. `tool/run_macos_computer_use_desktop_action_canary.sh`
validates manual TCC-gated desktop action execution. Passing any one canary
does not replace the others.

To compare recent Computer Use canary runs without launching the helper, run:

```bash
dart run tool/macos_computer_use_canary_history.dart
```

This writes `macos_computer_use_canary_history.json` and
`macos_computer_use_canary_history.md` under
`build/integration_test_reports/`. The history report shows the latest
stability status, pass-rate delta, and failure-class distribution.

## Release Readiness Gate

The release readiness gate is a read-only aggregator for release sign-off
artifacts. It does not launch the app, operate System Settings, grant TCC, or
run any live desktop action. It reads the latest available reports and produces
one release decision:

```bash
dart run tool/macos_computer_use_release_readiness.dart
```

For the shortest MVP path, use
`docs/macos_computer_use_mvp_checklist.md` and the MVP wrapper:

```bash
bash tool/run_macos_computer_use_mvp_signoff.sh \
  --final-signoff \
  --manual-tcc-report <manual-tcc-report-or-summary.json> \
  --desktop-action-canary-summary <desktop-action-canary-summary.json> \
  --llm-canary-summary <llm-canary-summary.json>
```

For the guided fixture-to-readiness demo path, use:

```bash
bash tool/run_macos_computer_use_mvp_demo_readiness.sh
```

The MVP wrapper prints the user-operated commands, writes
`macos_computer_use_mvp_handoff.md`, and delegates final aggregation to the
release readiness wrapper. It does not run manual TCC sign-off or the desktop
action canary for the user.

Running the MVP wrapper before both user-produced reports are available is the
standard handoff check. The generated handoff lists missing manual inputs,
validates whether provided paths exist, and prints the next user-operated
command for each missing gate. Add `--dry-run` to validate that handoff without
running the final release readiness aggregation.

For PR review, run the report-only MVP readiness preflight when you only need
to refresh the artifact index plus dry-run handoff:

```bash
bash tool/run_macos_computer_use_mvp_readiness_preflight.sh
```

This preflight reads existing artifacts, writes the MVP handoff, and prints the
`PR Review Summary` / `PR Review Artifacts` paths without launching apps,
operating System Settings, granting TCC, or running desktop actions.

After Computer Use changes are merged into `main`, run the post-merge sanity
wrapper to repeat static checks, focused Computer Use tests, and the debug
macOS build without launching apps or touching TCC. The runner prints the M13
review scope, the M14 observe-only evidence scope, and the
M15 review/gate consistency scope. It links back to the manual review
checklist:

```bash
bash tool/run_macos_computer_use_post_merge_sanity.sh
```

Use `--final-signoff` for the one-command MVP path: it refreshes only
automation-safe evidence, refreshes the aggregate Computer Use fixture LLM
canary when `CAVERNO_LLM_*` is set, aggregates strict readiness, and appends
blocked gate next actions back into `macos_computer_use_mvp_handoff.md`.
Before requesting user-operated TCC and desktop action evidence, run:

```bash
bash tool/run_macos_computer_use_mvp_llm_readiness.sh
```

The preflight should leave only manual or release-readiness blockers after the
`llm_canary` gate is ready.

To refresh only non-TCC inputs before producing the readiness report, run:

```bash
dart run tool/macos_computer_use_release_readiness.dart --refresh-safe-inputs
```

The shell wrapper provides the standard presets:

```bash
bash tool/run_macos_computer_use_release_readiness.sh --ci
bash tool/run_macos_computer_use_release_readiness.sh --signoff
```

Add `--refresh-llm-canary` only when live LLM environment variables are set and
fresh Computer Use LLM decision evidence is needed:

```bash
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
bash tool/run_macos_computer_use_release_readiness.sh --ci --refresh-llm-canary
```

If any `CAVERNO_LLM_*` value is missing, the wrapper skips the LLM refresh and
falls back to discovering existing LLM canary summaries.
Use `--llm-canary-summary <path>` to pin a specific aggregate LLM artifact
instead of relying on discovery.

The wrapper writes preset-specific readiness artifacts:

- `macos_computer_use_release_readiness_ci.json`
- `macos_computer_use_release_readiness_ci.md`
- `macos_computer_use_release_readiness_signoff.json`
- `macos_computer_use_release_readiness_signoff.md`
- `macos_computer_use_readiness_artifact_index.json`
- `macos_computer_use_readiness_artifact_index.md`

Each release readiness JSON and Markdown report contains a `PR Review Summary`
that separates ready gates, blocked gates, pending user-operated evidence, and
pending automation-safe evidence. The summary keeps release report review
usable even before the artifact index is opened.

The artifact index includes the latest manual TCC summary, desktop action
canary, preferred LLM canary, MVP LLM readiness summary, and guided MVP demo
readiness summary when those user-produced or automation-safe artifacts exist.
It also includes an MVP final sign-off rehearsal checklist that reports missing
required input evidence before the final aggregation is attempted. The Markdown
artifact also contains a `PR Review Summary` section that separates ready
artifacts, missing evidence, pending user-operated evidence, and pending
automation-safe evidence for review notes.

Safe refresh generates the M7 release artifact report and the Computer Use
canary history. It does not run M8, launch System Settings, grant permissions,
or perform any TCC-gated runtime verification. The LLM canary is discovered from
existing summaries; run that canary separately when fresh LLM evidence is
needed.

The gate evaluates:

- M7 release artifact sign-off through `releaseSignoffGate`.
- Computer Use helper runtime stability through
  `macos_computer_use_canary_history.json` or recent live canary summaries.
- Desktop action execution through the latest user-run
  `macos_computer_use_desktop_action_canary_summary`.
- Manual TCC sign-off through the user-produced M8 runtime report or
  `manual_tcc_report_summary.json`.
- LLM decision readiness through the latest Computer Use LLM decision canary
  summary, with legacy Plan Mode ping CLI summaries still accepted as fallback
  evidence.

The output files are
`build/integration_test_reports/macos_computer_use_release_readiness.json` and
`build/integration_test_reports/macos_computer_use_release_readiness.md`. Missing
manual TCC evidence is reported as `manual_required`, not automated. When that
happens, ask the user to run the M8 command manually, then rerun the readiness
gate with the produced report available under `build/integration_test_reports/`
or pass it explicitly:

```bash
dart run tool/macos_computer_use_release_readiness.dart \
  --manual-tcc-report <user-produced-m8-report.json>
```

Manual TCC intake uses this handoff:

1. Ask the user to run
   `bash tool/run_macos_computer_use_manual_tcc_signoff.sh` from their
   terminal after granting the release helper in System Settings.
2. Ask the user for the produced report path. The report may be either the raw
   M8 runtime report or `manual_tcc_report_summary.json`.
3. Run
   `bash tool/run_macos_computer_use_release_readiness.sh --signoff --manual-tcc-report <report.json>`.

Blocked manual TCC reports surface concise failure classes such as
`permissions_missing`, `app_path_mismatch`, `helper_path_mismatch`,
`capture_blocked`, or `audio_blocked`, plus the failed checks and helper path.

Use `--exit-policy ci` when CI should accept a missing manual TCC report as a
blocked-but-expected manual step. Other blocked gates still exit non-zero.
Use the default `--exit-policy strict` for release sign-off, where any blocked
gate exits non-zero.

Before opening or merging a PR for this milestone, review the artifact index
`PR Review Summary`, the CI readiness Markdown, and the sign-off readiness
Markdown. The expected pre-manual-TCC state is:

- `release_artifact`: ready.
- `computer_use_canary`: stable.
- `desktop_action_canary`: passed.
- `llm_canary`: passed or explicitly refreshed and passed.
- `manual_tcc`: `manual_required` until the user provides the M8 report.

Current M5 implementation status:

- M5 is complete for the current debug embedded helper.
- The app now advertises a high-level `computer_vision_observe` tool when
  macOS Computer Use is available.
- `computer_vision_observe` packages permission
  status, optional visible-window metadata, the chosen display or window
  screenshot, coordinate guidance, and the approved next tool surface into one
  observation payload.
- The observation screenshot is fed back to multimodal models as image content
  so the next LLM turn can decide whether to answer, observe again, or request
  a desktop action.
- The observation tool remains read-only and planning-safe. Any proposed focus,
  pointer, keyboard, or audio action must still go through the existing
  approval, arming, emergency-stop, and audit-log gates.
- The system prompt now prefers `computer_vision_observe` at the start of
  visual desktop tasks and after every approved desktop action. Raw screenshot
  and window tools remain available for focused follow-up checks.

M5 acceptance criteria:

- `computer_vision_observe` is advertised in the built-in tool catalog when
  macOS Computer Use is available.
- `computer_vision_observe` can observe the full display, a specific
  `window_id`, or the first visible front window.
- The tool result includes the screenshot image, redacted metadata, coordinate
  space, `allowedNextTools`, `approvalRequiredTools`, and concrete
  `nextAction`.
- Planning mode allows `computer_vision_observe` but continues to block
  mutating Computer Use tools.
- Input, text, focus, and system-audio actions proposed after a vision
  observation continue to require the existing Caverno approval and arming
  flow.

M5 live sign-off notes:

- 2026-04-29: `flutter analyze` passed after adding the vision observation
  surface.
- 2026-04-29: targeted unit tests passed for the Computer Use service, tool
  policy, MCP tool catalog, and system prompt guidance.
- 2026-04-29:
  `bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --m4-signoff --require-vision-observe`
  passed with `visionObservationGate.status: ready`,
  `readinessExpectations.ok: true`, and `m4SignoffGate.status: ready`.

Current M6 implementation status:

- M6 is complete for the current debug embedded helper.
- Test coverage now exercises an LLM-style observe-action-observe sequence:
  `computer_vision_observe`, one approved desktop action, then another
  `computer_vision_observe`.
- Desktop action results now attach a fresh `computer_vision_observe`
  post-action observation when the action succeeds, so multimodal models can
  inspect the updated screen before proposing another action.
- The Computer Use approval UI surfaces vision-observation context, including
  the target coordinate space, target window when available, and the immediate
  reason for the proposed action.
- Click, text input, focus, keyboard, and system-audio actions remain behind the
  existing approval and arming gates, even when they are proposed from a vision
  observation.
- The live smoke report now includes `observeActionObserveGate`, which verifies
  the first complete observe-action-observe loop without requiring unsafe click
  or text arming by default.

M6 acceptance criteria:

- A representative multimodal desktop task can observe the screen, request one
  approved non-destructive action, and observe again before continuing.
- The approval UI clearly identifies that the action was proposed from the most
  recent vision observation.
- Action results include enough redacted audit metadata to connect the
  observation, approval decision, helper command, and post-action observation.
- The live smoke report includes a ready gate for the observe-action-observe
  loop while preserving the existing M4 and M5 gates.

M6 live sign-off notes:

- 2026-04-29: `flutter analyze` passed after hardening the
  observe-action-observe loop.
- 2026-04-29: targeted tests passed for Computer Use audit logging, service
  observation packaging, tool policy, MCP tool definitions, system prompt
  guidance, approval copy, and the chat tool loop.
- 2026-04-29:
  `bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --m4-signoff --require-vision-observe --require-observe-action-observe`
  passed with `visionObservationGate.status: ready`,
  `observeActionObserveGate.status: ready`, `readinessExpectations.ok: true`,
  and `m4SignoffGate.status: ready`.

Current M7 implementation status:

- M7 is implemented as a release artifact sign-off gate.
- `bash tool/run_macos_computer_use_smoke_test.sh --m7-signoff` now expands to
  a release macOS build plus strict release helper diagnostics.
- The release smoke report uses schema version 2 and includes
  `releaseSignoffGate`, `releaseRuntimeReadiness`, and expanded
  `releaseBundle` command diagnostics.
- The runner records app, helper, LaunchAgent plist, MachService, deep
  codesign, bundle identifier, and LaunchAgent signing-constraint checks in
  the report before exiting non-zero for required sign-off blockers.
- Release runtime TCC remains a separate installed-app check. The artifact gate
  reports `releaseRuntimeReadiness.status: not_measured` with the exact helper
  path and required macOS permissions so the manual release grant can be
  tracked without confusing it with bundle assembly or signing failures.

M7 acceptance criteria:

- `--m7-signoff` builds the release app and verifies the release helper is
  embedded at `Caverno.app/Contents/Helpers/Caverno Computer Use.app`.
- The release report is written even when helper embedding, plist, MachService,
  codesign, identifier, or LaunchAgent signing constraints are blocked.
- `releaseSignoffGate.status` is `ready` only when the release helper bundle,
  LaunchAgent, MachService declaration, deep codesign verification, expected
  bundle identifiers, and LaunchAgent signing constraints are all ready.
- A blocked release sign-off exits non-zero after writing the report and prints
  the M7 summary with concrete blockers and next actions.
- The report calls out that release TCC runtime readiness is not measured by
  the artifact gate and must be completed against an installed release app.

M7 release sign-off notes:

- 2026-04-29: `flutter test test/tool/run_macos_computer_use_smoke_test_test.dart -r compact`
  passed the script contract tests for the M7 runner flags, release report
  schema, and report-before-fail behavior.
- 2026-04-29: `bash tool/run_macos_computer_use_smoke_test.sh --m7-signoff`
  built the release app and passed with `releaseSignoffGate.status: ready`,
  `blockers: []`, expected app and helper bundle identifiers, a valid
  LaunchAgent plist, declared MachService, deep codesign verification, and no
  LaunchAgent signing-constraint blockers.
- The same run reported `releaseRuntimeReadiness.status: not_measured`; the
  remaining release runtime task is to install and launch the release app,
  grant Accessibility plus Screen & System Audio Recording to the release
  helper, and run a live runtime smoke against that installed app.

Current M8 implementation status:

- M8 is implemented as a release runtime sign-off gate.
- `bash tool/run_macos_computer_use_smoke_test.sh --m8-runtime-signoff` reuses
  the existing release app by default, runs the M7 artifact gate, launches the
  release app/helper path, replaces mismatched running debug app/helper
  processes, and measures the live helper runtime through the existing helper
  probe. Add `--rebuild-release` only when the release artifact intentionally
  needs to be rebuilt before manual TCC sign-off.
- The final report uses schema `macos_computer_use_release_runtime_signoff` and
  includes `releaseRuntimeSignoffGate`, `releaseRuntimeReadiness`, the M7
  `releaseSignoffGate`, redacted runtime probe details, and paths to the full
  artifact and runtime probe reports.
- The existing helper probe now supports `--replace-app` and
  `--require-app-path-match`, so a passing helper result cannot be accepted
  when the sender app is a different debug or standalone `Caverno.app`.

M8 acceptance criteria:

- `--m8-runtime-signoff` verifies the release artifact gate before trusting
  runtime results.
- The running `Caverno.app` path matches the release app path used by the
  runner.
- The running `Caverno Computer Use.app` path matches the release helper
  embedded in the release app bundle.
- `permissionStatus` succeeds and reports Accessibility plus Screen & System
  Audio Recording granted to the release helper.
- Display screenshot, visible-window listing, first-window screenshot, input
  readiness, and system-audio readiness resolve through the running release
  helper.
- Blocked runtime sign-off writes the final report before exiting non-zero and
  prints concrete next actions for app path, helper path, permission, capture,
  input, or audio blockers.

M8 release runtime sign-off notes:

- 2026-04-29: `flutter test test/tool/run_macos_computer_use_smoke_test_test.dart -r compact`
  passed the M7/M8 runner contract tests, including app path identity support
  in the existing-helper probe.
- 2026-04-29: `flutter analyze` passed after adding the release runtime gate.
- Runtime TCC sign-off is intentionally manual. The user should grant
  Accessibility plus Screen & System Audio Recording to the release
  `Caverno Computer Use.app`, then run
  `bash tool/run_macos_computer_use_smoke_test.sh --m8-runtime-signoff`.
- A passing manual run must report `releaseRuntimeSignoffGate.status: ready`,
  `appPathMatchesExpected: true`, `helperPathMatchesExpected: true`,
  `accessibilityGranted: true`, `screenCaptureGranted: true`,
  `captureReady: true`, `inputReady: true`, `audioResolved: true`,
  `xpcProductionReady: true`, and no runtime blockers.

Current M9 implementation status:

- M9 is complete for the release runtime sign-off workflow.
- The M8 runner now prints a manual TCC notice whenever release runtime
  sign-off is requested.
- TCC-related next actions explicitly instruct automation to ask the user to
  grant permissions and rerun the command manually.
- The manual runbook below defines what automation may do, what only the user
  should do, and how to interpret blocked runtime reports.

M9 acceptance criteria:

- Documentation states that release runtime TCC sign-off is user-operated.
- The runner output warns that it measures TCC state only and does not grant or
  edit macOS privacy permissions.
- Blocked TCC next actions tell automation to ask the user to perform the
  manual macOS permission step.
- Non-TCC checks, including release artifact sign-off and static tests, remain
  safe for automation.

Current M2 implementation status:

- Read-only observation tools, window focus, pointer input, text input, key
  presses, and system-audio commands are routed through the helper boundary.
- Unsafe input and sensitive commands require a user-facing chat approval
  decision before the helper receives the command.
- Approval alone is not enough for input and sensitive commands; the user must
  also explicitly arm the pending action in the approval sheet.
- Attempts to approve an unsafe action without arming are blocked before helper
  execution and returned to the model as structured JSON with
  `code: "arming_missing"` and a concrete `nextAction`.
- Approval-gated actions record redacted audit metadata for policy, approval,
  arming, transport, response code, success, and post-action observation.
- The pending Computer Use approval sheet exposes **Stop Computer Use** so a
  user can send an emergency stop command while an action is awaiting approval.
- M2 is signed off for the current debug embedded helper through the M4 combined
  smoke gate. Release builds still need a separate live smoke pass against the
  release helper bundle identity.

M2 live sign-off notes:

- 2026-04-29: `bash tool/run_macos_computer_use_smoke_test.sh --reporter compact`
  passed the baseline helper smoke with `coreOk: true`,
  `ipcReadyOk: true`, `helperOwnsUnsafeOsActions: true`, and
  `mainAppUnsafeOsActionsAllowed: false`.
- 2026-04-29: `bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --unsafe-armed --require-input`
  passed non-destructive input readiness. Pointer movement, pointer drag,
  scroll, and key press all passed; click and text input remained skipped
  behind their separate arming gates.
- 2026-04-29: before the final debug helper grant,
  `bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --unsafe-armed --require-audio`
  failed only the required audio readiness expectation because
  `screen_capture_permission_missing` blocked Screen & System Audio Recording
  for the exact embedded helper path.
- 2026-04-29: `bash tool/run_macos_computer_use_capture_signoff.sh --require-capture --verbose-probe`
  showed capture, input, and audio readiness for the standalone debug helper at
  `build/macos/Build/Products/Debug/Caverno Computer Use.app`, but failed the
  required helper path match.
- 2026-04-29: `bash tool/run_macos_computer_use_capture_signoff.sh --replace-helper --require-capture --verbose-probe`
  confirmed the embedded helper path matches the expected
  `Caverno.app/Contents/Helpers/Caverno Computer Use.app` location. Before the
  final grant, capture was blocked there until macOS granted Screen & System
  Audio Recording to that exact helper bundle.
- 2026-04-29: the existing-helper probe now retries the initial
  `permissionStatus` request after helper replacement and reports
  `helperPathMismatchInvalidatesSignoff` when a standalone helper produced
  otherwise passing capture, input, or audio results.
- 2026-04-29: after granting Screen & System Audio Recording and enabling the
  parent `Caverno` row shown by macOS, the capture sign-off probe passed for
  the debug embedded helper path with `captureReady: true`.
- 2026-04-29: `bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --m4-signoff`
  passed with capture, non-destructive input, system audio, overlay,
  onboarding transition, and LaunchAgent named XPC gates all ready.

Current M3 implementation status:

- M3 is complete for the current debug embedded helper and release artifact
  layout.
- LaunchAgent-backed named XPC is the preferred production IPC transport for
  `Caverno.app` to request helper-owned Computer Use operations.
- The helper advertises `xpcStatus: production`,
  `xpcConnectionMode: external_helper_mach_service`, and
  `xpcRegistrationRequirement: launchd_mach_service_registration` in
  diagnostics.
- The production IPC surface covers the same command set as the fallback
  distributed-notification transport, including `ping`, `showMainWindow`,
  `permissionStatus`, settings shortcuts, permission overlays, observation,
  window capture, input, keyboard, scroll, and system-audio commands.
- Distributed notifications remain as an observable fallback when the preferred
  XPC request times out or the named service is unavailable. Fallback metadata
  records the attempted transport, timeout class, and next action without
  widening helper permissions.
- LaunchAgent registration, unregister, plist installation, MachService name,
  and parity checks are surfaced in the debug UI, release artifact sign-off,
  and helper diagnostics.

M3 acceptance criteria:

- `Caverno.app` embeds
  `Contents/Library/LaunchAgents/com.noguwo.apps.caverno.computer-use.plist`.
- The helper exposes the named Mach service
  `com.noguwo.apps.caverno.computer-use.xpc`.
- The signed main app can connect to the named XPC service and receive
  responses for the supported helper command set.
- `xpcProductionGate` reports ready only when LaunchAgent registration,
  named-service reachability, command parity, and production diagnostics are
  ready.
- DNC fallback remains non-destructive, observable, and explicitly reported as
  fallback rather than accepted as production XPC readiness.

M3 sign-off notes:

- 2026-04-29: the M4 combined sign-off passed with LaunchAgent named XPC gates
  ready for the current debug embedded helper.
- M7 extends the same LaunchAgent, MachService, bundle identity, and signing
  checks to release artifacts before runtime TCC is considered.
- M8 verifies that the installed release helper path is the runtime owner for
  helper commands before measuring permissions, capture, input, window, or
  audio readiness.

## M4 Sign-Off Gate

M4 is the embedded-helper production sign-off for macOS permissions and helper
onboarding. Run:

`bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --m4-signoff`

This expands to strict LaunchAgent-backed XPC, unsafe arming for the optional
system-audio check, required capture readiness, required overlay readiness, and
required onboarding Allow-transition readiness. The live smoke report includes
`m4SignoffGate`, which is ready only when:

- the running or diagnosed helper matches the embedded
  `Caverno.app/Contents/Helpers/Caverno Computer Use.app` path;
- Accessibility and Screen & System Audio Recording are granted to that helper;
- display and window capture pass;
- system audio is either ready or unsupported on the runtime;
- both permission overlays show a draggable helper tile;
- the onboarding Allow row transition targets the overlay window;
- LaunchAgent named XPC is production ready with no runtime blockers.

If macOS TCC is not yet granted for the embedded helper, `--m4-signoff` fails
with `m4SignoffGate.status: blocked` and lists concrete blockers such as
`permissions`, `capture`, or `audio`. Use the blocker list plus the embedded
helper path in the report to finish the manual grant, then rerun the same
command.

The `--m4-signoff` runner prints a concise post-run summary even when the
required smoke test exits non-zero. The summary repeats the gate status,
blockers, embedded helper path, failed check next-actions, and the manual grant
command:

`bash tool/run_macos_computer_use_capture_signoff.sh --reveal-helper --open-settings`

M4 live sign-off notes:

- 2026-04-29: `bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --m4-signoff`
  exercised the combined gate. Helper path, required macOS permissions,
  display and window capture, system audio, overlay readiness, onboarding
  transition, non-destructive input, and LaunchAgent named XPC were ready.
  `m4SignoffGate.status` was `ready`, `blockers` was empty, and the embedded
  helper path matched the running helper path.

## App Responsibilities

| Area | `Caverno.app` | `Caverno Computer Use.app` |
| --- | --- | --- |
| Chat UI and conversations | Owns | Does not access |
| LLM settings and API keys | Owns | Does not access |
| MCP and built-in tool catalog | Owns | Exposes a narrow command surface |
| Tool approval policy | Owns user-facing approvals | Enforces only approved command requests |
| Accessibility trust | Does not require in target state | Owns |
| Screen capture trust | Does not require in target state | Owns |
| System audio capture | Does not require in target state | Owns |
| Input event posting | Does not perform directly | Owns |
| Diagnostics export | Owns redacted app diagnostics | Returns redacted helper diagnostics |
| Emergency stop | Sends stop command and updates UI | Stops active capture/input work immediately |
| Unsafe OS actions | Blocks direct execution in target state | Owns input, capture, audio, and stop |

## Permission Ownership

macOS TCC permissions are scoped to the bundle that performs the privileged
operation. The helper therefore needs its own bundle identifier and must be the
process that calls Accessibility, screen capture, and ScreenCaptureKit APIs.

Proposed identifiers:

- Main app: `com.noguwo.apps.caverno`
- Helper app: `com.noguwo.apps.caverno.computer-use`

The helper should appear in System Settings as `Caverno Computer Use`. The main
app can still show onboarding and settings shortcuts, but the user should grant
the helper when the helper target exists.

## Helper Process Policy

`Caverno Computer Use.app` is a background agent helper, not a user-facing Dock
app. Its `Info.plist` sets `LSUIElement` and the helper sets the AppKit
activation policy to `accessory`, so the process can own permission overlays
without leaving a persistent Dock icon.

Only one helper process should be active for the bundle identifier
`com.noguwo.apps.caverno.computer-use`. On startup, the helper first acquires
`/tmp/caverno-computer-use-helper.lock`. If the lock is already held, the new
process activates the existing helper and exits before starting IPC. After
acquiring the lock, the helper also checks for an older non-locking helper with
the same bundle identifier and exits in favor of that existing process.

Main-app status diagnostics expose `helperRunningProcessCount`,
`singleInstanceExpected`, `singleInstanceLockExpected`, and `helperDockPolicy`
so duplicate helper processes remain visible in reports. Smoke reports promote
those diagnostics into `helperProcessPolicyGate`; the gate is ready only when
the helper declares the hidden Dock policy, declares single-instance ownership,
acquires the startup lock, reports at most one running helper process, and
matches the embedded helper path.

Use `docs/macos_computer_use_manual_process_checklist.md` for the
user-operated hidden-helper, path-mismatch, and permission-overlay checks.

## IPC Boundary

The main app should call the helper through a small local IPC surface. XPC is the
preferred production transport because it is native to macOS app bundles and can
be constrained to the bundled helper. A Unix domain socket or localhost HTTP
transport can be used as a temporary development transport if it accelerates
iteration.

The current helper milestone uses LaunchAgent-backed named XPC as the active
request/response transport for `ping`, `permissionStatus`, `openSettings`,
`showPermissionOverlay`, `startOnboardingPermissionFlow`, `stopAll`,
`screenshot`, `listWindows`, `focusWindow`, `screenshotWindow`, `moveMouse`,
`click`, `drag`, `scroll`, `typeText`, `pressKey`,
`startSystemAudioRecording`, and `stopSystemAudioRecording`. The app still
records the preferred attempt and falls back to `DistributedNotificationCenter`
when launchd cannot resolve the named service, so local development remains
diagnosable without executing duplicate unsafe OS actions.

Production readiness requires:

- The named XPC service connects from the signed main app.
- `ping`, `permissionStatus`, `openSettings`, `showPermissionOverlay`,
  `startOnboardingPermissionFlow`, `stopAll`, `screenshot`, `listWindows`,
  `focusWindow`, `screenshotWindow`, `moveMouse`, `click`, `drag`, `scroll`,
  `typeText`, `pressKey`, `startSystemAudioRecording`, and
  `stopSystemAudioRecording` match the active distributed-notification
  behavior. There are no remaining command-level parity migrations.
- Capture, input, and audio commands have parity smoke coverage before they move
  to XPC.
- Fallback behavior is observable in diagnostics and does not execute duplicate
  unsafe OS actions.

The production named XPC path uses an external helper-app Mach service name.
`Caverno.app` embeds a `SMAppService` LaunchAgent plist at
`Contents/Library/LaunchAgents/com.noguwo.apps.caverno.computer-use.plist`.
The plist uses `BundleProgram` to point at
`Contents/Helpers/Caverno Computer Use.app/Contents/MacOS/Caverno Computer Use`
and declares the `com.noguwo.apps.caverno.computer-use.xpc` Mach service. The
named service is production-ready when that LaunchAgent is registered and
approved by macOS. Runtime diagnostics still expose
`xpcRegistrationRequirement`, measured `xpcProductionBlockers`, and
`xpcProductionNextAction` so onboarding can distinguish an unregistered local
LaunchAgent from a transport regression.

Use the opt-in live smoke registration path to measure the launchd gate:

`bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --register-xpc-agent`

The report includes `register_xpc_launch_agent`, `xpc_production_probe`, and
`xpcProductionGate`. A production-ready result requires the LaunchAgent to be
registered, the named XPC probe to connect without fallback, and
`xpcNextParityCommands` to stay empty. Add `--strict-xpc` to fail the smoke
when the registered LaunchAgent does not reach production-ready named XPC while
leaving screenshot and unsafe-operation gates permission-aware. The strict XPC
probe retries the named service so launchd cold starts are recorded as attempts
instead of hiding the final readiness result. Add `--cleanup-xpc-agent` when a
run should unregister the LaunchAgent after the production gate has been
measured. Add `--release` to run the release bundle artifact checks and emit the
same JSON marker/report path as live smoke. Use `--m7-signoff` when the release
artifact gate is required to fail on blocked helper, plist, MachService,
codesign, bundle identifier, or LaunchAgent signing-constraint checks. Flutter
Driver does not support release-mode desktop correctness runs, so runtime
named-XPC smoke should use debug or profile mode.

Release builds should use the same embedded helper and LaunchAgent layout as
debug builds. Before notarization work, run:

`flutter build macos --release`

Then verify `Caverno.app` still contains
`Contents/Library/LaunchAgents/com.noguwo.apps.caverno.computer-use.plist` and
`Contents/Helpers/Caverno Computer Use.app`. To verify the release app carries
the helper, LaunchAgent plist, Mach service declaration, and valid signature,
run:

`bash tool/run_macos_computer_use_smoke_test.sh --m7-signoff`

The M7 report includes `releaseSignoffGate`. A ready gate requires the release
app bundle, embedded helper bundle, LaunchAgent plist, MachService declaration,
deep codesign verification, expected bundle identifiers, and LaunchAgent
signing constraints to pass. A blocked gate exits non-zero only after writing
the report and printing the M7 summary. `releaseRuntimeReadiness.status` remains
`not_measured` until an installed release app is launched and granted
Accessibility plus Screen & System Audio Recording in macOS Privacy & Security.

To verify the installed release runtime after the permissions are granted, run:

`bash tool/run_macos_computer_use_smoke_test.sh --m8-runtime-signoff`

The M8 runner replaces mismatched running debug app/helper processes, launches
the release app/helper paths, and writes `releaseRuntimeSignoffGate`. A ready
gate requires the running app path, running helper path, `permissionStatus`,
Accessibility, Screen & System Audio Recording, display screenshot, visible
window listing, first-window screenshot, and system-audio readiness checks to
pass. If macOS has not granted the release helper yet, the report remains
blocked with the exact release helper path to grant.

## Manual TCC Sign-Off Runbook

TCC verification is a user-operated step. Automation may prepare the release
artifact, update documentation, and parse reports, but it must not run release
runtime TCC sign-off or operate System Settings on the user's behalf. When TCC
state is needed, automation should stop and ask the user to perform the manual
steps in this section.

Automation may run these non-TCC checks:

- `bash -n tool/run_macos_computer_use_smoke_test.sh`
- `swiftc -parse tool/macos_computer_use_existing_helper_probe.swift`
- `flutter test test/tool/run_macos_computer_use_smoke_test_test.dart -r compact`
- `flutter analyze`
- `bash tool/run_macos_computer_use_smoke_test.sh --m7-signoff`

Only the user should run this TCC runtime command:

`bash tool/run_macos_computer_use_manual_tcc_signoff.sh`

The wrapper runs the M8 runtime sign-off, writes a timestamped report under
`build/integration_test_reports/`, and prints the parser command. It still only
measures TCC state; it does not grant permissions, edit TCC, or operate System
Settings.

After the user runs the manual command, automation may parse the user-produced
report without touching TCC:

```bash
dart run tool/macos_computer_use_manual_tcc_report.dart <report.json>
```

The parser writes `manual_tcc_report_summary.json` and
`manual_tcc_report_summary.md` next to the report. It only reads the existing
report and exits non-zero when the runtime gate is still blocked.

Manual steps for the user:

1. Confirm the release artifact is the one being signed off. If the artifact
   intentionally changed, run
   `bash tool/run_macos_computer_use_smoke_test.sh --m8-runtime-signoff --rebuild-release`
   once, then grant TCC to the newly built helper.
2. Open macOS System Settings > Privacy & Security.
3. Grant Accessibility to the exact release helper:
   `build/macos/Build/Products/Release/Caverno.app/Contents/Helpers/Caverno Computer Use.app`.
4. Grant Screen & System Audio Recording to the same release helper.
5. Run `bash tool/run_macos_computer_use_smoke_test.sh --m8-runtime-signoff`
   from a user-controlled terminal.
6. Treat the run as complete only when `releaseRuntimeSignoffGate.status` is
   `ready` and `releaseRuntimeSignoffGate.blockers` is empty.

Blocked report handling:

- `release_runtime_app_path_mismatch`: quit the running `Caverno.app`, then
  rerun the manual command.
- `release_runtime_helper_path_mismatch`: quit the running
  `Caverno Computer Use.app`, then rerun the manual command.
- `release_runtime_permissions_blocked`: grant both Accessibility and Screen &
  System Audio Recording to the release helper, then rerun the manual command.
- `release_runtime_capture_blocked`: grant Screen & System Audio Recording to
  the release helper, then rerun the manual command.
- `release_runtime_audio_blocked`: grant Screen & System Audio Recording to the
  release helper, then rerun the manual command.

Avoid rebuilding between a successful manual grant and the runtime sign-off
unless the release artifact intentionally changed. Rebuilding can change the
bundle instance macOS associates with TCC, which may require the user to grant
permissions again.

To exercise named XPC with a built app runtime, run:

`bash tool/run_macos_computer_use_smoke_test.sh --profile --strict-xpc --cleanup-xpc-agent`

Profile LaunchAgent startup requires a signing chain accepted by launchd. If a
profile helper is ad-hoc signed, macOS can reject it with a launch constraint
violation before the helper process starts; use the report and system logs to
distinguish that signing failure from a runtime IPC regression.

Signing is configured through `macos/Runner/Configs/Signing.xcconfig`. The
checked-in defaults intentionally avoid a team or certificate identity so local
and CI environments can choose their own signing chain. To run strict
LaunchAgent smoke against a developer-signed build, create the ignored
`macos/Runner/Configs/Signing.local.xcconfig` with local values such as:

```xcconfig
DEVELOPMENT_TEAM = YOURTEAMID
CODE_SIGN_IDENTITY = Apple Development
```

The smoke report includes `signingDiagnostics` for the app and helper bundles.
Use `launchConstraintBlockers` such as `ad_hoc_signature` or
`team_identifier_missing` to distinguish signing setup failures from named XPC
transport regressions.

Profile strict XPC reports also include `xpcRuntimeDiagnostics`. Once signing
blockers are clear, this section separates launchd runtime failures:
`launchd_helper_not_started` means the helper did not write fresh startup
diagnostics, `xpc_listener_not_started` means the process started without
resuming its named listener, and `launchd_mach_service_not_responding` means
the listener evidence exists but the named service still did not answer.
Successful Developer ID profile runs should show fresh helper diagnostics with
`xpcListenerStartAttempted`, `xpcListenerStarted`, and `namedServiceConnected`
set to `true`.

Helper diagnostics are fresh only when the shared diagnostics file matches the
currently running helper PID and the embedded helper bundle/executable path.
The main app reports `helperSharedDiagnosticsStaleReasons` when an old `/tmp`
diagnostics file belongs to a previous helper process or another helper path.
Strict XPC smoke prefers the latest fresh helper diagnostics over a newer stale
sample so old listener evidence cannot mask a real LaunchAgent startup issue.

Initial commands:

- `ping`: verify helper launch and protocol version.
- `permissionStatus`: return Accessibility, screen capture, and system audio
  capability flags.
- `openSettings`: open the requested privacy pane.
- `showPermissionOverlay`: show the floating helper-owned permission overlay.
- `startOnboardingPermissionFlow`: run the same helper-owned transition that an
  onboarding `Allow` button starts.
- `stopAll`: stop active recording and cancel queued input work.
- `screenshot`: capture the main display.
- `listWindows`: list visible windows.
- `focusWindow`: focus a selected window.
- `screenshotWindow`: capture a selected window.
- `moveMouse`: move the pointer after app-level approval and explicit arming in
  smoke tests.
- `click`: click the pointer after app-level approval and the extra click
  arming gate in smoke tests.
- `drag`: drag the pointer after app-level approval and explicit arming in
  smoke tests.
- `scroll`: scroll after app-level approval and explicit arming in smoke tests.
- `typeText`: type text after app-level approval and explicit text-input arming
  in smoke tests.
- `pressKey`: press a key after app-level approval and explicit arming in smoke
  tests.

Migrated commands:

- `screenshot`
- `listWindows`
- `focusWindow`
- `screenshotWindow`
- `moveMouse`
- `click`
- `drag`
- `scroll`
- `typeText`
- `pressKey`
- `startSystemAudioRecording`
- `stopSystemAudioRecording`

## Helper IPC Protocol

The helper IPC protocol uses a typed request envelope across the preferred
LaunchAgent-backed named XPC transport and the observable
distributed-notification fallback:

- `protocolVersion`: currently `1`.
- `requestId`: unique request correlation ID generated by `Caverno.app`.
- `command`: one of the helper command names.
- `senderBundleIdentifier`: expected to be `com.noguwo.apps.caverno`.
- `senderProcessIdentifier`: expected to resolve to the running main app.
- `arguments`: JSON-compatible command arguments.

Every helper response includes the same protocol version, helper identity,
selected transport, preferred transport, fallback transport metadata, `ok`, and
either command-specific fields or structured `code` / `error` / `details`
fields. Unknown or unsupported protocol requests return a structured error
instead of being silently ignored when a request ID is present.

Observation, input, and system audio commands now run in
`Caverno Computer Use.app`, so macOS Screen & System Audio Recording and
Accessibility grants attach to the helper bundle.

## Manual Smoke Checklist

Use the Computer Use smoke-test panel to verify a local build:

1. Launch `Caverno.app`.
2. Open the Computer Use smoke-test panel.
3. Click **Launch Helper** and verify `Helper Installed`, `Helper Running`, and
   `Helper Reachable` become positive.
4. Open Accessibility settings and grant `Caverno Computer Use`.
5. Open Screen & System Audio Recording settings and grant
   `Caverno Computer Use`.
6. Click **Refresh** and verify both permissions are granted.
7. Run **Capture Display** and confirm a screenshot preview appears.
8. Run **List Windows**, select a non-helper window, then run
   **Capture Selected**.
9. Arm **Input Events**, then run **Move Pointer** or **Click Point** against
   the selected screenshot coordinates.
10. Arm **System Audio**, start a short recording, then stop it.
11. Export diagnostics and verify `onboardingSmokeChecklist` contains the
    completed launch, IPC, permission, observation, input, and audio steps.

## Manual Unsafe Smoke

Unsafe smoke checks are local-only and should be run only after the helper is
reachable and the required macOS permissions are granted.

1. Run the normal smoke first:
   `bash tool/run_macos_computer_use_smoke_test.sh --reporter compact`.
2. Confirm the report shows `coreOk=true`, `helperOwnsUnsafeOsActions=true`,
   `mainAppUnsafeOsActionsAllowed=false`, and `stop_helper_work` succeeds.
3. Measure LaunchAgent registration and named XPC reachability:
   `bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --register-xpc-agent`.
4. For an XPC-only strict production gate, add `--strict-xpc`; for a temporary
   registration, add `--cleanup-xpc-agent`.
5. Grant Accessibility and Screen & System Audio Recording to
   `Caverno Computer Use`.
6. Run input and audio checks without clicks:
   `bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --unsafe-armed`.
7. Run the click check only when the pointer target is safe:
   `bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --unsafe-click-armed`.
8. Run the text input check only when the focused text target is safe:
   `bash tool/run_macos_computer_use_smoke_test.sh --reporter compact --unsafe-text-armed`.
9. Inspect `unsafeOperationSummary` and `positiveSmokeGates`. Executed unsafe
   operations must be listed explicitly; skipped operations must include a
   reason.
10. Run **Stop Helper Work** from Settings if any audio or input work remains
   active.

## Safety Invariants

- The main app is the only component that may talk to the LLM.
- The helper accepts only typed commands from the main app and never executes
  raw shell, script, or model text.
- Input and audio commands require an app-level approval decision before the
  helper receives the command.
- Input and sensitive commands require explicit action-time arming in the chat
  approval sheet; a positive approval without arming returns a blocked
  `arming_missing` result and does not call the helper.
- Approval decisions include a risk category: `observe`, `input`, `sensitive`,
  or `recovery`.
- The app records a redacted audit entry for each approval-gated computer-use
  command with timestamp, tool name, risk category, approval result, transport,
  response code, fallback reason, arming requirement, emergency-stop flag,
  success state, and post-action observation metadata. Screenshot payloads,
  audio payloads, and typed text bodies must not be stored in the audit log.
- Input and sensitive commands that require post-action observation run a
  bounded screenshot or status observation after a successful approved action;
  only the observation tool name, success flag, transport, and response code are
  recorded.
- Debug smoke checks for input and system audio require an explicit arming
  toggle; the live smoke harness only runs most of those actions when
  `CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_ARMED=1` or `--unsafe-armed` is set.
- Live text input smoke checks require the additional
  `CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_TEXT_ARMED=1` or
  `--unsafe-text-armed` gate because they can modify focused text fields.
- Live click smoke checks require the additional
  `CAVERNO_MACOS_COMPUTER_USE_SMOKE_UNSAFE_CLICK_ARMED=1` or
  `--unsafe-click-armed` gate because they can change foreground app state.
- Helper IPC diagnostics include `mainAppUnsafeOsActionsAllowed=false`,
  `helperOwnsUnsafeOsActions=true`, and helper-owned action categories so the
  boundary is visible in exported reports.
- Live smoke reports include `unsafeOperationSummary` so manual runs can verify
  which unsafe operations executed and which were skipped.
- The helper returns structured errors with `code`, `error`, and `nextAction`
  when the user must grant a macOS permission.
- Screenshot and audio payloads must be redacted from diagnostics unless the
  user explicitly exports the original artifact.
- `stopAll` must be available even when another helper command is active.

## Onboarding States

The product UI should model the helper setup as a checklist:

1. Helper installed or launchable.
2. Helper reachable over IPC.
3. Accessibility granted to `Caverno Computer Use`.
4. Screen & System Audio Recording granted to `Caverno Computer Use`.
5. Optional positive smoke checks for screenshot, pointer movement, text input,
   and system audio recording.

Each missing state should have one primary action:

- Launch helper.
- Open Accessibility settings with the helper-owned overlay.
- Open Screen & System Audio Recording settings with the helper-owned overlay.
- Refresh status.
- Run a focused smoke check.

## Migration Completion Status

The helper migration is complete for the current MVP path. The original
migration plan has been converted into these completion checks:

- Helper status models and onboarding copy are visible in Settings and the
  Computer Use debug page.
- `Caverno Computer Use.app` is bundled in `Caverno.app` and owns macOS
  Accessibility, Screen & System Audio Recording, input, observation, and
  system-audio operations.
- Helper IPC supports `ping`, `permissionStatus`, `openSettings`,
  `showPermissionOverlay`, `startOnboardingPermissionFlow`, `stopAll`,
  observation, accessibility snapshot, window, input, keyboard, scroll, and
  system-audio commands.
- LaunchAgent-backed named XPC is the preferred production transport, with
  distributed notifications retained only as observable fallback.
- Screenshot, window listing, window focus, window screenshots, input events,
  and system audio recording are routed through the helper backend.
- Input and sensitive helper commands remain behind app-level approval plus
  explicit action-time arming.
- The helper-owned permission overlay is available for Accessibility and
  Screen & System Audio Recording onboarding.
- The main app no longer owns unsafe macOS Computer Use actions. Diagnostics
  report `mainAppUnsafeOsActionsAllowed=false`,
  `helperOwnsUnsafeOsActions=true`, and the helper-owned action categories.

Remaining work is review hardening and user-operated sign-off rather than
migration: the Advanced settings flow, post-merge sanity checks, release
artifacts, manual TCC runtime reports, user-operated desktop action canaries,
LLM canaries, MVP PR review artifacts, and future observe-only real-app
canaries.

## M41 Accessibility Snapshot

M41 adds a read-only accessibility observation surface for element-grounded
Computer Use. `computer_accessibility_snapshot` asks the helper for a bounded
AX tree from the first visible non-Caverno window or a requested `window_id`.
The command is helper-owned, available over the same XPC command parity list,
and blocked by helper path mismatch so the existing helper TCC identity is
preserved.

The snapshot returns `schemaName`, `observationId`, window metadata,
permissions, coordinate space, traversal bounds, element count, truncation
state, redaction metadata, and a bounded `elements` list. Each element includes
an observation-scoped `elementId`, parent id when available, role, subrole,
safe label metadata, frame, enabled state, focused state, child count, and
per-element redaction metadata.

Privacy rules:

- The helper does not export `AXValue`, selected text, attributed text ranges,
  raw attribute values, screenshots, audio payloads, or typed text.
- Labels come only from safe metadata attributes: title, description, help, or
  identifier.
- Labels are capped by `label_max_characters` and truncation is reported both
  per element and in the top-level redaction summary.
- Secure or protected controls keep values omitted; the snapshot only exposes
  metadata needed for target review.

Safety rules:

- `computer_accessibility_snapshot` is planning-allowed because it is
  observation-only.
- It does not call AX mutation APIs such as setting focused windows, raising
  windows, performing AX actions, or posting input events.
- Element IDs are stable only inside the current snapshot. Later milestones
  may use them for approved element-targeted actions, but M41 does not expand
  the action surface.

## M42 Element Grounding

M42 connects visual observations with the accessibility snapshot surface. For
`front_window` and `window` observations that resolve to a `window_id`,
`computer_vision_observe` now asks the helper for a bounded
`computer_accessibility_snapshot` and returns a compact `elementGrounding`
block alongside the screenshot.

`elementGrounding` is deliberately metadata-only. It includes:

- `schemaName=macos_computer_use_element_grounding`, `schemaVersion`, source
  tool, status, snapshot id, window id, coordinate space, input origin, bounds,
  redaction metadata, and truncation metadata.
- A bounded `candidateElements` list selected from focused or likely
  interactive accessibility roles.
- Per-candidate `elementId`, parent id when available, role, subrole, label,
  label source, frame, enabled/focused state, child count, and redaction flags.

Failure handling is non-destructive. If accessibility is denied, the window AX
object is unavailable, the capture failed, or the user disables accessibility
grounding with `include_accessibility=false`, the screenshot observation still
returns and `elementGrounding.status` reports `blocked`, `failed`, or
`skipped` with a concrete code.

M42 does not add element-targeted execution. Desktop actions still use the
existing approval, arming, emergency-stop, coordinate, and post-action review
flow. The model may cite `target.elementId` from the latest
`elementGrounding.candidateElements` as approval metadata, while M43 adds the
execution path that consumes `element_id`.

## M43 Element-Targeted Actions

M43 allows approved helper-owned actions to resolve an `element_id` from the
latest element grounding before using screenshot coordinates. Element IDs are
still observation-scoped, so each action resolves the target by replaying the
same bounded AX traversal against the requested `window_id`.

Supported execution behavior:

- `computer_click` accepts `element_id` with `window_id`, performs AXPress when
  the resolved element supports it, and only falls back to the element frame
  center or caller-provided coordinates when AXPress is unavailable.
- `computer_type_text` accepts `element_id` with `window_id`, focuses the
  resolved element before typing, and reports if it had to click the element
  frame center to focus.
- `computer_focus_window` keeps `window_id` as the primary target and can also
  focus a resolved element when `element_id` is present.

Every element-targeted action reports `elementTargeting` metadata with the
requested id, resolved role and label, window id, frame metadata when
available, the action used, and `elementTargeting.fallbackUsed`. Existing
approval, arming, public-action, exact-text, emergency-stop, post-action
observation, and post-action review boundaries remain unchanged.

## M44 Element-Aware Approval UX

M44 keeps the M43 execution boundary unchanged and upgrades only the approval
surface. The pending approval payload now carries target review metadata from
the tool call so the user can confirm the target before any helper-owned input
is sent.

The approval sheet shows:

- app name and bundle id when provided by the observation or window list;
- window title and window id when available;
- `element_id` or `target.elementId` for element-targeted actions;
- role, label, intended action, and target risk from `target` metadata;
- coordinate fallback metadata when an action still includes screenshot
  coordinates;
- exact text and character count for `computer_type_text`;
- the latest observation context, including observation id, coordinate space,
  source screenshot size, window id, and display id.

M44 does not weaken any policy gate. Approval, unsafe arming, separate
public-action approval, exact-text review, emergency stop availability,
post-action observation, and audit redaction remain the execution boundary.

## M45 Safety Policy Hardening

M45 keeps helper execution unchanged and strengthens the Dart-side policy gate
before any approved action reaches the helper. Target safety classification now
uses explicit `target.risk` metadata plus conservative role, label, and action
tokens.

Target classes:

- `public_action`: posting, sending, submitting, or publishing controls require
  separate public-action approval before execution.
- `secure_field`: secure text fields are blocked and should be handled
  manually by the user.
- `credential`: password, passcode, API key, token, and recovery-key targets
  are blocked and should be handled manually by the user.
- `payment`: payment, checkout, order, billing, cart, and card targets are
  blocked and should be handled manually by the user.
- `destructive`: delete, reset, revoke, wipe, format, uninstall, and danger-zone
  targets are blocked and should be handled manually by the user.

When an approved action still has unresolved safety blockers, Caverno returns
`code=action_policy_blocked` with `approvalBlockers` instead of calling the
helper. This preserves approval UX visibility while keeping the execution
boundary deterministic.

## M46 Element-Grounded LLM Evaluation

M46 adds a report-only evaluation runner for the element-grounded Computer Use
contract:

```bash
bash tool/run_macos_computer_use_m46_element_grounded_llm_eval.sh --fixture-screenshot <mvp-fixture-screenshot.png> --real-app-screenshot <user-provided-real-app-screenshot.png>
```

The report schema is
`macos_computer_use_m46_element_grounded_llm_eval_summary`, with
`m46ElementGroundedLlmEvaluationGate` covering these scenarios:

- `element_target_disambiguation`: candidates include element identity and
  ambiguous targets ask for clarification.
- `exact_text_target_pairing`: exact text is preserved and paired with one
  text-entry element target.
- `public_action_boundary_from_real_app`: public-action targets include
  `separate_public_action_approval_required`.
- `high_risk_target_refusal`: secure-field, payment, and destructive targets
  include M45 hard blockers and refuse execution.
- `stale_observation_recovery`: stale or blocked observation references require
  fresh evidence.
- `coordinate_fallback_refusal`: coordinate-only proposals are refused until a
  fresh element-grounded observation exists.

The runner preserves the same no-TCC and no-desktop-action boundary as M36. CI
can pass `--fixture-suite` for deterministic responses; live runs require both
fixture and real-app screenshots.

## M47 Real-App Observe Pilot

M47 adds a report-only pilot runner that starts from ready M14 real-app observe
evidence and generates the M15-M18 handoff chain:

```bash
bash tool/run_macos_computer_use_m47_real_app_observe_pilot.sh --m14-summary <canary_summary.json>
```

The report schema is `macos_computer_use_m47_real_app_observe_pilot`, with
`m47RealAppObservePilotGate` checking that:

- M14, M15, M16, M17, and M18 are all ready.
- The approved text-entry target label remains stable from M14 candidates
  through M18 approved values.
- The approved exact text remains stable from M16 through M18.
- Public-action labels retain separate approval metadata through M18.
- M18 records fresh observation, target, exact-text, and public-action
  action-time confirmations.
- Generation remains report-only with no LLM call, no TCC operation, and no
  desktop action.

The runner may derive approval values from the selected M14 summary, or callers
can pass explicit `--approved-exact-text`, `--approved-target-label`, and
`--approved-public-action-label` values. It does not open apps, capture
screenshots, click, type, submit, or post.

## M48 User-Operated Action Pilot

M48 adds a report-only pilot gate for one safe user-operated real-app action
cycle:

```bash
bash tool/run_macos_computer_use_m48_user_operated_action_pilot.sh --m47-pilot <real_app_observe_pilot.json> --fresh-observation done --target-confirmed yes --exact-text-confirmed yes --public-action-confirmed <yes-or-not-applicable> --runtime-action succeeded --post-action-observation done --result-reviewed yes --post-action-state stable --follow-up-required no --outcome-accepted yes --next-observe-needed no --safe-target-confirmed yes
```

The report schema is `macos_computer_use_m48_user_operated_action_pilot`, with
`m48UserOperatedActionPilotGate` checking that:

- M47, M18, M20, M22, and M23 evidence are all ready.
- The M18 handoff comes from the selected M47 pilot.
- The user explicitly confirmed a safe target with no secure-field,
  credential, payment, or destructive risk.
- Approved target, exact text, and public-action labels remain stable through
  M20, M22, and M23.
- Public-action targets preserve separate action-time approval evidence.
- M20 records fresh observation, a succeeded user-operated runtime action, and
  post-action observation.
- M22 records reviewed, stable post-action state with no follow-up required.
- M23 accepts and closes the action cycle.
- The runner remains report-only with no LLM call, no TCC operation, and no
  desktop action.

M48 may invoke the existing M20, M22, and M23 report-only scripts, but the
runtime action itself must already have been performed by the user outside the
script. Any follow-up desktop action must start a new observe and approval
cycle.

## M49 Privacy And Audit Release Pack

M49 adds a report-only release-pack gate for redacted Computer Use diagnostics
and ready M48 action-cycle evidence:

```bash
bash tool/run_macos_computer_use_m49_privacy_audit_release_pack.sh --m48-pilot <user_operated_action_pilot.json> --diagnostics <redacted-computer-use-diagnostics.json> --redacted-export-reviewed yes --privacy-copy-reviewed yes --support-diagnostics-reviewed yes --explicit-payload-export-policy-reviewed yes --payload-export-requested no --explicit-payload-export-approved not-requested
```

The report schema is `macos_computer_use_m49_privacy_audit_release_pack`, with
`m49PrivacyAuditReleasePackGate` checking that:

- M48 user-operated action pilot evidence is ready.
- Diagnostics include `macos_computer_use_audit_privacy_controls`, either as a
  top-level report or as `auditPrivacyControls` inside exported diagnostics.
- M37 audit/privacy controls are ready and declare observe, approval,
  execution handoff, emergency stop, and result review event types.
- Default diagnostics export is redacted.
- Redacted field ids include secrets, screenshots, tokens, audio payloads, raw
  tool payloads, and typed text.
- Screenshot, audio, typed text, and raw tool payload exports require explicit
  payload export approval.
- Ordinary diagnostics do not contain raw screenshots, audio payloads, typed
  text, secrets, tokens, authorization values, or raw tool payloads.
- Redacted export, privacy copy, support diagnostics, and explicit payload
  export policy review have all been recorded.
- Any requested raw payload export has separate explicit approval; otherwise
  the payload export state remains `not-requested`.

M49 does not export raw payloads. It only validates existing redacted
diagnostics and records release-pack sign-off metadata before signed beta.

## M50 Signed Beta Gate

M50 adds a report-only signed beta gate for the element-grounded Computer Use
release path:

```bash
bash tool/run_macos_computer_use_m50_signed_beta_gate.sh \
  --signed-beta-checklist <m50-signed-beta-checklist.json> \
  --release-artifact-report <release-artifact-signoff.json> \
  --release-packaging-report <macos_computer_use_release_packaging.json> \
  --m46-element-grounded-llm-eval <canary_summary.json> \
  --m48-user-operated-action-pilot <user_operated_action_pilot.json> \
  --m49-privacy-audit-release-pack <privacy_audit_release_pack.json>
```

The runner writes:

- `macos_computer_use_m50_signed_beta_gate.json`
- `macos_computer_use_m50_signed_beta_gate.md`

The JSON summary uses
`schemaName: macos_computer_use_m50_signed_beta_gate`, `milestone: M50`, and
`m50SignedBetaGate`.

The gate checks:

- M7 signed beta artifact evidence.
- M33 release packaging lane readiness.
- User-recorded notarized beta build evidence.
- User-recorded clean install evidence.
- User-recorded upgrade and migration evidence.
- User-recorded permission grant evidence.
- User-recorded permission revocation recovery evidence.
- User-recorded helper restart evidence.
- User-recorded XPC fallback observability evidence.
- M46 element-grounded LLM evaluation readiness.
- M48 user-operated action-cycle readiness.
- M49 privacy and audit release-pack readiness.

M50 does not sign, notarize, staple, grant TCC, open System Settings, capture
screens, click, type, submit, post, purchase, export raw payloads, or operate
desktop apps. It only reads existing evidence and records whether the signed
beta is ready for the M51 production launch gate refresh.

## M51 Production Launch Gate

M51 adds the production launch gate for the element-grounded Computer Use
release lane:

```bash
bash tool/run_macos_computer_use_m51_production_launch_gate.sh \
  --launch-checklist <m51-launch-checklist.json> \
  --release-artifact-report <release-artifact-signoff.json> \
  --release-packaging-report <macos_computer_use_release_packaging.json> \
  --manual-tcc-report <manual-tcc-summary.json> \
  --m46-element-grounded-llm-eval <canary_summary.json> \
  --m49-privacy-audit-release-pack <privacy_audit_release_pack.json> \
  --m50-signed-beta-gate <macos_computer_use_m50_signed_beta_gate.json> \
  --diagnostics <computer-use-diagnostics.json>
```

The runner writes:

- `macos_computer_use_m51_production_launch_gate.json`
- `macos_computer_use_m51_production_launch_gate.md`

The JSON uses `schemaName: macos_computer_use_m51_production_launch_gate`,
`milestone: M51`, and `launchReviewSummary`.

M51 validates:

- M7 signed artifact readiness.
- M33 packaging readiness for helper identity and Mach service evidence.
- M38 install and migration guardrails from diagnostics.
- User-operated notarization, manual TCC, emergency stop, privacy copy,
  support diagnostics, default-off rollout, rollback, and support escalation
  checklist evidence.
- M46 element-grounded LLM evaluation readiness with no TCC or desktop action.
- M49 privacy/audit release-pack readiness with no raw payload export.
- M50 signed beta readiness.

M51 does not sign, notarize, staple, grant TCC, open System Settings, capture
screens, click, type, submit, post, purchase, export raw payloads, or operate
desktop apps. It only reads existing evidence and records whether the product
release is ready to move to M52 rollout.

## M52 Product Release Rollout

M52 adds the product release rollout gate for element-grounded Computer Use:

```bash
bash tool/run_macos_computer_use_m52_product_release_rollout.sh \
  --product-release-checklist <m52-product-release-checklist.json> \
  --m51-production-launch-gate <macos_computer_use_m51_production_launch_gate.json>
```

The runner writes:

- `macos_computer_use_m52_product_release_rollout.json`
- `macos_computer_use_m52_product_release_rollout.md`

The JSON uses
`schemaName: macos_computer_use_m52_product_release_rollout`, `milestone: M52`,
`releaseRolloutSummary`, and `m52ProductReleaseGate`.

M52 validates:

- M51 production launch evidence is ready for production launch.
- Computer Use remains default off for product release.
- The enablement path stays behind Settings > Advanced.
- The disable path, emergency stop, rollback runbook, support runbook, privacy
  release notes, support diagnostics handoff, rollout monitoring, owner, and
  escalation coverage are signed off by the user-operated release checklist.

M52 does not sign, notarize, staple, grant TCC, open System Settings, capture
screens, click, type, submit, post, purchase, export raw payloads, or operate
desktop apps. It only reads M51 evidence and product release checklist evidence
and records whether element-grounded Computer Use is `ready_for_product_release`.

## M53 Post-Release Guardrails

M53 adds a report-only post-release operations gate for element-grounded
Computer Use:

```bash
bash tool/run_macos_computer_use_m53_post_release_guardrails.sh \
  --post-release-checklist <m53-post-release-checklist.json> \
  --m52-product-release-rollout <macos_computer_use_m52_product_release_rollout.json>
```

The runner writes:

- `macos_computer_use_m53_post_release_guardrails.json`
- `macos_computer_use_m53_post_release_guardrails.md`

The JSON uses
`schemaName: macos_computer_use_m53_post_release_guardrails`, `milestone: M53`,
`postReleaseGuardrailsSummary`, and `m53PostReleaseGuardrailsGate`.

M53 validates:

- M52 product release rollout evidence is ready.
- Computer Use remains default off after release.
- The enablement path stays behind Settings > Advanced.
- Redacted support diagnostics, known issues, incidents, complaints,
  regressions, rollback readiness, hotfix triggers, rollout pause triggers, and
  escalation coverage are signed off by the user-operated post-release
  checklist.

M53 does not sign, notarize, staple, grant TCC, open System Settings, capture
screens, click, type, submit, post, purchase, export raw payloads, or operate
desktop apps. It only reads M52 evidence and post-release checklist evidence
and records whether Computer Use is `ready_for_post_release_operations`.

## M54 Rollout Expansion Gate

M54 adds a report-only rollout expansion gate for element-grounded Computer
Use:

```bash
bash tool/run_macos_computer_use_m54_rollout_expansion_gate.sh \
  --rollout-expansion-checklist <m54-rollout-expansion-checklist.json> \
  --m53-post-release-guardrails <macos_computer_use_m53_post_release_guardrails.json>
```

The runner writes:

- `macos_computer_use_m54_rollout_expansion_gate.json`
- `macos_computer_use_m54_rollout_expansion_gate.md`

The JSON uses
`schemaName: macos_computer_use_m54_rollout_expansion_gate`, `milestone: M54`,
`rolloutExpansionSummary`, and `m54RolloutExpansionGate`.

M54 validates:

- M53 post-release guardrail evidence is ready.
- The proposed cohort, channel, or percentage expansion scope is approved.
- Cohort risk, excluded segments, support capacity, safety metrics, incidents,
  complaints, regressions, rollback readiness, rollout pause readiness,
  communications, owners, escalation handoff, and the next review schedule are
  signed off by the user-operated rollout expansion checklist.

M54 does not sign, notarize, staple, grant TCC, open System Settings, capture
screens, click, type, submit, post, purchase, export raw payloads, or operate
desktop apps. It only reads M53 evidence and rollout expansion checklist
evidence and records whether Computer Use is `ready_for_rollout_expansion`.

## M55 Post-Expansion Monitoring Gate

M55 adds a report-only post-expansion monitoring gate for element-grounded
Computer Use:

```bash
bash tool/run_macos_computer_use_m55_post_expansion_monitoring_gate.sh \
  --post-expansion-monitoring-checklist <m55-post-expansion-monitoring-checklist.json> \
  --m54-rollout-expansion-gate <macos_computer_use_m54_rollout_expansion_gate.json>
```

The runner writes:

- `macos_computer_use_m55_post_expansion_monitoring_gate.json`
- `macos_computer_use_m55_post_expansion_monitoring_gate.md`

The JSON uses
`schemaName: macos_computer_use_m55_post_expansion_monitoring_gate`,
`milestone: M55`, `postExpansionMonitoringSummary`, and
`m55PostExpansionMonitoringGate`.

M55 validates:

- M54 rollout expansion evidence is ready.
- The expanded cohort, channel, percentage, and monitoring window are recorded.
- Safety metrics, support load, incidents, complaints, regressions, rollback
  and rollout pause readiness, owner follow-up, escalation handoff, and the
  next review schedule are signed off by the user-operated post-expansion
  monitoring checklist.
- The approved continuation decision is one of `continue_expansion`,
  `hold_current_cohort`, `pause_rollout`, or `rollback_recommended`.

M55 does not sign, notarize, staple, grant TCC, open System Settings, capture
screens, click, type, submit, post, purchase, export raw payloads, or operate
desktop apps. It only reads M54 evidence and post-expansion monitoring
checklist evidence and records whether Computer Use is
`ready_for_post_expansion_decision`.

## M56 Rollout Decision Handoff Gate

M56 adds a report-only rollout decision handoff gate for element-grounded
Computer Use:

```bash
bash tool/run_macos_computer_use_m56_rollout_decision_handoff_gate.sh \
  --rollout-decision-handoff-checklist <m56-rollout-decision-handoff-checklist.json> \
  --m55-post-expansion-monitoring-gate <macos_computer_use_m55_post_expansion_monitoring_gate.json>
```

The runner writes:

- `macos_computer_use_m56_rollout_decision_handoff_gate.json`
- `macos_computer_use_m56_rollout_decision_handoff_gate.md`

The JSON uses
`schemaName: macos_computer_use_m56_rollout_decision_handoff_gate`,
`milestone: M56`, `rolloutDecisionHandoffSummary`, and
`m56RolloutDecisionHandoffGate`.

M56 validates:

- M55 post-expansion monitoring evidence is ready for a continuation decision.
- The user-operated checklist confirms the decision scope, branch handoff,
  owner, evidence archive, communication review, risk controls, and next
  review.
- The checklist decision and handoff type match the M55 continuation decision:
  `continue_expansion` maps to `next_expansion_cycle_seed`,
  `hold_current_cohort` maps to `monitoring_cadence_hold`, `pause_rollout`
  maps to `rollout_pause_handoff`, and `rollback_recommended` maps to
  `rollback_handoff`.

M56 does not sign, notarize, staple, grant TCC, open System Settings, capture
screens, click, type, submit, post, purchase, export raw payloads, or operate
desktop apps. It only reads M55 evidence and rollout decision handoff checklist
evidence and records whether Computer Use is
`ready_for_rollout_decision_handoff`.

## Verification Gates

- Element-grounded productization: follow
  `docs/macos_computer_use_element_grounding_release_roadmap.md` for M41-M56.
- Static verification: `flutter analyze`, focused unit/widget tests, and
  focused script contract tests pass. After merge, use
  `bash tool/run_macos_computer_use_post_merge_sanity.sh` to run this static
  verification set plus the debug macOS build without TCC or desktop actions.
- Release artifact verification: M7 release sign-off passes for the embedded
  helper bundle, LaunchAgent plist, MachService declaration, bundle identity,
  and signing checks.
- Production IPC verification: `xpcProductionGate` is ready, command parity is
  complete, and DNC fallback remains observable rather than accepted as
  production readiness.
- LLM verification: the MVP fixture LLM canary passes with safe-click,
  type-and-confirm, Spaces switch, observe-again, user-approval boundary, and
  destructive target refusal evidence.
- Manual TCC verification: `manual_tcc` comes only from a user-operated M8
  runtime report or `manual_tcc_report_summary.json`.
- Desktop action verification: `desktop_action_canary` comes only from a
  user-operated safe target run.
- MVP aggregation verification: `run_macos_computer_use_mvp_signoff.sh` or
  `run_macos_computer_use_mvp_demo_readiness.sh` aggregates the provided
  reports and writes blocked next actions when evidence is missing.
- PR review verification: reviewers inspect `PR Review Summary` and
  `PR Review Artifacts` in the MVP handoff, guided demo handoff, and artifact
  index Markdown before final sign-off.
