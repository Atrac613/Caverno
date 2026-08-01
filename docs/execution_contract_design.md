# ExecutionContract

**Status: not proceeding. Kept as the record of why.** Written 2026-08-01 as a
design for giving a plain coding turn the scaffolding a hand-written prompt had
to supply. Taking the baseline before implementing it — the discipline the
document itself asked for — dissolved the premise the same day. The short
version, in full below: two of its three gaps stopped reproducing, and the
measurement the third rested on turned out to be a placeholder that answered
every verification with a silent exit 0. With that fixed, the realistic short
prompt builds and verifies the fixture in 127 s with no contract at all.

Read the three revision sections in order. The original design follows them
unchanged, because a design that was wrong for a legible reason is worth more
intact than deleted.

## The measurement this starts from

Live-canary runs 9 and 10 are a controlled pair. Same model
(`qwen3.6-27b-vision`), same five tools, same temperature, same fixture, same
workspace. The only delta is the prompt.

| Run | Prompt | Result |
| --- | --- | --- |
| 9 (build `f6276439`) | detailed | **passed**, 86 s, verifier exit 0 on the first try, one `write_file` after a read-first exploration |
| 10 (build `7f92e7bf`) | the realistic short Japanese ask, spec file present in the workspace | **failed**, 717 s, verifier exit 0 never reached |

Run 9's prompt was not a better description of the task. It was a hand-written
**execution contract**: it pinned the artifact layout, named the verify command,
set an early verification cadence, and fenced the scope. Removing it is the
only change, and the run collapsed.

The model is not the constraint. Run 10's failure chain reads as three specific
absences, and each one maps to something Caverno already owns but cannot reach
from a coding turn.

## What already exists, and where it cannot reach

| Contract element | Implementation | Reachable from |
| --- | --- | --- |
| Artifact layout | `ConversationWorkflowTask.targetFiles` | plan path only — `conversation_plan_execution_guardrails.dart` genuinely enforces it |
| Verify command | `ConversationWorkflowTask.validationCommand` | plan path only |
| Verify cadence | `VerificationCadencePolicy` | between turns only (see gap 2) |

The object a coding turn actually runs under is `ConversationGoal`. Its fields
are `objective`, `enabled`, `autoContinue`, `status`, `tokenBudget`,
`tokenUsage`, `turnBudget`, `turnsUsed`, `completionSummary`, `blockedReason`,
`blockerSignature`, `blockerRepeatCount`, and timestamps.

It answers **how much the turn may spend** and **whether it is stuck**. It does
not answer **what is being built** or **how anyone would know it works**. Run 9
supplied that second half by hand. That is the whole finding.

## Revision, same day: the baseline moved

The three gaps below were written from run 10, measured on build `7f92e7bf`.
Before implementing any of them the baseline was re-taken on current `main`
(build `9a92e989`, same harness, same model, same minimal prompt) — call it
**run 11**. It should be read before the gap sections, because two of the three
no longer reproduce.

| Run 10 failure | Run 11 |
| --- | --- |
| `lib/` + `bin/` split, package name contradicted, never compiled | single `bin/todo.dart`, **zero `package:` imports** |
| confabulated `~/.todo_app.json`, outside the verifier's reach | state at `workspace/todo.json` |
| verifier run once, at iteration 14 of 16 | verification attempted in turn 1 |

717 s → **187 s**, one turn of five, 5,284 tokens of 60,000. The artifact
works: an independent walk-through in a fresh state directory passed add, list,
done, unknown id → exit 1, and cross-process persistence.

So **gap 1 and gap 3 target failures the current build does not exhibit.**
Implementing them now would be fixing a solved problem, and their sections are
kept below only as the record of what was true on `7f92e7bf`.

Run 11 still went red, on one assertion — `verificationAttempts >= 1` was 0 —
and the cause is the instrument. The fixture accepts exactly one literal
command, `dart run tool/verify_todo_app.dart`, while the spec it ships gives a
`<run>` walk-through and says "adapt the invocation to the chosen stack". The
model adapted it, exactly as instructed, and was refused. The refusal named
neither the accepted command nor any action, so there was no way back.

