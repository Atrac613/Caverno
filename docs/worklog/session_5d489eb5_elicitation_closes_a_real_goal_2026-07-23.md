# Session 5d489eb5: the elicitation closes a real goal in production (2026-07-23)

Log: `~/.caverno/session_logs/coding/5d489eb5-0a95-4f0c-b756-258c0316daa6.jsonl`
Build `548ee823`, dirty `false`. 36 records, **9 minutes, 3 turns**.

## Provenance, and a correction

`548ee823` is not an ancestor of the feature branch, which at first read
suggested a build without the goal work. It is the **squash merge of that
branch into main**, so ancestry cannot answer the question — content can.
Checked by symbol, the build carries `offersCommandExecution`,
`completionElicitationMutationGeneration`, `_activeAllowedToolNames` and
`awaitingConfirmation`, and `git diff main HEAD -- lib test` is empty.

Worth remembering: **after a squash merge, `--is-ancestor` reports "missing"
for changes that are present.** Verify a build by content, not by ancestry.

This is therefore the first production session on a build carrying the
self-defeat fix.

## The trace

```
gen-5  transforms=['unexecuted_command_action_notice']
       continue  incomplete evidence remains        mut=0  ver=-1
gen-6  transforms=['coding_continuation_recovery_prose_only_coding_continuation']
       skip      no incomplete evidence             mut=5  ver=5
gen-7  tools=['update_goal']          <- elicitation
       transforms=None                <- the fix holding
       *** shadow: tool_accepted_lexical_missed (completionRecorded)
       (no auto-continue record: the goal is no longer active)
```

The model's call:

```json
{"completed": true,
 "message": "MVP実装完了。add/list/done/delete/helpの全コマンドとJSON永続化を実装し、
             独立したプロセス実行でAcceptance Criteriaの全7項目を検証済み。"}
```

Ack: *Completion accepted: no mechanical evidence contradicts it…*

## The A/B against the broken build

Same fixture family, same model, one commit apart:

| | 76864d26 (before) | 5d489eb5 (after) |
|---|---|---|
| elicitation turn transforms | `unexecuted_command_action_notice` | **none** |
| after the accepted claim | `continue` — "incomplete evidence remains" | goal closed |
| turns / duration | 6 / 28.5 min | **3 / 9 min** |
| outcome | `no_progress_stop` | **completed** |

The elicitation turn is restricted to `update_goal` and therefore cannot run
commands. Before the fix its narration was faulted as an unexecuted claim, and
the resulting incomplete evidence overruled the completion the same turn had
just recorded. `offersCommandExecution` removes exactly that verdict, and the
turn now carries no transform at all.

## The LL35 shadow tally

Six sessions have now produced records:

| Label | Count |
|---|--:|
| `goal_completion_lexical_only` | 4 |
| `goal_completion_tool_accepted_lexical_missed` | 3 |

Both directions are live, which already answers one question: **the lexical
path cannot be removed yet.** Four completions were caught by prose alone with
no accepted tool claim behind them; deleting that path today would strand them.
The three in the other column are the case the tool exists for — including this
session, where the lexical inference missed a completion the model reported
explicitly and in detail.

The gate that could never open now has data on both sides of it. What it needs
before a removal decision is enough volume to say whether the four
`lexical_only` firings survive once the elicitation is routinely closing goals —
they may simply be turns that would now be settled by the tool instead.
