# ChatPage Decomposition — Tranche 1 Task Specs

Status: ready for implementation. Anchors verified against commit `a6142cc4`
(branch `claude/elated-perlman-67fb41`, clean tree). Line numbers WILL drift —
always re-locate symbols by name with grep before editing.

This document turns Phase 2 of `docs/large_file_refactor_plan.md` into seven
self-contained Codex tasks plus one docs task. Hand Codex **one task section at
a time**, together with the "Shared Context" section below. Execute in order:

```
Task 1 (listeners) → Task 2 (SSH sheets) → Task 3 (Git/local sheets)
→ Task 4 (computer-use sheet) → Task 5 (file/participant/BLE/serial sheets)
→ Task 6 (status presentation helpers) → Task 7 (image drop target)
→ Task 8 (docs)
```

Each task is one conventional commit and one review pass (per AGENTS.md).

---

## Shared Context (include with every task)

### Problem

`lib/features/chat/presentation/pages/chat_page.dart` is 8,296 lines, plus ten
same-library part files (~15,800 lines total for the library). A single
`_ChatPageState` owns layout, an ~810-line `build()`, twelve approval-dialog
listeners, nine inline approval bottom sheets (~2,700 lines), workflow task
execution/recovery orchestration (~2,500 lines), slash commands, and drag/drop.
This tranche extracts the low-risk UI clusters — approval sheets into
standalone widgets, plus small pure helpers — reducing the main file by roughly
3,000 lines and leaving the risky orchestration clusters for later tranches.

### Invariants (every task)

- **Behavior-preserving only.** No visual changes, no copy changes, no logic
  "improvements", no reformatting of moved code beyond what the move itself
  requires. Layout must remain pixel-identical.
- `ChatPage`'s public API stays untouched (constructor, `showDashboardOnStartup`).
- The `@visibleForTesting` hooks in `chat_page_support.dart`
  (`debugRemoteCodingMobilePlatformOverride`, `isRemoteCodingMobilePlatform`,
  `shouldPresentDesktopApproval`) stay untouched.
- All existing tests stay green **without edits** (allowed exceptions: adding
  imports). The whole directory
  `test/features/chat/presentation/pages/` is the tripwire suite.
- Every `resolve*` call on `ChatNotifier` (e.g. `resolveSshConnect`,
  `resolveComputerUseAction`) stays in the page-side wrapper method and must
  fire exactly once per pending request — including the dismissed case
  (`approved ?? false`). Do not move `resolve*` calls into sheet widgets.
- Localization keys and user-facing strings move **verbatim**; `.tr()` calls
  keep working unchanged (easy_localization string extension needs no context).
- Sheet presentation flags (`isDismissible: false`, `enableDrag`,
  `isScrollControlled`, transparent background, `DraggableScrollableSheet`
  sizes) move verbatim.
- English-only comments and identifiers. Conventional commit messages in
  English, no AI attribution.

### Extraction idioms (copy these patterns exactly)

The repo already contains both target patterns:

- **Idiom A — same-library part file:** extension on `_ChatPageState` in a
  `part of 'chat_page.dart'` file. Reference:
  `lib/features/chat/presentation/pages/chat_page_header_builders.dart`
  (`extension _ChatPageHeaderBuilders on _ChatPageState`). Use for code that
  genuinely needs page state but bloats the main file.
- **Idiom B — standalone sheet widget:** the sheet is a widget that takes the
  pending payload and pops a typed result; the page keeps a thin wrapper that
  awaits the sheet and calls `resolve*`. Private reference:
  `_WorkflowDecisionSheet` (`chat_page_workflow_support.dart:607`) consumed by
  `_showWorkflowDecisionDialog` (`chat_page.dart:1200`). Public reference:
  `lib/features/chat/presentation/widgets/plan/plan_document_approval_sheet.dart`.
  Use for the approval sheets (Tasks 2–5); new files go under
  `lib/features/chat/presentation/widgets/approval/`.

When a dialog body currently uses `StatefulBuilder` with local variables
(controllers, toggles), convert it to a `StatefulWidget` and dispose the
controllers. If a dialog body reads `_ChatPageState` fields beyond the pending
payload, pass them in as constructor parameters — audit each body with grep
before moving it.

### Pinned behaviors (do not break; these tests are the tripwires)

