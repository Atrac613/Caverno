# ChatPage Workspace Navigation Coordinator

## Task

- Goal: Move the workspace, project, conversation, and assistant-mode routing
  concern out of `ChatPage` behind the completed product-path contract.
- User-visible behavior: Drawer navigation must preserve the current dashboard
  exit, workspace activation, coding-project selection, conversation scope,
  routine-home reset, and assistant-mode synchronization behavior.
- Non-goals: Do not move dashboard visibility, companion sidebar visibility,
  Files-tab state, workflow, approval, composer, persistence, or drawer UI.

## Context

- Affected files or components:
  - `lib/features/chat/presentation/pages/chat_page.dart`
  - `lib/features/chat/presentation/coordinators/chat_page_workspace_navigation_coordinator.dart`
  - `test/features/chat/presentation/coordinators/chat_page_workspace_navigation_coordinator_test.dart`
  - `test/features/chat/presentation/pages/chat_page_state_transition_test.dart`
  - `test/features/chat/presentation/pages/chat_page_companion_panel_test.dart`
  - `test/quality/file_size_ratchet_test.dart`
- Related docs:
  - `docs/chat_page_state_transition_contract_codex_task.md`
  - `docs/large_file_refactor_plan.md`
  - `docs/large_file_boundary_inventory_2026_07_18.md`
- Reference implementation or pattern:
  - `lib/features/chat/presentation/coordinators/slash_command_action_coordinator.dart`
  - `lib/features/chat/presentation/coordinators/plan_review_action_coordinator.dart`
- Known quirks, compatibility rules, or release gates:
  - Entering Coding prefers the active project, then the selected project.
  - First-open Coding activation defers fresh conversation creation.
  - General mode promotes to Coding mode, while another non-General mode is
    preserved.
  - Selecting a missing conversation still exits the dashboard before
    returning.

## Implementation Notes

- Preferred approach:
  - Add a presentation coordinator with injected notifier objects and narrow
    state, mode, dashboard, and routine-selection callbacks.
  - Keep Riverpod reads and feature-to-feature composition in `ChatPage`.
  - Replace the three page-owned routing bodies with thin delegates.
  - Add direct coordinator tests and retain the existing product-path tests.
- Constraints:
  - The coordinator must not import Flutter, Riverpod, localization, settings,
    routines, workflow, approval, or widget code.
  - Preserve exact activation flags and assistant-mode transitions.
  - Lower both ChatPage file and same-library line-count ratchets after the
    extraction and add a non-increasing coordinator ratchet.
- Generated files needed: None.
- Migration or data compatibility concerns: None.

## Similar-Pattern Search

- Search terms: `_switchWorkspaceMode`, `_activateCodingProject`,
  `_selectDrawerConversation`, `activateWorkspace`, `selectProject`,
  `updateAssistantMode`, `selectRoutine(null)`.
- Files or modules inspected:
  - `lib/features/chat/presentation/pages/chat_page.dart`
  - `lib/features/chat/presentation/coordinators/slash_command_action_coordinator.dart`
  - `lib/features/chat/presentation/coordinators/plan_review_action_coordinator.dart`
  - `test/features/chat/presentation/pages/chat_page_state_transition_test.dart`
  - `test/features/chat/presentation/widgets/conversation_drawer_test.dart`
- Follow-up tasks found: Re-rank ChatPage, `chat_remote_datasource.dart`, and
  MessageInput after the extraction rather than widening this coordinator.

## Acceptance Criteria

- Required behavior:
  - Chat, Coding, and Routines workspace activation preserves current flags and
    side effects.
  - Coding project activation preserves project selection, deferred first-open
    conversation creation, and mode promotion.
  - Drawer conversation selection preserves missing, Chat, Coding, and
    Routines behavior.
  - Existing Dashboard and companion sidebar product paths remain green.
- Edge cases:
  - Coding without an active or selected project still activates the empty
    Coding workspace and promotes General mode.
  - Coding conversation selection without a normalized project does not select
    a project.
  - Existing non-General assistant modes are not overwritten by Coding routes.
- Failure paths: Missing conversation IDs must not mutate selection or
  assistant mode.
- Accessibility, localization, or platform expectations: No presentation copy
  or platform behavior changes.

## Verification

```bash
tool/codex_verify.sh \
  --test test/features/chat/presentation/coordinators/chat_page_workspace_navigation_coordinator_test.dart \
  --test test/features/chat/presentation/pages/chat_page_state_transition_test.dart \
  --test test/features/chat/presentation/pages/chat_page_companion_panel_test.dart \
  --test test/quality/file_size_ratchet_test.dart
tool/codex_verify.sh --coverage
```

## Handoff Notes

- Summary: Extracted workspace, project, conversation, and assistant-mode
  routing into a 127-line presentation coordinator. `ChatPage` now composes
  the coordinator through three thin delegates while retaining Riverpod and
  all page-owned UI state.
- Tests run: The focused verifier passed analysis, 92 root tests, and 13
  internal-package tests. The full verifier passed analysis, 3,927 root tests,
  and 13 internal-package tests.
- Coverage or low-coverage notes: Full line coverage reached 75.19%
  (53,527/71,192). The coordinator reached 100.00% (40/40), `chat_page.dart`
  reached 54.26% (420/774), and their combined executable coverage is 56.51%
  (460/814).
- Risks or follow-ups: No visual or persistence behavior changed. Re-rank the
  clear-ownership response-normalization or streaming contract in
  `chat_remote_datasource.dart` ahead of widening this coordinator. Dashboard,
  sidebar, Files-tab, workflow, approval, and composer state remain page-owned.
