# ExecutionContract

A design for giving a plain coding turn the scaffolding that a hand-written
prompt currently has to supply.

Written 2026-08-01. Grounded in the CMVP-1 live-canary runs, not in
speculation; every gap below names the run that exposed it.

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

## Three gaps, each measured

### 1. The artifact layout is never pinned

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
