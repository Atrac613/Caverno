# Codex Task: Execute the Pending Declared Batch at Loop Exhaustion + Encourage Command Batching

Two coupled changes to the tool-loop budget mechanics, both aimed at the same
observed failure chain: the loop cap cutting the model off **mid-declared
action** leaves "I was about to do X" dangling in context, and over several
nudged turns that dangling intent degrades into narrated-but-never-executed
work. Separately, the model spends the budget one command per round even
though multi-command execution is already supported, which is why the cap is
reached at all on Starter-tier tasks.

## Motivating Evidence (do not skip)

- Mid-intent truncation → degradation (all on `qwen3.6-27b-vision`,
  CMVP-1 fixture):
  - `39ce9b0d` (2026-07-09): turn 2 hit `bounded_tool_loop_exhausted` twice;
    final injection: "the bounded tool loop stopped before a requested tool
    call (edit_file) was executed".
  - `fb9d799b(.1)` (2026-07-09): gen-16/17/21 each ended with an unexecuted
    write_file / local_execute_command / edit_file; by gen-22 the model
    emitted a **zero-tool narrated-execution turn** ("テストが16件全てパス
    しました" with no tool calls at all) — the dangling-intent endgame.
  - `1b29b760` (2026-07-09): the cap cut a pending edit_file 1 round short
    of turn completion.
- Batching gap: the hermes agent completed the same fixture (Dart pinned,
  same LAN server, same non-thinking model) in one turn using 27 `terminal`
  calls averaging ~8 command lines per call. Caverno's runs issue one
  command per `local_execute_command` round, so 12 iterations buy ~12
  commands instead of ~100. `LocalShellTools._executeInternally`
  (`local_shell_tools.dart` ~483) already splits and sequentially executes
  conditional multi-command strings (`_splitConditionalCommands`) with
  early-exit on nonzero — the capability exists; the model is never told.

## Task

### Part A — pending-batch exit

- Goal: when the loop reaches `maxIterations` with tool calls already
  declared by the model, execute **that final declared batch** (all tool
  classes, not just read-only), append its results, and then end the loop —
  no further LLM tool rounds. The `tool_call_not_executed` /
  `bounded_tool_loop_exhausted` injection then only covers calls that
  genuinely could not run (e.g. approval pause), not calls dropped by the
  budget.
- User-visible behavior: turns that today end with "an edit_file remains
  unexecuted" instead end with the edit applied and the final answer
  reporting its actual result. Approval-gated calls in the final batch still
  go through the normal gate; if manual approval is required, the turn
  pauses exactly as today (safety pause, absolute — see
  [[harness-dont-override-safety-pauses]] principle: never auto-approve to
  finish a batch).
- Non-goals:
  - Do not raise the base cap (12, `chat_notifier.dart` ~5383
    `resolveToolLoopMaxIterations(12)`); the point is to change what
    happens *at* the cap, not to move it. Re-evaluate the cap only after
    this and batching land (evidence-driven).
  - Do not add more recovery rounds; the existing bounded exhaustion
    recovery (`_shouldRequestToolLoopExhaustionRecovery`, which can extend
    `maxIterations` by 2–4) stays as is. Part A runs *after* recovery is
    spent.

### Part B — batching encouragement

- Goal: make the model use multi-command strings. Update the
  `local_execute_command` tool description to state that the command string
  may contain multiple newline- or `&&`-separated commands executed
  sequentially with early-exit on failure, and that related commands (e.g.
  format → analyze → test) SHOULD be batched into one call. Add one line to
  the coding system prompt section (near the existing tool-usage guidance in
  `system_prompt_builder.dart`) encouraging batching of related
  verification commands.
- Non-goals: no schema change (the tool already takes one string), no
  parallelism, no changes to `_splitConditionalCommands` semantics.
  Approval auto-review already reviews the full command string; confirm the
  audit shows the whole batch (it does — the string is the unit) and leave
  it.

## Context

- Loop: `chat_notifier.dart` ~5383 (cap), ~5423 (`while` loop), ~5885
  (existing final **read-only** inspection batch at cap —
  `_hasUnseenReadOnlyInspectionToolCalls` +
  `_executeFinalReadOnlyInspectionToolCalls`), ~5911 (bounded exhaustion
  recovery). Part A generalizes the ~5885 path: after recovery is exhausted,
  a pending batch of any class executes once via the normal dispatch
  (approval gates, batch executor dedup, telemetry all apply), then
  `currentToolCalls = []` and the loop ends.
- The exhaustion notice text lives in `tool_result_prompt_builder.dart`
  (~413, ~456, ~515) — after Part A it should only be produced for calls
  that remained unexecuted for a *non-budget* reason (approval pause,
  dispatch error), so audit its trigger conditions rather than deleting it.
- `ToolExecutionScheduler.executeBatch` and the lifecycle logging used by
  the final-inspection path show the pattern to reuse (including
  `_logToolLifecycleEvent` states), so the new batch is observable in
  session logs.
- Session log: turns that take the new exit should be distinguishable —
  reuse the tool lifecycle events and consider a `turnExit` hint (grep
  `_turnExitReasonHint`) such as `pending_batch_executed` so triage can
  count them.
- Tool description: `local_execute_command` schema/description lives with
  the built-in tool definitions (grep the description string used for
  `local_execute_command` under `lib/features/chat/data/datasources/`).

## Similar-Pattern Search

The read-only final-batch path (~5885) is the template for Part A — match
its generation checks (`_isCurrentInteractionGeneration`, `ref.mounted`) and
its result plumbing into `executedToolResults`. For Part B, check
`docs/session_logs.md` and the harness-config docs for any per-model tool
description overrides before editing the base description.

## Acceptance Criteria

1. Loop test: model declares `edit_file` on the round that reaches the cap →
   the edit executes, its result reaches the final-answer injection, no
   `tool_call_not_executed` notice is produced, and the loop issues no
   further LLM rounds after the batch.
2. Loop test: pending batch contains an approval-gated command and the mode
   requires manual approval → the turn pauses for approval exactly as
   today; nothing is auto-approved; on denial the denial result is what the
   final answer sees.
3. Loop test: dispatch failure inside the final batch still produces the
   honest unexecuted/failed notice.
4. The bounded exhaustion recovery still runs before the final batch and its
   `maxIterations` extension still works (existing tests keep passing).
5. `local_execute_command` description mentions multi-command batching;
   a multi-line command string executes sequentially with early exit
   (existing `LocalShellTools` behavior — add a regression test if none
   exists).
6. `flutter analyze` and `flutter test` pass.

## Verification

Re-run the CMVP-1 controlled dogfood (Dart pinned, per
`docs/coding_mvp_fixtures/README.md`) and compare against session
`1b29b760`: the run should no longer end with an unexecuted edit_file, and
`local_execute_command` calls should show batched command strings. Attach
both session log paths in the PR.

## Handoff Notes

Part A changes turn-ending semantics that several guards key off
(`TASK NOT COMPLETE` injections, unexecuted-action notices) — run the full
guard test suites and the auto-continue policy tests, not just loop tests.
If the final batch executing mutations right before turn end interacts
badly with the goal auto-continue evidence
(`docs/goal_auto_continue_default_on_codex_task.md`, "mutated without
execution verification" trigger), note it in the PR; the two tasks are
designed to compose (the batch's own command results count as execution).
English only in code/comments/commit messages (repo rule).
