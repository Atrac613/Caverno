# Computer Use Debug Input Card Extraction

Status: complete on `feature/computer-use-debug-input-card`.

## Task

- Goal: move Input Smoke Checks presentation and action eligibility out of
  `computer_use_debug_page.dart` behind an independently importable widget and
  an immutable typed view model.
- User-visible behavior: none. Copy, icons, spacing, field order, keyboard
  types, arming state, coordinate-target summary, action order, and enabled or
  disabled conditions remain unchanged.
- Non-goals: controller ownership, coordinate parsing, source-coordinate
  arguments, service calls, text validation, snackbars, smoke completion,
  disarming, screenshot selection, or native Computer Use actions.

## Context

- The completed diagnostics, audio, and display-screenshot slices reduced
  `computer_use_debug_page.dart` from 2,275 to 2,114 lines.
- `_buildInputCard()` still mixes three page-owned text controllers and three
  state flags with reusable arming, target-summary, field, and action
  presentation.
- Move and click require a coordinate target, while type intentionally does
  not. All three actions require explicit arming and a non-busy page.

## Current Behavior Contract

- The card title is `Input Smoke Checks` with the existing explicit-input
  subtitle and click icon.
- `Input Events Armed` reflects page-owned state and can change only while the
  page is not busy.
- The coordinate-target row displays the exact page-owned active-source label.
- X and Y use page-owned controllers, numeric keyboards, and remain editable
  while actions are busy. `Text to type` also remains editable while busy.
- `Move Pointer` and `Click Point` are enabled only when the page is not busy,
  input is armed, and a valid display or window coordinate target exists.
- `Type Text` is enabled only when the page is not busy and input is armed; it
  does not require a screenshot coordinate target.
- Actions remain ordered as move, click, and type. Each enabled action invokes
  exactly its supplied callback once; the widget does not mutate arming,
  controllers, target state, or smoke state.
- The page continues to reject non-numeric coordinates and blank trimmed text
  with the existing snackbars. Rejected input stays armed. A valid attempted
  action disarms after page-owned execution, and type forwards the original
  untrimmed text.
- The card remains between window targeting and System Audio.

## Implementation Notes

1. Add an immutable `ComputerUseDebugInputViewModel` with busy, armed,
   coordinate-target availability, and target-label state plus derived arming,
   move, click, and type eligibility.
2. Add `ComputerUseDebugInputCard` with the three existing page-owned
   controllers and explicit arming, move, click, and type callbacks.
3. Replace `_buildInputCard()` with typed widget construction in the page.
4. Keep `_coordinates()`, `_coordinateArguments()`, `_movePointer()`,
   `_clickPoint()`, `_typeText()`, snackbars, smoke state, and disarming in the
   page.
5. Add direct tests for idle-unarmed, armed-without-target, armed-with-target,
   and busy paths, including controller reuse and callback order.
6. Add page tests for blank-text rejection and original-text forwarding with
   post-attempt disarming. Preserve existing display and window coordinate
   argument product paths.
7. Remove the obsolete builder and lower exact line-count ratchets.

## Constraints

- Do not move or recreate the X, Y, or text controllers in the widget.
- Do not let the extracted widget import Riverpod, Computer Use services,
  platform APIs, page types, coordinate-target enums, or mutable page state
  other than the explicitly supplied text controllers.
- Do not disable text fields while busy or add a coordinate-target requirement
  to Type Text.
- Do not change validation, trimming, source dimensions, window IDs, click
  arguments, success tracking, disarming, visible English copy, icons, field or
  action order, keyboard types, or card spacing.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_buildInputCard`, `_inputActionsArmed`, `_hasCoordinateTarget`,
  `_coordinateTargetLabel`, `_xController`, `_yController`, `_textController`,
  `_movePointer`, `_clickPoint`, `_typeText`, and `_disarmInputActions`.
- Files inspected: the debug page, status-primitives boundary, page product
  tests and fake service, audio and display-card patterns, line-count ratchets,
  refactoring plan, roadmap, and active worktrees.
- Follow-up tasks found: window targeting owns list, selection, bounds, focus,
  screenshot, and preview state. Keep it out of this slice.

## Acceptance Criteria

- The widget and view model are independently importable and directly tested
  without a provider scope, native service, platform permission, or file IO.
- Derived eligibility exactly matches the existing busy, armed, and
  coordinate-target expressions, including Type Text's target independence.
- All fields retain their page-owned controllers and remain editable while
  busy, while arming and action callbacks are disabled.
- Product-path tests retain coordinate argument mapping, invalid-input
  snackbars, original-text forwarding, post-attempt disarming, and service call
  counts.
- The page shrinks and both it and the new boundary have exact non-increasing
  line-count ratchets.
- Focused and full repository verification pass without analyzer findings or
  real desktop actions.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/presentation/widgets/computer_use_debug_input_card_test.dart \
  --test test/features/settings/presentation/pages/computer_use_debug_page_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: extracted the Input Smoke Checks presentation into an independently
  importable 133-line card with an immutable view model and explicit callbacks.
  The page retains all three text controllers, validation, source-coordinate
  arguments, service calls, snackbars, success tracking, and disarming. The
  page fell from 2,114 to 2,037 lines.
- Tests run: the focused verifier passed 81 root tests plus 13 internal-package
  tests. The full verifier passed analysis, 3,818 root tests, and 13
  internal-package tests.
- Coverage or low-coverage notes: repository line coverage reached 74.39%
  (52,832/71,023). The extracted input card reached 100.00% line coverage
  (34/34), and the coordinating debug page reached 93.19% (903/969).
- Risks or follow-ups: no native desktop action was executed. The next unowned
  action boundary is the window-targeting card; characterize copied window
  snapshots, selected-ID transitions, action eligibility, and preview cleanup
  before moving it.
