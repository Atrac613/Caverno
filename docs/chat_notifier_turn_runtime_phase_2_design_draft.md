# ChatNotifier TurnRuntime Phase 2 Design

**Status: draft. Sections marked OPEN are decisions this document does not
make.** Written 2026-08-04 at `f0e32c62`, against the boundary that the Phase
1.5 prototype and the owner-implicit port decision left in production.

The Phase 1.5 decision required five things of this document before Phase 3
extraction is authorized. They are the five sections below. Everything a
measurement can settle is settled here; everything else is marked OPEN with the
information needed to decide it.

## Starting position

| Fact | Value | Source |
| --- | --- | --- |
| Ports | 5, owner-bound | `lib/features/chat/application/runtime/turn_runtime.dart` |
| Binders | 2 | `turn_runtime_goal_continuation_ports_factory.dart` |
| Boundary files | 8, all declared collaborators | decomposition manifest |
| Public declarations | 35 | see §2 |
| Identity parameters | 317 | turn-scope baseline |
| Turn-reachable ambient reads | 49 | turn-scope baseline |
| Live gate | 3 of 4 passing, with an attribution rule | pre-prototype decision |

The baseline is the source of truth: a slice that raises identity parameters or
turn-reachable reads above these numbers is a regression to explain, not a
baseline to refresh.

## 1. Which ports are reusable

The Phase 1.5 cost review asked which prototype ports serve at least one
additional concern or catalogue binding group. Measured against what each port
actually exposes:

| Port | Method | Reuse |
| --- | --- | --- |
| `TurnRuntimeOwnerLeasePort` | `bool get isCurrent` | **Generic.** Pure identity liveness with no goal vocabulary. Every concern needs it, and `SubagentCatalogChildToolExecutionAdapter` already hand-rolls the same check before and after dispatch. |
| `TurnRuntimeGoalSafeBoundaryPort` | `capture()` | **Shape-reusable.** "Snapshot this owner's pending thread state" is generic; the returned `GoalAutoContinueSafeBoundary` is not. A second concern needs the same shape with its own payload type. |
| `TurnRuntimeConversationGoalPort` | `conversation`, `markGoalStatus` | Concern-specific. |
| `TurnRuntimeGoalTrackerPort` | 5 tracker methods | Concern-specific. |
| `TurnRuntimeGoalContinuationLogPort` | `record` | Concern-specific. |

**One port of five is directly reusable, and one more is reusable in shape.**

This is the economic finding Phase 2 has to confront, and it is less favourable
than the renewal plan assumed. The plan's cost case rested on identity
parameters collapsing into `this` as concerns migrate. The owner-implicit
experiment confirmed that happens *within* a concern — but it does not
transfer: concern two arrives with its own ports, its own adapters, and its own
public types, paying the first concern's structural cost again minus one shared
lease port.

The honest projection for seven capability boundaries is therefore closer to
"seven times the goal-continuation cost, less the lease port and the binder
machinery" than to a shared framework that later concerns join cheaply.

**OPEN — the reuse question this raises.** Two answers are available and this
document does not choose:

- **(a) Accept per-concern cost.** Each concern gets its own ports. Predictable,
  independently reversible, and the line cost is roughly linear. Phase 3 becomes
  a long series of small slices.
- **(b) Generalise the two reusable ports first.** Extract
  `TurnRuntimeOwnerLeasePort` and a payload-generic pending-state capture into a
  concern-neutral core, then migrate concerns against it. Higher up-front cost,
  and it risks designing a framework against one known concern.

Deciding needs one datum this document does not have: what concern two's ports
look like. §3 proposes obtaining that cheaply before committing.

**Update — Slice 0 was run, and it contradicts the framing above.** See
`docs/chat_notifier_turn_runtime_slice_0_probe.md`. Concern two reuses one port
and needs three new ones, so the reuse arithmetic here holds. But it absorbs
**six** owner- or generation-keyed stores against the goal concern's one, on a
part a third the size. Port reuse is not the measure of value; turn-local state
absorbed is. A re-ranking run in the same probe then corrected its own
conclusion: the goal part touches eight absorbable stores, tied for the most, so
the selection was sound and the **slice scoping** was what left only one
absorbed. Option (c) survives in amended form — continue per-concern, and treat
slice width rather than part choice as the lever. Read the probe before deciding
between (a) and (b).

## 2. Public-surface budget

Current surface, 35 declarations across 8 files:

| Group | Count | Files |
| --- | ---: | --- |
| Ports | 5 | `turn_runtime.dart` |
| Binders | 2 | ports factory |
| Result and dispatch types | 8 | `turn_runtime.dart` |
| UI effect types | 4 + 1 enum | `turn_runtime.dart` |
| Inputs and value types | 5 | `turn_runtime.dart` |
| `TurnRuntime`, lifecycle | 2 | `turn_runtime.dart` |
| Adapters, stores, composition, scope | 8 | remaining 7 files |

Justification by group:

- **Ports and binders (7)** are the boundary. Each is load-bearing and none can
  merge without restoring an owner argument or hiding a capability.
- **Result and dispatch types (8)** exist because the runtime returns decisions
  instead of performing presentation work. They are the mechanism that keeps
  `ChatNotifier` out of the runtime, and collapsing them re-introduces
  callbacks.
- **UI effects (5)** are a sealed family; the count is the number of distinct UI
  outcomes, not incidental.
- **Inputs and value types (5)** carry immutable per-turn input. One member of
  this group shrank rather than being justified: `TurnRuntimeGoalStatusUpdate`
  carried an `owner` field that nothing read once the port became owner-bound,
  so it was removed. A second copy of the identity could only ever disagree with
  the port's.
