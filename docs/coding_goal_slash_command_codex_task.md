# Codex Task: `/goal` Slash Command for Coding Threads

Add a `/goal` slash command to coding-mode threads, modeled on the Codex goals
feature (<https://developers.openai.com/cookbook/examples/codex/using_goals_in_codex>).
Caverno already has the entire goal engine (thread-scoped `ConversationGoal`
with lifecycle status, budgets, system-prompt injection, and per-turn progress
inference). This task adds only the missing command front-end. **Do not build a
new goal engine — reuse the existing one.**

## Task

- Goal: Expose the existing per-conversation coding goal through a
  Codex-compatible slash command with the lifecycle
  `/goal [objective]`, `/goal pause`, `/goal resume`, `/goal clear`.
- User-visible behavior:
  - `/goal <objective>` sets (or replaces) the thread goal, enabled and
    active, and confirms via a feedback snackbar.
  - `/goal` with no arguments shows the current goal (objective, status,
    enabled flag, budget usage) via a feedback message; if no goal exists it
    opens the existing goal editor sheet so the user can create one.
  - `/goal pause` temporarily disables the goal (removed from the system
    prompt, progress accounting preserved).
  - `/goal resume` re-enables a paused goal and reactivates a
    blocked/completed one.
  - `/goal clear` removes the goal from the thread.
  - The command appears in the composer suggestion popup and in the `/help`
    sheet like every other built-in command.
  - Outside a coding workspace (or with no current conversation) the command
    keeps the input and shows an "available in coding threads" message,
    matching `/plan` and `/agent`.
- Non-goals:
  - No autonomous cross-turn continuation loop (Codex's "auto-continue when
    idle"). Caverno's goal already persists via system-prompt injection
    (`SystemPromptBuilder`) and per-turn accounting
    (`recordCurrentGoalTurn`); leave that engine untouched.
  - No `complete` / `block` subcommands — the goal chip UI in
    `message_input.dart` already covers manual status changes.
  - No budget syntax in the command arguments (budgets stay in the editor
    sheet). Do not wipe existing budgets, though — see Implementation Notes.
  - No changes to `ConversationGoal`, so no `build_runner` regeneration.
  - Not enabled while a response is streaming (`enabledWhileLoading` stays
    `false`; goal turn accounting runs at turn finalization and must not race
    a mid-stream mutation).

## Context

- Affected files or components:
  - `lib/features/chat/presentation/slash_commands/slash_command.dart` —
    add `goal` to `SlashCommandAction`.
  - `lib/features/chat/presentation/slash_commands/slash_command_prompt_template.dart`
    — add `'goal'` to `reservedSlashCommandNames` so custom prompt templates
    cannot shadow it.
  - `lib/features/chat/presentation/pages/chat_page.dart` — register the
    `SlashCommandDefinition` in `_buildSlashCommands` (~line 511) and add the
    `case SlashCommandAction.goal` to `_handleSlashCommand` (~line 618).
  - `lib/features/chat/presentation/pages/chat_page_goal_builders.dart` —
    put the actual handler here (it is the home of all goal UI logic:
    `_handleGoalSwitch`, `_showGoalEditor`, `_markGoalCompleted`,
    `_reactivateGoal`, `_clearGoal`).
  - `assets/translations/en.json` and `assets/translations/ja.json` — new
    `chat.slash_goal_*` keys.
- Existing goal engine (reuse, do not duplicate):
  - Entity: `lib/features/chat/domain/entities/conversation_goal.dart`
    (`ConversationGoalStatus { active, completed, blocked }`, `enabled` flag,
    token/turn budgets, `isActive` requires `enabled && active && objective`).
  - Mutations: `ConversationsNotifier` in
    `lib/features/chat/presentation/providers/conversations_notifier.dart`
    (~lines 925–1130): `saveCurrentGoal`, `setCurrentGoalEnabled`,
    `markCurrentGoalStatus`, `clearCurrentGoal`, `recordCurrentGoalTurn`.
  - Prompt injection: `SystemPromptBuilder` (~lines 177–245) emits
    "Active coding goal for this thread" plus remaining budgets and a
    budget-exhausted stop instruction whenever `goal.isActive`.
  - Progress inference: `ConversationGoalProgressInference` marks the goal
    completed/blocked from assistant responses; wired via
    `recordCurrentGoalTurn` in `ChatNotifier` at turn finalization.
- Reference implementation or pattern:
  - Coding-only gating with `keepInput` + unavailable message: `/plan`
    handler (`chat_page.dart` ~line 674) and `/agent` handler (~line 696).
  - Argument-taking definition: the `/agent` `SlashCommandDefinition`
    (~line 557) with `argumentHint` and `argumentRequirement`.
  - Enable/resume semantics: `_handleGoalSwitch` in
    `chat_page_goal_builders.dart` (enable → if status not active,
    `markCurrentGoalStatus(active)`; else `setCurrentGoalEnabled(true)`).
- Known quirks, compatibility rules, or release gates:
  - `saveCurrentGoal` resets `tokenUsage`/`turnsUsed`/blocker tracking when
    the objective changes (`resetProgress`) — this is intentional; keep it.
  - `saveCurrentGoal` defaults `tokenBudget`/`turnBudget` to `0`
    ("unlimited"). A naive call from the command would silently erase budgets
    the user configured in the editor sheet. Pass the previous goal's budgets
    explicitly when replacing the objective.
  - `markCurrentGoalStatus` does not touch `enabled`. A goal that is both
    disabled and blocked needs `setCurrentGoalEnabled(true)` **and**
    `markCurrentGoalStatus(status: active)` on resume.
  - `docs/coding_goal_composer_release_checklist.md` covers the existing goal
    chip flows; do not regress them.
  - All code comments, strings in code, and this feature's identifiers must
    be English (repo rule).

## Implementation Notes

- Preferred approach:
  1. Add `goal` to `SlashCommandAction`.
  2. Register in `_buildSlashCommands`:
     - name `'goal'`, description `'chat.slash_goal_desc'.tr()`,
     - `argumentHint: '[objective] | pause | resume | clear'`,
     - `argumentRequirement: SlashCommandArgumentRequirement.optional`,
     - `enabledWhileLoading` left at default (`false`).
  3. In `_handleSlashCommand`, add
     `case SlashCommandAction.goal:` that gates on
     `isCodingWorkspace && currentConversation != null` (otherwise
     `SlashCommandExecutionResult.keepInput(feedbackMessage:
     'chat.slash_goal_unavailable'.tr())`) and delegates to a new
     `_handleGoalSlashCommand(context, currentConversation, invocation.args)`
     in `chat_page_goal_builders.dart`.
  4. Subcommand parsing inside `_handleGoalSlashCommand`:
     - Trim args. A **reserved keyword** matches only when the trimmed args
       equal exactly (case-insensitive) `pause`, `resume`, or `clear`.
       Any other non-empty args — including multi-word strings that merely
       start with a keyword, e.g. `/goal pause the deployment` — are treated
       as an objective. Document this rule in a short code comment.
     - Empty args, goal with objective exists → return
       `SlashCommandExecutionResult(feedbackMessage:
       'chat.slash_goal_status'.tr(namedArgs: ...))` summarizing objective
       (truncate to ~120 chars), status label (reuse
       `_conversationGoalStatusLabel`), and paused state when
       `enabled == false`.
     - Empty args, no goal → call the existing
       `_showGoalEditor(context, currentConversation)` and return
       `SlashCommandExecutionResult.handled`.
     - Objective → `conversationsNotifier.saveCurrentGoal(objective: args,
       enabled: true, status: ConversationGoalStatus.active,
       tokenBudget: previousGoal?.tokenBudget ?? 0,
       turnBudget: previousGoal?.turnBudget ?? 0)`; feedback
       `'chat.slash_goal_set'` with the (truncated) objective.
     - `pause` → if no goal with objective, feedback
       `'chat.slash_goal_none'` via `keepInput`; else
       `setCurrentGoalEnabled(false)`; feedback `'chat.slash_goal_paused'`.
     - `resume` → if no goal with objective, `'chat.slash_goal_none'`; else
       `setCurrentGoalEnabled(true)` and, when
       `goal.status != ConversationGoalStatus.active`,
       `markCurrentGoalStatus(status: ConversationGoalStatus.active)`;
       feedback `'chat.slash_goal_resumed'`.
     - `clear` → if no goal with objective, `'chat.slash_goal_none'`; else
       `clearCurrentGoal()`; feedback reuses existing `'chat.goal_cleared'`.
  5. Add `'goal'` to `reservedSlashCommandNames`.
  6. Localization keys (add to **both** `en.json` and `ja.json` under
     `chat`): `slash_goal_desc`, `slash_goal_unavailable`, `slash_goal_set`
     (`{objective}`), `slash_goal_paused`, `slash_goal_resumed`,
     `slash_goal_none`, `slash_goal_status` (`{objective}`, `{status}`).
     Follow the tone of the existing `slash_*` / `goal_*` keys.
- Constraints:
  - Do not modify `ConversationsNotifier` goal methods,
    `SystemPromptBuilder`, `ConversationGoalProgressInference`, or the goal
    chip UI unless a bug blocks the task; if one does, report it in Handoff
    Notes instead of drive-by fixing.
  - Do not trigger the LLM goal-suggestion flow (`_applySuggestedGoal`) from
    the command; the command path must stay deterministic and offline.
  - Keep the handler small; `chat_page.dart` is already large — the switch
    case should be gate + delegate only.
- Generated files needed: none.
- Migration or data compatibility concerns: none (no entity changes; goals
  already persist in Hive via the conversation JSON).

## Similar-Pattern Search

Before finishing, check whether the same pattern appears elsewhere.

- Search terms: `SlashCommandAction.`, `findSlashCommand`,
  `reservedSlashCommandNames`, `slash_goal`, `hasObjective`.
- Files or modules inspected: confirm the exhaustive `switch` over
  `SlashCommandAction` in `_handleSlashCommand` is the only switch that needs
  the new case (the enum is also consumed by suggestion filtering, which is
  data-driven and needs no change); confirm `/help` picks the command up
  automatically from `_buildSlashCommands`.
- Follow-up tasks found: note (do not fix here) that
  `reservedSlashCommandNames` is missing the pre-existing built-ins
  `feedback` and `agent`/`worktree`/`worktree-agent`; flag it in Handoff
  Notes as a candidate follow-up.

## Acceptance Criteria

- Required behavior:
  - In a coding thread, `/goal Ship the parser fix with tests green` creates
    an enabled, active goal whose objective appears in the goal chip and in
    the next request's system prompt ("Active coding goal for this thread").
  - `/goal` then reports that objective and status; `/goal pause` removes the
    goal from subsequent system prompts (`isActive == false`) without
    resetting `turnsUsed`/`tokenUsage`; `/goal resume` restores it;
    `/goal clear` deletes it.
  - Replacing the objective via `/goal <new objective>` keeps previously
    configured token/turn budgets and resets progress counters.
  - `/goal resume` on a blocked or completed goal returns it to active.
- Edge cases:
  - `/goal pause`/`resume`/`clear` with no goal set → `keepInput` +
    `slash_goal_none`, input preserved.
  - `/goal PAUSE` (any casing) is the keyword; `/goal pause everything else`
    is an objective.
  - `/goal` in the general workspace or with no current conversation →
    `keepInput` + `slash_goal_unavailable`.
  - `/goal` while a response is streaming → blocked by the generic
    `slash_blocked_while_loading` path (no special handling needed; verify).
  - Custom prompt template named `goal` cannot be created
    (`reservedSlashCommandNames`).
- Failure paths: notifier calls are awaited; if the current conversation
  changes out from under the sheet (existing `_showGoalEditor` handles this),
  no crash.
- Accessibility, localization, or platform expectations: all new strings in
  both `en.json` and `ja.json`; no hard-coded UI strings in Dart.

## Verification

Extend existing suites rather than creating parallel ones:

- `test/features/chat/presentation/slash_commands/slash_command_test.dart` —
  suggestion filtering includes `/goal`; parsing of `/goal pause` vs
  `/goal pause the deployment`.
- `test/features/chat/presentation/pages/chat_page_slash_commands_test.dart`
  — command dispatch: set / view / pause / resume / clear, coding-workspace
  gating, no-goal edge cases (follow the harness already used there).
- `test/features/chat/presentation/providers/conversations_notifier_goal_test.dart`
  — only if you add coverage for the budget-preservation call pattern.

```bash
tool/codex_verify.sh --test test/features/chat/presentation/slash_commands/slash_command_test.dart
tool/codex_verify.sh --test test/features/chat/presentation/pages/chat_page_slash_commands_test.dart
tool/codex_verify.sh
```

## Handoff Notes

- Summary:
- Tests run:
- Coverage or low-coverage notes:
- Risks or follow-ups:
