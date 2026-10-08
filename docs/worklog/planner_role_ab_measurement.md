# Planner Role A/B — CMVP-1 measurement (2026-07-25)

Does routing **plan drafting** to a stronger external model improve a coding run,
when execution stays on the local model?

## Setup

- Fixture: `docs/coding_mvp_fixtures/todo_app.md` (CMVP-1), seeded into a fresh
  directory per run.
- Prompt (identical in both arms, deliberately short — the plan is supposed to
  supply the structure, so the prompt must not):
  > todo_app.md を読んで、その仕様どおりの TODO アプリを実装してください。言語は Dart とします。
- Execution model (both arms): `qwen3.6-27b-vision` on the LAN llama.cpp server.
- Planner arm: planning role pinned to `grok-4.5` (xAI, OpenAI-compatible).
  Baseline arm: planning role unassigned, so the primary model drafts the plan
  it will execute.
- Every run's arm was confirmed from its session log (which model served
  `Create a workflow proposal` / `Create a task proposal`), not assumed.
- **Acceptance was re-checked by hand**: each deliverable was copied to a scratch
  directory and the fixture's full walk-through was run against it. The model's
  own completion report was not treated as evidence — twice it was wrong.
- All seven runs are on builds that already contain the tool-catalog prompt fix
  (see "Defects surfaced"), so that change is not part of the comparison.

## Results

| Run | Arm | Wall | Plan drafting | Execution calls | Tasks | Acceptance (7 criteria) | Verification behaviour |
|---|---|---|---|---|---|---|---|
| run9 | planner | 360s | 4 calls / 17.7s | 19 | 3 | pass | exit status masked by a trailing `; test $? -ne 0` |
| run13 | planner | 355s | 4 / 14.3s | 15 | 2 | pass | negative checks correctly scoped in subshells |
| run14 | planner | 280s | 3 / 25.8s | 10 | 2 | **fail** | fabricated: 8 verification steps claimed, zero tool calls |
| run15 | planner | 390s | 4 / 29.7s | 17 | 2 | pass | verification failed, was repaired, then passed |
| run10 | baseline | 474s | 3 / 50.9s | 22 | 3 | pass | happy path only |
| run11 | baseline | 506s | 3 / 50.2s | 29 | 3 | pass | happy path only |
| run12 | baseline | 432s | 3 / 69.3s | 21 | 3 | **fail** | happy path only; missed an unknown-id crash |

Planner: 3/4 passed, mean 346s. Baseline: 2/3 passed, mean 471s.

## What the numbers support

1. **Wall clock is consistently lower on the planner arm.** The ranges do not
   overlap (planner 280–390s vs baseline 432–506s). Plan drafting itself is also
   faster on the cloud model (14–30s vs 50–69s), so routing the role out did not
   cost latency — it saved it.
2. **Quality is a tie.** 3/4 vs 2/3 is not a difference at this sample size.
3. **Verification coverage differs consistently.** All four planner runs put a
   full acceptance walk-through — including the unknown-id cases — into the plan
   as its own task. None of the three baseline plans did; they validated the
   happy path only, and the one baseline failure is exactly an unknown-id crash
   that a happy-path check cannot see.

Point 3 is the most interesting result, and the one worth building on: the
difference is not "the plan is prettier" but "the plan says what to verify".

## What the numbers do not support

- **Speed is confounded by task count.** Planner plans had 2–3 tasks, baseline
  plans always 3. Fewer tasks means less execution work regardless of plan
  quality, and the fastest run of all (run14, 280s, 10 calls) is a *failure* that
  was fast because it skipped the verification it claimed to have done. Speed
  alone must not be read as a quality signal.
- n = 4 vs 3, one fixture, one executor model, one language. Nothing here
  generalizes beyond "CMVP-1 in Dart on this pair of models".
- No claim about cost: the planner arm spends cloud tokens the baseline does not.

## Defects the measurement surfaced

The runs were more valuable as a defect detector than as an A/B. Three distinct
failures of the same underlying kind — *the harness believing the model's account
of its own verification* — showed up in one afternoon:

| Observed | Fix |
|---|---|
| Plan-drafting requests carried a system prompt advertising 169 tools while attaching none, so grok answered the JSON-only proposal with a (mangled) tool call and every task proposal failed | The tool-observation helper no longer writes back into the prompt's tool list (`chat_notifier_context_surgery.dart`). System prompt 29.5k → 11k chars |
| A chain ending in `; test $? -ne 0` reported exit 0 after breaking at its second command, and the model read that 0 as "all criteria verified" | `CodingCommandOutputGuardrailService.detectMaskedExitStatusIssue` refuses such a result as evidence (evidence-only, never blocks execution) |
| A task was reported complete while its own saved `validationCommand` was never run — a neighbouring task's successful validation satisfied the gate | `ConversationPlanExecutionGuardrails.savedValidationCommandSucceeded` requires the task's own command to have succeeded |

Also fixed while measuring: plan mode was unreachable from a new thread, the
plan review sheet silently no-opped for a task-less draft, and the sidebar
progress spinner never stopped because the busy set was not observable state.

## Decisions

- **Keep the planning role, default off.** It is cheap, it lowers latency, and it
  costs nothing in quality. Use it when a stronger planner is available.
- **Stop the A/B here.** Detecting a real quality difference would need a much
  larger n against a confound (task count) we cannot cheaply remove, while the
  failures that actually break runs are verification-integrity bugs.
- **Next work goes to verification integrity**, not planner selection. The open
  gap: a plan whose `validationCommand` does not cover the acceptance criteria
  (run12) still passes every guard, because the guards check that the saved
  command ran, not that it checks the right things.

## Repeating this

`tool/run_plan_mode_todo_app_planner_ab_canary.sh` runs one arm end to end and
writes `planner_ab_summary.json` with the numbers above. It verifies the arm from
the session logs and exits non-zero on a mismatch. Set
`CAVERNO_PLANNING_BASE_URL` / `_API_KEY` / `_MODEL` for the planner arm; omit them
for the baseline. Note the canary's acceptance check is its own post-validator —
it has not yet been cross-checked against a hand-run walk-through.
