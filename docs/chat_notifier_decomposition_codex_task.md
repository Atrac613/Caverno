# Codex Task: ChatNotifier Library Decomposition (Phase 1, Tranche 2)

Status: not started. Continues `docs/large_file_refactor_plan.md` Phase 1 after
Tranche 1 (`PlanningResearchCollector`, `WorkflowProposalParser`,
`ActiveResponseRegistry`, `ProjectScopedToolArgumentResolver`, …).

## Motivating Evidence (do not skip)

On 2026-07-25/27 roughly twenty defects were fixed on
`fix/cross-thread-tool-result-contamination`, squashed as `b0c19fdb`. Every one
had the same shape:

> `ChatNotifier` serves every thread from one object and `ChatState` belongs to
> the thread **on screen**, so turn-scoped code that reads it gets the wrong
> value for free.

A background turn quoted another thread's history, resolved relative tool paths
against the visible project, leased the wrong workspace, persisted its
transcript onto whoever was being read, lost its queue and plan draft on a
switch, and — the last one, read out of a running app over the VM service —
raised a plan question on the visible thread, where that thread's own flow
cleared it, stranding the turn with its registration, runtime handle and
workspace lease held until the app was quit.

Two ratchets now guard this (`test/quality/thread_scoped_state_ratchet_test.dart`
and the line budgets), but a call-graph pass found **45 methods that read
visible-thread state, take no turn identity, and are reachable from a turn**.
The thread-scope ratchet cannot see them: they have no argument to key on. No
rule can catch them while they live inside the library.

**A file that is `part of 'chat_notifier.dart'` can reach `state`, `ref`, and
every private field. A file that is not, cannot.** That is the point of this
task. Line count is the measurement, not the goal.

## Task

- Goal: convert the `chat_notifier.dart` same-library part files into
  independently importable collaborators that take explicit inputs, halving the
  library as a consequence.
- User-visible behavior: none. This is extraction only.
- Non-goals:
  - Any behavior change, including "obvious" improvements noticed in passing.
  - The per-thread notifier split (stage 3 in
    `docs/multi_thread_architecture_study.md`). Tranches A–E are deliberately
    independent of that decision and make it safer to attempt later.
  - Renaming providers, changing `ChatState` shape, or touching persistence
    schemas.
  - Raising any ratchet budget. See Constraints.

## Baseline (measured 2026-07-27, at `b0c19fdb`)

| | lines |
|---|---|
| `chat_notifier.dart` (orchestrator) | 9,376 |
| 43 declared part files | 13,717 |
| **same-library aggregate** | **23,093** |
| budget in `test/quality/file_size_ratchet_test.dart` | 23,030 |

**The library is currently 19 lines over budget and the ratchet test fails.**
That debt was taken deliberately at the end of `b0c19fdb`; Tranche A clears it.

### Part-file inventory, by coupling

`state` counts bare `state` references, `ref` counts `ref.`, `settings` counts
`_settings`. Low numbers mean the file barely uses the notifier and is mostly a
move; high numbers mean it needs an explicit context object first.

