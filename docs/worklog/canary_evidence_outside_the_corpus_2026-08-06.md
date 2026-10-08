# Canary Evidence Outside The Corpus (2026-08-06)

Question this answers: **LL34, LL35 and LL36 are each gated on "let the
instrument run longer". Where is the data supposed to come from?**

It already exists. There are **452 turns of coding evidence** in
`build/integration_test_reports/`, and no measurement has ever read them.

## The two corpora

| | Grounded logs | `turn_exit` turns |
|---|---:|---:|
| `~/.caverno/session_logs` — what every roadmap figure counts | 173 | 190 |
| `build/integration_test_reports/**/session_logs` — never read | **257** | **452** |

The canary tree spans 2026-07-11 → 2026-08-06 across 12 canary kinds
(`coding_todo_app_minimal_prompt` 50 logs, `plan_mode_todo_app` 38,
`coding_markdown_toc_exact_short` 35, `coding_stalled_diagnostic_repair` 32,
and eight more). It is **2.4x the turns of the measured corpus**, and it is the
*coding* population — the surface every one of these milestones is about.
`~/.caverno/session_logs` is mostly chat.

## Cause

Each `tool/run_*_live_canary.sh` sets

```
CAVERNO_SESSION_LOG_DIR="${RUN_DIR}/session_logs"
```

which is correct and required: after 2026-08-05 the store refuses to write under
`flutter test` unless the destination was chosen deliberately, and this is how
the canaries opt in. But nothing folds those logs back, and
`tool/triage_session_logs.py` globbed one and two levels only, while canary logs
sit three deep at `<run>/session_logs/<surface>/*.jsonl`.

So the fix for the contamination (isolate canary logs from the corpus) and the
gate on the milestones (accumulate more logs) were pulling in opposite
directions, and nobody noticed because the isolated logs were never counted.

## What this overturns

### 1. LL29's demotion rests on a 1.6% that is 14.2% on coding runs

LL29 is `later` with an explicit reason: "its LL31 evidence gate came back
negative (`tool_failure_abort` 1.6% of 377 turns), so it waits for a triage that
shows the abort path rising."

| | `tool_failure_abort` | `text_response` |
|---|---:|---:|
| Corpus (190 turns) | 3 (**1.6%**) | 156 (82.1%) |
| Canary (452 turns) | 64 (**14.2%**) | 305 (67.5%) |

The aborts are spread across many build commits, not concentrated in one old
binary. LL29 is about the tool loop halting the whole turn on a twice-failing
tool call — a coding-run failure mode measured almost entirely on chat traffic.

This does **not** by itself re-promote LL29. Canary fixtures are hard tasks run
repeatedly against local models, deliberately chosen to stress the loop, so a
higher abort rate is expected and is not a statement about typical usage. What
it removes is the basis for the demotion: the gate asked whether the abort path
is rare, and it was answered on the population where it would be rarest.

### 2. Three of LL36's seven "never fired" labels have fired

| label | corpus | canary |
| --- | ---: | ---: |
| `final_answer_concise_retry` | 0 | **24** |
| `truncated_tool_call_arguments_feedback` | 0 | **13** |
| `verification_claim_notice` | 0 | **2** |
| `narrated_transcript_repair` | 0 | 0 |
| `narrated_transcript_claim_notice` | 0 | 0 |
| `pending_action_length_recovery` | 0 | 0 |
| `unexecuted_tool_request_notice` | 0 | 0 |

`final_answer_concise_retry` is not merely non-zero — at 24 firings it is the
**largest single transform label in the canary corpus**, ahead of
`unexecuted_command_action_notice` (26 in the corpus, 2 here). The two
distributions barely overlap: the corpus's dominant guard is near-absent in
coding runs, and the coding runs' dominant guard is absent from the corpus.

Delete-by-measurement was one triage run away from proposing the deletion of a
guard that fires more than any other on the surface it protects.

Four labels are still at zero everywhere, and one of those is sharper than
before: `pending_action_length_recovery` has **its own canary**
(`coding_pending_action_length_recovery_live_canary`, 6 runs in this tree) and
still never fired. Either the guard is genuinely unreachable, or the canary
named for it does not reach it — the recurring pattern where a green canary
verifies a path other than the one it is named for. Read the harness before
reading that zero as evidence of anything.

### 3. LL35's shadow instrument has no denominator