| Behavior | Pinned by |
|---|---|
| Computer-use approval sheet content and approve/deny wiring | `test/features/chat/presentation/pages/chat_page_computer_use_approval_test.dart` |
| Scroll auto-follow: snap on new message, follow while streaming, stop when the user scrolls up | `chat_page_scroll_follow_test.dart` |
| Slash command palette and execution | `chat_page_slash_commands_test.dart` |
| Companion sidebar layout and toggling | `chat_page_companion_panel_test.dart` |
| Goal suggestion flow | `chat_page_goal_flow_test.dart` |
| Context/status header | `chat_page_context_status_test.dart` |
| Routines creation entry point | `chat_page_routines_create_test.dart` |
| Remote coding / personal eval entries | `chat_page_remote_coding_test.dart`, `chat_page_personal_eval_record_test.dart` |

For widget-test harness setup (translation loader, notifier overrides), copy
the pattern at the top of `chat_page_computer_use_approval_test.dart`
(`_TestTranslationLoader`, `_TestSettingsNotifier`, ...).

### Verification (every task)

```bash
flutter analyze
flutter test test/features/chat/presentation/pages/
# plus the task-specific tests listed in the task
```

After the last code slice (Task 7): `tool/codex_verify.sh --coverage`.

---

## Task 1 — extract approval listener wiring from build()

**Commit:** `refactor(chat): extract approval dialog listeners from ChatPage build`

### Task

- Goal: move the twelve pending-approval `ref.listen` blocks and the
  `_showApprovalDialogOnce` de-dup helper out of the main file into a new part
  file, shrinking `build()` and grouping the approval wiring in one place.
- User-visible behavior: none.
- Non-goals: touching the message-scroll listener (~L1256) or the
  conversation plan-backfill listener (`ref.listen<String?>` ~L1276) — both
  stay in `build()` unchanged.

### Context

- Source: `chat_page.dart` — `_showApprovalDialogOnce` (~L428–443) and the
  twelve `ref.listen<Pending*>` blocks (~L1296–1450), in this order:
  `PendingSshConnect`, `PendingSshCommand`, `PendingGitCommand`,
  `PendingLocalCommand`, `PendingComputerUseAction`, `PendingBrowserAction`,
  `PendingFileOperation`, `PendingWorkflowDecision`, `PendingAskUserQuestion`,
  `PendingBleConnect`, `PendingSerialOpen`, `PendingParticipantToolApproval`.
- The Git listener also checks `shouldPresentDesktopApproval(next.origin)` —
  keep that guard verbatim (it is `@visibleForTesting` in
  `chat_page_support.dart`).
- `_activeApprovalDialogIds` (field, ~L108) stays in `_ChatPageState`.

### Implementation Notes

- New part file:
  `lib/features/chat/presentation/pages/chat_page_approval_listeners.dart`
  (`part of 'chat_page.dart'`, Idiom A), holding
  `extension _ChatPageApprovalListeners on _ChatPageState` with:
  - `_showApprovalDialogOnce` (moved verbatim),
  - `void _registerApprovalDialogListeners(BuildContext context)` containing
    the twelve listen blocks in the original order.
- `build()` calls `_registerApprovalDialogListeners(context)` at exactly the
  position the first moved block occupied. **`ref.listen` is only legal during
  build** — the helper must be invoked synchronously from `build()` on every
  build; do not convert to `listenManual`.
- Add the `part` declaration next to the existing ones (~L84–94).

### Similar-Pattern Search

- Search terms: `_showApprovalDialogOnce`, `ref.listen<Pending`.
- Confirm no part file registers its own pending-approval listeners.

### Acceptance Criteria

- `build()` shrinks by ~155 lines; main file by ~170.
- Approval dialogs still appear exactly once per pending id (existing
  computer-use approval test passes with zero edits).

### Verification

Shared commands only.

---

## Task 2 — extract SSH approval sheets into standalone widgets

**Commit:** `refactor(chat): extract SSH approval sheets into standalone widgets`

### Task

- Goal: move the SSH connect and SSH per-command approval bottom sheets into
  public widgets under `widgets/approval/`.
- User-visible behavior: none.
- Non-goals: changing `PendingSshConnect` / `SshConnectApproval` (defined in
  `chat_page_state`-adjacent `providers/chat_state.dart` ~L19/L41 — import,
  do not move) or the SSH credential storage flow.

### Context

