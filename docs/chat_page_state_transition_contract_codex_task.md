# ChatPage State Transition Contract

## Task

- Goal: Characterize the remaining state transitions owned directly by
  `ChatPage` before choosing another extraction boundary.
- User-visible behavior: Dashboard navigation, workspace and conversation
  selection, assistant-mode synchronization, and companion sidebar state must
  remain stable through future refactors.
- Non-goals: Do not extract production code, change workflow or approval
  behavior, redesign the drawer, or alter Computer Use pages.

## Context

- Affected files or components:
  - `lib/features/chat/presentation/pages/chat_page.dart`
  - `test/features/chat/presentation/pages/chat_page_state_transition_test.dart`
  - `test/features/chat/presentation/pages/chat_page_companion_panel_test.dart`
- Related docs:
  - `docs/large_file_refactor_plan.md`
  - `docs/large_file_boundary_inventory_2026_07_18.md`
- Reference implementation or pattern:
  - `test/features/chat/presentation/widgets/conversation_drawer_test.dart`
  - `test/features/chat/presentation/pages/chat_page_remote_coding_test.dart`
  - `test/features/chat/presentation/pages/chat_page_companion_panel_test.dart`
- Known quirks, compatibility rules, or release gates:
  - `ChatPage` owns dashboard visibility instead of a provider.
  - Coding conversation selection must synchronize both the active project and
    assistant mode.
  - The wide companion sidebar keeps its file viewer mounted while hidden.
  - This slice is contract-only. A production change is allowed only if a new
    characterization test exposes a confirmed defect.

## Implementation Notes

- Preferred approach:
  - Add product-path widget tests through public drawer and header controls.
  - Reuse small notifier fakes that preserve the provider-visible state
    transitions without persistence or native side effects.
  - Assert provider state and visible page state after every transition.
- Constraints:
  - Keep workflow, approval, tool execution, persistence, and Computer Use out
    of scope.
  - Do not add test-only methods to `ChatPage`.
  - Do not combine this work with a production extraction.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

- Search terms: `_showDashboard`, `_switchWorkspaceMode`,
  `_activateCodingProject`, `_selectDrawerConversation`,
  `_isCompanionSidebarVisible`, `_rightSidebarTab`.
- Files or modules inspected:
  - `lib/features/chat/presentation/pages/chat_page.dart`
  - `lib/features/chat/presentation/pages/chat_page_header_builders.dart`
  - `lib/features/chat/presentation/widgets/conversation_drawer.dart`
  - `test/features/chat/presentation/pages/chat_page_companion_panel_test.dart`
  - `test/features/chat/presentation/pages/chat_page_remote_coding_test.dart`
  - `test/features/chat/presentation/widgets/chat_right_sidebar_test.dart`
  - `test/features/chat/presentation/widgets/conversation_drawer_test.dart`
- Follow-up tasks found: Choose a production boundary only after these
  lifecycle contracts pass and the large-file ranking is refreshed.

## Acceptance Criteria

- Required behavior:
  - Selecting a workspace from the dashboard exits the dashboard and preserves
    the expected project and assistant-mode synchronization.
  - Selecting chat and coding conversations from the persistent drawer updates
    conversation, workspace, project, and assistant-mode state together.
  - Hiding and reopening the wide companion sidebar preserves the selected
    Files tab and its viewer request.
- Edge cases:
  - Dashboard navigation must not discard the currently selected conversation.
  - Returning to chat must clear the active project and select general mode.
- Failure paths: A missing drawer target must not be simulated through private
  methods or test-only production seams.
- Accessibility, localization, or platform expectations: Exercise the existing
  English localization and stable widget keys at desktop width.

## Verification

```bash
tool/codex_verify.sh \
  --test test/features/chat/presentation/pages/chat_page_state_transition_test.dart \
  --test test/features/chat/presentation/pages/chat_page_companion_panel_test.dart
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary: Product-path widget tests now freeze dashboard exits, workspace and
  conversation scope synchronization, assistant-mode changes, and Files-tab
  retention across companion sidebar visibility changes. No production defect
  was found, so this slice changed no production code.
- Tests run:
  - Focused gate: analysis, 7 root tests, and 13 execution-runtime package
    tests passed.
  - Full gate: analysis, 3,915 root tests, and 13 execution-runtime package
    tests passed.
- Coverage or low-coverage notes: Full line coverage reached 75.18%
  (53,522/71,190). `chat_page.dart` increased from 49.51% (402/812) to 55.91%
  (454/812) without changing its 2,133-line production boundary.
- Risks or follow-ups: A separate implementation task may extract the
  workspace, project, conversation, and assistant-mode routing concern behind
  the new contract. Keep dashboard and sidebar view state in `ChatPage`, and
  do not mix the move with workflow, approval, or composer behavior.