`GoalContinuationLogRecordBuilder.buildCompletionShadow` returns `null` when the
two paths agree, and `_recordGoalCompletionShadow` returns early on `null`
(`chat_notifier_goal_auto_continue.dart:773`). **A record is written only on
disagreement.** Agreements are never logged, so no disagreement *rate* can be
computed from this log — only a disagreement *count*.

Both published readings treat the record count as a sample size:

- 2026-08-05 (roadmap): "11 turns of data and one disagreement".
- 2026-08-05 (contamination correction): "7 shadow turns rather than 11", with
  "zero disagreements on all three labels".

Every one of those 7 grounded records *is* a disagreement. The real counts:

| label | corpus | canary | meaning |
| --- | ---: | ---: | --- |
| `goal_completion_tool_accepted_lexical_missed` | 6 | 26 | the tool caught a completion the lexical path missed |
| `goal_completion_tool_rejected_lexical_completed` | 1 | 0 | the lexical path completed what the tool would have rejected |
| `goal_completion_lexical_only` | 0 | 0 | prose completed with the tool silent |

**32 instances of "the case the tool exists to catch"** (the enum's own words),
against a roadmap note that says "the tool has never caught a completion the
lexical path missed." And the one `tool_rejected_lexical_completed` record
(2026-07-23T22:48, build `0006912c`) is precisely the motivation the same note
says "has not been observed once".

The corpus records are all dated 2026-07-22 → 2026-07-24, i.e. they predate both
readings. Nothing new happened; the counts were misread.

What does *not* follow: that the lexical path can now be deleted. 32 of 33
disagreements are the tool being **more** permissive than the lexical gate, and
`lexical_completed_tool_silent` — the one that would strand goals if the lexical
path were removed — is at zero in both corpora, which is the number a
never-firing instrument and a genuinely absent failure mode both produce.

### 4. LL34's shadow comparison accumulates nowhere at all

The other three instruments write session-log records and at least *could* be
counted. LL34's cannot: `chat_notifier_tool_loop_batch.dart:450` sends the
comparison to `appLog`, so it lands in `~/.caverno/app_logs` for real usage and
in the run's `flutter_test.jsonl` for a canary. `app_logs` holds **three days**
(2026-08-02, -05, -06) and contains zero `[ToolOutcomeShadow]` lines. Across
every canary run in this tree, exactly one contains any — the one run for this
document.

So LL34's entire live sample is **4 comparisons** (2 recorded 2026-08-05, 2
today), all agreeing. "Wait for the sample to grow" is not a plan for an
instrument whose output is deleted on rotation.

The fix is small and has a working model in the same track: make it a session-log
marker the way `goal_completion_shadow` is, and it accumulates in whichever
corpus the run belongs to.

### 5. LL30's premise is much stronger than the corpus shows

Sessions with at least one byte-identical re-read: **207 of 257 (80.5%)** in the
canary tree against 38 of 173 (22.0%) in the corpus; worst single repeat 13x
against 10x. The re-read loop is a coding-run phenomenon, and it was being
measured on chat.

## One fresh run, for provenance

`tool/run_coding_todo_app_mvp_live_canary.sh` on build `6dceec29` against
`qwen3.6-27b-vision` (LAN llama.cpp, reached through a loopback relay because
`flutter_tester` holds no macOS Local Network grant): **passed in 174.7 s**.

It produced two LL34 comparisons — `local_execute_command` exit 1 and exit 0,
both `agree` — reproducing the 2026-08-05 result on a second model day, and one
more `goal_completion_tool_accepted_lexical_missed` disagreement, the 33rd.

## What was changed

`_iter_log_files` now discovers `.jsonl` at any depth, so
`--dir build/integration_test_reports` works and the canary tree is one command
away. Verified not to change the corpus result (same top row, same 1,569 skipped
ungrounded). Covered by `test/python/triage_session_logs_test.py`.

Not changed: where the canaries write. Isolation is correct — the corpus should
not fill up with fixture traffic again. The tree just has to be *readable*.

## Not concluded here

Whether the two corpora should ever be pooled. They answer different questions:
one is what the user's real sessions do, the other is what hard coding fixtures
do to a local model under repetition. Every figure above is reported per-corpus
for that reason, and a pooled number would be the third instrument defect in
three days.

## Verification

```bash
python3 tool/triage_session_logs.py --dir build/integration_test_reports --top 3
```

```bash
python3 tool/triage_session_logs.py --top 3
```
