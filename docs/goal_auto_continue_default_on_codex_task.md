# Codex Task: Goal Auto-Continue Default-On + Zero-Execution Evidence

Follow-up to `docs/goal_auto_continue_codex_task.md` (implemented in
`c7e52afc`). That task shipped evidence-based auto-continuation as an opt-in
per-goal flag. Two dogfooding runs since have shown the opt-in default makes
the feature dead weight, and exposed a blind spot in the evidence gate. This
task flips the default to **on** for newly created goals, closes the
zero-execution blind spot, fixes the `/goal ... auto on` parsing trap, and
adjusts one line of goal guidance that currently steers the model away from
verification.

## Motivating Evidence (do not skip)

Both runs are CMVP-1 fixture dogfoods (`docs/coding_mvp_fixtures/todo_app.md`)
on `qwen3.6-27b-vision`, both with a goal active and the user *intending* to
enable auto-continue:

- `~/.caverno/session_logs/coding/1b29b760-1962-4bd5-aca7-d9c1d3ccc7a4.jsonl`
  (2026-07-09, build `c7e52afc`): the user typed
  `/goal <objective> auto on`. The trailing `auto on` was swallowed into the
  objective text (the parser only accepts `auto on|off` as the *entire*
  argument list, `chat_page_goal_builders.dart` ~119), so `autoContinue`
  stayed `false`. The turn then ended in `bounded_tool_loop_exhausted` with an
  unexecuted `edit_file` — the exact evidence trigger auto-continue exists
  for — and the thread sat idle.
- `~/.caverno/session_logs/coding/fc1c1bbf-95ec-4541-b302-e8d9f3d6c660.jsonl`
  (2026-07-10): same swallowed `auto on` suffix. Worse failure shape: the
  model wrote 2 files, fixed 2 LSP warnings, executed **zero** commands (no
  pub get, no analyze run, never ran the program), then declared the MVP
  implemented while listing two files it never wrote. Even if `autoContinue`
  had been `true`, the policy would have skipped: a turn that executes
  nothing produces no incomplete evidence
  (`conversation_goal_auto_continue_policy.dart` ~184 skips on
  `!input.evidence.hasIncompleteEvidence`).

Decision (user-approved 2026-07-10): goals should auto-continue **by
default**; the safety vetos stay absolute; the budget must be visible; the
evidence gate must treat "mutated files but never verified by execution" as
incomplete evidence.

## Task

- Goal: a newly created goal continues on its own by default, within the
  existing turn-budget / stall / veto machinery, and a turn that mutates
  files without any execution-class verification counts as evidence of
  incompleteness.
- User-visible behavior:
  - `/goal <objective>` and the goal composer/editor create goals with
    `autoContinue = true`. `/goal auto off` (existing keyword) opts out;
    the editor switch still works both ways.
  - A trailing ` auto on` / ` auto off` suffix on
    `/goal <objective> auto on|off` is stripped from the objective and
    applied as the flag, with a feedback message stating both the saved
    objective and the resulting auto state. The objective never silently
    contains the words `auto on`.
  - Whenever a goal with `autoContinue` enabled is active, the remaining
    auto-continue budget is visible without asking: the existing goal
    chip/indicator shows the continuation count against the effective turn
    budget (the `2/10`-style counter from the previous task), and
    `/goal status` includes it.
  - Safety pauses are untouched: a turn that ends waiting on a tool
    approval, or whose final answer asks the user a question, is never
    auto-continued (existing vetos; add regression coverage, do not
    reimplement).
- Non-goals:
  - No changes to the tool-loop iteration cap, `TASK NOT COMPLETE` guard
    text, or the no-progress/stall thresholds.
  - No judge-model completion verdict (tracked separately as the agreed
    escalation path).
  - Do not fix `ToolApprovalCache` stale replay or add an
    unwritten-file-claim guard here — both are separate tasks.
  - Do not auto-enable `autoContinue` on goals deserialized from storage
    that were saved without the flag (pre-existing goals keep behaving as
    before).

## Context

- `lib/features/chat/domain/entities/conversation_goal.dart:16` —
  `@Default(false) bool autoContinue`. Keep the entity default `false` so old
  persisted goals (JSON without the key) deserialize unchanged. Flip the
  default at **creation sites** instead:
  - `chat_page_goal_builders.dart` `_handleGoalSlashCommand` — the final
    `saveCurrentGoal(objective: trimmedArgs, ...)` branch (~152) currently
    omits `autoContinue` (falls back to false for a new goal; preserves the
    existing value when editing an existing goal — keep that distinction:
    default-on applies to goal *creation*, not to re-saving an existing goal
    whose flag the user turned off).
  - The goal composer/editor initial state
    (`chat_page_goal_builders.dart` ~297: `_autoContinue = goal?.autoContinue
    ?? false` → `?? true`).
