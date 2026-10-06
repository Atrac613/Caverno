# Caverno v1.3.54

> Release date: 2026-09-26

## Summary

A reliability release for release turns: commit and tag guard blocks are now
declared as refusals instead of being filed as executed, a question pending at
the tool-loop limit reaches the user instead of being settled by the model, and
a streamed response that ends carrying nothing is re-sent once instead of being
read as a final answer.

## Changes

### Fixes

- **Declare commit and tag guard blocks as refusals** — The uninspected-commit
  guard reported its block as a success, so the tool loop filed the refused
  commit as executed; after the model ran `diff --cached` as instructed, the
  identical commit was skipped as a duplicate and the stale refusal replayed.
  Both guards now declare `ok: false` + `result_origin: refusal`, and the turn
  digest treats declared refusals, malformed origins and `executed: false` as
  never run instead of listing them as "ran".
- **Put a question pending at the loop limit to the user** — When the tool
  loop hit its iteration limit with `ask_user_question` pending, the
  exhaustion recovery prompt had the model settle the question itself. A
  pending user question now declines that recovery, so the pending batch runs
  before finalization and the question reaches the user. The pending-call
  facts are derived in `ToolLoopExhaustionDecisionInput.fromPendingCalls`.
- **Re-send a streamed response that ended carrying nothing** — A tool-loop
  follow-up closed with no content, finish reason or usage, and the loop read
  the silence as a final answer. Chat event streams that end without any
  output-bearing event are now re-sent once; events carrying nothing are held
  so a re-send never follows consumed output, and a stopped turn is never
  re-sent.

### Tooling

- **Add firing signatures for guard refusals and loop-limit questions** —
  `guard_refusal_not_executed` fires when a declared commit refusal is
  followed by the same commit running, and `loop_limit_question_to_user` fires
  when an `ask_user_question` is followed directly by the tool-less final
  answer with no loop-limit recovery prompt. The silent-stream re-send leaves
  no session-log trace; its evidence is the app log line "re-sending it once".

### Documentation

- **Add the refused-commit lesson to FOR_ME.md** — The refused-commit lesson
  is recorded in FOR_ME.md.

## Version

- `1.3.54+68` (proposed)