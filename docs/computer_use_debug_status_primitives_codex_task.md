# Computer Use Debug Status Primitives Extraction

Status: complete on `feature/computer-use-debug-status-primitives`.

## Task

- Goal: move the contiguous presentation-only status primitives out of
  `computer_use_debug_page.dart` into an independently importable and directly
  tested widget boundary.
- User-visible behavior: none. Section headings, helper-boundary details,
  onboarding progress and rows, informational notes, permission and status
  rows, arming switches, and coordinate-target labels remain unchanged.
- Non-goals: card composition, service calls, permission requests, helper
  lifecycle, screenshot capture, input or audio dispatch, diagnostics, result
  parsing, state ownership, or any real Computer Use action.

## Selection Evidence

- The previous slice reduced `computer_use_debug_page.dart` from 2,864 to
  2,721 lines by extracting its image-preview boundary at 100% direct coverage.
- The remaining private presentation primitives form one contiguous block at
  the end of the page and depend only on immutable arguments, Flutter
  presentation types, and `MacosComputerUseBackendInfo`.
- Their callbacks expose user intent without reading providers, page state, or
  native services, so they can be tested without constructing the debug page or
  triggering platform behavior.
- `chat_notifier.dart` remains excluded because active worktrees own overlapping
  decomposition. `network_tools.dart` remains deferred because its lower
  coverage and process, socket, DNS, route, ping, and mDNS side effects require
  a separate safety plan.

## Current Behavior Contract

- Section titles use a primary-color icon, 12-pixel gap, title-medium text, a
  two-pixel vertical gap, and body-small subtitle text.
- The helper-boundary panel uses the highest surface container, an eight-pixel
  radius, 12-pixel padding, exact helper versus compatibility copy, and four
  ordered label/value rows. Values remain selectable.
- Onboarding progress is zero when total is zero and otherwise uses
  `completed / total`; the bar is clipped to a four-pixel radius and the label
  remains `<completed> of <total> complete`.
- Onboarding step rows preserve Done/Pending labels, icons, colors, spacing, and
  completed-label font weight.
- Informational notes preserve their outline border, eight-pixel radius,
  12-pixel padding, icon and text styles, and exact content.
- Permission rows map true, false, and null to Granted, Missing, and Unknown
  with the current icons and colors. The System Settings button appears only
  when permission is not granted and a callback exists; its default tooltip
  remains `Open System Settings`.
- Generic status rows preserve caller-supplied true, false, and unknown labels
  with the same tri-state icon and color mapping.
- Arming switches preserve error-container styling and unlocked icon while
  armed, highest-surface styling and locked icon otherwise, clipping, title,
  subtitle, value, and nullable callback behavior.
- Coordinate-target rows preserve highest-surface styling, primary location
  icon, spacing, and caller-supplied label.

## Implementation Notes

1. Add one standalone widget file containing public, Computer Use-specific
   versions of the existing private presentation primitives.
2. Add direct widget tests for layout metadata, tri-state mappings, conditional
   actions, callbacks, progress values, helper-boundary variants, arming state,
   and coordinate labels.
3. Replace private usages in the page without moving card composition, state,
   providers, or service operations.
4. Remove the obsolete private widgets and imports, then lower the page and new
   boundary line-count ratchets to their exact values.

## Constraints

- Do not initialize or call the native Computer Use service in direct widget
  tests.
- Do not pass `WidgetRef`, providers, page state, native result maps, text
  controllers, or service objects into the extracted widgets.
- Do not change user-visible copy, ordering, icons, colors, sizing, padding,
  radii, text styles, button visibility, tooltips, or callback timing.
- Keep `_Coordinates` and `_CoordinateTarget` private because they carry page
  command state rather than presentation.
- Generated files needed: none.
- Migration or data compatibility concerns: none; this slice changes transient
  presentation composition only.

## Similar-Pattern Search

- Search terms: `_SectionTitle`, `_HelperBoundaryPanel`, `_BoundaryValueRow`,
  `_OnboardingProgressRow`, `_OnboardingStepRow`, `_OnboardingNote`,
  `_PermissionRow`, `_StatusRow`, `_ArmSwitch`, and `_CoordinateTargetRow`.
- Files inspected: the Computer Use debug page, its product-path test, the
  previous image-preview boundary, file-size ratchets, active worktrees, and
  the F5 refactoring roadmap.
- Adjacent work deliberately excluded: card-level page composition, coordinate
  command values, native Computer Use operations, and network data-layer code.

## Acceptance Criteria

- Every extracted widget is independently importable and directly exercised.
- Existing product-path tests retain exact visible copy and service-call
  assertions without initializing a real native service.
- Callback tests prove that presentation actions delegate exactly once and do
  not introduce service ownership.
- `computer_use_debug_page.dart` shrinks and both it and the new boundary have
  exact non-increasing line-count ratchets.
- Focused and full repository verification pass without analyzer findings or
  real desktop actions.

## Verification

Run the focused gate:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/presentation/widgets/computer_use_debug_status_primitives_test.dart \
  --test test/features/settings/presentation/pages/computer_use_debug_page_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: nine Computer Use-specific presentation widgets now own section
  titles, the helper boundary, onboarding progress and rows, notes, permission
  and status rows, arming switches, and coordinate-target labels. The debug
  page retains every card, provider read, state transition, service call, and
  native result mapping.
- Size: `computer_use_debug_page.dart` fell from 2,721 to 2,322 lines. The new
  independently importable status-primitives boundary is ratcheted at 424
  lines.
- Tests run: the focused verifier passed 71 root tests plus 13 internal-package
  tests. The full repository gate passed 3,767 root tests plus 13 package tests
  with analyzer checks clean and no real Computer Use actions.
- Coverage: repository line coverage is 74.12% (52,558/70,913). The extracted
  boundary reached 100.00% (165/165), while the remaining debug page is at
  92.22% (972/1,054).
- Risks or follow-ups: card-level onboarding composition is the next promising
  presentation seam, but it should begin with a typed view-model contract. Keep
  permission operations, helper lifecycle, smoke actions, and network tooling
  outside that slice.
