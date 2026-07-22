# Session f2a25c20: three of today's mechanisms fire live, in one struggling run that converged (2026-07-22)

Log: `~/.caverno/session_logs/coding/f2a25c20-8560-4019-b4b4-cc34cb745cb9.jsonl`

## Provenance, checked first

`build.commit 11980f89`, `dirty: false`, built `08:39:28Z` = 17:39:28 JST — the
same binary as `d66c4261`, containing every fix from this session. The session
ran 18:45:07 – 19:08:21 JST: **23 minutes, 94 records, 5 turns**, against the
same CMVP-1 fixture directory. Where `d66c4261` was a 5-minute clean pass, this
one is the hard case.

## Headline: the previous log's open item is closed

`docs/session_d66c4261_cadence_now_legible_2026-07-22.md` closed with "the
branch the fix added still has not fired in production". It fired in the very
next session.

Turn gen-9, 18:50:50:

```
AUTO_CONTINUE continue  turn=3/10  streak=1
  reason: verification has not caught up with the latest change
  cadence=required  mut=4  ver=-1
```

That reason string is **exclusive to the cadence path**. In
`conversation_goal_auto_continue_policy.dart` it is the third arm of a chain
reached only when `input.validationOutstanding` is true, and the two earlier
arms (`hasPendingExecutionVerification`, `requiresValidationContinuation`) are
false. With `requiresValidationContinuation` false, the only remaining source
of `validationOutstanding` is `verificationCadence == VerificationCadence.required`
— the clause added in `a2c1d0c5`.

So the fix diagnosed from session `2659093b`, instrumented after `cfaa8297`
could not explain itself, and confirmed correct-but-unexercised in `d66c4261`,
is now proven in production.

## Two more first firings in the same log

**LL36's closed blind spot.** Turn gen-9's `turn_exit` carries
`transforms: ['coding_continuation_recovery_prose_only_coding_continuation']`.
That label was added 2026-07-21 because the coding-continuation recovery
changed the on-screen answer while recording nothing, making the whole
subsystem invisible to triage. It is now producing countable records — the
first observed firing.

**LL35's structured self-report with acknowledgement.** The model called
`update_goal {"completed": true}` and received:

> Completion accepted: no mechanical evidence contradicts it. It has not been
> independently verified, so state plainly what you did and what remains
> unchecked.

This is `GoalUpdateAckResolver` doing exactly what it was built for: accepting
the claim because nothing contradicts it, while refusing to dress that up as
verification. The hedge is the feature.

## The run: a struggle that converged

| Turn | Exit reason | Transform | Auto-continue | cadence / mut / ver |
|---|---|---|---|---|
| gen-8 | text_response | `unexecuted_command_action_notice` | continue — validate file changes | required 4 / -1 |
| gen-9 | text_response | `coding_continuation_recovery_prose_only…` | continue — **cadence** | required 4 / -1 |
| gen-10 | pending_batch_executed | — | continue — retry unexecuted validation | required 14 / -1 |
| gen-11 | text_response | `unexecuted_command_action_notice` | continue — incomplete evidence | notDue 14 / 14 |
| gen-12 | text_response | — | **skip** — no incomplete evidence | notDue 20 / 20 |

Five of a ten-turn budget. `unresolvedErrorCount` sat at 5 for three turns then
went to 0. The final commands — including the edge cases (`done 99` on an
unknown ID, an empty list, a fresh state file) — all exited 0.

This is the auto-continue value proposition demonstrated on a run that needed
it: a turn that stopped mid-work was restarted four times and finished.

## Measured friction

39 distinct tool results, seven tools. **History replay inflated the raw
message slots 13.2x (303 → 23 distinct)** — a grep-based count of this log
would have been off by an order of magnitude.

| Signal | Count |
|---|---|
| `edit_file` anchor misses | **6 of 9 (67%)** |
| … absent entirely | 4 |
| … first line matches, block drifted | 2 |
| `local_execute_command` non-zero exits | 8 of 17 (exit 2 ×4, 254 ×2, 1 ×2) |

The two `exit 254` calls are the model running `bin/todo.dart` and then
`lib/todo.dart` before settling on the latter, alongside a `--state-file` vs
`--file` flag flip-flop. Same family as the package-name flip-flop recorded in
the CMVP-1 notes: early, self-corrected, but it costs turns.

The 67% anchor-miss rate is high, and four of the six were text **absent
entirely** — the model quoting an anchor the file never contained. That is
model fidelity (LL3), not something the edit tool can repair; noted as a
measurement, not a fix proposal.

## A trap avoided

Three commands appeared twice in the transcript, one copy each carrying an
empty `reason` — which looks exactly like the failure-dedup key (which strips
`reason`) failing to suppress a repeat.

It is not. The empty-reason copy of `dart analyze lib/todo.dart` carries a
**byte-identical result hash** to the earlier one; it is the prompt builder
re-rendering history with the reason stripped, not a second execution. The one
genuine repeat of that command went `exit 2` → `exit 0`: a legitimate
verify-after-fix.

Recorded because the false version of this claim was one query away, and the
tell was cheap — hash the result, not the arguments.

## Bottom line

One session, three mechanisms confirmed live: the cadence continuation, the
LL36 recovery label, and the LL35 completion ack. Nothing here needs a fix. The
open measurement is the edit-anchor miss rate, which belongs to LL3.
