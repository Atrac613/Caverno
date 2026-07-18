# Computer Use Debug Audio Card Extraction

Status: complete on `feature/computer-use-debug-audio-card`.

## Task

- Goal: move the System Audio arming, recording-state, and start or stop action
  presentation out of `computer_use_debug_page.dart` behind an independently
  importable widget and an immutable typed view model.
- User-visible behavior: none. Copy, icons, colors, spacing, arming state,
  recording state, button order, and enabled or disabled conditions remain
  unchanged.
- Non-goals: audio service calls, ScreenCaptureKit arguments, start or stop
  result handling, smoke completion, diagnostic state, manual smoke execution,
  permission display, or native Computer Use actions.

## Context

- The diagnostics/result slice reduced `computer_use_debug_page.dart` from
  2,275 to 2,198 lines.
- `_buildAudioCard()` still mixes three page booleans with reusable status
  primitives and two service-bound callbacks.
- `_startAudioRecording()` and stop-result handling must remain page-owned so
  the extraction cannot alter arming reset, recording state, smoke completion,
  or error behavior.

## Current Behavior Contract

- The card title is `System Audio` with the existing ScreenCaptureKit subtitle.
- `System Audio Armed` reflects the page-owned arming flag and can change only
  while the page is not busy and no recording is active.
- Recording state uses `radio_button_checked` in the theme error color with
  `Recording active`, or `radio_button_unchecked` in the disabled color with
  `Not recording`.
- `Start Recording` is enabled only when the page is not busy, no recording is
  active, and the action is armed.
- `Stop Recording` is enabled only when the page is not busy and a recording is
  active.
- Start precedes stop. Each enabled action invokes exactly its supplied callback
  once; the widget does not mutate recording or arming state itself.
- The card does not add a separate platform or backend-support gate. Existing
  service results remain the source of unsupported or permission failures.
- The page keeps the audio card between input controls and diagnostics.

## Implementation Notes

1. Add an immutable `ComputerUseDebugAudioViewModel` with busy, recording, and
   armed flags plus derived toggle, start, and stop eligibility.
2. Add `ComputerUseDebugAudioCard` using the existing section-title and arming
   primitives with explicit arming, start, and stop callbacks.
3. Replace `_buildAudioCard()` with typed widget construction in the page.
4. Keep `_startAudioRecording()` and the existing stop closure in the page,
   including all `_run()` and result-state behavior.
5. Add direct tests for idle-unarmed, idle-armed, recording, and busy states,
   exact copy and icons, callback dispatch, and disabled controls.
6. Remove the obsolete builder and lower exact line-count ratchets.

## Constraints

- Do not move `_startAudioRecording()`, `_run()`, manual smoke logic, audio
  service calls, result decoding, or diagnostic serialization.
- Do not let the extracted widget import Riverpod, Computer Use services,
  platform APIs, page types, or mutable controllers.
- Do not add platform availability or system-audio support behavior that the
  current card does not have.
- Do not change visible English copy, icon choices, theme colors, action order,
  arming reset, smoke completion, result handling, or card spacing.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_buildAudioCard`, `_audioRecording`,
  `_audioRecordingArmed`, `_startAudioRecording`,
  `stopSystemAudioRecording`, and `ComputerUseDebugArmSwitch`.
- Files inspected: the debug page, status-primitives boundary, page product
  tests and fake service, diagnostics task, line-count ratchets, refactoring
  plan, roadmap, and active worktrees.
- Follow-up tasks found: input controls use separate coordinate and text
  controller state and remain out of scope for this slice.

## Acceptance Criteria

- The widget and view model are independently importable and directly tested
  without a provider scope, native service, platform permission, or file IO.
- Derived eligibility exactly matches the existing busy, recording, and armed
  boolean expressions.
- Product-path tests retain successful start and stop behavior, service call
  counts, arming safety, manual-smoke behavior, and result handling.
- Direct tests cover idle-unarmed, idle-armed, active-recording, and busy paths.
- The page shrinks and both it and the new boundary have exact non-increasing
  line-count ratchets.
- Focused and full repository verification pass without analyzer findings or
  real desktop actions.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/presentation/widgets/computer_use_debug_audio_card_test.dart \
  --test test/features/settings/presentation/pages/computer_use_debug_page_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: extracted the System Audio presentation into an independently
  importable 99-line card with an immutable view model and explicit callbacks.
  The page retains all recording service calls, arming reset, result handling,
  smoke completion, and diagnostic state. The page fell from 2,198 to 2,145
  lines.
- Tests run: the focused verifier passed 76 root tests plus 13 internal-package
  tests. The full verifier passed analysis, 3,803 root tests, and 13
  internal-package tests.
- Coverage or low-coverage notes: repository line coverage remained 74.00%
  (54,020/73,000). The extracted audio card reached 100.00% line coverage
  (30/30), and the coordinating debug page reached 92.35% (918/994).
- Risks or follow-ups: no native desktop action was executed. The next smallest
  coherent presentation boundary is the display screenshot card; characterize
  max-width input, busy and armed eligibility, preview state, and coordinate
  selection before moving it.