| file | lines | state | ref | settings | tranche |
|---|---:|---:|---:|---:|---|
| `chat_notifier_local_file_handlers.dart` | 1381 | 6 | 0 | 9 | C |
| `chat_notifier_goal_auto_continue.dart` | 1063 | 27 | 6 | 2 | E |
| `chat_notifier_command_guardrails.dart` | 1045 | 5 | 0 | 0 | D |
| `chat_notifier_computer_use_handlers.dart` | 782 | 4 | 0 | 0 | C |
| `chat_notifier_participant_turns.dart` | 763 | 35 | 1 | 6 | E |
| `chat_notifier_tool_loop_batch.dart` | 722 | 1 | 0 | 0 | B |
| `chat_notifier_unexecuted_action_recovery.dart` | 560 | 1 | 2 | 0 | B |
| `chat_notifier_coding_verification_feedback.dart` | 484 | 0 | 1 | 4 | B |
| `chat_notifier_coding_continuation_recovery.dart` | 458 | 0 | 0 | 1 | B |
| `chat_notifier_ask_user_question.dart` | 403 | 14 | 0 | 0 | E |
| `chat_notifier_git_handlers.dart` | 391 | 6 | 0 | 2 | C |
| `chat_notifier_turn_finalization_recovery.dart` | 375 | 3 | 2 | 2 | B |
| `chat_notifier_approval_handlers.dart` | 344 | 1 | 0 | 2 | C |
| `chat_notifier_ssh_handlers.dart` | 330 | 8 | 2 | 2 | C |
| `chat_notifier_subagent_handlers.dart` | 326 | 0 | 4 | 8 | C |
| `chat_notifier_browser_handlers.dart` | 281 | 3 | 2 | 1 | C |
| `chat_notifier_routine_handlers.dart` | 280 | 1 | 2 | 0 | C |
| `chat_notifier_final_answer_recovery.dart` | 279 | 1 | 2 | 6 | B |
| `chat_notifier_context_surgery.dart` | 271 | 6 | 3 | 3 | D |
| `chat_notifier_prompt_context.dart` | 267 | 0 | 2 | 7 | A |
| `chat_notifier_python_attachment_repair.dart` | 235 | 0 | 0 | 2 | A |
| `chat_notifier_tool_handler_registry.dart` | 199 | 1 | 0 | 0 | C |
| `chat_notifier_execution_runtime.dart` | 187 | 9 | 2 | 0 | keep |
| `chat_notifier_tool_result_telemetry.dart` | 167 | 0 | 6 | 11 | D |
| `chat_notifier_proposal_parsing.dart` | 163 | 0 | 0 | 0 | A |
| `chat_notifier_serial_handlers.dart` | 162 | 4 | 0 | 1 | C |
| `chat_notifier_skill_handlers.dart` | 161 | 1 | 2 | 0 | C |
| `chat_notifier_content_tool_result_format.dart` | 150 | 0 | 0 | 0 | A |
| `chat_notifier_ble_handlers.dart` | 143 | 4 | 1 | 1 | C |
| `chat_notifier_proposal_option_extraction.dart` | 137 | 0 | 0 | 0 | A |
| `chat_notifier_python_handlers.dart` | 125 | 1 | 0 | 1 | C |
| `chat_notifier_workflow_proposal_parser.dart` | 121 | 0 | 0 | 0 | A |
| `chat_notifier_response_finalization.dart` | 120 | 6 | 0 | 0 | keep |
| `chat_notifier_error_handling.dart` | 120 | 5 | 2 | 2 | keep |
| `chat_notifier_turn_exit.dart` | 117 | 0 | 0 | 2 | keep |
| `chat_notifier_task_proposal_quality.dart` | 112 | 0 | 0 | 0 | A |
| `chat_notifier_terminal_tool_response_policy.dart` | 111 | 0 | 0 | 0 | A |
| `chat_notifier_cancellation.dart` | 105 | 1 | 0 | 0 | keep |
| `chat_notifier_duplicate_recovery.dart` | 80 | 0 | 0 | 0 | A |
| `chat_notifier_task_proposal_parser.dart` | 61 | 0 | 0 | 0 | A |
| `chat_notifier_mesh_routing.dart` | 58 | 0 | 0 | 7 | A |
| `chat_notifier_planning_research.dart` | 53 | 1 | 0 | 0 | A |
| `chat_notifier_turn_rollback_handlers.dart` | 25 | 0 | 0 | 0 | A |

`keep` marks the turn lifecycle — `_startRuntimeTurn`, `_completeRuntimeTurn`,
`_failRuntimeTurn`, `_finishStreaming`'s finalization, cancellation, error
handling, turn-exit recording. These belong with the orchestrator; they are the
one place a turn's registration, runtime handle and workspace lease are released
together, and splitting them re-opens the defect class this task exists to
close. Do not extract them.

## Tranches

Land one tranche per PR. Within a tranche, land one file (or one cohesive group)
per commit. Never mix an extraction with a behavior change.

### Tranche A — pure helpers (1,573 lines, 13 files)

`prompt_context`, `python_attachment_repair`, `proposal_parsing`,
`content_tool_result_format`, `proposal_option_extraction`,
`workflow_proposal_parser`, `task_proposal_quality`,
`terminal_tool_response_policy`, `duplicate_recovery`, `task_proposal_parser`,
`mesh_routing`, `planning_research`, `turn_rollback_handlers`.

These reference no notifier state. Most become top-level functions or small
value classes. Start here: it is close to a pure move, it clears the 19-line
debt in the first commit, and it establishes the pattern for reviewers.

### Tranche B — recovery and verification services (2,878 lines, 6 files)

`tool_loop_batch`, `unexecuted_action_recovery`,
`coding_verification_feedback`, `coding_continuation_recovery`,
`turn_finalization_recovery`, `final_answer_recovery`.

Each takes the tool results, the turn's messages and the settings it needs as
arguments. `turn_finalization_recovery` touches `state` three times — resolve
those into explicit parameters rather than passing the notifier.

### Tranche C — tool handlers (4,905 lines, 13 files)

`local_file`, `computer_use`, `git`, `ssh`, `subagent`, `browser`, `routine`,
`serial`, `skill`, `ble`, `python`, `approval_handlers`,
`tool_handler_registry`.

The largest tranche and the one that removes the most ambient-read capability.
Handlers need three things: the tool service, an approval port, and the turn's
project root. Give them a single explicit context:

```dart
/// What a tool handler is allowed to know. Deliberately not the notifier:
/// a handler that can reach ChatState can resolve a path against the thread
/// the user happens to be reading, which is how 2026-07-25 happened.
class ToolHandlerContext {
  const ToolHandlerContext({
    required this.projectRoot,
    required this.conversationId,
    required this.settings,
    required this.requestApproval,
  });
  ...
}
```

`TurnProjectRoot` and `TurnThread` (Zone-scoped, in
`turn_project_root.dart` / `turn_thread_scope.dart`) already carry the identity
these need; read them at the call site and pass the values in, rather than
reading the Zone inside the extracted class.

### Tranche D — guardrails and telemetry (1,483 lines, 3 files)

`command_guardrails`, `context_surgery`, `tool_result_telemetry`.

