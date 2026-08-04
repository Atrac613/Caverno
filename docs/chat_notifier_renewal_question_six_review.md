# Renewal Review Question 6, Re-asked

The architecture plan closed with six review questions. The sixth was:

> **Should this happen at all?** The status quo is a large file that is
> ratcheted, audited and covered by canaries. "Stop growing it and live with it"
> is a legitimate answer if the cost case does not hold.

It has not been re-asked since the plan was written on 2026-08-02, and the cost
case has been revised downward twice since. This document re-asks it with the
evidence that now exists. It makes a recommendation; it does not make the
decision.

## The plan's own goals, measured

The plan proposed replacing the retired line target with four goals. Measured at
`3610ef56`:

| Proposed goal | Then | Now |
| --- | ---: | ---: |
| Recorded ambient reads: 67 → **0** | 67 | **67** |
| Turn-reachable ambient reads | 50 | **49** |
| Adding a tool handler requires **zero** edits to `chat_notifier.dart` | — | still required; the registry is a part of that library |
| Identity parameters (not a stated goal; the plan's cost case) | 314 | **317** |

**On its own headline metric the program has moved one read of fifty, and zero
of sixty-seven.** That is the single most important number in this review and it
should not be softened.

## What the program has cost

| | |
| --- | --- |
| Span | 2026-06-23 to 2026-08-04, about six weeks |
| Commits mentioning the runtime | 27 |
| Documents in `docs/` matching the program | 79 |
| Production code added | 1,041 lines in `lib/features/chat/application/runtime/` |
| Notifier family size | 19,683 → 19,258 (−2.2%) |

Three counterweights, in fairness:

- **Most of the six weeks went to measurement, not extraction.** Phases 0, 0A,
  0B and 1 built the turn-scope audit, the mechanical selector, the guard
  inventory, and the repair of four canaries that had been reporting on a
  placeholder verifier. That apparatus is real and now works: it caught the
  boundary sitting outside audit scope, it forced a factory extraction, and it
  is what makes every claim in this document checkable.
- **The line target was explicitly retired.** −2.2% is not the measure and
  should not be read as one.
- **The actual extraction is days old**, covering one concern of seven.

## What the diagnosis turned out to be worth

The diagnosis — turn-local state simulated at notifier scope, with no turn
object — is **confirmed, and more sharply than the plan stated it**:

- 40 owner- or generation-keyed stores exist on the notifier.
- The turn's destructor is roughly **21 manual steps across two chained
  functions** (`_terminalizeRuntimeTurn`, then
  `_clearActiveResponseForGeneration`). Every new piece of turn state adds a
  line someone must remember to write.
- That shape has produced real defects: the stale active-response registration
  fixed in `e59fe248` stranded a thread under a spinner from one missed release,
  and the cross-thread contamination class has the same origin.

So the diagnosis is not the weak part. The cost case is.

## What the cost case got wrong, twice

- **The plan predicted identity parameters collapse into `this` as concerns
  migrate.** The first boundary *added* 14 until owner binding removed them.
  Net across the whole prototype: **+3**.
- **The Phase 2 draft predicted port reuse would amortize later concerns.** One
  port of five is generic. Concern two reuses one and needs eight.

Both errors were optimistic, and both were found by measurement rather than
review.

## The cost nobody has priced

`_turnToolResults` keys by `ChatTurnOwner` exactly like the nine stores around
it, carries a ten-minute retention, and is torn down by neither destructor.
Absorbing it would silently destroy results the system retains on purpose.

The classification that caught it was **manual, per store, by tracing teardown**
— the key type is identical for the trap and the nine safe cases.

There are **40 such stores**. Phase 3's real cost is not ports; it is forty
manual scope determinations where a wrong answer leaks state into the next turn
and no test in the same turn fails. That cost does not amortize, and the
probability of getting one wrong accumulates across the program.

## Three options

**(a) Stop. Live with it.** The ratchet holds, the audit works, the boundary
exists for one concern, and the gates fire. Cost: the 21-step destructor stays,
the defect class stays, and `ChatToolHandlerCatalog` stays permanently blocked —
its WS6-19 no-capture condition cannot be met without exactly this extraction.

**(b) Continue as scoped: seven boundaries, Phase 3 as a program.** Buys the
plan's original goals. Costs six more concerns at roughly concern-one economics,
plus forty manual scope determinations. On present evidence the ambient-read
goal is not close.

**(c) Narrow the goal to the destructor.** Authorize **one** slice on
`chat_notifier_execution_runtime.dart` — 197 lines, 9 absorbable stores, the
owner of the destructor's first half — with the object of replacing manual
teardown with dropping an object. Then stop and re-evaluate against measured
results rather than projections.

## Recommendation

**(c).**

The reasoning is that the diagnosis and the cost case have come apart. The
diagnosis is confirmed and points at a specific, defect-producing structure. The
cost case for generalising it across seven boundaries has been wrong twice, both
times optimistically, and carries a forty-fold manual verification risk nobody
has priced.

(c) takes the part of the renewal that is demonstrably load-bearing and bounds
it: one part, one slice, all six existing stop conditions plus two specific to
it — `_turnToolResults` stays behind a port, and all 21 teardown steps are
proven still to happen. It converts an open-ended architecture program into a
bounded fix for a defect class with two documented instances.

It also produces the number (b) needs and does not have: what a wide slice
actually costs. If (c) comes in cheap, (b) becomes arguable on evidence. If it
comes in like concern one, (a) is the honest answer and the program stops having
spent one more slice rather than six.

**What would change this recommendation:** a live-gate for
`execution_runtime` proving unreachable, or a decision that the catalogue
migration is required soon — the latter forces (b), since the catalogue needs
the full boundary.

## Decision

**(c) accepted, 2026-08-04.** The renewal's goal narrows from seven capability
boundaries to the turn destructor. One measured slice is authorized on
`chat_notifier_execution_runtime.dart`; nothing beyond it is.

The amendment to the Phase 1.5 decision's Phase 3 block is recorded there. Its
scope is one slice, and the re-evaluation after it decides whether anything
follows.

### Slice authorization

| Term | Value |
| --- | --- |
| Part | `chat_notifier_execution_runtime.dart`, 197 lines |
| Objective | Replace the destructor's first half — `_terminalizeRuntimeTurn`'s ten owner-scoped teardown steps — with dropping an owned object |
| Absorbed | The 8 stores proven cleared by a destructor and observed empty after a real turn |
| Explicitly not absorbed | `_turnToolResults` and `_hiddenAssistantEvidence`; both outlive the turn by design and stay behind ports |
| Stop conditions | The Phase 2 draft's six, plus: all 21 teardown steps proven still to happen, and neither retained store absorbed |
| Reported | Identity parameters, turn-reachable ambient reads, public declarations, touched files, production line delta |
| After | Stop. Re-evaluate (a)/(b)/(c) against the measured result. |

Nothing in this authorization extends to a second slice, to the remaining 31
turn-local stores, or to catalogue wiring.
