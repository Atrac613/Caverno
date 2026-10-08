# Live Canaries Did Not Exercise the Grounded-Verification Changes — and the Fix (2026-07-21)

Question this answers: **the LL34/LL35 changes were run through three live LLM
canaries and all passed — does that verify the new behavior?**

No. Reading the canary harnesses showed all three passes exercised only the
*old* code paths — a regression gate, not verification. Two new canaries were
then written and verified live the same day (see "Closed the same day"). The
original finding is kept in full so "all canaries passed" is never again read as
"the changes were verified live" without first checking what the harness can
structurally reach.

## Run provenance

- Branch `feature/ll36-guard-terminal-state` at `9c4ed7a3` (includes all of
  main's LL34/LL35 plus the LL36 additions).
- Endpoint: LAN llama.cpp `192.168.100.241:1234`, model
  `qwen3.6-35b-a3b-vision`, reached through a 127.0.0.1:18234 loopback relay
  (macOS Local Network Privacy blocks flutter_tester from the LAN IP directly —
  see `caverno-lan-canary-local-network-privacy`).
- Reports under `build/integration_test_reports/coding_{goal_live_llm,overwrite_transparency,output_feedback}_live_canary_*`.

## What each canary actually exercised

| Session change | Canary | New code exercised? | Why |
|---|---|:--:|---|
| LL35 `update_goal` tool + ack | coding goal | **No** | `_NoToolsMcpToolService.getOpenAiToolDefinitions()` returns `const []` (test line 529, 765). The model is offered **no tools**, so `update_goal` can never be called. Only the lexical `ConversationGoalProgressInference` path runs. |
| LL35 shadow comparison (tool side) | coding goal | **No** | With no tool call possible, `_shadowGoalToolCompletionOutcome` is always null. `recordGoalCompletionShadow` runs at turn end but can only ever record `goal_completion_lexical_only`, and the test reporter does not capture transforms anyway. |
| LL34 `ToolFailureClassifier` reads `outcome` | output feedback | **No** | The canary's `_toolResult` builds `McpToolResult` with no `outcome` field (test line 815). With `outcome == null`, the classifier takes its payload-parsing **fallback** — the old path. Same verdict, so the test cannot tell the two apart. |
| LL34 `write_file` UNCHANGED note | overwrite transparency | **No** | The canary writes **new** content, so `changed: true` and the note reads "updated or overwrote". The modified branch (`changed: false` → "UNCHANGED") is never reached. |
| LL36 coding-continuation recovery label | — | — | Not covered by any canary. |
| LL36 validation-success grounding | — | inert | `validationExitCode` defaults null (nothing wires it yet), so there is no live-observable behavior to test. |

## Why this is structural, not incidental

The canaries were written before the grounded-verification work and use
deliberately stripped harnesses:

- Goal canaries strip **all** tools to isolate the completion inference. That
  isolation is exactly what makes them blind to a completion **tool**.
- The tool-bearing canaries hand-roll `executeTool` / `_toolResult` and do not
  attach the LL34 `outcome` envelope, because the envelope did not exist when
  they were written. Every consumer therefore falls through to its lexical
  fallback.

Running these same canaries again cannot close the gap; the harnesses cannot
reach the new code.

## Closed the same day

Two canaries were added (`082855e0`) and verified live against
`qwen3.6-35b-a3b-vision`:

| Gap | Canary | Live evidence |
|-----|--------|---------------|
| LL35 tool path | `coding_goal_live_llm_canary_test.dart` — "reports goal completion through the update_goal tool" | The model called `update_goal` and paraphrased the resolver's ack back, including its deliberate hedge that the completion "has not been independently verified". Only `GoalUpdateAckResolver` produces that wording, so the whole round trip fired — and the ack's careful phrasing survives all the way to the user. |
| LL34 UNCHANGED note | `coding_overwrite_transparency_live_canary_test.dart` — "is told a byte-identical write changed nothing" | The byte-identical write produced `changed: false` and the model quoted the operation note "the file is UNCHANGED". Producer and consumer both confirmed on the branch that targets the measured re-read loop. |

Reaching the goal-tool path needed two harness changes, both of which were
independently blocking: the tool service had to offer `update_goal`, **and**
`mcpEnabled` had to be true (it was false, so no catalog was sent at all).

**The LL34 consumer path (classifier reading `outcome`) was deliberately not
given a live canary.** Which branch fired is a unit-level distinction: with a
realistic payload the `outcome` path and the payload fallback return the same
verdict, so a live run cannot separate them. It is fixed instead by the unit
test `outcome overrides a payload that disagrees with it`, which constructs the
discriminating case a live run cannot.

### Three runs, three lessons about canary design

The write canary failed twice before passing, and **both failures were test
flaws, not product faults** — the `changed` fact was correct in every run:

1. Asserting the file still equalled the original fixture ignored that the
   model's first write-back legitimately drops the fixture's trailing newline —
   a real change, correctly reported as `changed: true`.
2. With that newline present, the model's write-back always differs by one
   byte, so `changed: false` was reached only if the model happened to write a
   second time. The test depended on model whim rather than on the behavior
   under test.
3. Reseeding with short, newline-free content makes the first write-back
   byte-identical by construction, which is what made the run deterministic.

The general lesson matches the rest of this work: a canary that cannot
*reliably reach* the branch under test proves nothing about it, whether it
passes or fails.

## What real live verification required

New or modified canaries:

1. **LL35 tool path** — a coding-goal harness that offers `update_goal`, prompts
   toward completion, and asserts (a) the model calls `update_goal`, (b) the ack
   distinguishes recorded from rejected against the run's completion evidence,
   (c) a `goal_completion_*` transform is recorded when the tool and lexical
   paths disagree. Assert the transform via the session log, not the test
   reporter.
2. **LL34 consumer path** — route tool results through the production
   `McpToolResultNormalizer` / built-in handlers so `McpToolResult.outcome` is
   populated, then assert the classifier decided from `outcome`, not the payload
   fallback (e.g. a command whose prose and exit code disagree).
3. **LL34 UNCHANGED note** — a byte-identical `write_file`, asserting the model
   is told the file is UNCHANGED and does **not** re-read it. This is the exact
   edit→re-read loop the `changed` fact targets, and no canary covers it.

## Standing note

This is the same distinction the whole session turned on: a green result proves
what it structurally can reach, not what you hoped it would. The first three
greens meant "the old paths did not regress" — established by reading the
harnesses, not by trusting the colour. Verifying the changes took canaries
built to reach them, and then the failures were informative: twice the product
was right and the test was wrong.
