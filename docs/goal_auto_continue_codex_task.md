# Codex Task: Evidence-Based Goal Auto-Continuation (Safe Boundaries)

Follow-up to `docs/coding_goal_slash_command_codex_task.md` (implemented on
`feature/coding-goal-slash-command`). This task adds the missing Codex-goals
behavior: when a turn ends with the active goal demonstrably incomplete, the
agent continues on its own instead of waiting for the user — but **only at
safe boundaries** and **only on concrete evidence**, never on the model's
prose intent.

Reference model: <https://developers.openai.com/cookbook/examples/codex/using_goals_in_codex>
("Continuation only triggers at safe boundaries: when turns complete, the
thread is idle, and no user input is queued"; "evidence-based continuation").

## Motivating Evidence (do not skip)

Session log `~/.caverno/session_logs/coding/8fc5332e-9aa3-4ba3-9e12-8a9d3d598c00.jsonl`
(build `352c5f19`, goal: "todo_app.mdを参考にしてMVPの実装を"):

- The tool loop ran 13 rounds and was cut by the iteration cap (base 12,
  `chat_notifier.dart` ~line 5343) while the model was still mid-work.
- The `TASK NOT COMPLETE` guard (`tool_result_prompt_builder.dart`) correctly
  forced an honest final answer: 6 unresolved Error-severity diagnostics in
  `bin/todo_cli.dart`, model stated it would fix them.
- `recordCurrentGoalTurn` correctly left the goal `active` (response matched
  an unresolved-incomplete signal).
- Then the thread simply stopped, waiting for a user re-prompt. That gap —
  mechanical stop, objectively incomplete goal, idle thread — is exactly what
  this task closes.

## Task

- Goal: after turn finalization, when the thread is at a safe boundary and
  the active goal has concrete evidence of incompleteness, automatically send
  a hidden continuation prompt so the model resumes work, bounded by the
  goal's turn budget and a no-progress stall detector.
- User-visible behavior:
  - Opt-in per goal via a new `autoContinue` flag (default **off**), exposed
    in the goal editor sheet and via `/goal auto on` / `/goal auto off`
    (new reserved keywords in `_handleGoalSlashCommand`); `/goal` status
    output shows the flag.
  - When a continuation fires, the user sees the assistant simply keep
    working (no fake visible user message), plus a lightweight indicator that
    an auto-continuation is in progress (goal chip badge or snackbar with the
    continuation count, e.g. "Goal auto-continue 2/10").
  - The existing stop/cancel control aborts the continued turn like any other
    turn; `/goal pause` (or disabling the flag) prevents further
    continuations.
  - When continuation stops on budget or stall, the goal is not silently
    abandoned: budget exhaustion leaves the goal active (the system prompt
    already instructs a stop-and-summarize on exhausted budgets); a stall
    marks the goal blocked with a reason.
- Non-goals:
  - Do NOT trigger on the model's stated intent ("これらを修正します" /
    "I'll fix these"). Prose intent is neither necessary nor sufficient;
    evidence is the trigger. Intent phrasing must not appear in the gate.
  - No continuation for general-workspace threads, routines
    (`RoutineExecutionService`), participant/group turns, or voice mode.
  - No changes to the tool-loop iteration cap, the `TASK NOT COMPLETE`
    guard, or `ConversationGoalProgressInference` signal lists.
  - No retry/backoff sophistication: one pending continuation at most; if the
    gate says no, the thread stays idle.
  - The known tool-catalog flapping (60↔50 tools mid-loop, KV-cache impact)
    is a separate investigation — do not fix it here.

## Context

