# State Authority by Lifetime

Inventory required by the pilot gate in
`docs/chat_notifier_renewal_state_of_play_codex_task.md` ("After H0–H2 and a
state-authority-by-lifetime inventory, a production pilot may be proposed").

Measured 2026-08-04 against `feature/chat-turn-harness-thread-contention`
(`262f15e9`), and amended the same day after P1
(`refactor/unify-turn-destructors`) corrected the destructor section — see
*Correction*. Enumeration is mechanical
(`tool/`-external script, retained in the session scratchpad); classification
below is read, not inferred from names.

## What was counted

Every field under `lib/` whose declared type or initializer is keyed by
`ChatTurnOwner` or by an interaction generation `int`, across all layers — not
just the notifier library.

| | count |
| --- | ---: |
| Raw regex hits | 68 |
| — non-generation `int` keys removed | −5 |
| — `_handlesByGeneration` removed (see *Alias*) | −1 |
| **Keyed stores** | **62** |
| of which tombstone/retirement sets | 25 |
| of which state maps | 37 |

The five removed `int` keys were a static WMO weather-code lookup table, a
widget's collapsed-block indices, a listener-id map, JSON-RPC request ids in
`mcp_stdio_client`, and `FileMutationEffectCoordinator`'s effect tokens. None is
turn state; the shared `Map<int, …>` shape is what made them look like it.

### The prior figure was scoped, not wrong

Earlier documents state **40**. That count covered the notifier and its
immediate collaborators. Widening to all of `lib/` gives 62. Both are correct
for their scope; the 62 matters because the same identity discipline is being
maintained in `core/security`, `core/services`, and `data/datasources`, i.e. the
pattern has already spread beyond the file the renewal was chartered to fix.

## The five authority patterns

The useful axis is not the key type. It is **which holder is authoritative, and
what ends its authority.**

| # | Pattern | Authoritative holder | Authority ends when | Count | Unit |
| --- | --- | --- | --- | ---: | --- |
| **A** | Per-thread authority; `ChatState` is a derived view | the authority | thread is deleted | 4 | authority |
| **A′** | Owner-keyed registry authoritative; `ChatState` is an explicit projection | the registry | the approval is taken or cancelled | 10 | `ChatState` field |
| **B** | Visibility-flipping stash | **flips**: `ChatState` while visible, `ThreadScopedChatState` while not | never — it moves | 8 | `ChatState` field |
| **C** | Singular `ChatState` field, no per-thread home | `ChatState` | overwritten by the next thread | 19 | `ChatState` field |
| **D** | Owner-keyed registry; `ChatState` mirrors it | the registry | turn teardown, or a retention window | 37 | keyed store |
| **E** | Tombstone set (negative state) | nothing — records absence | never (monotonic) | 25 | keyed store |

A′ + B + C = 37 `ChatState` fields; D + E = 62 keyed stores. The two 37s are
unrelated — one counts fields on one class, the other counts stores across
`lib/`.

> **Corrected 2026-08-04, starting P2.** This table first read B as **18**,
> because `ThreadScopedChatState` was inspected on its own: all 18 of its fields
> are stashed and restored the same way, so they looked alike. Reading the
> *writers* separates them. Ten are pending tool approvals whose authority is
> `PendingToolApprovalRegistry`, and the stash is a rendering copy — pattern A′
> below. Only 8 are genuinely homeless. **The inventory overstated P2's scope by
> more than half**, and this is the first of the renewal's three estimate errors
> that was pessimistic rather than optimistic.

### A — the places that already work

`syncConversation` (`chat_notifier.dart:763`) rebuilds `ChatState` on every
thread switch, and it pulls from **four independent per-thread authorities**:

| Authority | Field it feeds |
| --- | --- |
| `ThreadScopedMessageQueue` (owns `_drainingOwners`) | `queuedMessages` |
| `_pendingAskUserQuestionsByThread` | `pendingAskUserQuestion` |
| `_activeResponseRegistry` | `busyConversationIds`, `messages` when a response is live |
| conversation persistence | `messages` otherwise |

For all four, `ChatState` is unambiguously a projection: the authority is
elsewhere and the field is recomputed on arrival. `ThreadScopedMessageQueue` is
the fullest example — a real object with 16 members, owning its own drain
ownership rather than exporting it.

This is the shape the rest would take under a `ThreadRuntime`, and it is already
in the codebase four times over, working. That materially lowers the design risk
for a per-thread pilot: it is generalisation, not invention.

### A′ — the ten that already have the target shape

`ChatState`'s ten `pending*` tool approvals are **not** homeless.
`PendingToolApprovalRegistry` (`chat_state.dart`) holds the
`PendingToolApproval` objects with their completers, keyed by `ChatTurnOwner`
and by id. `chat_notifier_approval_handlers.dart` routes every one of them
through a single register/take pair, and the projection is explicit in the
names:

```dart
_pendingToolApprovals.registerCurrent(pending, ownerIsCurrent: …, show: …)
_pendingToolApprovals.takeCurrent<T>(id: …, clear: _clearPendingToolApprovalProjection)
```

`show` writes the field; `clear` removes it. The registry decides; `ChatState`
and the stash render. This is pattern A with an owner key instead of a thread
key, and it is why each of the ten has exactly one `copyWith` write site while
the eight below have 78 between them.

### B — the eight that move with the camera

`ChatState` declares **37** fields. `ThreadScopedChatState` stashes 18, but ten
of those are A′ above. For the remaining **8** — the seven plan/workflow
drafting fields and `participantTurnRuntime` — the authoritative copy really is
`ChatState` while the conversation is visible and the stash while it is not,
swapped by `ThreadScopedChatState.from(state)` / `.applyTo(…)` on switch.

Confirmed by their writers: the drafting fields have no registry anywhere, and
`participantTurnRuntime` is read-modify-written on the state itself
(`s.copyWith(participantTurnRuntime: s.participantTurnRuntime?.copyWith(…))`,
`chat_notifier_participant_turns.dart:94`).

The first draft of this section said "this is not a bug — it is consistent, and
the switch path is covered." **That was wrong**, and it was wrong in the way
inventories usually are: it described the mechanism and inferred the behaviour
instead of running it. Two of the drafting entry points were writing to the
wrong thread outright — see *The unrouted half held a real defect* below.

What survives is the cost, now with a price attached: every writer of these 8
fields must decide to route, nothing in the type says so, and a reader cannot
tell a correct write from an incorrect one. A per-thread object removes the
decision rather than requiring 78 of them to be made correctly.

### C — the 19 that have no per-thread home

```
messages, queuedMessages, isLoading, response, busyConversationIds, working,
approvalRequiredConversationIds, error, promptTokens, completionTokens,
totalTokens, estimatedPromptTokens, contextTokenPressureLevel,
promptCompactionActive, contextSurgerySnapshot, pendingAskUserQuestion,
goalAutoContinueCount, goalAutoContinueBudget, goalAutoContinueNotice
```

Reading `syncConversation` splits them three ways, and the split is the finding:

- **Restored from a pattern-A authority** (6) — `messages`, `queuedMessages`,
  `isLoading`, `busyConversationIds`, `error`, `pendingAskUserQuestion`.
- **Derived on arrival** (2) — `approvalRequiredConversationIds` from
  `ThreadScopedChatState.awaitingApproval(_threadStates)`;
  `contextTokenPressureLevel` from `_refreshContextTokenPressureFromState()`,
  which recomputes from the restored `messages`.
- **Reset to the `ChatState` default** (11) — `response`, `working`,
  `promptTokens`, `completionTokens`, `totalTokens`, `estimatedPromptTokens`,
  `promptCompactionActive`, `contextSurgerySnapshot`, `goalAutoContinueCount`,
  `goalAutoContinueBudget`, `goalAutoContinueNotice`.

Only the third group is genuinely singular, and only there would a
`ThreadRuntime` change behaviour rather than relocate code. Most of it is
plausibly *correct* to reset — `response` and `promptCompactionActive` describe
an in-flight turn on the thread being left. The `goalAutoContinue*` trio and the
usage counters are the ones worth an explicit answer, recorded below.

### D — the registries, and why shape does not tell you

37 state maps. The gate already established that owner-keyed does not imply
turn-scoped, from two examples. The mechanical removal counts confirm the
discriminator is the **removal path**, not the key:

| Store | Removal path | Lifetime |
| --- | --- | --- |
| `TurnFinalizationStateRegistry._states` | `TurnReleaseScope` `'turnEnd'` | turn-bounded |
| `ContentToolTurnStateRegistry._states` | `TurnReleaseScope` `'contentToolTurns'` | turn-bounded |
| `ResponseMetadataRegistry._states` | `TurnReleaseScope` `'responseMetadata'` (was the legacy path, see *Correction*) | turn-bounded |
| `TurnToolResultLedger._states` | timed retention | **outlives the turn** |
| `HiddenAssistantEvidenceRegistry._states` | `publish`, not dispose | **outlives the turn** |
| `AskUserQuestionTurnCache._entriesByOwner` | only `_clearAllActiveResponses` (**bulk reset**) | **not turn-bounded** |

Three stores have **no removal path at all** in their library:
`_terminalOwners` in `PythonExecutionAuthority`,
`BrowserSessionOwnershipCoordinator`, and `LocalCommandExecutionAuthority`. All
three are pattern E despite being reached through D.

### The turn had three destructors, and only one was keyed cleanly

This was the sharpest structural finding in the inventory, and it was not
visible before the release-scope slice created the contrast. **Resolved by P1
(`refactor/unify-turn-destructors`); recorded here because the first version of
this section got the count and the relationship wrong.**

As inventoried:

| Path | Entered with | Removal steps | Discharged by |
| --- | --- | ---: | --- |
| `TurnReleaseScope` | `ChatTurnOwner` | 11 | dropping the scope |
| `_clearActiveResponseForGeneration` (`:2474`) | `int` generation | 7 | explicit call |

The legacy path was not cleanly generation-keyed: it was *entered* with a
generation, then derived the owner via
`_activeResponseRegistry.ownerForGeneration` and mixed both — six owner-scoped
releases alongside the generation removals.

#### Correction: two destructors, then three, and not the relationship stated

Reading the callers for P1 produced two corrections to the paragraph above.

**They were not competing destructors for one event.** Four of
`_clearActiveResponseForGeneration`'s five callers are the *start-failure* path
(`_startRuntimeTurn(...) == null`). One tears down a *started* turn's resources;
the other clears a *registration* that exists whether or not the turn started.
`_releaseTurnScope`'s own doc said as much and this inventory did not read it.

**There was a third.** `_startRuntimeTurn`'s acquisition-guard failure undid
four of the eleven obligations by hand, so that list had to be kept in step with
the scope by inspection.

#### What P1 changed

| | before | after |
| --- | --- | --- |
| start failure (guard) | 4 of 11 duplicated inline | `_releaseTurnScope`, one call |
| owner-keyed releases | 11 in the scope, 6 in the legacy path | 17 in the scope |
| generation cleanup | 12 steps, derives the owner | 6 steps, names no owner |

Safe because all six moved releases are acquired only after the turn starts
(`_responseMetadata.start` at `:2873` follows `_startRuntimeTurn` at `:2652`;
`_participantTurnControls.begin` sits in the success branch), so the paths that
never reach a scope have nothing to release. The paused-participant guard
travels with its release: disposing the controls of a turn the user paused would
end it.

The contract test now asserts the generation cleanup **names no owner**, so a
second destructor cannot grow back by the route that produced this one.

#### Not a destructor, and still there

`_clearAllActiveResponses` is a bulk reset reached from `syncConversation`
(`:793`, preserving a paused participant turn) and `clearMessages` (`:8905`). It
is **not** a turn destructor, which is why `AskUserQuestionTurnCache` above is
misfiled by anyone reading its `clear()` as turn teardown — as this inventory
initially did.

### E — 25 tombstone sets

Across 20 files:

```
_retiredOwners ×10   _knownOwners ×4   _terminalOwners ×3
_pollingOwners   _clearedOwners   _observedOwners   _terminatedOwners
_replayedOwners  _forcedCompactionOwners   _ownerTombstones   _retired
```

**Every one of these exists to answer a question an object identity would answer
for free**: "is this owner still the live one?" Because a turn has no object
whose disposal is observable, each collaborator keeps its own monotonic record
of owners it has finished with, and each is a permanent growth surface — none is
ever pruned.

This is the largest single category in the inventory and it is **pure
compensation for the missing middle level** identified in
`docs/chat_notifier_renewal_root_cause_findings.md`. Under codex's arrangement
these are not smaller; they do not exist. `turn_state_for_sub_id` returning
`None` *is* the tombstone.

## Alias: two objects, one mutable map

`RuntimeTurnEventPublisher._handlesByGeneration` is not a store. It is
`ChatNotifier._runtimeTurns`, passed by reference at `chat_notifier.dart:360`:

```dart
final _runtimeTurns = <int, CavernoRuntimeTurnHandle>{};
late final _runtimeEvents = RuntimeTurnEventPublisher(_runtimeTurns);
```

Two objects held the same mutable map with no stated ownership rule. Nothing was
broken by it — the publisher only reads — but it was the one place in the
inventory where the authority question had no answer at all.

**Resolved.** `RuntimeTurnEventPublisher` now wraps what it is given in an
`UnmodifiableMapView`, so the notifier keeps ownership and a write added to the
publisher fails to compile rather than racing the turn lifecycle.

## What this means for the pilot

**For a `ThreadRuntime`:** patterns B (8) and the singular half of C are the
direct beneficiaries — roughly 15 fields gain one home instead of two or none.
Patterns A and A′ show the target shape already exists and works five times
over, which lowers the design risk from "unproven here" to "generalise the ones
we have."

**For an `ActiveTurnScope`:** pattern E is the prize. 25 monotonic sets across
20 files collapse to an identity check, and they are the category that most
resembles the defects on record — the stranded active-response registration
(`e59fe248`) and cross-thread tool-result contamination are both "an owner that
should have stopped being current." But they are spread across 20 collaborator
files in three layers, so retiring them is not one slice.

**Against both:** pattern D is 37 maps whose scope must still be determined one
at a time, and the removal-path table shows why — two of six sampled outlive the
turn deliberately. That cost is unchanged by the target shape. It is the
property of the existing code that the root-cause document already conceded.

### Two candidate pilots

**P1 — unify the destructors. Done** (`refactor/unify-turn-destructors`, three
commits). Entirely inside the notifier library, no new object, no collaborator
registrations. Preferred first not because it was more valuable — P2 tests the
actual hypothesis — but because it fixes the *instrument*: while a turn was torn
down through two differently-keyed paths, any claim that a thread object
simplified teardown could not be attributed, and the comparison this renewal has
already got wrong twice would have run against a moving baseline.

**P2 — one thread's worth of pattern B.** Give the **8** genuinely homeless
stashed fields a per-thread object modelled on `ThreadScopedMessageQueue`, so
authority stops flipping with visibility. Working precedent in the same codebase
five times over (pattern A four times, A′ once), no dependency on retiring
tombstones.

Measured blast radius: **78 write sites**, 66 of them in `chat_notifier.dart` —
7 plan/workflow drafting fields (68) plus `participantTurnRuntime` (10). The ten
pending approvals are *not* in scope; they are already A′.

#### Half of those writes bypass thread routing

Of the 78, **39 were inside a thread router** (`_routeThreadState`,
`_routeApproval`, `routeToThread`) and **38 were not** — bare
`state = state.copyWith(…)` against whatever thread is visible. Seven of the
unrouted have since been routed; see below.

That split is the concrete form of the pattern-B cost. A routed write knows
which thread it belongs to; an unrouted one cannot, because `ChatState` does not
carry a thread. Under a per-thread object the distinction disappears: there is
no visible-state shortcut to take.

#### The unrouted half held a real defect

`generateWorkflowProposal` and `generateTaskProposal` — both reachable from the
plan UI (`chat_page_workflow_builders.dart:119`, `:661`), neither covered by any
test — captured `currentConversation` for their *requests* and then wrote the
result with a bare `state = state.copyWith(…)` after awaiting the model, guarded
only by `ref.mounted`. **Switching threads while either drafted put the draft on
the thread the user switched to, and left the drafting thread spinning.**

Reproduced and fixed (`5434d4ee`, `ef82d062`). Every write now routes to the
captured thread, including the retry loop inside `_requestWorkflowProposal`.
`resolveWorkflowDecision` deliberately keeps its direct assignment: it answers
what the user is looking at.

Reproducing it took the shared harness. `_PlanProposalDataSource` fires its hook
on the first `createChatCompletion` and counts every completion together, but
this path needs a prior turn to satisfy a positive interaction generation — so
the opening turn consumed the hook the drafting request needed. Splitting
`createChatCompletion` onto its own script in `ScriptedChatDataSource` is what
made the two separable. That is the second capability gap the harness closed
under load, after the final-answer script.

**This is the pattern-B cost, priced.** Two entry points, same feature, one
routed and one not, and nothing in the type system distinguished them —
`ChatState` does not carry a thread, so an unrouted write cannot be told from a
correct one by reading it. A per-thread object removes the choice rather than
requiring every writer to make it correctly.

#### After the fix: 38 unrouted writes became 11, and all 11 are correct

Re-measured on the fixed tree. The remaining eleven were read individually:

| Site | Verdict |
| --- | --- |
| `conversation_drawer.dart` (2) | a `ref.watch(select(…))` **read**, not a write |
| `dismissWorkflowProposal`, `dismissTaskProposal` (6) | the user dismissed the visible draft |
| `resolveWorkflowDecision` (1) | the user answered the visible decision |
| `_cancelStreaming` (2) | targets `_activeResponseGenerationForConversation(conversationId)`, the visible thread |

The pre-fix 39/38 split was stable across 12-, 14- and 20-line lookback windows,
so it was not a measurement artefact; the post-fix count is window-sensitive
only because routed writes are multi-line callbacks.

`test/quality/thread_scoped_draft_write_contract_test.dart` now pins this:
every direct `state` write naming one of the eight must come from a method
where the visible thread is the subject, and a second check fails if an allowed
name stops writing them, so the exemption list cannot widen unnoticed.

**This weakens the case for the pilot rather than strengthening it.** With the
defect fixed and a gate holding the invariant, a per-thread object for these
eight buys structure, not correctness. It should be justified on its own terms
— or deferred.

**Net:** the inventory supported P1, which is now done. **P2 is no longer
recommended as the next slice** — see below. It does not support a pilot that
tries to absorb D or E.

### P2 was attempted and should now be deferred

Starting P2 produced three things, none of them the pilot:

1. The scope was wrong — pattern B is 8 fields, not 18 (above).
2. The unrouted half held a **real, reproduced defect** in two UI-reachable
   drafting entry points, now fixed.
3. A contract gate holds the invariant the pilot would have enforced
   structurally.

That sequence inverts the argument. The pilot's case was "these fields have no
home, so writers must each decide correctly and nothing checks them." The
second clause is now false: something checks them, cheaply, and it caught a
regression under mutation. What remains is that eight fields are stashed rather
than owned — a shape complaint, not a behaviour one.

**Recommendation: do not build the per-thread object for these eight now.** Its
value was to make a class of defect unrepresentable; the class has one known
member, it is fixed, and it is fenced. Revisit if the gate starts firing, if the
eight grow, or if `participantTurnRuntime` — the one field with a genuine
read-modify-write cycle — produces a defect the gate cannot see.

Pattern **C** has since been examined: the `goalAutoContinue*` trio and the
usage counters both turned out correct, for different reasons (see *Open
questions*). What remains unexamined is pattern **E** — 25 tombstone sets across
20 files, the largest category in the inventory and the one whose defects are
already on record.

### What P1 cost, measured

Recorded because the renewal's cost case has been wrong twice, both
optimistically, and this is the first estimate made after the fact rather than
before.

| | |
| --- | --- |
| Production diff | one part file plus one method in `chat_notifier.dart` |
| Governance amendments | 3 (ratchet budget, AST teardown contract, obligations list) |
| New tests | 1 assertion on an existing start-failure scenario, 1 contract rule |
| Ratchet | +47 lines, all comment or registration; the legacy function shrank |

Three governance amendments against seven for the earlier 66-line slice. The
difference is what the root-cause document predicted: this touched no part
classification and registered no collaborator, because nothing moved across the
decomposition boundary — it moved between two things already inside it.

**One caveat on the evidence.** The stranded-scope `finally` added by the first
commit is not covered: mutating it away leaves the suite green, because nothing
between registration and return throws in practice. It is kept deliberately and
labelled as untested in both the code and the ratchet note. The six moved
releases *are* covered — dropping one is caught by both the contract test and
the behavioural teardown report.

## Open questions, with the test that settles each

*(None outstanding.)* The three questions this section opened are all closed
below and under *Alias*.

### Closed: the `goalAutoContinue*` fields are correctly visible-scoped

They reset on switch because **the feature itself does not run for a
non-visible thread**. `_applyTurnRuntimeGoalUiEffect` is gated by
`_isGoalAutoContinueOwnerCurrent`, which is
`TurnRuntimeOwnerLeaseRegistry.isConversationCurrent` — true only when the
conversation is *both* the visible and the selected one — and the dispatch that
produces the effect is guarded by the same predicate twice more
(`chat_notifier_goal_auto_continue.dart:598`, `:600`). There is no background
progress to preserve, so there is nothing for a switch to lose.

The tracker behind it *is* per-thread
(`GoalAutoContinueTrackerRegistry._trackers`, keyed by conversation id), which
is what made this look like a missing restore. It is not: the projection is
absent because the source never fires.

> **A larger product question falls out of this, and it is not mine to
> answer.** Goal auto-continue **halts when the user opens another thread**, and
> resumes only on return. That is a deliberate gate, not an oversight — it is
> checked in three places — but it sits against the standing thread-independence
> direction, and no test in
> `chat_notifier_goal_auto_continue_part.dart` switches threads at all, so the
> behaviour is unpinned either way. Every existing assertion there reads
> `goalAutoContinueCount == 0`; nothing ever observes a running indicator.

### Closed: the usage counters are correct, and degrade rather than blank

`_updateTokenUsage` already guards `owner.conversationId == conversationId`
(`chat_notifier_response_finalization.dart:18`), so a background turn never
writes them — no contamination. They hold the **last response's** usage, not a
running total.

Losing them on switch is covered by a fallback the inventory had not read:
`TokenUsageIndicator._contextUsageTokenCount()` falls through
`promptTokens` → `estimatedPromptTokens` → `estimatePromptTokens(messages)`,
and the messages *are* restored. Per-message metrics are persisted too
(`MessageResponseMetrics` on `Message`), so the authority survives the switch
even though the summary is recomputed rather than restored.

Both questions were drafted as suspected defects and both were disproved by
reading the code that consumes the fields, not just the code that writes them —
the same mistake that made pattern B look like 18 fields.

**Closed by this inventory:** whether `ChatState.pendingAskUserQuestion` is
lossy on switch. It is not — `_pendingAskUserQuestionsByThread`
(`chat_notifier.dart:2356`) is the per-thread authority and `syncConversation`
restores from it at `:816`. This was drafted here as a suspected defect and
disproved by reading the switch path.
