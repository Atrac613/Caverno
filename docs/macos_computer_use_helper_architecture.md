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
- The overlay includes `Done`, `Recheck`, and `Back` controls so the user can
  return to Caverno's setup flow after granting permissions.
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
- `bash tool/run_macos_computer_use_existing_helper_probe.sh --require-capture`
  can be used after a successful grant to verify the existing built helper
  without triggering another Flutter rebuild.
- Add `--require-helper-path-match` to the existing-helper probe when the
  sign-off must prove that the currently running helper is the same bundle path
  Caverno will launch.
- Add `--replace-helper` when the probe should terminate a running helper from
  a different path and launch the configured helper path before checking.

The drag/drop sign-off is intentionally manual. Adding the helper to macOS
privacy lists changes system privacy settings, so it must only happen after an
explicit action-time confirmation from the person operating the Mac.

Manual sign-off notes:

- 2026-04-28: `bash tool/run_macos_computer_use_smoke_test.sh --overlay-smoke`
  passed after the tile-target transition update. Both Accessibility and Screen
  & System Audio Recording overlays reported `overlayShown`,
  `draggableTileReady`, and matching permission identifiers. The current debug
  helper path still needs Screen Recording before capture readiness can pass,
  and the onboarding transition gate still requires an action-time `Allow`
  click.
- 2026-04-28: `bash tool/run_macos_computer_use_smoke_test.sh --require-overlay`
  passed with both permission overlays reporting `overlayShown` and
  `draggableTileReady`.
- 2026-04-28: System Settings accepted `Caverno Computer Use.app` through the
  standard Add flow for Accessibility and Screen & System Audio Recording.
  After restarting the helper, the helper onboarding UI reported both
  permissions as `Done`.
- 2026-04-28: The helper onboarding UI **Verify** action completed display and
  window observation checks: display screenshot `3600 x 2338 px` and window
  capture `Codex #203679`.
- Drag/drop tile acceptance remains a separate hands-on check. The successful
  permission grant above used the macOS Add flow because the running debug
  helper path must match the exact helper bundle that macOS records in TCC.

Drag/drop sign-off runbook:

- Run `bash tool/run_macos_computer_use_existing_helper_probe.sh --replace-helper --require-helper-path-match`
  and confirm the running helper path is the helper bundle intended for
  sign-off.
- If the path check passes but permissions are missing, grant that exact helper
  bundle in System Settings before continuing.
- Run `bash tool/run_macos_computer_use_smoke_test.sh --require-overlay` to
  show both overlays and confirm `draggableTileReady` is true.
- Drag the overlay tile into Accessibility and Screen & System Audio Recording.
  Record whether macOS accepts the drop, requests Quit & Reopen, or requires the
  standard Add flow fallback.

Follow-on milestones:

- M2: Complete capture, input, and optional system-audio readiness using the
  live smoke gates.
- M3: Harden unsafe action audit, arming, and emergency-stop behavior.
- M4: Promote named XPC and LaunchAgent registration to the production IPC
  path.
- M5: Connect the vision LLM loop to the approved helper tool surface.

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

## IPC Boundary

The main app should call the helper through a small local IPC surface. XPC is the
preferred production transport because it is native to macOS app bundles and can
be constrained to the bundled helper. A Unix domain socket or localhost HTTP
transport can be used as a temporary development transport if it accelerates
iteration.

The current helper milestone uses `DistributedNotificationCenter` as the active
request/response transport so the separate bundled app can prove the boundary.
XPC is exposed as an experimental preferred transport for `ping`,
`permissionStatus`, `openSettings`, `showPermissionOverlay`,
`startOnboardingPermissionFlow`, `stopAll`, `screenshot`, `listWindows`,
`focusWindow`, `screenshotWindow`, `moveMouse`, `click`, `drag`, `scroll`,
`typeText`, `pressKey`, `startSystemAudioRecording`, and
`stopSystemAudioRecording`; when the named service is unavailable, the app
records the preferred attempt and falls back to
`DistributedNotificationCenter`. XPC should not be treated as production-ready
until the named service and all migrated commands pass parity smoke checks.

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

The current named XPC attempt uses an external helper-app Mach service name.
`Caverno.app` now embeds a `SMAppService` LaunchAgent plist at
`Contents/Library/LaunchAgents/com.noguwo.apps.caverno.computer-use.plist`.
The plist uses `BundleProgram` to point at
`Contents/Helpers/Caverno Computer Use.app/Contents/MacOS/Caverno Computer Use`
and declares the `com.noguwo.apps.caverno.computer-use.xpc` Mach service. The
named service is expected to fall back until that LaunchAgent is registered and
approved by macOS. Diagnostics expose
`xpcRegistrationRequirement`, `xpcProductionBlockers`, and
`xpcProductionNextAction` so onboarding can distinguish a running helper process
from production-ready XPC reachability.

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
same JSON marker/report path as live smoke. Flutter Driver does not support
release-mode desktop correctness runs, so runtime named-XPC smoke should use
debug or profile mode.

Release builds should use the same embedded helper and LaunchAgent layout as
debug builds. Before notarization work, run:

`flutter build macos --release`

Then verify `Caverno.app` still contains
`Contents/Library/LaunchAgents/com.noguwo.apps.caverno.computer-use.plist` and
`Contents/Helpers/Caverno Computer Use.app`. To verify the release app carries
the helper, LaunchAgent plist, Mach service declaration, and valid signature,
run:

`bash tool/run_macos_computer_use_smoke_test.sh --release --strict-xpc --cleanup-xpc-agent`

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
- Approval decisions include a risk category: `observe`, `input`, `sensitive`,
  or `recovery`.
- The app records a redacted audit entry for each approval-gated computer-use
  command with timestamp, tool name, risk category, approval result, transport,
  response code, fallback reason, success state, and post-action observation
  metadata. Screenshot payloads, audio payloads, and typed text bodies must not
  be stored in the audit log.
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