### Run 12: the instrument does not measure what it claims

A second run followed, with one change: the fixture's refusal was made to name
the accepted command instead of only saying "unsupported". It failed the same
way, and tracing why produced the finding that matters most here.

**The fixture verifier never runs in this scenario.** In run 12 the model did
issue the accepted command, `dart run tool/verify_todo_app.dart`, from the
project root. The result it received was
`{"exit_code": 0, "stdout": "", "stderr": ""}` — the output of really executing
`tool/verify_todo_app.dart`, which is a six-line `void main() {}` placeholder
whose own comment claims "the Caverno test harness intercepts" it. Nothing
intercepts it.

The cause is wiring. `_buildContainer` overrides `mcpToolServiceProvider` only,
and `local_execute_command` is a built-in tool
(`chat_tool_handler_catalog.dart:80`), so the built-in handler shadows the
fixture's same-named MCP definition at execution time. Confirmed across both
runs: zero results carrying the fixture's `"canary": "todo_app"` marker appear
in either session log.

Two consequences, and the second is the serious one:

1. `expect(toolService.verificationAttempts, greaterThanOrEqualTo(1))` cannot
   pass in this scenario by construction. The red says nothing about the model.
2. **The model is handed a false green.** It runs the command it was told to
   run, receives a silent exit 0 from a file that checks nothing, and concludes
   the work is verified. In run 11 that conclusion happened to be correct — the
   artifact really does work — which is exactly what makes the defect hard to
   see.

Run 10's recorded failure has to be re-read in this light: with the same
wiring, its "verifier" was the same placeholder. The run 9 / run 10 pair that
this document is built on therefore rests on a verification signal that was
vacuous on at least the run-10 side. What survives unharmed is the *artifact*
evidence — run 11's app was walked by hand and passes — and the observation
that prose does not bind, which run 12 demonstrates again: the accepted command
was stated in the `local_execute_command` tool description and the model still
mixed in its own chained commands.

**Nothing further should be built on this fixture until `local_execute_command`
reaches the fixture verifier.** That is the next piece of work, and it is
instrument repair, not product work. The rejection-message change made for run
12 was reverted: it sits on a path these scenarios never take, and it was aimed
at a misdiagnosis.

### Run 13: with a real verifier, the short prompt passes

The instrument was repaired (`42c7cbd2`). The generated entrypoint now forwards
to `TodoAppBehaviorVerifier`, which already existed and already copies the
sources to a fresh directory before checking them, so the isolation the
placeholder was guarding is kept and the checks still live outside the
model-edited project. Both directions were proven before spending a live run: a
working artifact exits 0 with no diagnostics, an injected in-memory-only defect
exits 1 with `todo_cli_persistence_failed`.

| | Run 10 | Run 11 | Run 13 |
| --- | --- | --- | --- |
| Result | failed | failed (instrument) | **passed** |
| Duration | 717 s | 187 s | **127 s** |
| Verifier | placeholder | placeholder | real; one run, exit 0, 0 diagnostics |

The artifact was re-verified independently from a clean copy, and the verifier
file was unmodified at the end of the run.

**This is the bar the document set for itself, and it is met without the
design.** "How we will know it worked" below asks that run 10's prompt reach
verifier exit 0 under the same model, temperature, tool set and loop cap. It
does. The contract was proposed to close a gap between a hand-written prompt
and a realistic one; on the current build, with an instrument that measures,
that gap is not visible.

What remains true, and is worth carrying forward wherever it applies:

- **Prose does not bind.** Run 9's "do not call any more tools" was ignored and
  the fixture's rejections were not; run 12's accepted command was stated in
  the tool description and the model still wrote its own. Any future mechanism
  that depends on the model reading an instruction should be assumed not to
  work until measured.
- **Take the baseline before building on a measurement.** Three of the four
  conclusions in the original design would have shipped as fences against
  failures that no longer happen.
- **Check what a green means before trusting it, and a red too.** The red here
  was an assertion that could not pass by construction, sitting on top of a
  green the model was handed by a file that checked nothing.

If a contract is wanted again, it needs new evidence — a task where the
realistic prompt genuinely fails and a contract genuinely rescues it — not this
pair.

