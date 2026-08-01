# ChatNotifier Architecture Renewal: Plan for Review

**Status: proposal, seeking review. Nothing here is agreed.** Written
2026-08-02, after the decomposition program completed and its line-count target
was retired on measured grounds.

Codex: the review questions are at the bottom. The most useful thing you can do
is attack the diagnosis in the first section — everything downstream depends on
it, and if it is wrong the plan is wrong.

## The problem, stated as a diagnosis rather than a size

`chat_notifier.dart` and its 37 parts total 19,683 lines and keep growing back.
The decomposition program (71 collaborators, ~90 commits, several weeks)
extracted what could be extracted and closed with the aggregate at 19,647 —
against a 23,049 baseline, a 14.8% reduction for a very large effort.

The proposed diagnosis: **a turn is not an object.** It is a phase in the
notifier's life, identified by a `(conversationId, interactionGeneration)` pair
that every participant must be handed and must re-establish for itself.

Three consequences follow, and all three are measured:

1. **Everything that participates in a turn becomes a notifier method.** The
   manifest records 414 entrypoints across 43 historical parts (271 still
   resolvable in the current tree). A new tool, guard or recovery path has
   nowhere else to land.
2. **Turn-scoped state lives in conversation-keyed maps on the notifier** —
   `_goalAutoContinueTrackers`, `_threadStates` and others — because a turn
   cannot own its own state.
3. **Turn identity is re-derived by hand, everywhere.** 798 lines (4% of the
   library) touch `interactionGeneration`, `ChatTurnOwner`,
   `_turnOwnerForGeneration`, `TurnThread`/`TurnGeneration` zones or the
   ambient-read accessors. The turn-scope audit still reports 67 ambient reads,
   50 of them turn-reachable.

**The bugs follow the same shape.** The cross-thread contamination class, and
all three defects found on 2026-08-01, lived at seams between components rather
than inside any of them. None of them would have been prevented by a smaller
file; a halved `chat_notifier.dart` would have had every one of them.

This is also why the ratchet feels like an obstacle. It is working correctly —
it caught two of my own reflexive errors on 2026-08-01 — but new behaviour has
nowhere to land except inside the library, so **the ratchet collides with what
the structure forces**. Treating the ratchet as the problem would be treating
the smoke alarm as the fire.

## Why the line target was retired, and what replaces it

The 11,524.5 half-baseline was retired on measured grounds, recorded in the
decomposition doc's criterion 7:

- The program's realised ratio was **5.8 lines created per line removed**
  (18,107 created vs 3,115 removed across 71 collaborators). Extraction moves
  lines; it does not delete them.
- An AST walk at the close of workstream 8 found **9 pure members totalling 82
  lines** left to extract, averaging nine lines each and not forming a cluster.
  The extraction well is dry.
- The owner/generation plumbing that a per-turn split would directly eliminate
  is **798 lines**. Even a full split does not produce 8,000.

**The remaining 8,000 lines do not exist as extractable mass.** They are the
behaviour. Proposed replacement goals, all measurable and all achievable:

- Adding a tool handler requires **zero** edits to `chat_notifier.dart`.
- Ambient reads: 67 → **0**.
- Guards whose non-firing decides feature reachability: **observable**.
- Unreachable code: **0**.

Aggregate line count becomes a reported consequence, not a target.

## Proposed target shape

```
ChatNotifier            thread routing and UI projection only;
                        creates and disposes TurnRuntime
TurnRuntime             owner and generation are `this`
  ├─ tool loop, completion evidence, trackers
  ├─ ToolHandlerRegistry     handlers register; the loop does not name them
  └─ PolicyPipeline          guards report fired / did-not-fire structurally
```

**Why this does not repeat the 5.8× tax.** That tax was the cost of pulling
logic away from the state it needed, which required rebuilding the inputs at
every call site. This moves in the opposite direction: methods migrate *onto*
the object that owns their state, and the `owner` / `interactionGeneration`
parameters threaded through 414 entrypoints become `this`. Parameter
elimination reduces lines.

**The groundwork is mostly built.** `ChatTurnOwner`, the `TurnThread` and
`TurnGeneration` zones, `ActiveResponseRegistry`,
`TurnOwnerSnapshotRegistry`, `CavernoRuntimeTurnHandle`, the owner-fenced
mutation runtimes and `ThreadScopedChatState` were all built during the
thread-independence work. They amount to treating a turn as an identity with
fenced resources. What is missing is the object to hang them on.

## Proposed phases

**Phase 0 — make reachability-deciding guards observable.** Small.
376 of 377 `return null;` statements in `domain/services` have no log within six
lines. Instrumenting all of them would be noise; the proposal is to instrument
only guards whose silent non-firing can render a feature unreachable. Adding
one such field (`hasVerifierReplayCandidate`) on 2026-08-01 resolved in a single
run a question that had been invisible for as long as the feature existed. This
is the safety net for every later phase.

**Phase 1 — inventory.** See `docs/chat_notifier_inventory_codex_task.md`.
Deletion is the only reduction that does not pay the extraction tax, and the
design must know what will not be migrated.

**Phase 2 — design document.** Under the same discipline as the decomposition
program: explicit safety contract, regression gate, live-canary gate, slice
definitions with acceptance criteria. Not written until Phase 1 reports.

**Phase 3 — sliced execution.**

## Honest cost and risk

Comparable to or larger than the decomposition program, which ran several weeks
across ~90 commits. The difference in kind: that program treated the symptom,
this one treats the cause — and if the diagnosis is wrong, this is a very
expensive way to find out.

**The largest risk is that the turn loop is load-bearing in ways the tests do
not capture.** The evidence for this is direct: on 2026-08-01 a green unit
suite coexisted with a feature that nothing could reach, and every one of the
three defects was found by a live canary rather than by tests. Any slice plan
must gate on live canaries, not on the unit suite.

**Second risk: the canaries themselves.** Four MVP fixtures were found on
2026-08-01 to have been reporting on a placeholder verifier that answered every
verification with a silent exit 0. They are repaired and now guarded, but the
lesson stands — before trusting a canary as a gate, confirm what it measures.

## Review questions

1. **Is the diagnosis right?** Is "a turn is not an object" the cause of the
   regrowth, or a plausible story fitted to the symptoms? What would falsify
   it? Specifically: is there a large body of code in the library that is
   *not* turn-scoped and would therefore not move?
2. **Does the parameter-elimination argument hold?** The claim that this
   migration reduces lines where extraction increased them is central. Check it
   against a real part file rather than in principle.
3. **Is Phase 0 worth doing first**, or does it delay the work that matters?
4. **Is the phasing right?** Inventory before design assumes the design depends
   on what survives. Is that true, or could both proceed in parallel?
5. **What is missing?** In particular, is there a cheaper intervention that
   captures most of the benefit — and is there a reason to keep a shared
   notifier that this plan has not considered?
6. **Should this happen at all?** The status quo is a large file that is
   ratcheted, audited and covered by canaries. "Stop growing it and live with
   it" is a legitimate answer if the cost case does not hold.
