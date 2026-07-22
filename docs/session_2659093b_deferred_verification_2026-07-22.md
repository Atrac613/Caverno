# Session 2659093b: A Turn Ended on an Unkept Verification Promise (2026-07-22)

Log: `~/.caverno/session_logs/coding/2659093b-6281-497a-b77f-5c85fc31ba86.jsonl`

First real coding session on a build containing the whole grounded-verification
track, so it doubles as production evidence for LL34/LL35 and as a fresh
observation about deferred execution.

## Provenance

`build.commit 5c70cf97`, `dirty: false` — includes LL34, LL35, LL36 slice 1 and
the new live canaries. 20 records, ~6 minutes (14:35:43 → 14:41:44),
`workspaceMode: coding`. Task: implement a Dart CLI TODO MVP from
`todo_app.md` in the CMVP-1 fixture tree (`tmp/MVP/todo/run9`).

## LL34 behaved correctly in production

The command sequence is a clean demonstration of the structured outcome:

| # | Command | `exit_code` | Note |
|---|---------|------------:|------|
| 1 | `dart create --type=cli-app .` | **absent** | Blocked by a preflight guard (`dart_create_unsupported_option`) — the process never ran |
| 2 | `dart create --template cli-app .` | 64 | Invalid template value |
| 3 | `dart create --template cli .` | 73 | Directory already exists |
| 4 | `dart create --template cli --force .` | 0 | Succeeded |
| 5 | `dart analyze bin/todo.dart` | 0 | `No issues found!` |

**The absent exit code on #1 is the invariant working.** A guard-blocked command
never reached an exit, so no `exit_code` is reported, so `ToolOutcome` is null
and `ToolFailureClassifier` treats it as an execution failure rather than an
actionable command failure. That is exactly the distinction the type encodes,
confirmed on real data rather than a fixture.

`write_file` reported `changed: true` (4586 bytes) and the operation note read
"updated or overwrote an existing file" — the `changed: false` UNCHANGED branch
was not reached here.

Also healthy: three consecutive command failures (guard, 64, 73) did **not**
abort the tool loop; the model recovered and completed. The LL29
"degrade, don't abort" concern did not manifest.

## The finding: verification was announced, then never ran

The last two assistant messages:

> 静的解析は問題なし。次に受け入れ基準をすべてテストします。

> …**次のステップとして、実際にコマンドを実行して動作確認(検証)を行います。**

The turn then ended. **No command was ever run against the built app.** The only
execution was `dart analyze` — static analysis, not the runtime behaviour the
model said it would check.

Nothing caught it:

- `turn_exit` carries **no `transforms` at all** — not one guard fired.
- `goal_auto_continue` decided **`skip: "no incomplete evidence"`**, so the
  harness did not continue.
- `execution_shadow` simultaneously reports `taskStatus: inProgress`,
  `completedTaskCount: 0 / totalTaskCount: 1`.

So the task is recorded as unfinished while the continuation policy concluded
there was nothing left to continue, and the turn stopped on an unkept promise.

### Why each check missed it

The auto-continue evidence explains itself:

| Signal | Value | Why it missed |
|--------|-------|---------------|
| `mutatedWithoutExecution` | `false` | A command (`dart analyze`) ran after the write. **This is deliberate, not a miss** — see the correction below |
| `unresolvedErrorCount` | `0` | Analyze was clean |
| `hasUnexecutedActionClaim` | `false` | The claim guard did not read the promise as an unexecuted action |

And `StructuredCodingExecutionDeferralDetector` did not fire. Its Japanese
patterns (`実行計画`, `次の実装ステップ`, `確認事項`) are **heading-shaped** —
they expect a line that is essentially just the marker. The sentence here is
ordinary prose ("次のステップとして、〜を行います。"), so the non-match is the
detector working as designed. This is a coverage gap, not a defect.

## What this says about LL35

This is the first production instance of the case LL35 was designed around:

- `update_goal` **was** in the offered catalog (61 tools) — registration works
  in the real app.
- The model **did not call it**, even having finished the work it was going to
  claim. Local tool-call fidelity is exactly the bet LL35 identifies.
- The lexical path did not complete the goal either, so the two agreed
  (both silent) and no `goal_completion_*` shadow disagreement was recorded —
  correct behaviour for the shadow comparison.
- Net effect: **the goal stays open and nothing continues.**

That is precisely why LL35 carries a fourth mechanism — asking the user at
budget exhaustion — rather than assuming the tool will be called. This session
is a live example of the failure mode that rung exists to catch.

## Caveat

**n = 1.** This shows the deferral shape *can* pass every check on the current
build. It says nothing about frequency. Any claim about how often prose-form
deferral escapes detection has to be counted — with the record-parsing tools,
never grep (`caverno-tool-traffic-concentration`).

## Follow-up: done, and it argued against changing anything

The frequency measurement this section originally called for was run —
`docs/deferred_verification_frequency_2026-07-22.md`. It found the shape recurs
(5 confirmed cases) but at ~3-4% of a small, biased subset, and that widening
the deferral detector would pull in the legitimate recommendation/handoff class
(4 of 11 candidates). The second candidate this section proposed — splitting
analysis from execution — is withdrawn by the correction below.

