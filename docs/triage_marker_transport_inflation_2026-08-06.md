# Triage Marker Inflation (2026-08-06)

Question this answers: **the triage tool ranks one session at score 99.25, more
than twice the runner-up, on 37 transport errors. What broke in it?**

Nothing. All 37 were shadow-mode marker records, and the session had zero
transport errors. The instrument that decides what to investigate next was
ranking sessions by how much instrumentation they emitted.

## How it surfaced

Deciding the next milestone meant reading the triage ranking, and the top row's
shape was wrong: 37 transport errors across 80 entries, on a coding canary that
the LL34 note records as having **passed in 130 s**. A run that half-failed its
requests does not pass in 130 s.

Counting operations in that file settles it:

```
execution_shadow                    37     ← the 37 "transport errors"
createChatCompletion                20
createChatCompletionWithToolResults 17
streamChatCompletionWithTools        3
streamChatCompletion                 2
turn_exit                            1
```

## Cause

`LlmSessionLogStore` writes two kinds of entry. `record()` logs an LLM call and
always carries a `request` block. The marker writers — `recordTurnExit`,
`recordGoalAutoContinue`, `recordGoalCompletionShadow`, `recordExecutionShadow`
— carry neither `request` nor `response`, by design.

`analyze()` skipped markers with an **allowlist of two operations**
(`turn_exit`, `goal_auto_continue`). Everything else fell through to
`_is_transport_error`, whose test is "no `finishReason`, no content, no tool
calls" — true of every marker record ever written. The two markers added to the
app after this tool learned its two were therefore scored as aborted requests,
at the second-heaviest weight in the score (`WEIGHT_TRANSPORT = 2.5`).

The failure is the allowlist, not the two markers. An instrument that enumerates
what to ignore silently breaks every time the thing it measures grows.

## The measurement

Over the 173 grounded logs in `~/.caverno/session_logs`:

| | Entries |
|---|---:|
| Reported as transport errors | 316 |
| …that were `execution_shadow` markers | **275** |
| …that were `goal_completion_shadow` markers | **7** |
| **Real transport errors** | **34** (10.8%) |

**89.2% of the signal was the instrument measuring itself.** The 34 real ones
appear in 22 sessions.

Every other signal is unaffected, verified by running both versions over the
same corpus: `max_tool_run` 218 both, `fr_length` 5 both, `oversized` 2 both,
`tool_errors` 1438 both. Markers do reset the consecutive-tool-run counter, so
they *could* have masked tool loops, but measured across the corpus they never
fell between two identical calls. Only `transport` moved.

## What the ranking becomes

Four of the top five sessions change.

| Rank | Before | After |
|---:|---|---|
| 1 | `496ea473` — score **99.25**, txp 37 | `personal-eval-replay-case_49bb830e` — score 35.25, txp 9 |
| 2 | `76864d26` — 48.2 | `76864d26` — 25.7 |
| 3 | `934c6e48` — 48.15 | `9a56bc5b` — 18.25 |
| 4 | `9b3146ef` — 44.5 | `e865cb13` — 18.0 |
| 5 | `cae91d8a` — 42.0 | `beb92019` — 17.0 |

`496ea473` falls to **rank 29 of 173** at score 6.75. Ranks 1, 3, 4 and 5 were
all TODO-app coding canaries — the runs that emit the most `execution_shadow`
records — so the tool had inverted itself: **the better instrumented a run, the
more broken it looked.**

The session the ranking should have been pointing at was invisible. The new
top row is an LL19 personal-eval replay whose 9 errors are all one thing:

```
RequestTimeoutException: Request timed out after 600s (after 600s)
```

Not diagnosed here — it is from build `97d5d559` (2026-07-27), and 73046b91
has since bounded completions in the reasoning-fallback wrappers. It is
recorded as the first thing the corrected ranking surfaces.

## What was changed

1. `_is_completion_entry` replaces the operation allowlist with a structural
   test: an entry is scored only if it carries a `request` or a `response`.
   A marker type added later cannot leak into scoring through it. The two
   markers that own counters (`turn_exit`, `goal_auto_continue`) keep their
   explicit branches, because those read fields, not just skip.
2. The session title is now read from any entry, including markers, so the
   stricter skip cannot cost a session its name.
3. `test/python/triage_session_logs_test.py` — six cases, including an
   invented future marker operation and a marker-only log that must stay
   ungrounded and unscored. Verified against the negative control: the pre-fix
   tool scores the shadow-marker fixture at 3 transport errors / 7.5, the
   fixed one at 0 / 0.

Not changed: the score weights. The weighting was never the problem.

## Why this came before the milestone work

Three roadmap items (LL34 exit-status agreement, LL35 shadow sample, LL36
delete-by-measurement) are each explicitly gated on accumulating more real logs,
and all three read from this tool. The inflation source is LL34/LL35's own
shadow instrumentation, so it grows with exactly the runs those items are
waiting for — a corpus that gets more misleading the more evidence it collects.

This is the second instrument defect in two days
(`docs/session_log_corpus_contamination_2026-08-05.md` was the first), and both
have the same shape: a filter written against the corpus as it was, silently
outgrown. The grounding filter prints how many files it skipped for that reason.

## Verification

```bash
python3 test/python/triage_session_logs_test.py
```

```bash
python3 tool/triage_session_logs.py --top 8
```
