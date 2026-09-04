# Building the Anabasis orchestrator (2026-09-04)

One branch, squashed into main, so the reasoning that lived in thirty commit
messages lives here instead. `docs/roadmap.md` carries the milestone state and
the per-PR evidence; this is the narrative and the parts that do not belong to
any single milestone.

Anabasis entered the day as a design document and one canary failing by design.
It left as a parent you address with `@anabasis`, which holds a project's
understanding, refuses to edit, and delegates instead.

## What shipped

| Milestone | State |
| --- | --- |
| ANA0 Epistemic grounding | done — confirmation path, producer, parent authority, `@anabasis` entry, transcript header |
| ANA1 Decompose | done — precondition edges, derived readiness, producer, rendering |
| ANA2 Delegate | policies done and wired — candidates, premises, runner routing, contradiction policy |
| ANA3 Accept | PR 1 and 2a — derived levels, and what must hold before the parent may accept |

## Three decisions settled by measurement

The LAN endpoint became reachable from `dart` during this work (the Local
Network grant that had blocked it is resolved), which is why these are numbers
rather than arguments.

**Which channel the model writes a precondition edge through.** Three arms over
the production task prompt, `qwen3.8-27b-vision`, 36 requests plus a 12-request
pilot. A per-task `preconditions` array produced 1.06 edges per task against a
title marker's 0.64; every edge in both arms resolved to something the plan
contained; and the schema arm parsed 12 of 12, exactly like the others. **ANA0
PR 3b's reason for keeping its own marker out of the JSON schema — that a
growing schema costs weak local models their structured-output fidelity — does
not reproduce on this model.** The control wrote no edges but described the
ordering in prose in 6 of 12 responses: the model knows what depends on what
and spends that knowledge on text nothing can read when it has no channel.

**Whether the parent's prompt keeps it from editing.** Two arms, same request,
same four tools, scored off the tool call rather than the prose. 18 requests.

| arm | edited | delegated |
| --- | --- | --- |
| no parent block | 9/9 | 0/9 |
| parent block | 4/9 | 5/9 |

Necessary and not sufficient. Without the block the parent tries to edit every
turn and is refused every turn; without the guard the block leaks in nearly
half. "The prompt says not to, so it won't" is wrong four times in nine.

**What a refused parent does next.** Not measurable from a fixture, and
answered by a real session (`459bd75f`, build `7d362b177`): the parent called
`write_file`, read the refusal, and called `spawn_subagent` **in the same
request**. The child then edited, ran a command, listed a directory and edited
again. No repeat, so the refusal wording needs no work — and the tool loop's
two-strike abort never came into play.

## Two defects only the app found

Both while the full suite was green and the live measurements passed.

**The parent's role never reached the turn.** It was carried in a zone opened
around the turn, and `_runWithLlmSessionLogContextForGeneration` opens its own
zone defaulting to `ModelUsageRole.chat` — deliberately, so a secondary role
started mid-turn wins — and an inner zone beats an outer one. Two real turns
reached the model with `@anabasis` in the user message, a 29,784-character
system prompt, and none of the parent's instructions in it. The tool loop was
worse off: it runs outside the request zone entirely, so the authority guard
never armed. Fixed by carrying the role per interaction generation and reading
it explicitly at both sites, which is what the design asked for in the first
place — its warning was written about authority and applies to the prompt path
too.

**The header went on the wrong literal.** `chat_notifier.dart` created
assistant messages in three identical places, and the marker landed on the
hidden-prompt path. The ordinary send and the post-tool continuation — the two
a user actually reads — kept the plain shape. Fixed by one
`_newAssistantMessage`, guarded by a source-scan test that fails when
`MessageRole.assistant` appears in a second literal there.

The lesson both share: the unit tests exercised the zone directly and the live
measurement built its own system prompt, so neither went through the path that
nests inside. Same shape as the canary-harness blindness recorded earlier — a
green harness verifying the old path.

## One fix worth its own note

