# Execution Runtime Port Matrix

Read-only. Produced 2026-08-04 at `7d066ee9`. No production file was edited.

`chat_notifier_execution_runtime.dart` is the densest candidate the Slice 0
re-ranking found: 197 production lines and more turn-local state per line than
any other declared part. This matrix exists
to price a *wide* slice against the *narrow* one already executed, which is the
question the Phase 2 draft cannot answer from what has been measured so far.

## Dependency classification

The part declares 14 private members and references **19** declared elsewhere,
plus the inherited `ref` and `state`. Each external member was classified by
resolving its declaration and, for registries, the key type of its own storage —
then, for every owner-keyed store, by matching it to the teardown step that
destroys it. The second check changed one classification.

| Disposition | Count | Members |
| --- | ---: | --- |
| **Owner- or generation-keyed turn state the runtime absorbs** | **8** | `_activeResponseRegistry`, `_contentToolTurns`, `_goalCompletionEvidence`, `_responseMetadata`, `_toolApprovalCache`, `_runtimeEvents`, `_runtimeTurns`, `_turnEnd` |
| **Owner-keyed but deliberately outlives the turn — needs a port** | **2** | `_turnToolResults` (10-minute retention, no destructor touches it); `_hiddenAssistantEvidence` (`publish` closes writes and starts a retention window instead of removing the entry) |
| Ambient turn identity, eliminated by the owner-bound shape | 1 | `_runtimeEventGeneration` — reads `TurnGeneration.current`, becomes `owner.interactionGeneration` |
| Covered by the existing boundary | 1 | `_isCurrentInteractionGeneration` → `TurnRuntimeOwnerLeasePort.isCurrent` |
| Needs a new port | 7 | `_backgroundProcessMonitorService`, `_executionRuntime`, `_mcpToolService` (all `ref` reads), `_conversationTaintState`, `_fileMutationRuntime`, `_pythonScriptRuntime`, `_clearSshOwner` |

Each of the ten owner-keyed stores was then checked against the two teardown
functions, which is what proves turn scope rather than merely suggesting it:

| Store | Torn down in |
| --- | --- |
| `_contentToolTurns`, `_goalCompletionEvidence`, `_toolApprovalCache`, `_runtimeEvents`, `_runtimeTurns`, `_turnEnd` | `_terminalizeRuntimeTurn` |
| `_activeResponseRegistry`, `_responseMetadata` | `_clearActiveResponseForGeneration` |
| **`_turnToolResults`** | **neither — read only** |
| **`_hiddenAssistantEvidence`** | **`publish`ed, not disposed — retained** |

## Narrow versus wide, priced

| | Slice 1, executed | This part, whole-part slice |
| --- | --- | --- |
| Part size | 790 lines | **197 lines** |
| Scope taken | reserved path: 2 symbols, 10 of 26 dependencies | whole part: 19 dependencies |
| Turn-local stores absorbed | **1** | **8** |
| Ambient identity reads eliminated | 0 | 1 |
| Existing ports reused | — | 1 |
| New ports needed | 5 | 9 |
| Production line delta | `+708`, later corrected to `+36` by owner binding | unmeasured |

The comparison is not like-for-like and should not be read as one: slice 1 also
paid for the binder machinery, the ports factory, the lifecycle and the effect
vocabulary, none of which recurs. What it does show is the shape of the trade.
A wide slice on this part absorbs **eight times** the turn-local state for
**four** additional ports, on a part **a quarter** the size.

That is the strongest available argument that the narrow-slice discipline, not
the port design, is what made slice 1 expensive per unit of progress.

## The finding that came out of resolving it: this part owns the turn destructor

Tracing `_toolApprovalCache` led somewhere more useful than the answer.

`_terminalizeRuntimeTurn` (`chat_notifier_execution_runtime.dart`, reached from
two call sites in the same part) performs **ten** owner-scoped teardown steps —
`_runtimeEvents`, `_pythonScriptRuntime`, `_fileMutationRuntime`,
`_backgroundProcessMonitorService`, `_conversationTaintState`,
`_toolApprovalCache`, `_hiddenAssistantEvidence`, `_contentToolTurns`,
`_turnEnd`, `_goalCompletionEvidence` — and then calls
`_clearActiveResponseForGeneration`, which performs **eleven** more,
generation-scoped.

**The turn's destructor is roughly 21 manual steps across two chained
functions, and this part owns the first of them.** The renewal plan's diagnosis
named exactly this: turn-local state simulated at notifier scope, where every
new piece of turn state adds a line someone must remember to write.

That reframes what a slice here is worth. The matrix above prices it as nine
stores absorbed for three extra ports. The stronger reading is that this part is
where "a turn has no object" is most concentrated: it does not merely *touch*
turn-local state, it is *responsible for destroying* it. A runtime that
owned this part replaces the first destructor with dropping the object — the
codex `ActiveTurn` shape from `docs/turn_runtime_codex_reference_findings.md`,
and the one place in the codebase where that substitution is largest.