## Correction (same day): analyze-as-verification is deliberate

This document first described `mutatedWithoutExecution: false` as a static check
"standing in for" behavioural verification, i.e. as a gap. That framing was
wrong, and reading the code settles it.

`_hasAnyExecutionVerification` (`tool_result_prompt_builder.dart`) counts a
`local_execute_command` whose `ToolCapabilityClassifier` command effect is
`verification`; `dart analyze` classifies that way. The signal's own notice text
is "a file was edited but **nothing was run or tested** in this turn", so it
means *did you check anything at all* — and analysis is a real check that
catches compile and type errors. The design is documented in place:

> Unlike the Dart analyzer (**a safe static re-run**) an arbitrary shell command
> may have side effects, so surface the gap as a caution instead of
> auto-running it.

So the harness behaved as designed at every step of this trace. Splitting
"analysis" from "execution" in that signal would flag legitimate
analysis-only turns (docs edits, config changes, a deliberate analyze pass) as
unverified — a regression whose cost is not paid for by the evidence gathered
in `docs/deferred_verification_frequency_2026-07-22.md`.

**What remains is not a defect but a product question**: should auto-continue
recover only from *evidence of incompleteness* (what it does today, correctly),
or should it drive an incomplete task forward absent negative evidence? Here
auto-continue was enabled, the budget was untouched (turn 1 of 10), the task
stood at 0/1, and the evidence was clean — so it stopped. Which reading is
intended is a decision, not a bug fix.

That ambiguity is itself the argument for LL35: it only arises because
completion is *inferred*. Had the model called `update_goal` — or been asked via
the confirmation rung — the goal state would be explicit and no inference would
be needed. This trace is a live instance of the tool being offered and not
called, which is what the remaining LL35 slices (LL3 fidelity probe, user
confirmation) exist to handle.

## Second correction: there *was* a harness defect, and it is now fixed

The correction above concluded "no harness change is justified; what remains is
a product question". That was also wrong, and it was wrong because I had only
looked at the auto-continue evidence and never at what the harness itself was
saying about verification.

Checking `todo_app.md` — the spec the traced session was implementing — forced
the issue. It defines the completion bar explicitly:

- Acceptance criteria include "After completing/deleting, a *fresh process run*
  of `list` reflects the change — state survived process exit (**this is the
  criterion models miss**)".
- Its "Common failure modes" list opens with "**Completion claimed while
  broken**: model says the app is done **without ever running it**".

So `dart analyze` alone is precisely the failure this fixture exists to catch,
and not one acceptance criterion had been exercised. The task was not complete
by its own written definition — this is answerable against the spec, not a
matter of intent.

### What the harness actually knew

Tracing the execution snapshot across the turn's requests settles it:

| request | mutation gen | verification gen | cadence |
|---|---:|---:|---|
| 1–4 | 0 | -1 | `notDue` (nothing mutated yet — correct) |
| 6 | 1 | -1 | **`required`** |
| 9–14 | 2–3 | -1 | **`required`** |
| 15 (final answer) | 3 | **-1** | **`required`** |

`VerificationCadencePolicy` was right the whole time, and the verdict was in the
system prompt the model received. Verification never ran: the generation stayed
at -1 because `dart analyze` does not advance it.

Meanwhile `goal_auto_continue` skipped on "no incomplete evidence" — and
`ConversationGoalAutoContinuePolicy` had **no reference to the cadence at all**.

### The defect

"Verified" meant two different things in the same system:

| | Counts `dart analyze`? | Verdict here |
|---|---|---|
| `ToolResultCompletionEvidence` — did any verification-classified command run | **yes** | nothing incomplete |
| `VerificationCadencePolicy` — has verification caught up with the mutation | **no** | `required` |

Auto-continue consulted only the lenient one. That is the defect: not a wrong
classification, but an authoritative signal the continuation policy never read.

### The fix (`a2c1d0c5`)

Both notions now feed one `validationOutstanding` on the policy input, used for
the continuation gate **and** the miss counter — so the cadence path inherits
the existing escalation (continue once, then block) rather than continuing
unbounded. `due` stays advisory; only `required` forces a continuation. The call
site reuses `ExecutionSnapshotProjector`, which already computes the cadence for
the snapshot shown to the model, so the policy and the prompt cannot drift.

Five tests cover it, including the real regression shape and the escalation.

### Why this took three passes

1. "A static check stood in for behavioural verification" — wrong; that is
   deliberate, documented design.
2. "No harness change is justified; it is a product question" — wrong; I had
   not looked at the cadence, which was screaming `required`.
3. "Auto-continue never reads the cadence" — correct, and mechanical.

Both corrections came from being asked to check something specific rather than
reason further: whether a fix was truly unnecessary, and what the spec defined
as complete. Reading `todo_app.md` replaced my guess about intent with a written
standard, and reading the per-request snapshot replaced my assumption about what
the harness knew with what it actually recorded.