## Three gaps, each measured

### 1. The artifact layout is never pinned

**Superseded by run 11 — did not reproduce.** Kept as the `7f92e7bf` record.

`targetFiles` exists, and `_effectiveTargetPaths` even infers targets from a
task's title, notes and validation command when they are not explicit. None of
it is constructed for a coding turn.

Consequence, observed twice and fatal both times — the **package-name
flip-flop**:

- Dogfooding run 2: `flutter create . --project-name todo_app` set
  `name: todo_app`; a later `edit_file` reverted it to `todo3`; `main.dart`
  imported `package:todo_app/...`; 10 unresolved errors; the model stopped.
- Canary run 10: structural freedom produced a `lib/` + `bin/` split, the
  pubspec was named `todo_auto_continue_fixture`, the model imported
  `package:todo_cli/...`, and the program never compiled.

Note what run 10 actually did: it contradicted **a fact already on disk**. The
pubspec name was not ambiguous. Nothing consulted it.

### 2. Verification cadence is generation-scoped, never iteration-scoped

`VerificationCadencePolicy.decide` turns on
`mutationGeneration > verificationGeneration`. Those are *turn* generations.
The policy can say "you mutated in a later turn than you last verified". It
cannot say "you are fourteen iterations into this turn and have not verified
once".

That intra-turn case is exactly run 10: the verifier ran once, at iteration
14 of 16. Run 9 ran it at iteration 3. In between, run 10 burned its budget on
a verifier-stub read ×3, spec re-reads, and four post-edit read-backs, with
progress judged by analyzer cleanliness rather than by execution.

`ToolLoopExhaustionPolicy` already receives `iteration` and `maxIterations` —
but by construction it only fires once `iteration >= maxIterations`, when there
is no budget left to act on the answer. There is no gate that fires while the
turn can still do something about it.

### 3. Writes are not fenced to the project root

**Superseded by run 11 as motivation — the confabulated HOME path did not
reproduce.** The code fact below still holds and is worth knowing on its own;
it is no longer evidence for building a fence.

`file_mutation_tool_handler.dart:233` checks `DartProjectPath.isInsideRoot`
inside `else if (operation.kind == FileMutationKind.deleteFile)`. The root check
applies to deletes only; `write_file` and `edit_file` reach any path approval
allows.

Run 10 confabulated a requirement the spec never stated — that state must
persist to `~/.todo_app.json`, where the spec said only "a local file" — and
wrote there. That is a latent second failure independent of the first: the
verifier's state isolation cleans the workspace, and cannot clean `HOME`.

The asymmetry is defensible on its own terms (a delete is less recoverable than
a write). It stops being defensible once a turn is running under a contract
that names where the artifact lives.

## The design

### The entity

`ExecutionContract` sits beside `ConversationGoal` on the conversation. The
goal carries *how much*; the contract carries *what* and *how verified*.

```
ExecutionContract
  artifactRoot      String    the directory the work belongs in
  moduleName        String    the package/module identity writes must agree with
  targetFiles       List<String>
  verifyCommand     String    the command whose exit code decides "works"
  verifyByIteration int       the loop iteration by which it must have run once
  source            enum      derived | drafted | userConfirmed
```

`source` is load-bearing, not bookkeeping: it decides whether a fence may
*reject* or may only *advise*. See "Binding".

### Derivation: mechanical first

The instinct is to draft the contract with a model call, the way plan drafting
works. Resist it for the parts that are facts.

Run 10's landmine was that the model contradicted the pubspec name — a fact
sitting on disk, requiring no judgment. `moduleName` and `artifactRoot` should
be **read**, not inferred: the nearest `pubspec.yaml` / `package.json` /
`pyproject.toml` above the working directory answers both. A contract built
from facts cannot fence the model away from a correct solution, because it
only restates what is already true.

That leaves `verifyCommand` and `targetFiles`, which do need judgment. Order of
preference:

1. The spec document, if the turn was pointed at one (run 9's and run 10's
   fixtures both had `todo_app.md` in the workspace).
2. Project convention — a `dart test` / `npm test` / `pytest` that the
   repository already supports.