It also raises the cost of getting it wrong. Absorbing a store whose teardown is
load-bearing, without preserving the teardown, leaks state into the next turn.
The stale active-response registration bug fixed in `e59fe248` shows one missed
release stranding a thread under a spinner. A slice here must prove each of the
21 steps still happens.

## What a wide slice would have to preserve

The five stop conditions in the Phase 2 draft apply unchanged. Two are worth
naming for this part specifically:

- **`_toolApprovalCache` — resolved, and it is turn-scoped.** The concern was
  that approval decisions cached per owner might be consulted after the turn
  ends, making absorption an approval-safety bug. Tracing it settles the
  question the other way: `_terminalizeRuntimeTurn` in this same part calls
  `_toolApprovalCache.clear(owner)` as one step of turn teardown. Its lifetime
  is already the turn's; a runtime that owned the turn would own it correctly.
- **`_turnToolResults` must not be absorbed.** It is the store the same check
  cleared `_toolApprovalCache` of, answered the other way.
  `TurnToolResultLedger` keys by `ChatTurnOwner` like the rest, but it carries a
  `retention` of ten minutes and expires entries on a clock, and neither
  destructor touches it. It is deliberately readable after its turn ends. A
  slice that absorbed it into a runtime dropped at turn end would destroy
  results the system retains on purpose — silently, because nothing reads them
  in the same turn that would fail.

  This is the concrete reason the mechanical classification could not be
  trusted: all ten stores present as `Map<ChatTurnOwner, …>`, and the key type
  is the same for the ones that must stay behind a port.

- **`_hiddenAssistantEvidence` must not be absorbed either.** Found the same
  way, one step later. The destructor calls `publish(owner)`, which stops
  writes and starts a retention window rather than removing the entry;
  `dispose(owner)` exists and is called only on a start failure. Matching the
  destructor's *call sites* classified it as torn down, because the matcher
  treated `publish` as teardown. Only running a turn and reading the store
  afterwards showed otherwise.

- **No live gate covers this part.** The existing canary exercises goal
  auto-continuation. Under the Phase 2 gate rules a slice here needs its own
  live gate, or an explicit recorded statement that none exists. Slice 1's
  lesson was that a green unit suite coexisted with an unreachable feature.

## Correction to the Slice 0 store counts

The store set used for the Slice 0 re-ranking was built by name pattern and
collection-key pattern, and it **missed registries whose keying is only visible
inside their own class**. Resolving each registry field to its class found two
more (`ResponseMetadataRegistry`, `ToolApprovalCache`), for 41 rather than 39.

The re-ranking's order is unaffected at the top, and this part's classification
above is from direct per-member resolution rather than the set, so it stands.
But the Slice 0 table's counts are a lower bound, not exact.

## Not established here

- The line delta of a wide slice. Only production editing produces that, and
  this document does not authorize it.
- Whether the reserved-path subset of this part is smaller than the whole part.
  Slice 1's was 10 of 26; this part's 19 are all reachable from its 11
  entrypoints, so the gap is likely smaller, but that was not traced.
- Nothing further about the nine confirmed stores. Each was matched to the
  teardown step that destroys it, so their turn scope is established by
  construction rather than inferred from a key type.

## Reserved path, traced

Added 2026-08-04 from the audit's AST call graph rather than a hand-written
scan, after a hand-written one resolved 2 of 11 entrypoints and was discarded.

**The manifest declares 11 entrypoints for this part. Three exist.** The other
eight — `_emitRuntimeAssistantContent`, `_emitRuntimeToolLifecycle`,
`_emitRuntimeApprovalRequired`, `_emitRuntimeQuestionRequired`,
`_emitRuntimeWorkflowTransition`, `_emitRuntimeUsage`,
`_runtimeTurnForGeneration`, `_runtimeToolLifecycleState` — are absent from the
codebase entirely. They are historical names left behind when the emit path
moved into `RuntimeTurnEventPublisher`, and the manifest was never updated.

The selector is unaffected: it ranks on resolved audited methods and records
unresolved names separately. But any scope reasoning that read "11 entrypoints"
as real surface — including this document's own opening line, now corrected —
was inflated by nearly four times.

From the three real entrypoints (`_startRuntimeTurn`, `_completeRuntimeTurn`,
`_failRuntimeTurn`):

| | |
| --- | --- |
| In-part methods reached | 5 of 8 |
| Not reached | `_failAllRuntimeTurns`, `_finishStreamedCompletionInBackground`, `_runtimeEventGeneration` |
| **`_terminalizeRuntimeTurn` on the path** | **yes** — the slice's objective is reachable from the declared surface |
| External private method calls | 7 |

The audit's call graph records method calls, not field reads, so the ten
owner-keyed stores do not appear in it. They are reached through
`_terminalizeRuntimeTurn`, which is on the path, so the field inventory earlier
in this document stands.

**Scope consequence.** The slice covers 5 of 8 in-part methods. The three
unreached ones are candidates for staying put, which makes the slice smaller
than "the whole part" — the shape the first slice's port matrix warned about
in the other direction.
