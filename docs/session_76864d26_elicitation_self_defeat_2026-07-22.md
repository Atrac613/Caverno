# Session 76864d26: the elicitation fired, and the harness overruled it (2026-07-22)

Log: `~/.caverno/session_logs/coding/76864d26-8fd5-4f32-a9f9-af07948b5437.jsonl`
Build `d95a1e3d`, dirty `false` — the first production session carrying the
completion elicitation. 139 records, 28.5 minutes, 6 turns.

## Two firsts worth recording

**The LL35 shadow instrument produced data.** Two `goal_completion_shadow`
records, both `goal_completion_tool_accepted_lexical_missed` — the tool
accepted a completion the lexical path did not see. That label was
*structurally unrecordable* until today (it was added to a transform set after
the `turn_exit` entry was already written), which is why the gate on removing
the lexical path never accumulated evidence. It accumulates now.

**The elicitation fired in production.** Turn gen-7 skipped on "no incomplete
evidence"; gen-8 arrived 49 seconds later restricted to `tools=['update_goal']`
with the elicitation prompt, and the model called the tool. Everything up to
that point worked.

## And then the harness overruled itself

```
gen-7  skip     no incomplete evidence          mut=15 ver=15
gen-8  *** shadow: tool_accepted_lexical_missed (completionRecorded)
       transforms=['unexecuted_command_action_notice']
       continue  incomplete evidence remains
gen-9  skip     no incomplete evidence          mut=18 ver=18
gen-10 *** shadow: tool_accepted_lexical_missed (completionRecorded)
       transforms=['unexecuted_command_action_notice']
       no_progress_stop  no measurable progress
```

The elicitation turn is restricted to `update_goal`, so it **cannot run
commands**. The model narrated a verification anyway, the unexecuted-action
guard faulted the claim, `hasUnexecutedActionClaim` made the evidence
incomplete — and the incomplete-evidence gate then blocked the completion the
same turn had just recorded.

The harness withheld the command tools and then penalised the model for not
using them.

Its whole visible answer became the notice; message content for gen-8 is 227
characters and is nothing but:

> The requested command was not executed because no matching successful
> command-execution tool result is available for that claimed action.

## The loop that followed

The one-shot guard reset on *any* continuation. The elicitation turn's own
answer produced the evidence that caused the continuation, which cleared the
guard, which let the elicitation fire again at gen-10. Six turns, 28 minutes,
no completion, terminated by `no_progress_stop`.

Both defects are mine, from earlier the same day, and neither showed up in the
CMVP-1 live run that verified the feature — there the elicitation turn's answer
happened to be clean.

## Fixes

**`ToolCallExecutionPolicy.offersCommandExecution(allowedToolNames)`.** A claim
is unexecutable rather than unexecuted when the turn was never given a tool
that could run it, and the guard now returns null in that case. Deliberately
narrow: a validation-only continuation is restricted *to* the command tools, so
its claims keep being faulted; a repair-only continuation, like the
elicitation, is not.

**The re-ask is tied to progress, not to continuations.** The tracker now
records the mutation generation at which an elicitation was spent, and asks
again only once work has advanced past it. A turn whose only effect was the
elicitation cannot buy another elicitation.

## What this says about the method

The feature was verified live before shipping, on the same fixture, and still
carried two defects that only production surfaced. The live canary answered
"does this work when the model behaves as expected"; it could not answer "what
happens when the model narrates work it was not allowed to do". Worth
remembering the next time a green live run reads as proof.