- **Adapters and composition (8)** are one file per collaborator, matching the
  repository's existing collaborator convention.

**OPEN — the budget number.** A budget is only meaningful if exceeding it forces
a decision. Three framings, none obviously right:

- **35 as a hard ceiling** for the goal concern, with each later concern
  granted its own budget on the same justification-by-group basis.
- **A per-concern ceiling** (for example "no concern exports more than 5 ports
  and 15 types"), which constrains design rather than counting files.
- **No numeric budget**, replaced by the structural rule already enforced by the
  boundary tests: no `ChatNotifier`, no `Ref`, no callback types, no port that
  takes an owner. That rule has caught real regressions; a count has not yet.

The third is the cheapest and the one the existing gates already implement. The
first is what the Phase 1.5 decision asked for literally.

## 3. Slice plan

Every slice must be independently reversible and behaviour-preserving, and must
report the baseline metrics.

**Slice 0 — concern-two probe (read-only, proposed).** Before choosing between
§1(a) and §1(b), run the mechanical selector against the current tree to pick
the next concern, then produce its port matrix *without editing production*, the
way `docs/chat_notifier_turn_runtime_prototype_port_matrix.md` was produced. The
output is the missing datum: how many of concern two's dependencies the existing
ports already cover. Cost is one analysis pass; it cannot regress anything.

**Slices 1..n — one concern each**, in selector order. Each slice:

1. adds that concern's ports, owner-bound, behind its own binder;
2. moves only the reserved-path symbols the concern's matrix names;
3. leaves conversation- and thread-scoped state outside the runtime;
4. reports identity parameters, turn-reachable ambient reads, public
   declarations, touched files, and production line delta.

**OPEN — slice size.** The first prototype moved 2 reserved symbols and a
10-member dependency path, and cost `+708` production lines before the
owner-implicit correction. Whether later slices should be that size, or smaller,
is not determined by any measurement here.

**Not in Phase 2 or 3 as currently scoped:**

- Catalogue wiring. It stays blocked behind I2 and the WS6-19 no-capture
  condition, which `docs/chat_tool_handler_catalog_unwired_findings.md` shows
  cannot be met without exactly this port extraction. The catalogue is a
  consumer of the boundary, not a peer workstream.
- The per-thread question below.

**OPEN — thread scoping.** `TurnRuntimeGoalContinuationLifecycle` holds one
active-runtime slot per notifier, with an identity-checked release. That
preserves the previous single-boolean behaviour exactly, and it is the codex
`active_turn` shape — except codex has one slot *per session*, and Caverno's
session equivalent is the thread. `docs/turn_runtime_codex_reference_findings.md`
argues the runtime should hang off `ThreadScopedChatState`. Nothing measured so
far requires the change, and no observed defect is attributed to it. It should
be decided explicitly rather than inherited.

## 4. Gates per slice

Retained from Phase 1.5, all of which exist and have been exercised:

| Gate | Command | Evidence it produced |
| --- | --- | --- |
| Turn-scope baseline | `audit_chat_notifier_turn_scope.dart --check-baseline` | Caught that the boundary sat outside audit scope |
| Structural boundary tests | `flutter test test/features/chat/application/runtime/` | Catch `ChatNotifier`, `Ref`, callback and owner-argument leaks; mutation-checked |
| Size ratchet and collaborator boundary | `flutter test test/quality/` | Forced the ports factory extraction |
| Focused behaviour | the manifest's recorded focused command | Passed each slice |
| Live canary | `tool/run_coding_goal_auto_continue_todo_fixture_live_canary.sh` | 3 of 4 baseline with an attribution rule |
| Repository suite and coverage | `flutter test`, `tool/codex_verify.sh --coverage` | 6,645 passing |

The live canary must reach the *migrated* path for the slice under test. The
existing canary exercises goal auto-continuation; a slice touching another
concern needs its own live gate or an explicit statement that none exists — the
Phase 1.5 lesson was that a green suite coexisted with an unreachable feature.

**Environment note.** The live canary cannot reach a LAN endpoint from
`flutter_tester` under macOS Local Network Privacy; it fails in about 200 ms
with `No route to host` while `curl` succeeds. Run it through a loopback relay.

## 5. Stop conditions

Phase 3 halts and returns to design if any holds:

1. **Identity plumbing grows.** A slice raises turn-scope identity parameters
   above the baseline without a recorded, accepted reason. This is the condition
   the owner-implicit experiment was run to make measurable.
2. **Notifier capture returns.** Any new collaborator or effect captures
   `ChatNotifier` or `Ref`. Already enforced by the boundary tests.
3. **A port re-takes the owner.** Enforced by
   `isNot(contains('(ChatTurnOwner owner)'))` in the runtime contract test.
4. **Conversation or thread state moves inside the runtime.**
5. **Two consecutive slices produce no reuse.** If concerns two and three each
   add a full port set with no port shared beyond the lease, §1's projection is
   confirmed and the remaining cost should be re-approved before continuing.
6. **A live gate cannot be produced** for a slice's migrated path.

Condition 5 is the one this document adds. The others restate gates that already
exist and have fired.

## Summary of OPEN decisions

1. Per-concern ports (§1a) or a generalised core (§1b) — resolve after Slice 0.
2. The public-surface budget's form: hard count, per-concern ceiling, or the
   structural rule alone.
3. Slice size.
4. Whether the runtime becomes thread-scoped.

Nothing in Phase 3 is authorized by this draft.