- Source: `chat_page.dart` `_showSshConnectDialog` (~L5557–5988, ~430 lines)
  and `_showSshCommandDialog` (~L5989–6201, ~215 lines).
- `_showSshConnectDialog` owns four `TextEditingController`s plus
  `savePassword` / `obscure` toggles inside a `StatefulBuilder`
  (`setState` sites ~L5813, ~L5874) — this becomes a `StatefulWidget` per the
  shared idiom, with controllers disposed.

### Implementation Notes

- New files:
  - `lib/features/chat/presentation/widgets/approval/ssh_connect_approval_sheet.dart`
    — `class SshConnectApprovalSheet` with
    `static Future<SshConnectApproval?> show(BuildContext context, PendingSshConnect pending)`
    wrapping the existing `showModalBottomSheet` call verbatim.
  - `lib/features/chat/presentation/widgets/approval/ssh_command_approval_sheet.dart`
    — same shape for the per-command sheet and its result type.
- The page keeps thin wrappers:

```dart
Future<void> _showSshConnectDialog(
  BuildContext context,
  PendingSshConnect pending,
) async {
  final approval = await SshConnectApprovalSheet.show(context, pending);
  if (!mounted) return;
  ref.read(chatNotifierProvider.notifier).resolveSshConnect(/* unchanged */);
}
```

- Keep the sheet content byte-identical (drag handle, header, saved-password
  hint, obscure toggle, sizes 0.65/0.4/0.9).

### Similar-Pattern Search

- Search terms: `PendingSshConnect`, `PendingSshCommand`, `resolveSshConnect`,
  `resolveSshCommand`.

### Acceptance Criteria

- Main file shrinks by ~600 lines.
- New widget test
  `test/features/chat/presentation/widgets/approval/ssh_connect_approval_sheet_test.dart`:
  renders host/username fields from the pending payload; approve pops a
  `SshConnectApproval`; cancel pops null.

---

## Task 3 — extract Git and local command approval sheets

**Commit:** `refactor(chat): extract git and local command approval sheets`

### Task

- Goal: same extraction as Task 2 for the Git write-command sheet and the
  local shell command sheet.
- Non-goals: touching the origin gating (`shouldPresentDesktopApproval`) —
  that lives in the listener (Task 1), not the sheet.

### Context

- Source: `chat_page.dart` `_showGitCommandDialog` (~L6202–6416, ~215 lines)
  and `_showLocalCommandDialog` (~L6417–6707, ~290 lines).
- Both end in a single `resolveGitCommand` / `resolveLocalCommand` call —
  keep those in the page wrappers.

### Implementation Notes

- New files under `widgets/approval/`:
  `git_command_approval_sheet.dart`, `local_command_approval_sheet.dart`,
  same `static show(...)` shape as Task 2.
- Audit both bodies for reads of page fields beyond the pending payload
  before moving; pass any such value as a constructor parameter.

### Acceptance Criteria

- Main file shrinks by ~470 lines.
- One focused widget test per sheet (render + approve/deny pop values).

---

## Task 4 — extract computer-use action approval sheet

**Commit:** `refactor(chat): extract computer-use action approval sheet`

### Task

- Goal: move the computer-use approval sheet — the largest single dialog —
  plus its risk-style helpers into a standalone widget file.
- Non-goals: changing risk copy, boundary labels, or blocker labels; changing
  anything in `core/services/macos_computer_use_*`.

### Context

- Source: `chat_page.dart` `_showComputerUseActionDialog` (~L6708–7470,
  ~765 lines), `_computerUseRiskStyle` (~L7471), `_computerUseBoundaryLabel`
  (~L7536), `_computerUseBlockerLabel` (~L7550), plus the carrier class
  `_ComputerUseRiskStyle` in `chat_page_workflow_support.dart:1437`.
- **This sheet is directly pinned** by
  `chat_page_computer_use_approval_test.dart` — it must pass with zero edits.

### Implementation Notes

- New file:
  `lib/features/chat/presentation/widgets/approval/computer_use_action_approval_sheet.dart`
  containing the sheet widget, the three helpers (as private functions or
  static members of the sheet), and `_ComputerUseRiskStyle` renamed public
  (`ComputerUseRiskStyle`) since it leaves the library.
- Page keeps the thin wrapper calling `resolveComputerUseAction` verbatim.
- Grep `_ComputerUseRiskStyle` across `lib/` before deleting the original —
  update any remaining same-library reference to the public name.

