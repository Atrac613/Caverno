# macOS Computer Use Helper Architecture

## Status

This document defines the target split between `Caverno.app` and a separate
`Caverno Computer Use.app` helper. The helper target is bundled inside
`Caverno.app`, can be launched from the settings smoke-test panel, and now owns
permission status, System Settings shortcuts, reachability checks, emergency
stop requests, visual observation, window focus, input events, and system audio
recording.

## Goals

- Keep chat, model configuration, memory, MCP orchestration, and network access
  in `Caverno.app`.
- Keep Accessibility, screen capture, input events, and system audio capture in
  `Caverno Computer Use.app`.
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
- The helper milestone does not need to replace the temporary IPC transport.
  XPC can replace distributed notifications after the helper boundary is stable.

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

- Read the current desktop through `computer_vision_observe`.
- Run one explicitly armed `computer_click`.
- Run a second `computer_vision_observe` and require an attached image.
- Report the result through `desktopActionCanaryGate`.

Non-goals:

- Automating TCC grants or operating System Settings on behalf of the user.
- Proving arbitrary LLM-chosen click safety.
- Replacing the LLM/tool-loop canary or the manual M8 TCC sign-off.

Manual run after the user grants Accessibility and Screen & System Audio
Recording and prepares a safe click target:

```bash
bash tool/run_macos_computer_use_desktop_action_canary.sh
```

The runner writes
`macos_computer_use_desktop_action_canary_<timestamp>/canary_summary.json` and
`.md` under `build/integration_test_reports/`. The summary schema is
`macos_computer_use_desktop_action_canary_summary`, and each run classifies
failures such as `initial_observe_failed`, `click_failed_or_skipped`, and
`post_click_observe_failed`.

The LLM live canaries and the Computer Use live canary cover different risks.
`tool/run_plan_mode_ping_cli_live_canary.sh` validates the live LLM,
tool-calling, saved-task recovery, and coding workflow behavior.
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
  --manual-tcc-report <manual-tcc-report-or-summary.json> \
  --desktop-action-canary-summary <desktop-action-canary-summary.json>
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
fresh LLM/tool-loop evidence is needed:

```bash
CAVERNO_LLM_BASE_URL=... \
CAVERNO_LLM_API_KEY=... \
CAVERNO_LLM_MODEL=... \
bash tool/run_macos_computer_use_release_readiness.sh --ci --refresh-llm-canary
```

If any `CAVERNO_LLM_*` value is missing, the wrapper skips the LLM refresh and
falls back to discovering existing LLM canary summaries.

The wrapper writes preset-specific readiness artifacts:

- `macos_computer_use_release_readiness_ci.json`
- `macos_computer_use_release_readiness_ci.md`
- `macos_computer_use_release_readiness_signoff.json`
- `macos_computer_use_release_readiness_signoff.md`
- `macos_computer_use_readiness_artifact_index.json`
- `macos_computer_use_readiness_artifact_index.md`

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
- LLM/tool-loop readiness through the latest Plan Mode ping CLI canary summary.

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

Before opening or merging a PR for this milestone, review the artifact index,
the CI readiness Markdown, and the sign-off readiness Markdown. The expected
pre-manual-TCC state is:

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

The temporary distributed-notification transport uses a typed request envelope:

- `protocolVersion`: currently `1`.
- `requestId`: unique request correlation ID generated by `Caverno.app`.
- `command`: one of the helper command names.
- `senderBundleIdentifier`: expected to be `com.noguwo.apps.caverno`.
- `senderProcessIdentifier`: expected to resolve to the running main app.
- `arguments`: JSON-compatible command arguments.

Every helper response includes the same protocol version, helper identity
metadata, `ok`, and either command-specific fields or structured `code` /
`error` / `details` fields. Unknown or unsupported protocol requests return a
structured error instead of being silently ignored when a request ID is present.

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

## Migration Plan

1. Keep the current in-process native channel as the compatibility backend.
2. Add helper-oriented status models and onboarding copy to the debug page.
3. Add the `Caverno Computer Use.app` target with a minimal window and no
   privileged operations.
4. Add IPC `ping`, `permissionStatus`, `openSettings`, and `stopAll`.
5. Move permission status and settings shortcuts to the helper backend.
6. Bundle the helper in `Caverno.app` and launch it from the permission panel.
7. Move screenshot, window listing, window focusing, and window screenshots.
8. Move input events behind the existing approval and arming flow.
9. Move system audio recording behind the existing approval and arming flow.
10. Add the helper-owned permission overlay for Accessibility and Screen &
    System Audio Recording onboarding.
11. Remove or disable privileged computer-use APIs from the main app once parity
    is verified.

## Verification Gates

- Unit tests cover checklist state and user-facing next actions.
- Widget tests cover missing and granted permission states.
- `flutter analyze` passes.
- Focused computer-use tests pass.
- `flutter build macos --debug` passes.
- Manual smoke tests cover missing permissions, each single-permission state,
  both permissions granted, stale windows, and emergency stop.
