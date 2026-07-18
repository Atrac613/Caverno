# Computer Use Debug Permission Actions Extraction

Status: complete on
`feature/computer-use-debug-permission-actions`.

## Task

- Goal: move the ordered helper and permission action controls out of
  `computer_use_debug_page.dart` behind an independently importable widget and
  immutable busy-state view model.
- User-visible behavior: none. Labels, icons, keys, action order, wrapping,
  spacing, and enabled or disabled conditions remain unchanged.
- Non-goals: helper lifecycle, permission requests, result storage, permission
  refresh, native service calls, System Settings navigation, page busy-state
  mutation, or permission guidance.

## Context

- The completed permission-checklist slice reduced
  `computer_use_debug_page.dart` from 1,991 to 1,950 lines.
- `_buildPermissionsCard()` still declares nine ordered
  `FilledButton.tonalIcon` controls inline, while `_actionButton()` applies the
  shared page busy gate.
- Active-worktree inspection on 2026-07-18 found no second owner of the debug
  page or its product test, so the previous ownership conflict is resolved.

## Current Behavior Contract

- The controls remain in an 8-pixel horizontal and vertical `Wrap` below the
  three permission rows.
- Actions remain ordered as Launch Helper, Restart Helper, Ping Helper,
  Refresh, Request Accessibility, Open Accessibility Settings, Request Screen
  Recording, Stop Helper Work, and Open Screen Recording Settings.
- The respective icons remain rocket launch, restart, sensors, refresh,
  accessibility, settings, screenshot monitor, stop circle, and application
  settings outlines.
- Launch, restart, ping, open Accessibility settings, stop helper work, and
  open Screen Recording settings retain their current value keys. The other
  three actions remain unkeyed.
- Every control is a tonal filled icon button. All nine are enabled while the
  page is idle and disabled while the page is busy.
- Each enabled control invokes exactly its supplied callback once.
- The page retains the existing action implementations and arguments: helper
  launch or restart plus IPC readiness and refresh, ping and stop result
  storage, permission refresh, split Accessibility or Screen Recording
  requests, and targeted System Settings sections.

## Implementation Notes

1. Add an immutable `ComputerUseDebugPermissionActionsViewModel` containing
   only `isBusy`.
2. Add `ComputerUseDebugPermissionActions` with nine explicit callbacks and
   the exact ordered action specifications.
3. Keep the shared button construction private to the extracted widget.
4. Replace the inline `Wrap` with typed widget construction and remove
   `_actionButton()` from the page.
5. Add direct tests for labels, icons, keys, order, wrapping, spacing, idle
   callback dispatch, and busy disablement.
6. Retain product-path tests for helper lifecycle, ping, stop, refresh,
   permission requests, and both System Settings sections.
7. Lower exact line-count ratchets after formatting.

## Constraints

- Do not pass services, raw result maps, permission snapshots, helper state, or
  page state into the extracted widget.
- Do not move service execution, `_run()`, result storage, permission refresh,
  helper lifecycle, or System Settings navigation.
- Do not let the extracted widget import Riverpod, Computer Use services,
  platform APIs, page types, or mutable page state.
- Do not change labels, icons, keys, order, button type, spacing, eligibility,
  callback count, request arguments, or action behavior.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_actionButton`, `Launch Helper`, `Restart Helper`,
  `Ping Helper`, `Request Accessibility`, `Request Screen Recording`,
  `Stop Helper Work`, and `Open Screen Recording Settings`.
- Files inspected: the debug page, page product tests, permission-checklist and
  peer action-card boundaries, line-count ratchets, refactoring plan, roadmap,
  and active worktrees.
- Follow-up tasks found: after this coherent action group lands, refresh the
  full large-file and same-library aggregate inventory before selecting
  another boundary.

## Acceptance Criteria

- The widget and view model are independently importable and directly tested
  without a provider scope, native service, platform permission, or file IO.
- Direct tests pin all nine labels, icons, keys, order, `Wrap` spacing, idle
  callbacks, and busy disablement.
- Product-path tests retain helper launch and restart sequences, ping and stop
  storage, refresh, split permission requests, and targeted settings actions.
- The page shrinks and both it and the new boundary have exact non-increasing
  line-count ratchets.
- Focused and full repository verification pass without analyzer findings or
  real desktop actions.
- After the slice lands, the live large-file inventory and active ownership
  map are refreshed before choosing another implementation boundary.

## Verification

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/settings/presentation/widgets/computer_use_debug_permission_actions_test.dart \
  --test test/features/settings/presentation/pages/computer_use_debug_page_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: extracted all nine helper and permission controls into an
  independently importable 119-line widget with immutable busy state and
  explicit callbacks. The page retains helper lifecycle, permission requests,
  service execution, result storage, and System Settings navigation. The page
  fell from 1,950 to 1,910 lines.
- Tests run: the focused verifier passed 84 root tests plus 13 internal-package
  tests. The full verifier passed analysis, 3,833 root tests, and 13
  internal-package tests.
- Coverage or low-coverage notes: repository line coverage reached 74.43%
  (52,927/71,105). The extracted action widget reached 100.00% line coverage
  (31/31), and the coordinating debug page reached 94.36% (887/940).
- Risks or follow-ups: no native desktop action was executed. Squash the slice
  into local main, then refresh the complete large-file, same-library
  aggregate, and active-worktree ownership inventory before choosing another
  implementation boundary.