### Similar-Pattern Search

- Search terms: `_ComputerUseRiskStyle`, `_computerUseRiskStyle`,
  `resolveComputerUseAction`, `computer_use_boundary`.

### Acceptance Criteria

- Main file shrinks by ~830 lines (plus ~15 from the workflow-support part).
- `chat_page_computer_use_approval_test.dart` green with zero edits.

### Verification

```bash
flutter analyze
flutter test test/features/chat/presentation/pages/chat_page_computer_use_approval_test.dart
flutter test test/features/chat/presentation/pages/
```

---

## Task 5 — extract file, participant, BLE, and serial approval sheets

**Commit:** `refactor(chat): extract remaining approval sheets into widgets`

### Task

- Goal: finish the approval-sheet extraction with the four remaining dialogs.
- Non-goals: none — after this task no `showModalBottomSheet` approval body
  should remain inline in `chat_page.dart`.

### Context

- Source in `chat_page.dart`:
  - `_showFileOperationDialog` (~L7565–7764, ~200 lines)
  - `_showParticipantToolApprovalDialog` (~L7765) with its helpers
    `_participantToolApprovalRow` (~L7897) and
    `_participantToolApprovalArgumentsPreview` (~L7920) — move all three
    together (~170 lines)
  - `_showBleConnectDialog` (~L7933–8113, ~180 lines)
  - `_showSerialOpenDialog` (~L8114–8296, ~180 lines)
- All four end in a single `resolve*` call — keep in page wrappers.

### Implementation Notes

- New files under `widgets/approval/`:
  `file_operation_approval_sheet.dart`, `participant_tool_approval_sheet.dart`,
  `ble_connect_approval_sheet.dart`, `serial_open_approval_sheet.dart`.
- Same `static show(...)` shape; audit for page-field reads first.

### Acceptance Criteria

- Main file shrinks by ~700 lines; after this task every approval dialog in
  `chat_page.dart` is a thin wrapper delegating to a sheet widget (the same
  shape as `_showWorkflowDecisionDialog`) — no inline sheet bodies remain.
- One focused widget test for the participant sheet (multi-row rendering and
  arguments preview truncation) — the other three follow the Task 2/3 pattern.

---

## Task 6 — extract workflow status presentation helpers

**Commit:** `refactor(chat): extract workflow status presentation helpers`

### Task

- Goal: move the pure label/color mapping helpers into a standalone
  presentation helper so they become unit-testable and stop padding the page.
- User-visible behavior: none.

### Context

- Source: `chat_page.dart` ~L5385–5556:
  `_workflowProjectionStatusLabelKey`, `_planDocumentEditLabelKey`,
  `_planDocumentHeaderEditTooltipKey`, `_workflowProjectionStatusColor`,
  `_workflowStageLabel`, `_workflowTaskStatusLabel`,
  `_workflowValidationStatusLabel`, `_workflowTaskEventLabel`,
  `_workflowTaskEventSummary`, `_planDocumentDiffEntryLabel`,
  `_workflowTaskStatusColor`, `_recommendedWorkflowStage`.
- Call sites exist in part files (`chat_page_companion_builders.dart:381,406`,
  `chat_page_plan_builders.dart:54`, `chat_page_workflow_builders.dart:128,
  608, 892–928`) — keeping delegates avoids touching them.
- Purity: everything is a pure function of its arguments; `.tr()` needs no
  context; the two `Color` helpers take `BuildContext` for `Theme.of`.
  `_recommendedWorkflowStage` — audit before moving; if it reads page state,
  it stays.

### Implementation Notes

- New file:
  `lib/features/chat/presentation/widgets/workflow_status_presentation.dart`
  — an abstract final class (or top-level functions; match repo style) with
  static equivalents of the moved helpers, public names without underscores.
- Keep one-line delegates on `_ChatPageState` for every moved helper so the
  part-file call sites stay untouched (mirrors the delegate idiom from
  `docs/chat_notifier_decomposition_tranche1.md`).
- Move the `.tr()` keys and `switch` arms byte-identical.

### Acceptance Criteria

- Net main-file reduction ~130 lines (bodies out, delegates in).
- New unit test
  `test/features/chat/presentation/widgets/workflow_status_presentation_test.dart`
  covering the stage/status label switches and the projection status key
  selection (fresh / stale / unavailable).

---

## Task 7 — extract the image drop target widget