- Affected files or components (all verified on the current engine code,
  which `feature/coding-goal-slash-command` does not modify):
  - `lib/features/chat/presentation/providers/chat_notifier.dart` —
    turn finalization: `recordCurrentGoalTurn` call (~line 8964) followed by
    `_drainQueuedChatMessagesIfIdle` (~line 8990). The continuation hook runs
    **after** the drain attempt, only if the thread is still idle.
  - `_drainQueuedChatMessagesIfIdle` (~line 3006) — copy its guard style
    (`ref.mounted`, `state.isLoading`, queue emptiness, re-entrancy flag).
  - `sendHiddenPrompt` (~line 3033) — existing mechanism that runs a full
    turn from a prompt without appending a visible user message; use it (or a
    thin variant) to inject the continuation prompt so goal injection,
    tool loop, guards, and `recordCurrentGoalTurn` all apply to the
    continued turn unchanged.
  - `lib/features/chat/presentation/providers/chat_state.dart` — safe-boundary
    veto fields: `queuedMessages`, `isLoading`, `pendingSshConnect`,
    `pendingSshCommand`, `pendingGitCommand`, `pendingLocalCommand`,
    `pendingComputerUseAction`, `pendingBrowserAction`,
    `pendingFileOperation`, `pendingBleConnect`, `pendingSerialOpen`,
    `pendingParticipantToolApproval`, `pendingAskUserQuestion`,
    `pendingWorkflowDecision`, `participantTurnRuntime`, `error`.
  - `lib/features/chat/domain/services/tool_result_prompt_builder.dart` —
    computes `unresolvedErrorCount` / `unresolvedErrorPaths` for the
    `TASK NOT COMPLETE` guard but keeps them internal; expose them (smallest
    change: return them alongside the built prompt, or surface a result
    object) so the gate can read this turn's diagnostic evidence.
  - `lib/features/chat/domain/entities/conversation_goal.dart` — add
    `autoContinue` (bool, `@Default(false)`); regenerate freezed/json.
  - `lib/features/chat/presentation/providers/conversations_notifier.dart` —
    `saveCurrentGoal` gains an `autoContinue` parameter (preserve on
    objective replace, same as budgets); `markCurrentGoalStatus` unchanged.
  - `lib/features/chat/presentation/pages/chat_page_goal_builders.dart`
    (on `feature/coding-goal-slash-command`) — `_handleGoalSlashCommand`
    keyword switch (`pause` / `resume` / `clear`) gains `auto on` / `auto
    off`; goal editor sheet gains the toggle; status view shows it.
  - `assets/translations/en.json` + `ja.json` — new `chat.goal_auto_*` keys.
- Related docs: `docs/coding_goal_slash_command_codex_task.md`,
  `docs/coding_mvp_fixtures/` (live verification corpus).
- Reference implementation or pattern: the queued-message drain
  (`_drainQueuedChatMessagesIfIdle`) is the canonical "act only when idle and
  nothing is waiting" pattern; the blocked-goal auto-marking in
  `recordCurrentGoalTurn` (blocker repeated ≥ 3 → status blocked) is the
  precedent for the stall detector.
- Known quirks, compatibility rules, or release gates:
  - **Never continue past a pause the model or harness chose for safety.**
    Any non-null pending approval/question state is an absolute veto. This is
    an established project principle; violating it is a review blocker.
  - Queued user input always outruns continuation: the gate runs only after
    `_drainQueuedChatMessagesIfIdle` and must re-check the queue.
  - `recordCurrentGoalTurn` must run **before** the gate (it may flip the
    goal to completed/blocked; the gate reads the post-inference goal).
  - Continued turns go through `sendHiddenPrompt`-style dispatch, so each
    one increments `turnsUsed` and token usage via the normal finalization
    path — the budget math needs no special casing.
  - Entity change ⇒ `dart run build_runner build --delete-conflicting-outputs`;
    generated files are committed.

## Implementation Notes

