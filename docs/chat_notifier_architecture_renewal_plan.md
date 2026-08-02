# ChatNotifier Architecture Renewal: Plan for Review

**Status: proposal, seeking review. Nothing here is agreed.** Written
2026-08-02. The decomposition documents currently disagree about whether the
program is complete. The decomposition task explicitly retires the line-count
target; reconciliation must determine whether its recorded close-out
measurements remain representative, not re-open that target by implication.

Codex: the review questions are at the bottom. The most useful thing you can do
is attack the diagnosis in the first section — everything downstream depends on
it, and if it is wrong the plan is wrong.

## The problem, stated as a diagnosis rather than a size

`chat_notifier.dart` and its 37 parts total 19,683 lines and keep growing back.
The decomposition close-out material records 71 collaborators, ~90 commits,
several weeks of work, and a 19,647-line aggregate against a 23,049 baseline —
a 14.8% reduction for a very large effort. The authoritative task index still
shows open work, so these are historical measurements rather than proof that
the program completed.

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

Three consequences follow. The first and third are measured; the second is
directly visible in the current ownership boundaries:

1. **Everything that participates in a turn becomes a notifier method.** The
   manifest records 414 entrypoints across 43 historical parts; the latest
   recorded audit resolves **271**, of which **82 carry an identity parameter**
   and 139 are turn-reachable. Reconcile the audit baseline before treating
   those figures as current. A new tool, guard or recovery path has nowhere
   else to land.
2. **Turn operations reach longer-lived state through implicit notifier
   access.** `_goalAutoContinueTrackers`, `_threadStates` and similar maps are
   deliberately conversation- or thread-scoped; they are not candidates for
   ownership by a turn. The architectural problem is that turn-scoped code
   reaches them through the notifier instead of an explicit scoped port.
3. **Turn identity is re-derived by hand, everywhere.** A historical scan found
   798 lines (4% of the library) touching `interactionGeneration`, `ChatTurnOwner`,
   `_turnOwnerForGeneration`, `TurnThread`/`TurnGeneration` zones or the
   ambient-read accessors. The latest recorded turn-scope audit reported 67
   ambient reads, 50 of them turn-reachable. Both figures require fresh,
   reproducible measurement before they become decision inputs.

**The bugs follow the same shape.** The cross-thread contamination class, and
all three defects found on 2026-08-01, lived at seams between components rather
than inside any of them. None of them would have been prevented by a smaller
file; a halved `chat_notifier.dart` would have had every one of them.

This is also why the ratchet feels like an obstacle. It is working correctly —
it caught two of my own reflexive errors on 2026-08-01 — but new behaviour has
nowhere to land except inside the library, so **the ratchet collides with what
the structure forces**. Treating the ratchet as the problem would be treating
the smoke alarm as the fire.

## Recorded rationale for retiring the line target

The decomposition close-out records the following rationale for retiring the
11,524.5 half-baseline in criterion 7. The retirement is explicit; the
prerequisite reconciliation below must re-measure the inputs before the renewal
relies on the recorded cost case:

- The program's realised ratio was **5.8 lines created per line removed**
  (18,107 created vs 3,115 removed across 71 collaborators). Extraction moves
  lines; it does not delete them.
- An AST walk at the close of workstream 8 found **9 pure members totalling 82
  lines** left to extract, averaging nine lines each and not forming a cluster.
  The extraction well is dry.
- The owner/generation plumbing that a per-turn split would directly eliminate
  is **798 lines**. Even a full split does not produce 8,000.

On that evidence, **the remaining 8,000 lines do not exist as extractable
mass.** They are the behaviour. Proposed replacement goals, subject to the
prerequisite reconciliation and fresh measurement:

- Adding a tool handler requires **zero** edits to `chat_notifier.dart`.
- Recorded ambient reads: 67 → **0**, after re-establishing the baseline.
- Guards whose non-firing decides feature reachability: **observable**.
- Unreachable code: **0**.

Aggregate line count becomes a reported consequence, not a target.

## Proposed target shape

