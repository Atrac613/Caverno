# TurnRuntime Slice 0: Concern-Two Probe

Read-only. Run 2026-08-04 at `4384a5f8`, clean worktree. No production file was
edited. Its purpose is the one datum the Phase 2 draft could not supply: how much
of a second concern the existing boundary already covers.

## Selection

```bash
python3 tool/measure_chat_notifier_turn_runtime_prototype.py select \
  --audit tool/chat_notifier_turn_scope_baseline.json \
  --manifest tool/chat_notifier_decomposition_manifest.json \
  --source-revision HEAD --require-clean --output <path>
```

| Rank | Part | Identity entrypoints | Turn-reachable ambient reads | Lines |
| ---: | --- | ---: | ---: | ---: |
| 1 | `chat_notifier_goal_auto_continue.dart` | 11 | 0 | 790 |
| 2 | **`chat_notifier_turn_finalization_recovery.dart`** | 9 | **2** | 286 |
| 3 | `chat_notifier_subagent_handlers.dart` | 7 | 0 | 354 |
| 4 | `chat_notifier_tool_loop_batch.dart` | 5 | 0 | 749 |

**The selector re-picks the already-migrated part.** It has no notion of prior
migration, so rank 1 is the goal concern again, now at 11 identity entrypoints
instead of 13 — it is measuring the residue of its own first slice. Concern two
is rank 2 by the selector's own ranking, and reading past rank 1 is a manual
step the tool does not support.

Rank 2 is also the first candidate with **non-zero turn-reachable ambient
reads**. The first prototype scored zero on that key, so the second ranking key
has never actually been exercised. Concern two tests the diagnosis on ground the
first slice never touched.

## Dependency inventory

`chat_notifier_turn_finalization_recovery.dart` declares 13 private members and
references **16** declared elsewhere, plus the inherited `ref` and `state`.

| Disposition | Count | Members |
| --- | ---: | --- |
| **Owner- or generation-keyed turn state the runtime absorbs** | **6** | `_activeResponseMessagesForGeneration`, `_isActiveResponseDetachedForGeneration`, `_lastStreamedToolResultFinalAnswersByGeneration`, `_turnFinalizationRecoveryGenerations`, `_turnEnd` (`TurnFinalizationStateRegistry`, `Map<ChatTurnOwner, …>`), `_turnToolResults` (`TurnToolResultLedger`) |
| Covered by the existing boundary | 2 | `_isCurrentInteractionGeneration` → `TurnRuntimeOwnerLeasePort.isCurrent`; `_turnOwnerForGeneration` → eliminated, the runtime *is* the owner |
| Needs no port — const domain services and pure helpers | 5 | `_claims`, `_fileMutationEvidencePolicy`, `_hasTimedOutCommandResult`, `_toolResultsContainFailedCommandValidation`, `_codingContinuationRecoveryCode` |
| Needs a new port | 3 | `_settings`, `_mcpToolService`, `_requestCodingContinuationRecovery` |

## What this changes

The Phase 2 draft projected cost from **port reuse**: one port of five is
generic, so seven boundaries look "closer to linear than to a shared framework."
That projection stands on its own terms — concern two reuses exactly one port
and needs three new ones.

**But port reuse is the wrong measure of value, and the draft's §1 leans on it
too heavily.** What the renewal exists to remove is turn-local state held in
generation-keyed maps at notifier scope. Measured that way:

| | Goal continuation (slice 1) | Turn finalization recovery (slice 2) |
| --- | ---: | ---: |
| Owner/generation-keyed stores absorbed | **1** (`_isSchedulingGoalAutoContinue`) | **6** |
| Existing ports reused | — | 1 |
| New ports needed | 5 | 3 |
| Turn-reachable ambient reads | 0 | 2 |

Concern two absorbs six times the turn-local state on a part barely a third the
size, and needs fewer new ports than the first concern did. The first slice was
the expensive one *because it was first* — it paid for the binder machinery, the
factory, the lifecycle and the effect vocabulary, none of which recurs.

So the linear-cost projection is probably pessimistic, and it is pessimistic for
a specific reason: it counted the wrong thing. The draft's §1 OPEN should be
re-framed before it is decided.

## Correction, same day: the re-ranking was run

The option below was proposed on the reasoning that the selector had chosen a
part with little absorbable state. **That reasoning is wrong**, and the check it
proposed is what shows it.

Re-ranking all 37 declared parts by the count of distinct notifier-level
turn-local stores each touches — 39 such stores exist, found by name
(`*ForGeneration`, `*ByGeneration`, `*Generations`), by collection key
(`Map<int,`, `Set<int>`, `Map<ChatTurnOwner,`), and by resolving each registry
field to its own owner-keyed class:

| New rank | Current rank | Part | Stores | Lines |
| ---: | ---: | --- | ---: | ---: |
| 1 | 7 | `chat_notifier_execution_runtime.dart` | 10 | 197 |
| 2 | 1 | `chat_notifier_goal_auto_continue.dart` | 8 | 790 |
| 3 | 19 | `chat_notifier_response_finalization.dart` | 8 | 227 |
| 4 | 2 | `chat_notifier_turn_finalization_recovery.dart` | 7 | 286 |
| 5 | 4 | `chat_notifier_tool_loop_batch.dart` | 6 | 749 |

**The goal part touches eight turn-local stores — tied for the most.** The
selector did not choose a part poor in absorbable state. The first slice
absorbed one store because the port matrix deliberately narrowed the reserved
path to two symbols and a 10-member dependency trace, on the explicit ground
that moving all 26 dependencies "would silently turn a bounded diagnostic into a
complete extraction of the selected part."

So the cause of the thin first slice was **slice scoping, not selection**. The
claim above that "the first slice was the weakest candidate available" is
withdrawn: it confused what a part offers with what a slice took.

Two findings survive the correction:

- **The rankings largely agree.** Three of the current top four stay in the new
  top five. Only `chat_notifier_subagent_handlers.dart` moves sharply, from
  current rank 3 to new rank 22 on one store. Re-keying the selector would not
  have changed the program's direction.
- **The new key does surface a denser candidate.**
  `chat_notifier_execution_runtime.dart` touches ten stores in 197 lines, against
  the goal part's eight in 790. Density, not rank order, is what the current key
  misses.

## Effect on the §1 OPEN

The draft asked whether to accept per-concern ports (a) or generalise the
reusable ports first (b). Neither is now the leading answer:

**(c) Continue per-concern, and widen the slice rather than re-key the
selector.** The re-ranking above shows the selection was sound and the scoping
was not: the goal part offered eight absorbable stores and the slice took one.
The lever is how much of a part's turn-local state a slice is allowed to absorb,
not which part is chosen.

That leaves a real tension the Phase 2 design must resolve, and it is the
port matrix's own: a slice narrow enough to stay a bounded diagnostic absorbs
almost nothing, and a slice wide enough to absorb meaningfully becomes a full
extraction of the part. The first slice sat at one end. Nothing measured so far
says where the middle is.

**Density is the usable addition to the selector.** Stores per production line
would rank `chat_notifier_execution_runtime.dart` first (10 stores, 197 lines)
over the goal part (8 stores, 790 lines). A denser part lets a slice absorb more
state per line of diff, which is the quantity a bounded slice is actually
trading against.

## Limits

- The 16-member inventory is a reference scan of the whole part, not a reserved-
  path trace. The first concern's matrix showed a reserved path reaching 10 of
  26; concern two's reserved path will be a subset of 16, not all of it.
- No live gate exists for turn finalization recovery. Under the Phase 2 gate
  rules a slice here needs one, or an explicit statement that none exists.
- Nothing here authorizes production editing.