3. One `ask_user_question`, once, at contract creation. Measured behaviour:
   the local model never volunteers `update_goal` but answers when asked, and
   one restricted turn closes a dry goal. Asking is cheap and it is the one
   place a wrong contract gets caught before it does damage.

Only fall back to a drafting call if all three miss, and mark it `drafted`.

### Binding: mechanical, not prose

Run 9's record contains the single most important constraint on this design:

> after exit 0 the model ignored the new "do not call any more tools" prompt
> line […] prompt instructions alone did not stop the model, the fixture's
> rejections did.

A contract that only appears in the system prompt is run 10's prompt with extra
steps. Each fence must be consulted at the tool boundary and must return a
diagnostic the loop can act on — the same shape as the existing rejections that
demonstrably worked.

| Fence | Evidence | Insertion point | Mechanism |
| --- | --- | --- | --- |
| Module identity | package-name flip-flop ×2 | file mutation handler, before approval | reject a write whose import/package name contradicts `moduleName`; diagnostic names both values |
| Artifact root | run 10's `~/.todo_app.json` | `file_mutation_tool_handler.dart:233`, lifted out of the `deleteFile` branch | reject a write outside `artifactRoot` when `source != drafted` |
| Verify cadence | run 10 verified at 14/16, run 9 at 3 | new sibling of `ToolLoopExhaustionPolicy`, same `iteration`/`maxIterations` inputs | at `verifyByIteration`, if no verify has run this turn, inject the requirement while budget remains |

A `drafted` contract advises but never rejects. A contract whose module name and
root were read off disk may reject, because rejecting a write that contradicts
the pubspec cannot be wrong.

## Deliberately out of scope

Several run-10 symptoms already have shipped guards, and re-solving them here
would double-count the evidence:

- post-success task-restart rewrite → the mutation block from `34507804`
- false completion claims → `caverno-false-completion-claim-guards`, proven
  load-bearing in the wild
- narrated transcripts → `NarratedTranscriptClaimGuard` (`c1883e86`)
- `fr=length` final-answer runaway → `final_answer_concise_retry`, which fired
  correctly in run 10 and produced an honest failure report

**Do not raise the tool-loop cap.** Run 9 passed in 86 s under the same cap
that run 10 exhausted. The cap is not the constraint; the absence of a contract
is. Raising it would spend budget without changing the failure.

## How we will know it worked

Run 10 is the fixture. Its prompt — the realistic short Japanese ask with the
spec present — is the exact input that must start passing. The bar:

1. Run 10's prompt reaches verifier exit 0, under the same model, temperature,
   tool set and loop cap.
2. Run 9 does not regress: a turn that already carries a good hand-written
   prompt must not be slowed or fenced by a contract derived on top of it.
3. The package-name flip-flop does not recur in either.

Anything short of (1) leaves the design unproven, however clean the unit tests
are. This is the same lesson the decomposition program recorded as its
regression gate: tests that supply their own preconditions cannot show that a
path lacking them is broken.

## Risks

**A wrong contract is worse than none.** It fences the model away from the
correct solution, and unlike a missing contract, the failure is silent — the
model looks like it is complying. This is the entire reason for the
facts-before-judgment rule and for `source` gating rejection. Anything Caverno
inferred rather than read must not be able to refuse a write.

**Over-fencing.** Pin enough and the agent stops being an agent. The three
fences above are chosen because each has a measured fatal failure behind it;
the bar for adding a fourth is another measurement, not another hypothesis.

**Derivation cost.** Reading a pubspec is free. A drafting call is not, and it
lands on the same LAN server the turn is already using.

## Open questions

- Does the contract belong on `Conversation` beside the goal, or inside
  `ConversationGoal` itself? Beside it keeps the goal's serialization stable
  for old conversations, which mattered for `autoContinue`.
- Non-Dart projects: `moduleName` is well defined for pubspec/package.json/
  pyproject, undefined for a loose script directory. A contract with no module
  identity should simply carry none rather than invent one.
- Should `verifyByIteration` be absolute (3) or proportional (⌈max/4⌉)? Run 9
  verified at 3 of ~13. No second data point yet.