```
ChatNotifier            thread routing and UI projection only;
                        creates and disposes TurnRuntime
TurnRuntime             owner and generation are `this`
  ├─ tool loop, completion evidence, turn-local trackers
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

**One piece is built and not connected.** `ChatToolHandlerCatalog` and
`SubagentCatalogChildToolExecutionAdapter` exist with tests, but neither is
wired into the production loop. Production still builds
`ChatToolHandlerRegistry.fromModules`, whose module callbacks capture the
notifier. Workstream 6 slice 19 specifies a registry-last migration with
explicit prerequisites and stop conditions. Learning **why it remains
unwired** may reveal an obstacle that also blocks the renewal; the catalogue's
existence alone does not prove that production wiring is cheap or safe.

**The rest of the groundwork is mostly built.** `ChatTurnOwner`, the `TurnThread` and
`TurnGeneration` zones, `ActiveResponseRegistry`,
`TurnOwnerSnapshotRegistry`, `CavernoRuntimeTurnHandle`, the owner-fenced
mutation runtimes and `ThreadScopedChatState` were all built during the
thread-independence work. They amount to treating a turn as an identity with
fenced resources. What is missing is a composition root for turn-local state
that reaches longer-lived state only through explicit boundaries.

## Prerequisite: reconcile the existing program's state

Reconciled on 2026-08-02 with
`docs/chat_notifier_decomposition_task_index.md` remaining authoritative:

- P1a-P14 and Workstreams 4 and 5 are complete.
- Workstream 8 is complete under its narrow-interface review, but none of
  WS8-1 through WS8-10 is thereby a completed slice-level prerequisite.
- Workstream 7 is closed with WS7-7 deferred because WS8-1 was retained.
- Workstream 6 is deferred after completing WS6-1 through WS6-5, WS6-10,
  WS6-12, and WS6-13. WS6-6 through WS6-9, WS6-11a, WS6-11b, and WS6-14
  through WS6-18 may be reconsidered only after this plan establishes stable
  turn-runtime and composition-root APIs.
- WS6-19 remains a separate Phase 1.5 decision. Its original registry-last
  gate still requires every preceding WS6 handler plus implemented WS8-2 and
  WS8-7; the workstream-level WS8 closeout does not satisfy those gates.

This transfers the old program's open work without requiring it as a blocker
for Phase 0. Do not revive a deferred extraction merely to lower line counts;
use it only when the renewal exposes a stable boundary that needs the handler.

The checked-in turn-scope baseline was also reconciled to 112 scanned files,
1,413 methods, 271 resolvable manifest entrypoints, 665 reachable methods, 67
ambient reads, and 50 turn-reachable reads. Recheck it before Phase 0 with:

```bash
fvm dart run tool/audit_chat_notifier_turn_scope.dart \
  --manifest tool/chat_notifier_decomposition_manifest.json \
  --check-baseline tool/chat_notifier_turn_scope_baseline.json
```

If it differs, review the report before changing the baseline. Regenerate only
after explaining the drift, inspect the diff, and then re-run the check:

```bash
fvm dart run tool/audit_chat_notifier_turn_scope.dart \
  --manifest tool/chat_notifier_decomposition_manifest.json \
  --write-baseline tool/chat_notifier_turn_scope_baseline.json
git diff -- tool/chat_notifier_turn_scope_baseline.json
fvm dart run tool/audit_chat_notifier_turn_scope.dart \
  --manifest tool/chat_notifier_decomposition_manifest.json \
  --check-baseline tool/chat_notifier_turn_scope_baseline.json
```

Do not refresh the baseline merely to make the gate green. Record whether the
drift is expected, which open workstream caused it, and which document becomes
the resulting source of truth.

## Prerequisite: make the inventory reproducible

The existing session analyser cannot enumerate uninvoked tools, parse all guard
telemetry, or replay an exact corpus manifest. Before Phase 1, implement and
test the measurement tooling contract specified in
`docs/chat_notifier_inventory_codex_task.md`. Phase 0A may define the static
guard manifest in the same tooling slice. Behavioural refactoring remains out
of scope until both prerequisites are satisfied.

## Proposed phases

An earlier draft had Phase 0 instrument "guards whose silent non-firing decides
reachability" and Phase 1 inventory the guards. That is circular — the
selection needs the inventory. Split:

**Phase 0A — static guard inventory (complete 2026-08-02).** The finite
checked-in inventory now represents 65 decision candidates and explicitly
excludes 15 matched helpers. It records whether silent non-fire can suppress a
guarded or recovery path, maps 13 existing structured events, and leaves all
action states unresolved pending production-root edge review and matching-build
observations. The focused analyser test enforces exact discovery coverage.
Historical notes counted 376 of 377 `return null;` statements in
`domain/services` without a nearby log, but that heuristic is not a reachability
proof and did not define this inventory.

**Phase 0B — telemetry for the subset 0A selects.** Adding one such field
(`hasVerifierReplayCandidate`) on 2026-08-01 resolved in a single run a question
that had been invisible for as long as the feature existed.

**Phase 1 — inventory against a pinned corpus.** See
`docs/chat_notifier_inventory_codex_task.md`. Fix the date range, file set and
build revisions first; a re-measurement during review produced 33 invoked tools
where an earlier note recorded 41, and without a pinned corpus there is no way
to distinguish drift from a different sample.

**Phase 1.5 — bounded experiments and the decision point.** Before committing
to a renewal:

- **Investigate why `ChatToolHandlerCatalog` is unwired** during Phase 1. Wire
  it in Phase 1.5 only if reconciliation proves that workstream 6 slices 1-18
  and workstream 8 slices 2 and 7 satisfy the existing WS6-19 gate. The
  migration must also meet the WS6-19 stop conditions: remove the old registry
  path, capture no `ChatNotifier` callback in catalogue bindings, and pass the
  binding/poison tests. Otherwise finish those prerequisites or separately
  review an explicit replacement safety contract; do not silently bypass the
  gate.
- **Prototype `TurnRuntime` on exactly one high-coupling part.** Measure lines
  removed, parameters eliminated, longer-lived state accessed through ports,
  and ports or callbacks introduced. It must not absorb thread-scoped state.

Make the prototype selection and decision reproducible. Before editing, add
`tool/measure_chat_notifier_turn_runtime_prototype.py` and
`test/python/measure_chat_notifier_turn_runtime_prototype_test.py`. Its `select`
mode ranks current declared part files by these keys, in order:

1. most turn-reachable entrypoints carrying an explicit owner or generation
   parameter;
2. most turn-reachable ambient reads;
3. most production lines; and
4. lexical path order as the final tie-breaker.

Do not hand-pick an easier part. Run `select` from a clean commit after the
baseline reconciliation; the tool must resolve `HEAD` to its full Git SHA:

```bash
python3 test/python/measure_chat_notifier_turn_runtime_prototype_test.py
python3 tool/measure_chat_notifier_turn_runtime_prototype.py select \
  --audit tool/chat_notifier_turn_scope_baseline.json \
  --manifest tool/chat_notifier_decomposition_manifest.json \
  --source-revision HEAD \
  --require-clean \
  --output /tmp/chat_notifier_turn_runtime_candidate.json
