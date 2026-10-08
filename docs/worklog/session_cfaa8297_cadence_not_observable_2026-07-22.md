# Session cfaa8297: the cadence fix did not fire, and the log cannot say why (2026-07-22)

Log: `~/.caverno/session_logs/coding/cfaa8297-2d7e-41d9-a5ca-9f8e7fa399d6.jsonl`

First production run on a build containing the auto-continue cadence fix
(`a2c1d0c5`). The fix did **not** take effect, and the reason is not
determinable from the log — because the value it depends on was never logged.

## Provenance, checked first

`build.commit ea06c0af`, `dirty: false`, built `06:43:45Z` = **15:43:45 JST**.
The fix `a2c1d0c5` was committed at 15:19:19 JST and `ea06c0af` at 15:20:57, so
the binary contains it (`git merge-base --is-ancestor a2c1d0c5 ea06c0af` passes).
The session ran 15:45:06 – 15:50:57 JST, two minutes after the build.

## The session itself went well

Same prompt as `2659093b` ("todo_app.md を参考にしてMVPを実装。言語はdartとする。"),
but this time the model **did** verify behaviourally:

```
dart bin/todo.dart add "Buy milk" && dart bin/todo.dart add "Walk d…
dart bin/todo.dart done 1 && dart bin/todo.dart list      ← separate process runs
```

That is the `todo_app.md` acceptance criterion the previous session promised and
skipped. A `dart_test_verification_evidence` record was also produced with
`trigger: completionClaim`. Turn 1 ended with an `unexecuted_command_action_notice`
transform and auto-continue **continued** on "claimed file or command actions
were not executed" — the existing evidence path working as intended.

## What did not work

Ordered record trace (times JST):

| # | time | record | state |
|---|---|---|---|
| 3 | 15:46:11 | `turn_exit` gen-5 | transforms: `unexecuted_command_action_notice` |
| 4 | 15:46:11 | `goal_auto_continue` | **continue** — "incomplete evidence remains" |
| 11–21 | 15:48–15:50 | requests | mutation generation climbs 1 → 5, **cadence `required`** |
| 22 | 15:50:36 | final answer | mut=5, ver=-1, **cadence `required`** |
| 23 | 15:50:37 | `turn_exit` gen-6 | no transforms |
| 24 | 15:50:37 | `goal_auto_continue` | **skip — "no incomplete evidence"** |

One second before the skip the harness's own snapshot said `Verification
cadence: required`, with verification generation still `-1` after five
mutations. With the fix in place, `validationOutstanding` should have been true
and that skip should not have happened.

## Why I cannot say more

`'no incomplete evidence'` is produced by exactly one gate — the one the fix
modified — so it was reached with both conditions true, meaning the policy
received a cadence other than `required`. Whether that came from
`_currentVerificationCadence()` reading a different conversation, from
`ExecutionSnapshotProjector.project()` taking its `!hasWorkflowContext` early
return (which yields the default `notDue`), or from something else **is not
recoverable from this log**: the `goal_auto_continue` record logs the evidence
fields but not the cadence, the mutation generation, or the verification
generation.

That is my own instrumentation gap. I added the cadence to the policy without
adding it to the record that exists to explain the policy's decisions.

## An extraction trap worth recording

My first pass read the cadence as `notDue` throughout and concluded the fix
correctly stayed silent. That was wrong. **Each request carries two execution
snapshots**: the live one, and a stale copy embedded in the replayed
continuation message from the previous turn ("The previous answer claimed file
or command actions…"). Taking the *last* match in the message list picks the
stale one, which still read `mut=0 / notDue`. Take the *first*, or scope to the
live system prompt.

This is the same class of error as the earlier grep contamination: the log
contains replayed copies of its own earlier content, and naive matching finds
them.

## Next step

`tool/analyze_deferred_verification.py`-style reasoning cannot settle this;
only the missing field can. The auto-continue record now logs
`verificationCadence`, `mutationGeneration` and `verificationGeneration`
alongside the evidence, so the next occurrence states directly what the policy
saw. **Do not attempt a second fix before that data exists** — the first fix was
written from a correct diagnosis and still did not fire, which is precisely the
situation where guessing again is most tempting and least warranted.
