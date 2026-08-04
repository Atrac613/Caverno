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
| **B** | Visibility-flipping stash | **flips**: `ChatState` while visible, `ThreadScopedChatState` while not | never — it moves | 18 | `ChatState` field |
| **C** | Singular `ChatState` field, no per-thread home | `ChatState` | overwritten by the next thread | 19 | `ChatState` field |
| **D** | Owner-keyed registry; `ChatState` mirrors it | the registry | turn teardown, or a retention window | 37 | keyed store |
| **E** | Tombstone set (negative state) | nothing — records absence | never (monotonic) | 25 | keyed store |

B + C = 37 `ChatState` fields; D + E = 62 keyed stores. The two 37s are
unrelated — one counts fields on one class, the other counts stores across
`lib/`.

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

### B — authority that moves with the camera

`ChatState` declares **37** fields. `ThreadScopedChatState` stashes **18**. For
those 18, the authoritative copy is `ChatState` while the conversation is
visible and the stash while it is not; `ThreadScopedChatState.from(state)`
copies one into the other on switch.

This is not a bug — it is consistent, and the switch path is covered. It is a
*cost*: every reader of those 18 fields must know which side of the switch it is
on, and that knowledge is not expressible in the type. A `ThreadRuntime` removes
the flip by giving the field one home regardless of visibility.

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

Two objects hold the same mutable map with no stated ownership rule. Nothing is
currently broken by it — the publisher only reads — but it is the one place in
the inventory where the authority question has no answer at all, and it should
be resolved (publisher takes a read-only view) independently of any pilot.

## What this means for the pilot

**For a `ThreadRuntime`:** patterns B (18) and the singular half of C are the
direct beneficiaries — roughly 25 fields gain one home instead of two or none.
Pattern A shows the target shape already exists and works, which lowers the
design risk from "unproven here" to "generalise the one we have."

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

**P2 — one thread's worth of pattern B.** Give `ThreadScopedChatState`'s 18
fields a per-thread object modelled on `ThreadScopedMessageQueue`, so authority
stops flipping with visibility. Bounded field list, working precedent in the
same codebase four times over (pattern A), no dependency on retiring tombstones.
*Blast radius is every reader of those 18 fields, which is larger than any slice
so far.*

**Net:** the inventory supported P1, which is now done, and supports P2 next. It
does not support a pilot that tries to absorb D or E.

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

1. **Do the `goalAutoContinue*` fields belong to the thread or the app?**
   Three fields reset on switch, while the goal coordinator is explicitly
   conversation-spanning. A budget that resets when the user looks at another
   thread is either a bug or an intended per-view display; the code does not say
   which.
   *Test:* start goals on two threads, switch between them, assert budget
   accounting neither cross-contaminates nor silently refills.

2. **Should the usage counters survive a switch?** `promptTokens`,
   `completionTokens`, `totalTokens`, `estimatedPromptTokens` reset to zero on
   arrival, so a thread with a completed turn displays no usage after a
   round trip.
   *Test:* run a turn on thread A, switch to B and back, assert A's displayed
   usage is what A actually consumed.

3. **Who owns `_runtimeTurns`?** See *Alias* — resolvable without a pilot.

Neither 1 nor 2 is claimed here as a defect; both are places where the inventory
found singular state serving a multi-thread product, which is the condition
under which the previously confirmed contamination class arose.

**Closed by this inventory:** whether `ChatState.pendingAskUserQuestion` is
lossy on switch. It is not — `_pendingAskUserQuestionsByThread`
(`chat_notifier.dart:2356`) is the per-thread authority and `syncConversation`
restores from it at `:816`. This was drafted here as a suspected defect and
disproved by reading the switch path.