`ToolFailureClassifier.isApprovalDenial` was a substring test for `denied` or
`auto-review`, and **neither** of ANA0's guards says either word. Both refusals
classified as `executionFailure`, so the abort notice told the user to check
their server configuration for a policy working exactly as designed — the
notice's own comment says not to do that for a policy decision — and
`lifecycleResultStatus` recorded `tool_failure` for a decision, polluting the
population the `tool_failure_abort` analysis counts. Now the machine-readable
`code` both guards already return is read first, with the prose branch kept as
the remainder for refusals that predate a code. An unrecognised code is still
an execution failure: treating every structured failure as policy would stop
the loop retrying what a retry can fix.

## Extractions the ratchet asked for

Nine, each a pure function or a per-type dispatch with no reason to live where
it was. They are listed because the pattern repeated: **every one was found by
hitting a ceiling, not by looking first.**

- `run_tests` command spelling → `RunTestsCommandBuilder`
- computer-use description and redaction → `ComputerUseActionPresentation` (twice)
- the ten approval sheets → `ApprovalSheetDispatcher`
- the workflow task menu → `workflow_task_menu_items.dart`
- the outstanding-approval registry, `PendingAskUserQuestion`, and the per-type
  clear dispatch → three files of their own
- the composer's slash keys → a part of `message_input.dart`

Chat page library 8,800 → 8,607. Notifier library 19,829 → 19,731.
`message_input.dart` 2,201 → 2,107, and its library aggregate was added to the
ratchet at the same time so that splitting a file cannot become a way to leave
it.

## What is next, and what stands in the way

ANA3 PR 2b: the parent's route to writing an acceptance. The judgement already
happens — the observed session had the parent read a child's result and write
the final answer from it — so what is missing is recording it where the next
turn can see it.

Three ceilings are at their limit and the tool definition, its handler and the
write path all land in them: `conversations_notifier.dart` 1,791/1,791,
`chat_notifier.dart` 8,778/8,778, notifier library 19,731/19,731.
`conversations_notifier.dart` is the one this work never touched, so unlike the
others its seams are unknown.

Also open, and unmeasured: whether the model **over**-generates precondition
edges. 69 edges across 65 tasks is close to one apiece, and telling a graph
from a reflex needs a fixture with a known-correct answer.

## Commits, before the squash

Grouped by what they were for. The branch was
`claude/next-step-investigation-7f7da4`.

- **ANA0 confirmation surface** — `3f53dffdb` state and three ceiling
  extractions, `eb3c6b828` approval sheets out of the page library,
  `0e60696e8` the gate, sheet, arming and canary unskip, `b768c8cf2` end-to-end
  evidence and the firing signature
- **ANA0 projection and UI** — `5d4bae721` the prompt stops describing
  assumptions with the wrong list, `81c310e0f` assumed items stop rendering as
  facts
- **ANA1** — `f6b4af876` edges and readiness, `ea97bc726` document round trip,
  `74d0937ff` the channel measurement, `bbdb4d526` shipping the measured
  channel, `12fe65791` rendering, `5f74d2ed0` telling the model
- **ANA0 parent boundary** — `f0931925a` the guard, `6ecc5a963` the `@anabasis`
  entry point, `852ffb49e` the boundary measurement, `276de22e7` the zone fix
- **ANA2** — `13200ee9a` candidates and premises, `b862ab51d` runner routing,
  `a8d52dd1e` the contradiction policy, `2e98d2552` handing the parent its queue
- **ANA3** — `aa7094699` the derived levels, `014a6c094` what must hold first
- **Surfaces** — `a311618ad` the transcript header, `dcd797d14` the composer
  extraction, `9b8f18841` `@` completion, `7d362b177` the header on the right
  literal
- **Fixes and records** — `ed6a202da` policy refusals read by code,
  `da6ccb9d6` the boundary firing in a real session, `0fa489da0` the two
  surfaces confirmed on screen, `0fd250991` what PR 2b has to clear