- `chat_page_goal_builders.dart` ~119–150 — `auto on|off` keyword parsing
  (whole-args form). Add the trailing-suffix form: if the args have ≥3
  tokens and the last two are `auto` + `on|off`, treat the head as the
  objective and the tail as the flag.
- `lib/features/chat/domain/services/conversation_goal_auto_continue_policy.dart`
  ~184 — the evidence gate. New signal: extend
  `ToolResultCompletionEvidence` (`tool_result_prompt_builder.dart:12`) or
  the policy input with a `mutatedWithoutExecutionVerification` boolean:
  true when the turn executed at least one file-mutation tool
  (`write_file` / `edit_file` / `rollback_last_file_change`) and zero
  execution-class tools (`local_execute_command`, `run_tests`,
  `git_execute_command`, `process_start`/`process_wait`). When true, the
  policy treats the turn as having incomplete evidence (subject to all
  existing vetos, budgets, and the no-progress stall counter — a model that
  keeps writing without ever executing must still hit `noProgress` and
  block rather than loop forever).
  - The continuation prompt for this trigger should name the reason, e.g.
    files were modified but nothing was executed to verify them, so the
    model is steered toward running verification, not more writing.
- `lib/features/chat/domain/services/system_prompt_builder.dart:247-250` —
  the exploration guidance ("For codebase exploration, prefer
  list_directory, find_files, search_files, and read_file before using local
  shell commands."). Append one sentence distinguishing exploration from
  verification, e.g.: "For verification the opposite holds: before claiming
  a coding task or goal is complete, run the program or its tests
  (local_execute_command / run_tests); clean static diagnostics alone are
  not completion evidence."
- Translations: new/changed feedback strings go through easy_localization
  (`assets/translations/en.json` / `ja.json`), reusing the existing
  `chat.goal_auto_continue_*` key family.
- Session logging: `goal_auto_continue` log entries
  (`llm_session_log_store.dart` ~461) already carry `evidence`; make sure the
  new trigger is distinguishable there (e.g. an evidence field naming
  `mutated_without_execution`), so dogfooding logs can tell which trigger
  fired.

## Similar-Pattern Search

Before implementing, check how the previous task wired evidence into the
policy (`ToolResultCompletionEvidence` accumulation across the turn) and reuse
that path rather than adding a parallel tracker. Check the live canaries added
in `c7e52afc` (TODO auto-continue canary) and extend the same harness instead
of inventing a new one.

## Acceptance Criteria

1. `/goal build X` creates a goal with `autoContinue == true`;
   `/goal build X auto off` creates it with `false` and the objective
   `build X`; `/goal build X auto on` yields objective `build X` (no `auto
   on` text) with the flag on; bare `/goal auto on|off` still toggles the
   existing goal as before.
2. A goal persisted before this change without an `autoContinue` field still
   deserializes to `false`.
3. Policy unit test: a turn with `write_file` executed, zero execution-class
   tools, no other incomplete evidence, active goal with budget remaining →
   decision is `continueTurn` with a reason naming the
   mutation-without-verification trigger. Same input but with a successful
   `local_execute_command` in the turn → `skip`.
4. Policy unit test: the new trigger still respects the no-progress stall
   (repeated mutation-without-verification turns with no diagnostic change →
   `stopAndBlock`), the turn budget, and both existing vetos (pending
   approval, question-to-user) — vetos win over the new trigger.
5. The goal indicator shows the auto-continue counter/budget whenever the
   flag is on, and `/goal status` prints it.
6. `flutter analyze` and `flutter test` pass; the auto-continue canary passes
   with the new default.

## Verification

- Run the existing auto-continue policy tests plus the new cases:
  `flutter test test/features/chat/domain/services/conversation_goal_auto_continue_policy_test.dart`
  and the goal slash-command widget/unit tests.
- Manual dogfood per `docs/coding_mvp_fixtures/README.md` (controlled run,
  Dart pinned): `/goal todo_app.md を参考にMVPの実装を auto on` — confirm the
  feedback message shows the cleaned objective + auto on, and that a turn
  ending with mutations-but-no-execution triggers a continuation whose next
  turn actually runs verification commands.

## Handoff Notes

Record in the PR description which trigger fired in the manual dogfood run
(the `goal_auto_continue` log entry) and attach the session log path. If the
mutation-without-verification trigger causes continuation loops in practice
(model keeps writing, never executes, stall counter too slow), tune only the
stall threshold interaction — do not weaken the vetos or reintroduce prose
triggers. English only in code/comments/commit messages (repo rule).