- Preferred approach:
  1. **Pure decision service** (unit-testable, no Riverpod):
     `lib/features/chat/domain/services/conversation_goal_auto_continue_policy.dart`
     with a single `decide(...)` taking an immutable snapshot:
     goal (post-inference), safe-boundary booleans, this turn's evidence
     (unresolved error count + paths, whether the completion-claim guard
     fired, whether the tool loop exhausted its cap while still requesting
     tool calls), consecutive-continuation count, previous evidence snapshot,
     and whether the final answer ends with a question mark (`?` or `？`).
     Returns `continue(prompt evidence)` / `skip(reason)` /
     `stopAndBlock(reason)`.
  2. **Gate conditions** (all must hold to continue):
     - `goal.isActive && goal.autoContinue && !goal.budgetExceeded`.
     - Effective turn budget: `goal.turnBudget` when > 0, else a default
       constant (suggest `kGoalAutoContinueDefaultTurnBudget = 10`, colocated
       with the policy); `turnsUsed` must be below it.
     - Safe boundary: not loading, queue empty, **every** pending field
       listed above null, `participantTurnRuntime == null`, no error.
     - Evidence of incompleteness from **this** turn, at least one of:
       (a) `unresolvedErrorCount > 0`; (b) the `TASK NOT COMPLETE` guard
       fired; (c) the tool loop hit its cap while the model was still
       issuing tool calls. No evidence ⇒ skip (a goal thread with no
       verification surface must not self-perpetuate).
     - Negative veto: final answer ending in a question mark ⇒ skip (the
       structured path is already covered by `pendingAskUserQuestion`; this
       cheap rule covers prose questions conservatively).
  3. **Stall detector**: keep an in-notifier tracker per conversation id
     (consecutive auto-continuations + last evidence snapshot; reset when a
     real user message is sent). If two consecutive auto-continued turns show
     no improvement (unresolved error count not decreasing and same paths),
     return `stopAndBlock` ⇒
     `markCurrentGoalStatus(status: blocked, blockedReason: <english reason>)`
     and notify the user. In-memory (not persisted) is acceptable for v1.
  4. **Hook placement**: in the finalization path of `chat_notifier.dart`,
     after `_drainQueuedChatMessagesIfIdle` returns. Guard with the current
     interaction-generation check like every other post-finalization step,
     and a re-entrancy flag so only one continuation can be pending.
  5. **Continuation prompt** (fixed English template, hidden):
     state that this is an automatic goal continuation (n of budget), the
     goal objective, the concrete evidence (e.g. "6 unresolved Error
     diagnostics in bin/todo_cli.dart"), instruction to continue the work
     now, verify with the available diagnostics/tools, and to state the
     blocking condition instead of retrying if genuinely blocked. Pass the
     conversation's language code through so the visible answer stays in the
     user's language.
  6. **Logging**: `appLog('[GoalAutoContinue] ...')` for every decision
     (continue/skip/stop + reason). Optionally record a session-log entry
     (`operation: goal_auto_continue`) next to `turn_exit` so
     `tool/triage_session_logs.py` can see continuations; if the log-store
     API makes this cheap, do it — it is how this feature will be audited.
- Constraints:
  - The decision service must be pure and covered by unit tests for every
    gate condition and veto independently.
  - Do not add new completion/intent phrase lists anywhere.
  - Keep the notifier-side glue thin; `chat_notifier.dart` is oversized
    already — put logic in the policy service.
- Generated files needed: `conversation_goal.freezed.dart` / `.g.dart`
  regeneration.
- Migration or data compatibility concerns: `autoContinue` defaults to false,
  so existing persisted goals deserialize unchanged and behavior is opt-in.

## Similar-Pattern Search

- Search terms: `sendHiddenPrompt`, `_drainQueuedChatMessagesIfIdle`,
  `recordCurrentGoalTurn`, `pendingAskUserQuestion`, `hiddenPrompt`.
- Files or modules inspected: confirm `sendHiddenPrompt` has no voice-mode
  side effects when `isVoiceMode: false`; confirm routines and participant
  turn coordinators never reach the interactive finalization hook; confirm
  the remote-coding feature does not share this finalization path.
- Follow-up tasks found: record any, e.g. persisting stall-tracker state, or
  a settings-level kill switch if testing shows the per-goal flag is not
  enough.

## Acceptance Criteria

- Required behavior (mirror the motivating session):
  - Goal active with `autoContinue` on; turn ends via iteration cap with
    unresolved Error diagnostics ⇒ exactly one hidden continuation fires,
    the model resumes fixing, and each continued turn repeats the gate.
  - Same scenario with `autoContinue` off (default) ⇒ current behavior,
    byte-for-byte no new requests.
- Edge cases (each is a unit test on the policy):
  - Queued user message present after drain ⇒ skip.
  - Any pending approval/question field non-null ⇒ skip (never continue past
    a safety pause).
  - Final answer ends with `?`/`？` ⇒ skip.
  - Goal completed or blocked by this turn's inference ⇒ skip.
  - `turnsUsed` at effective budget ⇒ skip, goal stays active, user notified
    once (snackbar/log), no repeat notifications.
  - Two consecutive continuations without diagnostic improvement ⇒ goal
    marked blocked with an English reason; no further continuations.
  - User sends a message mid-continued-turn ⇒ normal cancellation/queue
    semantics; stall tracker resets.
  - No verification evidence in the turn (plain Q&A on a goal thread) ⇒
    skip.
- Failure paths: if the hidden continuation send throws, log and stop (do
  not retry-loop); the goal stays active for manual resumption.
- Accessibility, localization, or platform expectations: new user-facing
  strings in both `en.json` and `ja.json`; continuation prompt itself is
  internal English (not localized).

## Verification

```bash
tool/codex_verify.sh --test test/features/chat/domain/services/conversation_goal_auto_continue_policy_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/providers/conversations_notifier_goal_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/pages/chat_page_slash_commands_test.dart
tool/codex_verify.sh
```

Live check (manual, after unit green): rerun the `todo_app.md` MVP fixture
with `autoContinue` on against the local model; confirm in the new session
log (schema v2 — check `build.commit` first) that a continuation request
follows `turn_exit`, the unresolved-error count decreases across continued
turns, and the run ends in either goal completion or an honest
blocked/budget stop.

## Handoff Notes

- Summary:
- Tests run:
- Coverage or low-coverage notes:
- Risks or follow-ups:
