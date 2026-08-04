# ChatNotifier TurnRuntime Phase 1.5 Decision

## Decision

**Go to Phase 2 design for the TurnRuntime renewal. Do not begin broad Phase 3
extraction yet.**

**Amended 2026-08-04.** Review question 6 was re-asked with the evidence the
prototype produced, and the renewal's goal narrowed from seven capability
boundaries to the turn destructor. See
`docs/chat_notifier_renewal_question_six_review.md`. The block on broad Phase 3
extraction stands; **one measured slice** on
`chat_notifier_execution_runtime.dart` is authorized under the terms recorded
there, and the re-evaluation after it decides whether anything follows. The
Phase 2 design document is not a prerequisite for that slice and is not being
written: two of its five sections were overturned by measurement, and the slice
produces the number the rest of it needs.

The bounded production prototype passed every structural and behavior gate.
It therefore supports the diagnosis that an owner-scoped composition root can
replace notifier identity plumbing without increasing ambient reads or
capturing `ChatNotifier` in callbacks.

Production `ChatToolHandlerCatalog` wiring remains **No-Go**. The prototype
proved one selected boundary, not the six catalogue binding groups. Catalogue
work may re-enter only after I2 maps those groups to explicit ports and the
existing WS6-19 no-capture, binding, fallback, and poison gates pass.

## Evidence

| Gate | Result | Evidence |
| --- | --- | --- |
| Identity parameter removal | Pass locally; see addendum | One explicit owner or generation parameter removed. Across the boundary the count rises by 14 once the runtime is in audit scope |
| Ambient reads | Pass | Turn-reachable delta `-1`, confirmed with the boundary in scope |
| Notifier capture | Pass | Zero new callbacks capture `ChatNotifier` |
| State ownership | Pass | Conversation and thread state remain outside `TurnRuntime` |
| Focused behavior | Pass | Selected goal auto-continue dispatch test passed |
| Repository verification | Pass | Analysis clean; 6,638 tests passed; 79.39% line coverage |
| Live behavior | Pass | Clean `fc12a1f2`; 1/1 passed; readiness `ready`; two continuations; diagnostics `2 -> 1` |

The formal comparison covers 15 production files and reports `+708` lines,
one introduced port method, two clock callback surfaces, and 19 public
declarations. The selected source at comparison base `0bac2bc0` is
byte-identical to the validated pre-squash selector source.

## Addendum: re-measurement after widening the audit scope

Added 2026-08-04. The gates above were measured while the prototype boundary sat
outside both governance instruments. The turn-scope audit reads the notifier
library, its parts, and manifest-declared collaborators;
`lib/features/chat/application/runtime/` held no collaborator marker and no
manifest entry, and the file-size ratchet is an allow-list that new files do not
join by default. `scannedFiles` stayed at 112 across the prototype.

Six boundary files are now registered as collaborators of the
`goal-auto-continue` part, which the boundary test also requires to carry
declared size budgets. Two files are deliberately not registered —
`turn_runtime_goal_safe_boundary_adapter.dart` and
`conversations_notifier_goal_runtime_store.dart` import provider libraries, so
they fail the collaborator import rules. That is the correct answer: they are
the notifier-side glue, not the boundary.

Re-measured against the pre-prototype baseline:

| Metric | Pre | Post, original scope | Post, boundary in scope |
| --- | ---: | ---: | ---: |
| `scannedFiles` | 112 | 112 | 118 |
| Turn-reachable ambient reads | 50 | 49 | **49** |
| Identity parameters | 314 | 312 | **328** |
| `reachableMethods` | 663 | 686 | 717 |

**The ambient-read gate holds.** `-1` survives the wider scope: the new layer
introduced no ambient reads. That result is now measured over the whole
boundary rather than one side of it.

**The identity-parameter gate inverts.** The recorded "one parameter removed" is
true locally, but across the boundary the count rises by 14. Attribution:

```
+8  application/runtime/turn_runtime.dart
+5  application/runtime/turn_runtime_goal_tracker_adapter.dart
+1  application/runtime/turn_runtime_conversation_goal_adapter.dart
+1  application/runtime/turn_runtime_owner_lease_registry.dart
+1  presentation/providers/turn_runtime_production_composition.dart
+1  presentation/providers/chat_notifier_goal_auto_continue.dart
+1  domain/services/goal_update_tool_handler.dart
-4  presentation/providers/chat_notifier_ask_user_question.dart  (unrelated slice)
```

The boundary itself accounts for `+16`. The selected part gained one rather than
shedding any.

The cause is structural, not incidental: every port takes the owner as an
argument — `isCurrent(owner)`, `conversationFor(owner)`, `snapshotFor(owner)`,
`applyDelta(owner, …)`, `markBudgetNoticePresented(owner)`,
`clearPendingRepairContract(owner)`, `removeTracker(owner)`, `capture(owner)`.
`TurnRuntime` holds `owner` as a field and re-supplies it on every call, so
identity plumbing was re-typed and relocated rather than removed. The codex
reference binds the owner into the turn's state and its ports do not re-take it
(`docs/turn_runtime_codex_reference_findings.md`).

