# Computer Use Debug Permission Checklist Extraction

Status: complete on
`feature/computer-use-debug-permission-checklist`.

## Task

- Goal: move permission-checklist presentation out of
  `computer_use_debug_page.dart` behind an independently importable widget and
  a typed ready, warning, or unknown status.
- User-visible behavior: none. Title, subtitle, icon, colors, spacing, border,
  and placement remain unchanged.
- Non-goals: setup evaluation, permission snapshots, helper reachability,
  backend ownership, permission rows, permission actions, native service calls,
  or macOS System Settings navigation.

## Context

- The completed peer action-card slices reduced
  `computer_use_debug_page.dart` from 2,864 to 1,991 lines.
- `_buildPermissionChecklist()` still maps the page-owned setup checklist to
  three visual states and renders the resulting guidance inline.
- `_buildPermissionsCard()` already constructs one
  `MacosComputerUseSetupChecklist`; the extracted widget needs only its title,
  subtitle, and derived presentation status.

## Current Behavior Contract

- A ready checklist uses `Icons.task_alt_outlined` and the theme primary color.
- A warning checklist uses `Icons.warning_amber_outlined` and the theme error
  color.
- An unknown checklist uses `Icons.info_outline` and the theme secondary color.
- Ready means `setupChecklist.isReady`. Warning means a permission snapshot is
  available but the checklist is not ready. Unknown means no permission
  snapshot is available.
- The page supplies the exact title and subtitle from
  `MacosComputerUseSetupChecklist`; the widget does not recreate setup policy
  or backend-specific guidance.
- The container uses an 8-pixel corner radius, a status color at 12 percent
  opacity, a status-color border at 35 percent opacity, and 12-pixel padding.
- The row is top-aligned with a 12-pixel icon gap. Title and subtitle use
  `titleSmall` and `bodySmall`, separated by 2 pixels.
- The checklist remains below the helper boundary panel and above helper status
  rows.

## Implementation Notes

1. Add a `ComputerUseDebugPermissionChecklistStatus` enum with ready, warning,
   and unknown values.
2. Add an immutable `ComputerUseDebugPermissionChecklistViewModel` containing
   title, subtitle, and status.
3. Add `ComputerUseDebugPermissionChecklist` and keep its theme-dependent
   presentation mapping local to the widget.
4. Construct the status from the existing page-owned setup checklist and
   replace `_buildPermissionChecklist()` with the typed widget.
5. Add direct tests for all three statuses, exact copy, icons, colors,
   decoration, spacing, and text styles.
6. Keep a page product-path assertion for the setup-to-presentation mapping.
7. Remove the obsolete builder and lower exact line-count ratchets.

## Constraints

- Do not pass `MacosComputerUseSetupChecklist`, raw service maps, permission
  snapshots, or backend types into the extracted widget.
- Do not move setup evaluation, permission state, helper state, permission
  actions, service execution, or System Settings navigation.
- Do not let the extracted widget import Riverpod, Computer Use services,
  platform APIs, page types, or mutable page state.
- Do not change setup titles or subtitles, readiness policy, icons, colors,
  opacity, spacing, text styles, card placement, or page action behavior.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_buildPermissionChecklist`, `_setupChecklist`, `hasSnapshot`,
  `isReady`, `MacosComputerUseSetupChecklist`, `task_alt_outlined`,
  `warning_amber_outlined`, and `info_outline`.
- Files inspected: the debug page, macOS setup model, existing debug-card
  widget tests, page product tests, line-count ratchets, refactoring plan,
  roadmap, and active branch scope.
- Follow-up tasks found: the next narrow boundary is the ordered group of nine
  helper and permission action buttons. Its copy, icons, busy eligibility, and
  callback order can move behind a typed widget while execution stays
  page-owned.

## Acceptance Criteria

- The widget, status enum, and view model are independently importable and
  directly tested without a provider scope, native service, platform
  permission, or file IO.
- Direct tests pin ready, warning, and unknown icons and theme colors plus the
  shared decoration, copy, spacing, and text styles.
- The page maps setup readiness and snapshot availability to the typed status
  while retaining setup evaluation and exact title and subtitle generation.
- Product-path tests retain the permission guidance produced by the existing
  setup policy.
- The page shrinks and both it and the new boundary have exact non-increasing
  line-count ratchets.
- Focused and full repository verification pass without analyzer findings or
  real desktop actions.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/presentation/widgets/computer_use_debug_permission_checklist_test.dart \
  --test test/features/settings/presentation/pages/computer_use_debug_page_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: extracted permission-checklist presentation into an independently
  importable 94-line widget with a typed ready, warning, or unknown status and
  immutable copy. The page retains setup evaluation, permission and helper
  state, backend-specific guidance, service execution, and System Settings
  actions. The page fell from 1,991 to 1,950 lines.
- Tests run: the focused verifier passed 84 root tests plus 13 internal-package
  tests. The full verifier passed analysis, 3,829 root tests, and 13
  internal-package tests.
- Coverage or low-coverage notes: repository line coverage reached 74.42%
  (52,889/71,073). The extracted checklist reached 100.00% line coverage
  (30/30), and the coordinating debug page reached 93.61% (879/939).
- Risks or follow-ups: no native desktop action was executed. The next narrow
  presentation boundary is the ordered helper and permission action group;
  keep service execution and state mutation page-owned.