```

If the selected part lacks a real focused test or live canary, create and
validate that gate in a separate preparatory commit; do not move to the next
part. Record the selected part, exact focused-test command, exact live-canary
command, canary contract and expected evidence in the checked-in
`tool/chat_notifier_turn_runtime_prototype_verification.json`. Re-run `select`
from that clean commit, then make the tool join and validate the mapping:

```bash
python3 tool/measure_chat_notifier_turn_runtime_prototype.py validate-gates \
  --selection /tmp/chat_notifier_turn_runtime_candidate.json \
  --verification-manifest tool/chat_notifier_turn_runtime_prototype_verification.json \
  --output /tmp/chat_notifier_turn_runtime_selection.json
```

`validate-gates` must fail if the manifest part differs from the selected part,
either command is missing, or the canary contract does not identify evidence
from the migrated path.

Run the prototype as an isolated slice; do not mix catalogue wiring or unrelated
changes into its diff. The tool's `compare` mode must report a before/after
table with production line delta across every touched or added non-generated
`lib/` file, identity parameters removed, port or callback methods introduced,
turn-reachable ambient-read delta, and callbacks that capture `ChatNotifier`.

```bash
python3 tool/measure_chat_notifier_turn_runtime_prototype.py compare \
  --selection /tmp/chat_notifier_turn_runtime_selection.json \
  --before-revision HEAD \
  --after-worktree . \
  --output /tmp/chat_notifier_turn_runtime_comparison.json
tool/codex_verify.sh --coverage
```

Also run the exact focused test and live-canary commands recorded by `select`,
and confirm the canary exercises the migrated path rather than a placeholder.
Do not refresh the global turn-scope baseline inside the experiment; compare
the worktree audit to it so regressions remain visible.

**Proceed to Phase 2 only if all gates pass and the comparison shows:**

- production line delta is at most zero;
- at least one identity parameter is removed;
- turn-reachable ambient reads do not increase;
- no new callback captures `ChatNotifier`; and
- the focused test, coverage gate and live canary preserve behaviour.

If any condition fails, abandon the full `TurnRuntime` renewal. Catalogue wiring
may still proceed independently, but only under its existing WS6-19 gate.

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

1. **Is the diagnosis right?** Is the missing turn-scoped composition root the
   cause of the regrowth, or a plausible story fitted to the symptoms? What
   would falsify it? Specifically: how much code is app-, conversation-, or
   thread-scoped and therefore must not move?
2. **Does the parameter-elimination argument hold?** The claim that this
   migration reduces lines where extraction increased them is central. Check it
   against a real part file rather than in principle.
3. **Are Phase 0A and Phase 0B ordered correctly?** Does the finite static
   inventory justify the telemetry slice, and can any selected telemetry wait
   until after the prototype?
4. **Is the phasing right?** Inventory before design assumes the design depends
   on what survives. Is that true, or could both proceed in parallel?
5. **What is missing?** In particular, is there a cheaper intervention that
   captures most of the benefit — and is there a reason to keep a shared
   notifier that this plan has not considered?
6. **Should this happen at all?** The status quo is a large file that is
   ratcheted, audited and covered by canaries. "Stop growing it and live with
   it" is a legitimate answer if the cost case does not hold.
