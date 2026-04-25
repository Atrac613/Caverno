# macOS Computer Use Helper Architecture

## Status

This document defines the target split between `Caverno.app` and a separate
`Caverno Computer Use.app` helper. The current implementation still runs the
native computer-use channel inside `Caverno.app`; the migration should keep the
public tool contracts stable while moving privileged macOS work behind the
helper boundary.

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
- The first helper milestone does not need to move every existing operation at
  once. Permission status and settings shortcuts are enough to prove the
  boundary.

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

Initial commands:

- `ping`: verify helper launch and protocol version.
- `permissionStatus`: return Accessibility, screen capture, and system audio
  capability flags.
- `openSettings`: open the requested privacy pane.
- `stopAll`: stop active recording and cancel queued input work.

Later commands:

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

## Safety Invariants

- The main app is the only component that may talk to the LLM.
- The helper accepts only typed commands from the main app and never executes
  raw shell, script, or model text.
- Input and audio commands require an app-level approval decision before the
  helper receives the command.
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
- Open Accessibility settings.
- Open Screen & System Audio Recording settings.
- Refresh status.
- Run a focused smoke check.

## Migration Plan

1. Keep the current in-process native channel as the compatibility backend.
2. Add helper-oriented status models and onboarding copy to the debug page.
3. Add the `Caverno Computer Use.app` target with a minimal window and no
   privileged operations.
4. Add IPC `ping`, `permissionStatus`, `openSettings`, and `stopAll`.
5. Move permission status and settings shortcuts to the helper backend.
6. Move screenshot and window listing.
7. Move input events behind the existing approval and arming flow.
8. Move system audio recording behind the existing approval and arming flow.
9. Remove privileged computer-use APIs from the main app once parity is verified.

## Verification Gates

- Unit tests cover checklist state and user-facing next actions.
- Widget tests cover missing and granted permission states.
- `flutter analyze` passes.
- Focused computer-use tests pass.
- `flutter build macos --debug` passes.
- Manual smoke tests cover missing permissions, each single-permission state,
  both permissions granted, stale windows, and emergency stop.