This does not overturn the Go decision — the boundary is achievable, behaviour
is preserved, and no callback captures `ChatNotifier`. It changes what Phase 2
must design. **Owner-implicit ports become the first design question**, because
at seven capability boundaries an owner-parameterised port set multiplies the
plumbing the renewal exists to remove.

The checked-in `tool/chat_notifier_turn_scope_baseline.json` was deliberately
not refreshed at the time. Regenerating it then would have adopted `+14` as the
accepted floor. It is refreshed below, after the owner-implicit result removed
that increase.

## Addendum: the owner-implicit port answer

Added 2026-08-04. The design question above was settled by experiment rather
than argument, because the audit can only measure real signatures.

The five goal-continuation ports were converted from owner-parameterised to
owner-bound: each is created for one owner by
`TurnRuntimeGoalContinuationPortsFactory` and none re-takes the owner per call.

| Metric | Pre-prototype | Owner-parameterised | Owner-bound |
| --- | ---: | ---: | ---: |
| Identity parameters | 314 | 328 | **317** |
| Turn-reachable ambient reads | 50 | 49 | **49** |

The boundary's identity cost falls from `+14` to `+3`, and the ambient-read
improvement is unchanged. The three that remain are the two binder declarations
and `TurnRuntimeProductionComposition.create` — identity entering the boundary
once per turn, which is the intended shape and matches the codex reference.

Cost: `+36` production lines against the owner-parameterised shape. Both files
the size ratchet actually guards shrank (`chat_notifier.dart` 8907 → 8905, the
composition 95 → 88). Four budgets on the two-day-old boundary files were raised
once, with the reason recorded in the budget map.

**This is a Phase 2 design decision reached by experiment, not the start of
Phase 3.** Phase 3 slicing still waits on the design document, whose reuse and
public-surface matrix should now be written against owner-bound ports.

## Turn-scope baseline refresh

Refreshed 2026-08-04, after the drift was explained rather than to make the gate
green. Every delta is accounted for:

| Metric | Old baseline | Refreshed | Cause |
| --- | ---: | ---: | --- |
| `scannedFiles` | 112 | 119 | The seven boundary files are now declared collaborators |
| `methods` | 1411 | 1459 | Those files' methods entered scope |
| `reachableMethods` | 663 | 717 | Reachability through the same files |
| `manifestEntrypoints` | 269 | 263 | The goal auto-continue part shed entrypoints as behaviour moved into `TurnRuntime` |
| `turnReachableReads` | 50 | 49 | The measured improvement |
| `methodsWithAmbientReads` | 40 | 39 | Same |
| `ambientReads` | 67 | 67 | Unchanged |
| `accessorBearingReads` | 41 | 41 | Unchanged |
| `methodTurnIdentityReads` | 26 | 26 | Unchanged |
| Identity parameters | 314 | 317 | The two binders and `create`, where identity enters once per turn |

**Expected:** yes. Two causes only — the deliberate scope widening, and the
improvement it was widened to measure. Nothing is unexplained.

**Which open work caused it:** the Phase 1.5 prototype and the owner-implicit
port decision recorded above. No deferred workstream contributed.

**Resulting source of truth:** `tool/chat_notifier_turn_scope_baseline.json` at
119 scanned files. Phase 2 slices measure against it, and a slice that raises
identity parameters or turn-reachable reads above these numbers is a regression
to explain rather than a baseline to refresh.

```bash
fvm dart run tool/audit_chat_notifier_turn_scope.dart \
  --manifest tool/chat_notifier_decomposition_manifest.json \
  --check-baseline tool/chat_notifier_turn_scope_baseline.json
```

## Cost Review

The structural result is positive, but the prototype is not yet an economical
template. A `+708` production-line delta and 19 public declarations for one
removed identity parameter is a high local cost. Phase 2 must therefore treat
the prototype as boundary evidence, not as a pattern to replicate mechanically.

Before Phase 3, the design must:

1. identify which prototype ports are reusable by at least one additional
   selected concern or catalogue binding group;
2. set an explicit public-surface budget and justify every exported type;
3. split execution into independently reversible, behavior-preserving slices;
4. retain comparison, coverage, and live-canary gates for each load-bearing
   turn path; and
5. define a stop condition if later slices add identity plumbing or notifier
   capture instead of removing it.

## Live Attribution

The post-prototype live canary exercised the migrated path and passed its
contract. It recorded two ordered continuations and diagnostic progress from
two unresolved diagnostics to one. The model did not reach terminal verifier
success and stopped with `post-verification repair was not revalidated` after
repeated unchanged reads. This matches the bounded model-repair variance
identified before the prototype; it is not evidence of a TurnRuntime ownership
or reentrancy regression.

## Next Action

Write the Phase 2 design document. Its first deliverable is a reuse and
public-surface matrix for the seven prototype capability boundaries, joined to
the I2 catalogue groups without wiring the catalogue. No additional production
extraction is authorized by this decision alone.