**Commit:** `refactor(chat): extract chat image drop target widget`

### Task

- Goal: move desktop drag-and-drop image handling into a reusable widget with
  a narrow callback API.
- Non-goals: changing supported extensions, overlay styling, or snackbar copy.

### Context

- Source: `chat_page.dart` `_buildImageDropTarget` (~L977–1053),
  `_handleImageDrop` (~L1054–1091), `_firstImageDropItem` (~L1092),
  `_isImageDropItem` (~L1104), `_readDropItemBytes` (~L1114),
  `_dropItemPathForImageHandling` (~L1135), `_mimeTypeForDropItem` (~L1142),
  and `_imageDropExtensions` (~L147).
- Page state involved: `_isImageDragActive` (moves into the widget),
  `_droppedImageAttachmentId` and `_droppedImageAttachment` (**stay** in the
  page — attachment identity is page-owned).

### Implementation Notes

- New file:
  `lib/features/chat/presentation/widgets/chat_image_drop_target.dart` —
  `class ChatImageDropTarget extends StatefulWidget` with:

```dart
ChatImageDropTarget({
  required bool enabled,
  required Widget child,
  required void Function(
    Uint8List bytes, String mimeType, String filePath) onImageDropped,
});
```

- The widget owns the drag-active overlay state and the unsupported/failed
  snackbars (strings verbatim: `message.drop_image_overlay`,
  `message.drop_image_unsupported`, `message.drop_image_failed`).
- The page wires `onImageDropped` to build the `MessageInputImageAttachment`
  with `++_droppedImageAttachmentId` and `setState`, exactly as today.
- Keep `unawaited(...)` on the drop handler and the
  `mounted` / `context.mounted` guard structure.

### Similar-Pattern Search

- Search terms: `DropTarget(`, `_imageDropExtensions`, `drop_image_`.
- Confirm no other page uses `desktop_drop` before generalizing anything.

### Acceptance Criteria

- Main file shrinks by ~180 lines (`desktop_drop` import may leave the main
  file if no other use remains).
- New widget test: dropping a supported extension invokes `onImageDropped`;
  unsupported items show the snackbar and do not invoke it (drive the handler
  directly; `DropTarget` events are hard to synthesize — testing the extracted
  `handleDrop` method on the widget state is acceptable).

### Verification

Shared commands plus:

```bash
tool/codex_verify.sh --coverage
```

---

## Task 8 — update the refactor plan doc

**Commit:** `docs: update large file refactor plan with chat page tranche 1 status`

- Refresh the line-count inventory in `docs/large_file_refactor_plan.md`
  (`wc -l` on the listed files).
- Mark Phase 2 progress: which slices landed, the new widget files under
  `widgets/approval/`, and the measured line reduction.
- Record the later-tranche roadmap:
  1. **Tranche 2 — workflow task run coordinator:** extract
     `_runWorkflowTask`, `_runWorkflowTaskValidation`,
     `_continueToNextPendingTaskIfNeeded`, the eight `_maybeRecoverFrom*`
     heuristics, `_maybePromoteCompletionFromValidationToolResults`, and the
     `_captureExecutionProgress*` pair (~L2883–5382, ~2,500 lines) into a
     presentation-layer coordinator class holding notifier handles plus an
     `isMounted` callback. **Precondition: add characterization tests first**
     — the recovery heuristics are only indirectly pinned today, and per repo
     policy recovery behavior must not drift without evidence.
  2. **Tranche 3 — plan review/approval actions** (~L2052–2882:
     `_editPlanInChat`, `_cancelPlanReview`, `_approveCurrentPlanAndStart`,
     workflow editor and task-menu handlers).
  3. **Tranche 4 — slash command handler** (~L524–954, pinned by
     `chat_page_slash_commands_test.dart`).
  4. **Tranche 5 — build() scaffold decomposition** plus the right-sidebar
     layout helpers (`_buildRightSidebarPanel` / `_wrapWithRightSidebar`,
     ~L322–427), following the existing `chat_page_*_builders.dart` idiom.

---

## What explicitly stays in _ChatPageState after this tranche

Scroll management and auto-follow, workspace-mode switching and project
activation, drawer wiring, the slash-command cluster, the plan review /
approval action handlers, the entire workflow task execution and recovery
cluster, the `build()` layout, and every `resolve*` bridge to `ChatNotifier`.
