# Computer Use Debug Display Screenshot Card Extraction

Status: complete on
`feature/computer-use-debug-display-screenshot-card`.

## Task

- Goal: move the Display Screenshot field, capture action, and optional image
  preview out of `computer_use_debug_page.dart` behind an independently
  importable widget and an immutable typed view model.
- User-visible behavior: none. Copy, icons, spacing, numeric keyboard, button
  eligibility, preview keys, active styling, and point selection remain
  unchanged.
- Non-goals: screenshot service calls, result decoding, max-width
  normalization, coordinate-field mutation, diagnostics, smoke execution,
  window capture, input actions, or native Computer Use behavior.

## Context

- The completed diagnostics and audio slices reduced
  `computer_use_debug_page.dart` from 2,275 to 2,145 lines.
- `_buildDisplayScreenshotCard()` still mixes reusable presentation with the
  page-owned max-width controller, screenshot state, and coordinate target.
- The existing image-preview boundary already owns PNG decoding, zoom, active
  border presentation, and viewport-to-source coordinate conversion.

## Current Behavior Contract

- The card title is `Display Screenshot` with the existing main-display
  preview subtitle and desktop icon.
- `Max image width` uses the page-owned text controller and numeric keyboard.
- `Capture Display` is enabled whenever the page is not busy. Display capture
  has no arming or backend-support gate beyond the existing service result.
- The page parses a positive integer from the trimmed field and falls back to
  `1200` for empty, non-numeric, zero, or negative input.
- A successful image result stores the display snapshot and makes it the active
  coordinate target. Missing or invalid image payloads do not replace the
  current snapshot or target.
- No preview is shown before a snapshot exists. A snapshot uses the existing
  preview and tap-area keys, receives the page-owned active flag, and dispatches
  selected source coordinates exactly once to the supplied callback.
- The card remains between onboarding and window controls.

## Implementation Notes

1. Add an immutable `ComputerUseDebugDisplayScreenshotViewModel` with busy,
   snapshot, and active-preview state plus derived capture eligibility.
2. Add `ComputerUseDebugDisplayScreenshotCard` with the existing max-width
   controller and explicit capture and point-selection callbacks.
3. Replace `_buildDisplayScreenshotCard()` with typed widget construction in
   the page.
4. Keep `_maxWidth()`, `_run()`, service invocation, `_imageSnapshot()`,
   snapshot storage, coordinate-target state, and `_selectImagePoint()` in the
   page.
5. Add direct widget tests for idle, busy, inactive-preview, and active-preview
   paths, including copy, keys, callbacks, and controller reuse.
6. Add page tests for configured and fallback max-width arguments and preserve
   the existing display-preview-to-input product path.
7. Remove the obsolete builder and lower exact line-count ratchets.

## Constraints

- Do not move the max-width controller or any service, provider, result,
  diagnostics, smoke, coordinate-field, or native action logic.
- Do not let the extracted widget import Riverpod, Computer Use services,
  platform APIs, page types, or mutable page state other than the explicitly
  supplied text controller.
- Do not add an arming requirement, eager input validation, platform gate,
  error message, or screenshot state mutation.
- Do not change visible English copy, icons, keys, keyboard type, active
  preview styling, or card spacing.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_buildDisplayScreenshotCard`, `_maxWidthController`,
  `_maxWidth`, `_displayScreenshot`, `_coordinateTarget`, `_imageSnapshot`,
  `_selectImagePoint`, and `computer-use-display-preview`.
- Files inspected: the debug page, image-preview and status-primitives
  boundaries, page product tests and fake service, audio-card pattern,
  line-count ratchets, refactoring plan, roadmap, and active worktrees.
- Follow-up tasks found: window capture owns selection and list state, while
  input controls own coordinate and text controllers. Keep both out of this
  slice.

## Acceptance Criteria

- The widget and view model are independently importable and directly tested
  without a provider scope, native service, platform permission, or file IO.
- Capture eligibility exactly matches the existing `!isBusy` expression and
  adds no arming or availability requirement.
- The page retains positive-integer parsing and the `1200` fallback for invalid
  max-width input.
- Product-path tests retain screenshot arguments, snapshot storage, active
  display selection, preview tap conversion, and source dimensions passed to
  input actions.
- The page shrinks and both it and the new boundary have exact non-increasing
  line-count ratchets.
- Focused and full repository verification pass without analyzer findings or
  real desktop actions.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/presentation/widgets/computer_use_debug_display_screenshot_card_test.dart \
  --test test/features/settings/presentation/pages/computer_use_debug_page_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: extracted the Display Screenshot field, capture action, and optional
  preview into an independently importable 81-line card with an immutable view
  model and explicit callbacks. The page retains the text controller,
  max-width normalization, service invocation, result decoding, snapshot and
  coordinate state, and input-field mutation. The page fell from 2,145 to
  2,114 lines.
- Tests run: the focused verifier passed 78 root tests plus 13 internal-package
  tests. The full verifier passed analysis, 3,811 root tests, and 13
  internal-package tests.
- Coverage or low-coverage notes: repository line coverage reached 74.37%
  (52,807/71,008). The extracted display screenshot card reached 100.00% line
  coverage (17/17), and the coordinating debug page reached 92.31% (912/988).
- Risks or follow-ups: no native desktop action was executed. The next smallest
  coherent presentation boundary is the input card; characterize busy, armed,
  and coordinate-target eligibility plus controller and callback wiring before
  moving it.
