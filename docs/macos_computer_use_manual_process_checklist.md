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
flutter analyze
flutter test test/features/settings/presentation/pages/settings_page_test.dart \
  test/features/settings/presentation/pages/computer_use_debug_page_test.dart \
  test/tool/run_macos_computer_use_smoke_test_test.dart \
  test/core/services/macos_computer_use_service_test.dart \
  test/core/services/macos_computer_use_setup_test.dart \
  test/core/services/macos_computer_use_transport_test.dart -r compact
flutter build macos --debug
```

Treat TCC grants, helper foreground checks, smoke sequence execution, and
desktop action canaries as user-operated follow-ups. Ask the user to run the
manual commands and provide the generated report when runtime evidence is
needed.

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
