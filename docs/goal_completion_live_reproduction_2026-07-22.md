# A goal that could not end, measured and then closed (2026-07-22)

Three CMVP-1 runs against the real LAN model (`qwen3.6-27b-vision`, llama.cpp
on 192.168.100.241:1234 via a loopback relay). Runs 1 and 2 reproduce the
reported symptom on a build that already contained the goal-completion fixes.
Run 3 adds the completion elicitation and the goal closes on its own.

## Result

| | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| `update_goal` offered | **no** | yes | yes |
| Completion elicitation | — | — | **yes** |
| `update_goal` called | 0 | **0** | **1** |
| Turns | 1 | 1 | 2 |
| Auto-continue | skip — "no incomplete evidence" | skip — same | skip, then elicit |
| **Final goal status** | **active** | **active** | **completed** |
| Canary verdict | green | green | green |

In every run the model wrote `bin/todo_cli.dart`, ran the fixture verifier, and
finished cleanly; the harness concluded mechanically that nothing was
incomplete. In runs 1 and 2 the goal stayed active anyway — the reported
symptom, on the fixed build.

Runs 1 and 2 are the negative control by construction: same fixture, same
model, same prompt, and they predate the elicitation. Run 3 differs by nothing
else.

## Run 1 nearly produced a false finding

Run 1's tool definitions were
`[list_directory, read_file, write_file, edit_file, delete_file, local_execute_command]`
— **no `update_goal`**. Read alone, run 1 says "the model does not call the
tool." It could not: the fixture never offered it, while production does
(session `f2a25c20` shows the model calling it). Same class as the canary
blindness recorded earlier — check what the harness actually offered before
reading anything into a green run. Run 2 exists because of that check, and the
fixture now offers the production definition.

## What runs 1–2 settled

The hypothesis the earlier fix rested on — "ground the ack in real evidence,
the model gets an honest rejection, and it re-claims once the gaps close" — was
**refuted**: there is no re-claim because there is no claim.

| Context | Calls `update_goal`? |
|---|---|
| Goal objective explicitly says to call it (`coding_goal_live_llm_canary`) | yes |
| Real coding task, tool offered, no instruction (`f2a25c20`) | once, at turn 1 of 5, while five errors were unresolved |
| Real coding task, tool offered, no instruction (CMVP-1 run 2) | **no** |

Read together these say the model *can* use the tool and does not *volunteer*
it. The missing ingredient is the instruction, not the capability — which is
what run 3 exploits.

## Run 3: asked directly, the model answers

```
[GoalAutoContinue] skip: no incomplete evidence
[GoalAutoContinue] eliciting a goal completion report
[Tool] Tool definitions: [update_goal]
[Tool] Executing tool: update_goal
Completion accepted: no mechanical evidence contradicts it...
[GoalAutoContinue] skip: goal is not active
[CanaryMeasure] final goal status=completed turnsUsed=2
```

One extra turn, on the warm prefix, once per dry episode, restricted to the one
tool that can answer. No user interaction.

`awaitingConfirmation` never fired, which is its intended role: the fallback
for a model that ignores the elicitation too, a goal with auto-continue off,
and a run that mutated nothing (never asked, by design).

## Why the harness still does not decide for itself

"No incomplete evidence" is not "done". A turn that did nothing also leaves
nothing incomplete, so the harness cannot promote its own silence into a
completion. It can only ask — the model first, and failing that, say what it
knows and leave the goal visibly unresolved.

## What the earlier fixes were worth

Narrower than claimed when they landed, but load-bearing here:

- The goal can complete without completion prose, which was structurally
  impossible before. Run 3 depends on it entirely.
- The ack no longer resolves a mid-turn claim against the *previous* turn's
  evidence.
- Two defects found while reviewing the fix: a rejected claim leaked through as
  a completion, and the evidence bar was weak enough to let a model end a run
  right after an unverified edit.

## Reproducing

```bash
python3 <relay>   # 127.0.0.1:11234 -> 192.168.100.241:1234, no idle timeout
export CAVERNO_CODING_TODO_APP_MVP_LIVE_CANARY=1 \
       CAVERNO_LLM_BASE_URL=http://127.0.0.1:11234/v1 \
       CAVERNO_LLM_API_KEY=no-key \
       CAVERNO_LLM_MODEL=qwen3.6-27b-vision \
       CAVERNO_CODING_GOAL_TODO_SESSION_LOG_ROOT=<dir> \
       CAVERNO_CODING_GOAL_TODO_WORK_ROOT=<dir>
fvm flutter test tool/canaries/coding_goal_auto_continue_todo_fixture_live_canary_test.dart \
  --plain-name "assembles the todo_app.md MVP"
```

The relay needs `settimeout(None)` after connecting: `create_connection`'s
timeout applies to every later `recv`, so a model thinking for more than 30
seconds looks like a dropped connection. The first attempt failed that way and
would have been misread as a Caverno transport error.

The scenario prints `[CanaryMeasure] final goal status=…` and deliberately does
not assert completion — runs 1 and 2 are exactly why that assertion would be
wrong to add.
