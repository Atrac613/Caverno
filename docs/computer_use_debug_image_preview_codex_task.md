# Computer Use Debug Image Preview Extraction

Status: complete on `feature/computer-use-debug-image-preview`.

## Task

- Goal: move image payload decoding, screenshot presentation, zoom ownership,
  and viewport-to-source coordinate mapping out of
  `computer_use_debug_page.dart` into an independently importable and directly
  tested widget boundary.
- User-visible behavior: none. Display and selected-window screenshot previews,
  active target styling, zooming, point selection, and downstream input command
  coordinates remain unchanged.
- Non-goals: screenshot execution, window selection, permission or arming
  policy, input dispatch, diagnostics assembly, native Computer Use services,
  labels outside the preview, or any production action.

## Selection Evidence

- Live 2026-07-17 inventory:
  - `chat_notifier.dart`: 9,468 lines, excluded because active ChatNotifier
    worktrees already own overlapping changes.
  - generated files: excluded from manual decomposition.
  - `computer_use_debug_page.dart`: 2,864 lines at 93.33% line coverage.
  - `network_tools.dart`: 2,578 lines at 39.31% line coverage and coupled to
    process, socket, DNS, route, interface, ping, and mDNS behavior.
- The image preview is the smallest high-leverage non-overlapping boundary: its
  state, decoding, layout, zoom controller, and coordinate transform are
  contiguous and have an existing display and window product path.
- `network_tools.dart` remains a later candidate that requires a separate
  platform-side-effect and coverage plan before extraction.

## Context

- Affected files or components:
  - `lib/features/settings/presentation/pages/computer_use_debug_page.dart`
  - a standalone Computer Use debug image-preview widget
  - direct image-preview widget tests
  - existing Computer Use debug page product-path tests
  - exact line-count ratchets and refactoring roadmap
- Baseline:
  - debug page: 2,864 lines.
  - direct page test: 1,399 lines.
- Reference pattern: follow the independently importable immutable presentation
  boundaries already extracted from Computer Use settings. Pass snapshot data
  and a typed point callback; do not pass page state, providers, services, or
  native result maps.

## Current Behavior Contract

- A valid base64 payload is decoded in memory and rendered with `BoxFit.contain`
  and gapless playback.
- Invalid base64 shows `Failed to decode image payload.`. Image decoder failures
  show `Failed to decode image: <error>` inside the preview.
- The metadata row renders title, source width and height, and MIME type in the
  existing format.
- Positive source dimensions determine the aspect ratio. Missing or non-positive
  dimensions use 16:9.
- The preview keeps an eight-pixel clip radius, a two-pixel primary border for
  the active target, a two-pixel divider-color border otherwise, and the
  surface-container-highest background.
- Preview height remains capped at 420 logical pixels. `InteractiveViewer`
  keeps a 0.5 minimum and 4.0 maximum scale.
- Taps are enabled only when a point callback exists. Tap coordinates pass
  through the active transformation controller, clamp to the viewport, and
  scale to source-image pixels.
- A tap with non-positive viewport or source dimensions is ignored.
- Display and window preview keys, target selection, text-controller updates,
  diagnostics values, and input command arguments remain page-owned.

## Implementation Notes

1. Add immutable `ComputerUseDebugImageSnapshot` and
   `ComputerUseDebugImagePoint` value objects beside the standalone preview.
2. Move base64 decoding, `TransformationController` lifecycle, presentation,
   error handling, and point conversion into `ComputerUseDebugImagePreview`.
3. Add direct widget tests for valid and invalid payloads, active and inactive
   styling, metadata and fallback aspect ratios, point mapping, and guarded
   taps.
4. Replace the two private preview usages and private snapshot/point types in
   the page while leaving native-result parsing and target state in place.
5. Remove obsolete imports and private classes, then lower the page and new
   boundary line-count ratchets to their exact values.

## Constraints

- Do not initialize or call the native Computer Use service in direct widget
  tests.
- Do not pass `WidgetRef`, providers, service objects, page state, native result
  maps, or coordinate text controllers into the extracted widget.
- Do not change image keys, user-visible copy, sizing, colors, border widths,
  zoom limits, transform math, clamping, callback timing, or target ownership.
- Keep diagnostics redaction and screenshot result parsing in the debug page.
- Generated files needed: none.
- Migration or data compatibility concerns: none; snapshot and point objects are
  transient presentation values and are never serialized.

## Similar-Pattern Search

- Search terms: `_ImagePreview`, `_ImagePreviewState`, `_ImageSnapshot`,
  `_ImagePoint`, `_displayScreenshot`, `_windowScreenshot`, `_imageSnapshot`,
  `_imageSummary`, `_selectImagePoint`, and `TransformationController`.
- Files inspected: Computer Use debug page and its product-path test, Computer
  Use settings presentation boundaries, line-count ratchets, active worktrees,
  live oversized-file inventory, and the network tools candidate.
- Adjacent work deliberately excluded: common debug status rows and cards remain
  a separate presentation-primitives slice; network parsing remains a separate
  data-layer slice.

## Acceptance Criteria

- Both display and selected-window product paths still produce source-relative
  point arguments with the same optional window ID behavior.
- Direct tests cover decoding, metadata, active styling, fallback sizing,
  coordinate scaling and clamping, disabled callbacks, and invalid dimensions.
- The extracted boundary imports only Dart conversion/typed-data and Flutter
  presentation libraries.
- `computer_use_debug_page.dart` shrinks and both it and the new boundary have
  exact non-increasing line-count ratchets.
- Focused and full repository verification pass without analyzer findings or
  real desktop actions.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/presentation/widgets/computer_use_debug_image_preview_test.dart \
  --test test/features/settings/presentation/pages/computer_use_debug_page_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: `ComputerUseDebugImagePreview` now owns payload decoding, preview
  presentation, zoom state, and viewport-to-source point conversion behind
  immutable snapshot and point values. The debug page retains native result
  parsing, target selection, command fields, diagnostics, and service calls.
- Size: `computer_use_debug_page.dart` fell from 2,864 to 2,721 lines. The new
  independently importable preview boundary is ratcheted at 153 lines.
- Tests run: the focused verifier passed 69 root tests plus 13 internal-package
  tests. The full repository gate passed 3,760 root tests plus 13 package tests
  with analyzer checks clean and no real Computer Use actions.
- Coverage: repository line coverage is 74.11% (52,555/70,912). The extracted
  preview reached 100.00% (56/56), while the remaining debug page is at 93.19%
  (1,135/1,218).
- Risks or follow-ups: common Computer Use debug status rows and cards are the
  next safe presentation candidate. `network_tools.dart` remains separate
  because its lower coverage and platform side effects require a dedicated
  characterization and safety plan.
