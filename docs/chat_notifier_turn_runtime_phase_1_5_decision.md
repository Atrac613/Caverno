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
| Identity parameter removal | Pass | One explicit owner or generation parameter removed |
| Ambient reads | Pass | Turn-reachable delta `-1` |
| Notifier capture | Pass | Zero new callbacks capture `ChatNotifier` |
| State ownership | Pass | Conversation and thread state remain outside `TurnRuntime` |
| Focused behavior | Pass | Selected goal auto-continue dispatch test passed |
| Repository verification | Pass | Analysis clean; 6,638 tests passed; 79.39% line coverage |
| Live behavior | Pass | Clean `fc12a1f2`; 1/1 passed; readiness `ready`; two continuations; diagnostics `2 -> 1` |

The formal comparison covers 15 production files and reports `+708` lines,
one introduced port method, two clock callback surfaces, and 19 public
declarations. The selected source at comparison base `0bac2bc0` is
byte-identical to the validated pre-squash selector source.

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
