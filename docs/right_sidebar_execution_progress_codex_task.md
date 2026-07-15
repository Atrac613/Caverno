# Right Sidebar Execution Progress

## Task

- Goal: Persist the active workflow task as in progress when coding execution
  starts instead of waiting for turn-finalization inference.
- User-visible behavior: The right sidebar changes the active task from pending
  to in progress while the first model request or tool loop is still running.
- Non-goals: Adding fractional subtask progress, changing completion inference,
  or redesigning the companion sidebar.

## Context

- Affected files or components: ChatNotifier execution startup, conversation
  execution progress persistence, execution snapshots, and focused provider
  tests.
- Related docs: `docs/goal_auto_continue_output_feedback_recovery_codex_task.md`
  and `docs/session_logs.md`.
- Reference implementation or pattern: Manual task execution already stores an
  `inProgress` status with a `started` event before running task work.
- Known quirks, compatibility rules, or release gates: Session
  `e865cb13-7a97-461e-999a-6bff1d3caa7e` remained `pending` from the initial
  request through multiple tool calls and changed to `inProgress` only before a
  later hidden continuation. The sidebar correctly renders persisted projected
  task state, so the state transition must happen earlier.

## Implementation Notes

- Preferred approach: Before the first coding execution request, find the
  execution-focus task and persist `inProgress`, `lastRunAt`, and one `started`
  event when its projected status is still pending.
- Constraints: Do not start tasks during Plan Mode proposal generation. Do not
  regress completed, blocked, or already-active tasks. Keep the update idempotent
  across Goal Auto-Continue requests.
- Generated files needed: None.
- Migration or data compatibility concerns: None. The persisted progress entity
  and event type already exist.

## Similar-Pattern Search

- Search terms: `projectedExecutionTasks`, `executionProgressForTask`,
  `updateCurrentExecutionTaskProgress`, `ConversationExecutionTaskEventType.started`,
  and `ExecutionShadow`.
- Files or modules inspected: Companion sidebar builders, ChatPage provider
  subscriptions, ChatNotifier prompt context, ConversationsNotifier progress
  persistence, execution snapshot projection, and provider tests.
- Follow-up tasks found: Fractional progress for acceptance criteria would be a
  separate product feature and is not needed to fix the stale pending state.

## Acceptance Criteria

- Required behavior:
  - A pending execution-focus task becomes in progress before the first coding
    model request completes.
  - The first execution snapshot reports the task as in progress.
  - Exactly one `started` event is stored for the transition.
  - The companion sidebar observes the persisted update through its existing
    provider subscription.
- Edge cases: Plan Mode proposal generation leaves tasks pending; later hidden
  continuations do not append duplicate start events.
- Failure paths: A persistence failure is logged but does not abort the chat
  turn.
- Accessibility, localization, or platform expectations: Existing localized
  task status labels and icons remain unchanged on desktop and compact layouts.

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/presentation/providers/chat_notifier_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/pages/chat_page_companion_panel_test.dart
tool/codex_verify.sh
```

## Handoff Notes

- Summary: Commit `1f73e1a2` persists the execution-focus task as in progress
  before the first coding model request. The transition stores `lastRunAt` and
  one `started` event, while Plan Mode proposal generation remains pending.
- Tests run:
  - Focused live-progress provider regression: passed.
  - ChatNotifier and companion panel suites: 309 tests passed.
  - `fvm flutter analyze --no-pub`: passed.
  - `tool/codex_verify.sh`: dependency install, generated-file verification,
    and analysis passed; the full parallel suite completed 3,240 tests and had
    one unrelated Settings diagnostics export timing failure.
  - The failing Settings diagnostics export test passed on an isolated rerun.
- Coverage or low-coverage notes: Coverage was not collected. The provider
  regression uses the production conversation persistence implementation, and
  the existing companion panel widget suite covers in-progress rendering.
- Risks or follow-ups: The numeric progress bar intentionally counts completed
  workflow tasks, so a single active task remains `0/1` until completion while
  its row now immediately shows the in-progress state. Fractional acceptance
  criterion progress would be a separate feature.