`tool_result_telemetry` reads `_settings` eleven times — pass a settings
snapshot, not the notifier.

### Tranche E — explicit-context conversions (2,229 lines, 3 files)

`goal_auto_continue`, `participant_turns`, `ask_user_question`.

Highest coupling, do last. These are genuine orchestration and may keep some
notifier surface; the goal here is to reduce them to a narrow, named interface
rather than to move them wholesale. If a file cannot be extracted without
passing the notifier itself, **stop and leave it** — record why in this document
instead of forcing it.

### Expected outcome

Tranches A–E move **13,068** of the 13,717 part-file lines out of the library,
leaving the 649-line `keep` set. Extraction adds some back — class scaffolding,
explicit parameters, the doc comments this repo expects — so the aggregate
should land near **10,500–12,000** against a half-of-baseline mark of 11,546.

Halving is therefore reachable without touching `chat_notifier.dart` itself.
**Do not force it if the arithmetic comes out short.** Going further means
shrinking the orchestrator, which is the per-thread notifier split, not an
extraction. Tighten the budget to whatever is achieved and record the number.

## Constraints

- **Budgets may only shrink.** After each tranche, lower the entries in
  `test/quality/file_size_ratchet_test.dart` to the achieved counts. Never raise
  a budget to make a change fit — extract instead. This rule has held through
  three prior extractions and is why the ratchet still means something.
- **Check the destination's budget before moving code into it.** On 2026-07-26
  an extraction targeted `project_scoped_tool_argument_resolver.dart`, which is
  itself ratcheted at 152, and had to be redone into its own file.
- **Take providers lazily.** An extracted collaborator that calls
  `ref.read(...)` eagerly in its constructor broke 167 tests with
  "SharedPreferences must be overridden". Pass a closure
  (`() => ref.read(fooProvider)`) and read on use.
- **Private names cross the `part` boundary; extracted ones do not.** A moved
  `_foo` used by other part files must become public (`foo`) with every call
  site updated in the same commit.
- **Never `git checkout` a whole file to undo part of an edit.** It silently
  discards unrelated work in the same file. Use targeted edits.
- All code, comments, docs and commit messages in English. Conventional Commits,
  imperative subject, ≤72 chars, no period, no AI attribution
  (see `CLAUDE.md`).

## Verification

Run per commit:

```bash
fvm flutter analyze lib packages test tool
fvm flutter test test/features/chat test/quality test/core
```

Run per tranche, additionally:

```bash
tool/codex_verify.sh --coverage
```

Tranches B, C and E touch tool execution, recovery and approval, so the live
multi-thread canary is the gate that has repeatedly caught what unit tests
missed. It needs a warmed model and, on macOS, a loopback relay because the test
binary cannot reach a LAN address:

```bash
CAVERNO_MULTI_THREAD_LIVE_CANARY=1 CAVERNO_LLM_BASE_URL=http://127.0.0.1:11434/v1 CAVERNO_LLM_API_KEY=no-key CAVERNO_LLM_MODEL=qwen3.6-27b-vision fvm flutter test integration_test/multi_thread_plan_live_canary_test.dart -d flutter-tester
```

All four scenarios must pass, and each ends on the lifecycle gate: no thread
still listed busy, and every turn recording an exit reason.

## Acceptance Criteria

1. `test/quality/file_size_ratchet_test.dart` passes, with the chat_notifier
   entries **lowered** to the achieved counts. No budget anywhere is higher than
   it is today.
2. The declared-part count falls from 43 to at most 8 — the five `keep` files
   plus whatever Tranche E could not safely convert, each with a recorded
   reason.
3. `test/quality/thread_scoped_state_ratchet_test.dart` still passes with **at
   most** its current one reviewed entry. Extraction must not add turn-scoped
   readers of visible state.
4. Re-running the blind-spot count finds fewer methods than the 45 recorded on
   2026-07-26. Report the new number; this is the measurement that matters more
   than the line count.
5. `fvm flutter analyze lib packages test tool` is clean.
6. `fvm flutter test test/features/chat test/quality test/core` passes — 2,329
   chat tests at baseline, none removed. Tests move with the code they cover.
7. The live multi-thread canary passes on all four scenarios after Tranches B,
   C and E.
8. `docs/large_file_refactor_plan.md` Phase 1 is updated with the achieved
   counts and the Tranche 2 status.

## Handoff Notes

- The extraction pattern is already established, with five examples from this
  week to copy: `TurnToolResultLedger`, `TurnCodingProjectResolver`,
  `BackgroundProcessFollowUpPolicy`, `TurnFinalMessage`, and
  `tool_argument_json.dart`. Match their shape — explicit inputs, a doc comment
  naming the defect the boundary prevents, focused tests.
- `docs/multi_thread_architecture_study.md` records why the boundary matters and
  compares Codex's thread model. Read it before Tranche E.
- Do not "fix" anything you notice while moving code. Note it and move on. Every
  mixed commit this week cost more to review than it saved.
- If a tranche turns out to need a behavior change to proceed, stop and write
  down what and why rather than proceeding. The extraction is worth less than
  the guarantee that it changed nothing.
