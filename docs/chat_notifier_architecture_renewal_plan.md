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

The proposed diagnosis, **corrected after review**: the notifier has no
**turn-scoped composition root**. An earlier draft said "a turn is not an
object", which was wrong in a way worth recording — it collapsed two scopes.
`CavernoRuntimeTurnHandle` already exists, and plenty of state deliberately
outlives a turn: `ThreadScopedChatState` is explicitly retained when the user
leaves a thread, and the goal auto-continue trackers span several turns by
design. Those are not leaks.

The target is three layers, not two:

```
app / notifier scope        settings, registries, cross-conversation services
conversation / thread scope thread state, goal trackers, plan progress
turn scope                  the tool loop, its evidence, its guards  ← no root
```

Only the third layer is missing a home. Everything that participates in one
turn must therefore be handed a `(conversationId, interactionGeneration)` pair
and re-establish its own context from it.

Three consequences follow, and all three are measured:

1. **Everything that participates in a turn becomes a notifier method.** The
   manifest records 414 entrypoints across 43 historical parts; the audit
   resolves **271** in the current tree, of which **82 carry an identity
   parameter** and 139 are turn-reachable. A new tool, guard or recovery path
   has nowhere else to land.
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
  ├─ ToolHandlerRegistry     ALREADY EXISTS as ChatToolHandlerCatalog,
  │                          unwired in production (see below)
  └─ PolicyPipeline          guards report fired / did-not-fire structurally
```

**Why this may not repeat the 5.8× tax — and how to check rather than assume.**
That tax was the cost of pulling logic away from the state it needed, which
meant rebuilding the inputs at every call site. This moves the other way:
methods migrate *onto* the object that owns their state, and identity
parameters become `this`.

An earlier draft claimed 414 entrypoints' parameters collapse. That was the
historical record used as an effect. The honest figure is **82 entrypoints
carrying an identity parameter** out of 271 resolvable, so parameter
elimination alone is worth low hundreds of lines, not thousands. Whether the
migration is net-negative on lines depends on how many ports and callbacks a
`TurnRuntime` needs to reach back into notifier scope — which is unknown and
is exactly what the prototype below exists to measure.

**One piece is built and not connected.** `ChatToolHandlerCatalog` exists with
its own tests and is used by the subagent adapter, while the production loop
still builds `ChatToolHandlerRegistry.fromModules`, which captures the
notifier. Workstream 6 slice 19 specifies the migration and it was never
completed. Wiring it is a fraction of the renewal's cost and delivers the
"adding a tool touches no notifier code" goal on its own — and learning **why
it was skipped** may reveal an obstacle that also blocks the renewal.

**The rest of the groundwork is mostly built.** `ChatTurnOwner`, the `TurnThread` and
`TurnGeneration` zones, `ActiveResponseRegistry`,
`TurnOwnerSnapshotRegistry`, `CavernoRuntimeTurnHandle`, the owner-fenced
mutation runtimes and `ThreadScopedChatState` were all built during the
thread-independence work. They amount to treating a turn as an identity with
fenced resources. What is missing is the object to hang them on.

## Prerequisite: reconcile the existing program's state

`docs/chat_notifier_decomposition_task_index.md` still lists workstreams 4-7 as
in progress and 8 as planned, while this plan and the decomposition doc treat
the program as closed. One of those is wrong and the index is the authoritative
one. Before any phase starts, either close the index or move its open items
into this plan explicitly. The turn-scope baseline also needs re-checking; it
reportedly no longer matches.

## Proposed phases

An earlier draft had Phase 0 instrument "guards whose silent non-firing decides
reachability" and Phase 1 inventory the guards. That is circular — the
selection needs the inventory. Split:

**Phase 0A — static guard inventory.** Enumerate the guards and recovery paths
and, for each, whether a silent non-fire can make a feature unreachable. Static
reading only. 376 of 377 `return null;` statements in `domain/services` have no
log within six lines, so the population is large and must be filtered by
consequence, not instrumented wholesale.

**Phase 0B — telemetry for the subset 0A selects.** Adding one such field
(`hasVerifierReplayCandidate`) on 2026-08-01 resolved in a single run a question
that had been invisible for as long as the feature existed.

**Phase 1 — inventory against a pinned corpus.** See
`docs/chat_notifier_inventory_codex_task.md`. Fix the date range, file set and
build revisions first; a re-measurement during review produced 33 invoked tools
where an earlier note recorded 41, and without a pinned corpus there is no way
to distinguish drift from a different sample.

**Phase 1.5 — the two cheap experiments, and the decision point.** Before
committing to a renewal:

- **Wire `ChatToolHandlerCatalog` into the production loop** (workstream 6
  slice 19). Delivers the "adding a tool touches no notifier code" goal by
  itself, and answers why it was skipped.
- **Prototype `TurnRuntime` on exactly one high-coupling part.** Measure lines
  removed, parameters eliminated, and ports or callbacks introduced.

**Proceed to Phase 2 only if that measurement supports it.** If the prototype
shows the ports cost more than the parameters save, this plan should be
abandoned in favour of wiring the catalogue and stopping there.

**Phase 2 — design document.** Under the same discipline as the decomposition
program: explicit safety contract, regression gate, live-canary gate, slice
definitions with acceptance criteria.

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
