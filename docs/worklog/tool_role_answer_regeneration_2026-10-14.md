# Tool-Role Answer Regeneration: Frequency, Cost, and Quality (2026-10-14)

## Question

When the tool loop's follow-up request returns a complete answer
(`finishReason: stop`, visible content, no tool calls), the turn discards it
and regenerates the final answer from a user-role re-send built by
`ToolResultPromptBuilder.buildAnswerPrompt` (label `tool-result final answer`
since `fe107074e`). An earlier note put this at 5 occurrences corpus-wide and
left it unchanged for lack of evidence. LL43 then showed the re-send breaking
the loop's prompt cache (session `b053bddd`): it has a different system prompt
and no tools, so it prefills from zero.

## Frequency and cost

Grounded logs under `~/.caverno/session_logs`, personal-eval replays excluded.
An occurrence is a `streamChatCompletionWithToolResults` entry with
`finishReason: stop`, non-empty post-`<think>` content and no tool calls,
followed by a tool-less `streamChatCompletion` /
`streamChatCompletionWithStructuredToolResults` request.

| Measure | Value |
|---|---|
| Regenerations | 391 in 123 sessions (382 coding, 9 chat) |
| By month | 90 in September, 301 in October |
| Wall clock | 4.9 h total, median 42.3 s each |
| Prompt size | median 17.9k tokens, prefilled without the loop's cache |
| Re-sends carrying completion-blocker instructions | 43 (11%) |

## Quality: 20 random pairs (seed 20261014)

| Verdict | Count | Pairs |
|---|---|---|
| Regeneration better | 3 | #5, #7, #11 |
| Discarded answer better | 0 | |
| Equivalent (regeneration longer, same facts) | 17 | the rest |

- #7 and #11: the discarded answer claimed `PROJECT_TASK_READY_FOR_REVIEW`
  while a `coding_output_feedback` Error (a traceback in a dry-run output) was
  unresolved; the regeneration reported the Error and withheld the marker.
  The re-send states completion blockers the tool-role turn did not see
  (`completionBlockerInstructions`), so here it works as a completion gate.
- #5: the discarded answer omitted the required
  `PROJECT_TASK_READY_FOR_REVIEW` line; the regeneration kept it.
- The regeneration was on average about 1.3x longer and never dropped a fact
  in the sample.

The earlier tally (3 discarded-better, 1 regeneration-better, 2 neutral) came
from hand-picked sessions; the random sample does not reproduce it.

## Conclusion

Accepting the tool-role answer unconditionally would lose the completion-gate
effect seen in 3 of 20 pairs. The 89% of re-sends that carry no blocker
instructions are where the cost is paid for a rephrase. Two candidate changes,
neither implemented:

1. Skip the regeneration when `completionBlockerInstructions` is empty and the
   turn has no required completion marker, accepting the tool-role answer.
   Saves most of the 4.9 h; needs a guard for the #5 pattern (missing marker).
2. Keep the regeneration but make it prefix-stable (same system prompt and
   tool catalog as the loop, instruction appended), so the 17.9k-token prompt
   is served from cache. Lower quality risk, smaller saving (prefill only),
   and tools in the request may invite another tool call.

Both change a deliberate design and need a user decision.
