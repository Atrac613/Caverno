# ChatNotifier TurnRuntime Phase 1.5 Decision

## Decision

**Go to Phase 2 design for the TurnRuntime renewal. Do not begin broad Phase 3
extraction yet.**

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

The checked-in `tool/chat_notifier_turn_scope_baseline.json` is deliberately not
refreshed here. Regenerating it would adopt `+14` as the accepted floor, and the
plan requires the drift to be explained and owned before a refresh. That
decision, and the resulting source of truth, remain open.

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
