# Computer Use Debug Window Targeting Card Extraction

Status: complete on
`feature/computer-use-debug-window-targeting-card`.

## Task

- Goal: move Window Targeting presentation and action eligibility out of
  `computer_use_debug_page.dart` behind an independently importable widget,
  immutable display items, and an immutable typed view model.
- User-visible behavior: none. Copy, icons, spacing, action order, dropdown
  behavior, window labels and bounds, preview keys, active styling, and enabled
  or disabled conditions remain unchanged.
- Non-goals: window-response parsing, selection mutation, preview or coordinate
  cleanup, max-width normalization, service calls, result decoding, smoke
  execution, or native Computer Use actions.

## Context

- The completed diagnostics, audio, display, and input slices reduced
  `computer_use_debug_page.dart` from 2,275 to 2,037 lines.
- `_buildWindowCard()` still mixes raw service maps, selected-window state,
  action execution, dropdown presentation, and image-preview presentation.
- Raw window maps remain useful for diagnostics and service argument assembly,
  but the extracted widget needs only stable IDs and formatted labels.

## Current Behavior Contract

- The card title is `Window Targeting` with the existing list, focus, and
  capture subtitle and window icon.
- `List Windows` is enabled whenever the page is not busy and sends the
  page-owned request with `include_current_app: true` and `max_windows: 80`.
- `Focus Selected` and `Capture Selected` are enabled only when the page is not
  busy and a window ID is selected.
- Actions remain ordered as list, focus, and capture. Each enabled action
  invokes exactly its supplied callback once.
- The dropdown is absent when no valid windows exist. Otherwise it is expanded,
  keyed by the selected ID, shows page-formatted labels, and can change only
  while the page is not busy.
- Window results accept integer-compatible IDs, discard entries without a
  valid ID, copy retained maps, preserve the selected ID when it still exists,
  and otherwise select the first valid window or clear selection.
- Changing to a different selected ID clears the current window preview and
  clears a window coordinate target. Re-selecting the same ID changes nothing.
- The selected window's page-formatted bounds label is shown below the
  dropdown. Missing bounds render `Window bounds unavailable`.
- A window preview remains visible while busy, uses the existing preview and
  tap-area keys, reflects the page-owned active flag, and dispatches selected
  source coordinates exactly once.
- Focus forwards the selected ID and existing debug reason. Capture forwards
  the selected ID and normalized max width; a valid result stores the preview
  and activates the window coordinate target.
- The card remains between display capture and input controls.

## Implementation Notes

1. Add an immutable `ComputerUseDebugWindowItem` with ID, label, and bounds
   label.
2. Add `ComputerUseDebugWindowViewModel` with a defensive unmodifiable item
   snapshot, busy and selected state, optional image snapshot, active-preview
   state, and derived action and selection eligibility.
3. Add `ComputerUseDebugWindowTargetingCard` with explicit list, focus,
   capture, selected-ID, and point-selection callbacks.
4. Replace `_buildWindowCard()` with typed widget construction. Add page-owned
   methods for formatting items, executing actions, and applying selection
   changes.
5. Keep `_storeWindows()`, raw maps, `_windowId()`, label and bounds formatting,
   `_maxWidth()`, `_run()`, `_imageSnapshot()`, snapshot state, coordinate
   state, and `_selectImagePoint()` in the page.
6. Add direct tests for empty, selected, preview, and busy states, immutable
   list snapshots, action order, dropdown dispatch, and preview callbacks.
7. Add page tests for list and focus arguments plus selection-change preview
   cleanup and selected-window capture. Preserve existing window-preview input
   arguments and smoke sequence behavior.
8. Remove the obsolete builder and lower exact line-count ratchets.

## Constraints

- Do not pass raw service response maps into the extracted widget.
- Do not move window-response parsing, selected-ID mutation, screenshot or
  coordinate cleanup, service execution, result decoding, or smoke state.
- Do not let the extracted widget import Riverpod, Computer Use services,
  platform APIs, page types, coordinate-target enums, or mutable page state.
- Do not hide the preview while busy, clear state inside the widget, or change
  ID coercion, fallback selection, request arguments, formatted copy, icons,
  keys, field order, action order, or card spacing.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_buildWindowCard`, `_windows`, `_selectedWindowId`,
  `_windowScreenshot`, `_storeWindows`, `_selectedWindow`, `_windowId`,
  `_windowLabel`, `_windowBoundsLabel`, `_windowTitle`, and
  `_CoordinateTarget.window`.
- Files inspected: the debug page, image-preview boundary, page product tests
  and fake service, display and input-card patterns, line-count ratchets,
  refactoring plan, roadmap, and active worktrees.
- Follow-up tasks found: after this action boundary, the remaining large debug
  page code is permission, runtime, diagnostics assembly, and smoke
  coordination rather than another peer action card.

## Acceptance Criteria

- The widget, item, and view model are independently importable and directly
  tested without a provider scope, native service, platform permission, or
  file IO.
- The view model snapshots its item list and derives list, focus, capture, and
  selection eligibility exactly from busy and selected state.
- The page retains compatible ID parsing, defensive raw-map copies, selected-ID
  preservation or fallback, and selection-change cleanup.
- Product-path tests retain list, focus, and capture arguments, window label and
  bounds copy, preview activation and cleanup, preview tap conversion, and
  source dimensions passed to input actions.
- The page shrinks and both it and the new boundary have exact non-increasing
  line-count ratchets.
- Focused and full repository verification pass without analyzer findings or
  real desktop actions.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/presentation/widgets/computer_use_debug_window_targeting_card_test.dart \
  --test test/features/settings/presentation/pages/computer_use_debug_page_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: extracted Window Targeting presentation into an independently
  importable 163-line card with immutable display items, a defensive typed view
  model, and explicit callbacks. The page retains raw response maps, parsing,
  formatting, selection and cleanup mutation, service execution, result
  decoding, and coordinate state. The page fell from 2,037 to 1,991 lines.
- Tests run: the focused verifier passed 83 root tests plus 13 internal-package
  tests. The full verifier passed analysis, 3,824 root tests, and 13
  internal-package tests.
- Coverage or low-coverage notes: repository line coverage reached 74.41%
  (52,877/71,063). The extracted window-targeting card reached 100.00% line
  coverage (50/50), and the coordinating debug page reached 93.64% (898/959).
- Risks or follow-ups: no native desktop action was executed. The peer action
  cards are now extracted. The next narrow presentation boundary is the
  permission checklist; characterize ready, warning, and unknown styling while
  keeping setup evaluation page-owned.
