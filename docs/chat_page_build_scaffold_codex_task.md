# ChatPage Build Scaffold Extraction

Status: complete on `feature/chat-page-build-scaffold`.

## Task

- Goal: complete ChatPage Tranche 5 by moving the responsive page scaffold and
  right-sidebar layout helpers out of the ChatPage library into independently
  importable, directly tested presentation widgets.
- User-visible behavior: none. Compact and persistent drawer layouts, headers,
  task banners, routine and conversation companion panes, file-workspace tabs,
  widths, dividers, and responsive visibility retain their current behavior.
- Non-goals: provider composition, workspace selection, browser-pane behavior,
  companion panel contents, file-viewer construction, message-list rendering,
  composer behavior, navigation, or any state and persistence schema.

## Context

- Baseline:
  - `lib/features/chat/presentation/pages/chat_page.dart`: 2,271 lines.
  - ChatPage same-library aggregate: 9,085 lines.
- Affected files or components:
  - `lib/features/chat/presentation/pages/chat_page.dart`
  - standalone responsive scaffold and right-sidebar widgets
  - companion-panel product-path tests
  - direct layout widget tests
  - exact file and library line-count ratchets
- Related docs:
  - `docs/large_file_refactor_plan.md` Phase 2, Tranche 5
  - `docs/chat_page_slash_command_handler_codex_task.md`
  - `docs/roadmap.md` F5
- Reference pattern: use independently importable widgets with explicit child
  and callback inputs. Keep Riverpod reads, localization lookup, page state,
  and private ChatPage types outside the extracted files.

## Current Behavior Contract

- The companion sidebar is available at widths of at least 1,180 logical
  pixels and is hidden on remote-coding mobile platforms.
- A conversation without an active file viewer shows only the companion panel
  at 344 logical pixels and does not show the tab selector.
- An active file viewer shows controlled Companion and Files tabs. Both tab
  bodies remain mounted in an `IndexedStack` while selection changes.
- File-viewer width is 42 percent of finite available width, clamped to
  420...720 logical pixels. A non-finite width falls back to 344 pixels.
- Conversation and routine split panes use a one-pixel vertical divider and
  stretch both children to the available height.
- At widths below 900 logical pixels, ChatPage uses an `AppBar` and temporary
  drawer. At wider widths it uses a fixed 320-pixel drawer, a one-pixel divider,
  and the persistent workspace header above the workspace body.
- `SubagentTaskBanner` remains above the responsive scaffold body in both
  layouts. The routines create FAB remains limited to the compact routines home
  state by page-owned composition.
- Mobile keyboard dismissal remains the final page-owned wrapper around the
  extracted scaffold.

## Implementation Notes

1. Add a controlled right-sidebar widget that owns width calculation, tab
   presentation, divider styling, and the indexed companion/file stack.
2. Add a generic split-pane widget so conversation and routine companion panes
   share the same row and divider contract.
3. Add a responsive ChatPage scaffold widget that switches between compact and
   persistent drawer/header composition using already-built child widgets.
4. Replace `_buildRightSidebarPanel`, `_wrapWithRightSidebar`, and the inline
   scaffold assembly with thin page-owned composition.
5. Keep responsive visibility decisions, provider reads, localization,
   callbacks, browser wrapping, and page state in `_ChatPageState`.
6. Add direct widget coverage before relying on the existing ChatPage product
   path, then lower exact file and aggregate line-count ratchets.

## Constraints

- Do not pass `WidgetRef`, provider containers, `_ChatPageState`, domain
  notifiers, or localization resolvers into the extracted widgets.
- Do not add another ChatPage `part` file; extracted code must reduce the
  same-library aggregate.
- Do not change labels, icons, keys, widths, breakpoints, padding, divider
  dimensions, colors, child order, or mounted-state behavior.
- Keep tab selection controlled by ChatPage so opening and closing file viewers
  preserves the existing state transitions.
- Generated files needed: none.
- Migration or data compatibility concerns: none.

## Similar-Pattern Search

- Search terms: `_buildRightSidebarPanel`, `_wrapWithRightSidebar`,
  `buildRoutineDetailBody`, `buildScaffoldBody`, `_RightSidebarTab`,
  `_companionSidebarBreakpoint`, `_persistentDrawerBreakpoint`,
  `right-sidebar-tabs`, and `SubagentTaskBanner`.
- Files inspected: ChatPage primary and companion/header/browser part files,
  companion-panel product tests, file-viewer widget tests, refactoring roadmap,
  and exact line-count ratchets.
- Adjacent work deliberately excluded: the browser pane already has a dedicated
  builder boundary; message-list and composer extraction require separate state
  and lifecycle characterization.

## Acceptance Criteria

- Compact layout exposes the same AppBar, temporary drawer, task banner,
  optional FAB, and workspace child.
- Persistent layout exposes the same fixed-width drawer, divider, workspace
  header, task banner, and expanded workspace child without an AppBar or
  temporary drawer.
- Companion-only, file-viewer, tab-switching, width-clamping, and split-pane
  behavior have direct widget tests.
- Existing ChatPage companion, workspace, mobile, slash-command, and layout
  product paths remain green.
- `chat_page.dart` and its same-library aggregate shrink, and every new boundary
  receives an exact non-increasing line-count ratchet.
- Analyzer, focused tests, full repository tests, and coverage complete without
  findings or regressions.

## Verification

Run the focused gate after implementation:

```bash
tool/codex_verify.sh --no-codegen \
  --test test/features/chat/presentation/widgets/chat_right_sidebar_test.dart \
  --test test/features/chat/presentation/widgets/chat_page_scaffold_test.dart \
  --test test/features/chat/presentation/pages/chat_page_companion_panel_test.dart \
  --test test/features/chat/presentation/pages/chat_page_routines_create_test.dart \
  --test test/quality/file_size_ratchet_test.dart
```

Run the broader gate before closeout:

```bash
tool/codex_verify.sh --coverage --no-codegen
```

## Handoff Notes

- Summary: `ChatRightSidebarPanel` now owns controlled Companion and Files tabs,
  width calculation, and mounted tab bodies. `ChatRightSidebarLayout` owns the
  shared conversation and routine split-pane contract. `ChatPageScaffold` owns
  compact AppBar/drawer/FAB composition and persistent drawer/header
  composition. ChatPage retains all provider, localization, state, visibility,
  child construction, browser, and keyboard-dismiss ownership.
- Size result: `chat_page.dart` fell from 2,271 to 2,133 lines and the
  same-library aggregate fell from 9,085 to 8,945 lines. The independent
  scaffold and sidebar boundaries are ratcheted at 87 and 114 lines.
- Tests run: the focused repository gate passed 58 root tests plus all 13
  `caverno_execution_runtime` package tests. The broader coverage gate passed
  all 3,754 root tests plus the same 13 package tests with no analyzer findings.
- Coverage or low-coverage notes: repository line coverage is 74.11%
  (52,555/70,912). Both extracted widgets reached 100.00% coverage: scaffold
  24/24 executable lines and sidebar 35/35 executable lines.
- Risks or follow-ups: Tranche 5 is behavior-preserving and the planned ChatPage
  sequence through this tranche is complete. Refresh the oversized-file
  inventory before choosing another application boundary; any future
  message-list or composer extraction needs a separate lifecycle contract.
