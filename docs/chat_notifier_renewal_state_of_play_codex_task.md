# ChatNotifier Renewal: State of Play, for Independent Review

Written 2026-08-04. Independent-review refresh performed against
`4182e055` on branch `feature/turn-teardown-characterization-gate`. That branch
is 12 commits ahead of `origin/main` (`33a53cad`) and 3 commits ahead of local
`main`; the working tree was clean before this documentation update. The Codex
reference checkout at `tmp/codex` is clean at
`61a44880a85d2fd0d8770908dea5733495e571c8`.

**What is wanted from this review: an independent judgement on whether the
renewal should continue.** The current decision follows the measured evidence;
the previous stop recommendation and missing-middle proposal remain later as
explicitly historical arguments. Every current number below is reproducible
from the commands given or labelled with its recorded revision.

## The program in one paragraph

`chat_notifier.dart` and its 37 part files total 19,357 lines and kept growing
back after a decomposition program that ran ~90 commits for a 14.8% reduction.
The renewal plan (`docs/chat_notifier_architecture_renewal_plan.md`, 2026-08-02)
diagnosed the cause as a missing turn-scoped composition root: turn-local state
is simulated at notifier scope in maps keyed by generation or owner, so every
turn-participating collaborator re-derives its identity and every new piece of
turn state adds a line to a hand-written destructor. The proposed remedy was a
`TurnRuntime` owning turn scope across seven capability boundaries. The
independent review below accepts the lifetime diagnosis but rejects treating
the existing prototype as the general active-turn runtime.

## What the plan proposed to achieve

The plan explicitly retired the line-count target and replaced it with four
goals. Measured now:

| Proposed goal | Then | Now |
| --- | ---: | ---: |
| Recorded ambient reads: 67 → **0** | 67 | **67** |
| Turn-reachable ambient reads | 50 | **49** |
| Adding a tool handler requires zero edits to `chat_notifier.dart` | — | still required |
| Identity parameters (the plan's cost case, not a stated goal) | 314 | **319** |

```bash
fvm dart run tool/audit_chat_notifier_turn_scope.dart \
  --manifest tool/chat_notifier_decomposition_manifest.json \
  --check-baseline tool/chat_notifier_turn_scope_baseline.json
```

## What has actually been built

**Phase 0–1: measurement.** A turn-scope AST audit with a checked-in baseline, a
mechanical prototype selector, a guard inventory, and the repair of four live
canaries that had been reporting on a placeholder verifier answering every
verification with a silent exit 0.

**Phase 1.5: one bounded prototype.** The type named `TurnRuntime` coordinates
post-response goal auto-continuation through five owner-bound ports, two
binders, a production composition, and a lifecycle slot. It is created after
the active response retires, and its owner lease deliberately treats another
generation of the same visible conversation as current. It is therefore a
goal-continuation coordinator, not an active execution-turn lifetime owner.
`lib/features/chat/application/runtime/` is 1,139 lines and holds no
`ChatNotifier` reference.

**One narrowed slice (2026-08-04).** `TurnReleaseScope`: a turn registers what
it owes at start; teardown drops the scope. `_terminalizeRuntimeTurn`'s eleven
owner-scoped release steps became one call.

**Verification in place.** The independent review reproduced the checked
turn-scope baseline (120 scanned files, 1,471 methods, 263 manifest entrypoints,
720 reachable methods, 67 ambient reads, 49 turn-reachable reads, and 41
accessor-bearing reads) and passed 27 focused runtime, composition, and teardown
tests. The most recent full verifier at the pre-edit source revision passed
6,657 tests with 79.40% coverage; it was not rerun for this documentation-only
update. Existing gates still include the size ratchet, collaborator boundary
tests forbidding
`ChatNotifier`/`Ref`/callback capture, and the goal auto-continuation live
canary's recorded attribution rule.

## Measured findings that contradicted the plan

Each was found by measurement, not review, and each was optimistic:

1. **Identity plumbing did not collapse into `this`.** The plan's cost case
   assumed it would. The first boundary *added* 14 identity parameters, because
   every port re-took the owner. Binding the owner at port construction removed
   them; the net across the whole prototype is **+3**.

2. **Port reuse does not amortize.** Of five ports, one is generic and one is
   reusable in shape. A second concern reuses one and needs eight more.

3. **Owner-keyed does not mean turn-scoped, and the shape does not tell you.**
   Ten owner-keyed stores in the candidate part all present as
   `Map<ChatTurnOwner, …>`. Two must not be absorbed: `TurnToolResultLedger`
   retains for ten minutes and no destructor touches it;
   `HiddenAssistantEvidenceRegistry` is `publish`ed rather than disposed, which
   opens a retention window instead of removing the entry. Neither was visible
   from the destructor's call sites — the second was found only by running a
   turn and reading the store afterwards. **40 such stores exist.**

4. **The decomposition manifest carries dead entrypoints.** It declares 11 for
   `chat_notifier_execution_runtime.dart`; three exist. The other eight are
   absent from the codebase. The selector is unaffected (it ranks resolved
   methods) but scope reasoning that read 11 as real surface was inflated.

5. **Governance cost is proportional to classification disturbed.** The 66-line
   slice required **seven** governance amendments: four size-ratchet budgets, a
   collaborator registration, a part reclassified `keep` → `partial`, and the
   audit tool's hard-coded keep-set guard plus its status-distribution
   expectation.

## The diagnosis, by contrast, strengthened

- 40 owner- or generation-keyed stores exist on the notifier.
- The turn's destructor was **21 manual steps across two chained functions**
  (`_terminalizeRuntimeTurn`, then `_clearActiveResponseForGeneration`), and no
  test asserted that any step ran.
- That shape has produced real defects: the stranded active-response
  registration fixed in `e59fe248` left a thread under a spinner until restart,
  and the cross-thread tool-result contamination class has the same origin.

## What the last slice changed, precisely

| | before | after |
| --- | ---: | ---: |
| `_terminalizeRuntimeTurn` release steps | 11 | **1** |
| Turn-reachable ambient reads | 49 | **49** |
| Identity parameters | 317 | **319** |
| Production lines | — | **+66** |
| Governance amendments | — | **7** |

A characterization test written *before* the slice asserts that a completed
turn leaves the seven stores exposed by `turnStateReportForTest` empty, and a
release report asserts the scope discharged all 11 registrations. During the
slice this test caught a regression introduced by the slice itself: an async
`dispose` deferred every release to a microtask and left three stores populated.

A later commit (`74092085`, by another author) added
`test/quality/chat_notifier_turn_teardown_contract_test.dart`: AST-backed gates
pinning the known 11 owner releases, terminalization-chain order, and 16 known
generation-scoped cleanup invocations across completed, cancelled, and failed
turns. This is a closed-world contract: it detects removal or reordering of a
known cleanup, but it cannot prove that a newly introduced keyed store was added
to the classification. The teardown is heavily specified, which strengthens
detection while leaving the structural-prevention question open.

## Independent review result

The renewal objective is **conditionally Go**, but the currently proposed
seven-boundary `TurnRuntime` expansion is **No-Go**. An immediate
`ThreadRuntime` production retrofit is also not authorized. The next production
decision must be preceded by a shared test harness that makes the current
concurrency and replacement contract reproducible.

| Subject | Decision |
| --- | --- |
| Lifetime-based runtime ownership as an objective | **Conditional Go** |
| Expanding the current seven-boundary `TurnRuntime` | **No-Go** |
| Implementing `ThreadRuntime` immediately | **Not yet authorized** |
| Building a shared, test-only turn harness | **Go; selected next slice** |

### The current `TurnRuntime` is a post-turn coordinator

The production composition creates `TurnRuntime` inside
`_maybeAutoContinueCurrentGoal`, after the active response has retired. Its only
direct mutable state is the goal-continuation scheduling flag. Its owner lease
checks the visible and selected conversation IDs, not the interaction
generation, and the lease test intentionally accepts a different generation of
the same conversation because continuation happens after active-response
registration ends.

That is coherent for a post-turn goal policy, but it is not exact active-turn
identity. The current type should remain behaviorally unchanged and be treated
as a future `GoalContinuationCoordinator`; it must not become the base class or
composition root for active execution by accumulating more ports.

Evidence:

- `lib/features/chat/application/runtime/turn_runtime.dart`
- `lib/features/chat/application/runtime/turn_runtime_owner_lease_registry.dart`
- `lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart`
- `test/features/chat/application/runtime/turn_runtime_owner_lease_registry_test.dart`

### Caverno already has an execution runtime

`packages/caverno_execution_runtime` already owns the frontend-neutral turn
handle, start preparation, execution ownership lease, ordered events, terminal
event idempotence, persistence drain, and lease release. `ChatNotifier` starts
that handle in `_startRuntimeTurn`, then separately owns generation-indexed
handles and owner-indexed release scopes.

A new application runtime must compose the existing
`CavernoRuntimeTurnHandle`; it must not reimplement start, terminal events,
ownership, or persistence release. Otherwise Caverno would have two lifecycle
owners and three things named as a turn runtime:

1. `CavernoExecutionRuntime`, the existing external lifecycle/event shell;
2. the current goal-continuation `TurnRuntime`; and
3. a proposed active execution object.

The missing responsibilities are narrower: a per-thread active-turn slot,
exact-instance replacement fencing, cancellation ownership, turn-local mutable
state, request snapshots, and tool-batch scope.

### Codex separates more than thread and turn

The pinned Codex source does not implement one general `TurnRuntime`. It
separates these lifetimes:

| Codex scope | Relevant responsibility | Caverno interpretation |
| --- | --- | --- |
| `ThreadManager` / `Session` | Multiple threads; one active main task per session | `ThreadRuntimeRegistry` / `ThreadRuntime` candidate |
| `ActiveTurn` / `TurnState` | Task, mutable waiters, exact active instance | `ActiveTurnScope` candidate |
| `TurnContext` | Inputs and configuration for a protocol turn | `TurnContextSnapshot` candidate |
| `StepContext` | Tools, router, environment, and MCP snapshot for one model request | Request-level snapshot; not thread state |
| `ToolCallRuntime` | Parallel/serial tool execution, cancellation, ordered results | Tool-response batch scope |

The transferable invariants are:

- a stale completion cannot clear its replacement; Codex uses instance identity,
  not only an ID;
- the active turn owns the root cancellation path and propagates cancellation to
  child work;
- the tools advertised to the model and the router used to execute them come
  from one request snapshot;
- tool calls may execute concurrently, but results return in model call order;
- terminal, retained, thread, and process lifetimes are classified explicitly.

The non-transferable details include Rust `Drop`, the HTTP mock-server shape,
and Codex's broad `SessionServices` bag. Codex also does not universally pass
only a narrow turn object to every collaborator. The useful reference is its
lifetime model and executable harness, not wholesale topology or a mandate to
create more ports.

### The harness finding is independent of the production design

Codex's shared harness scripts model responses as data, records exact outbound
requests, controls streaming/tool races with barriers, and drives the real
thread API. Caverno has the same raw capabilities but repeats them across 36
`ChatDataSource` implementations in 15 files. The nearest reusable seed is
`_SequencedToolDataSource` in
`chat_notifier_detached_turn_project_test.dart`, which already records request
messages and tool-result batches and supports response hooks.

This supports building a shared harness regardless of whether the later
production decision is Stop, `ThreadRuntime`-first, or another scoped design.
The harness must use an append-only request/event ledger; unlike Codex's
predicate waiter, waiting for one event must not discard unmatched events that
another assertion needs.

### Counting `_threadStates` is not a valid ThreadRuntime cost probe

`ThreadScopedChatState` is a stash for non-visible conversations. The visible
conversation's authoritative presentation state lives in the notifier's
Riverpod `state`, so direct `_threadStates` references undercount the thread
surface. A valid probe must inventory authority and lifetime across at least:

- visible `ChatState` and stashed `ThreadScopedChatState`;
- the thread-scoped message queue and drain ownership;
- pending user questions and approvals;
- active-response and goal-tracker registries;
- retained evidence ledgers;
- conversation persistence and runtime events.

The output must be a state-authority-by-lifetime matrix, not a comparison
between the 40 owner/generation-keyed stores and one map's reference count.

### The catalogue is not decisive for seven-boundary extraction

`ChatToolHandlerCatalog` still needs an I2 binding map and the WS6-19 no-capture
gate. That does not prove that seven concerns belong in one `TurnRuntime`.
Codex binds the advertised tool list and execution router at request/step scope;
Caverno can later provide a scoped tool invocation without making the catalogue
a child of either the goal-continuation coordinator or a thread object.

Catalogue wiring remains blocked, but it does not authorize broad Phase 3
extraction.

## Updated decision

Continue the architectural objective only through reversible evidence-building
slices. Preserve the current goal coordinator, `TurnReleaseScope`, teardown
characterization, audit baseline, and existing execution runtime. Do not add a
sixth goal-continuation port, do not move tool handlers, and do not implement a
new thread or turn runtime in the selected next slice.

The target model to test, not yet to implement, is:

```text
CavernoExecutionRuntime
  `- ThreadRuntime[conversationId]
       `- activeTurn: ActiveTurnScope?
            |- CavernoRuntimeTurnHandle
            |- exact owner / instance fence
            |- cancellation root
            |- TurnReleaseScope
            |- mutable turn state
            `- createStepContext()
                 `- ToolBatchRuntime

GoalContinuationCoordinator
  `- conversation-spanning goal policy and tracker
```

No separate `SessionRuntime` should be introduced unless Caverno demonstrates a
session lifetime distinct from a conversation/thread lifetime.

## Superseded decision path

The previous revision framed Stop, seven-boundary continuation, and one
destructor-only slice; the destructor slice was executed. It then recommended
stopping and later proposed `ThreadRuntime`-first as a fourth option. Two
arguments from that path remain useful: measured scope estimates were repeatedly
optimistic, and bounded audit/characterization slices produced value without
authorizing broad extraction.

The independent review supersedes its immediate actions for four reasons:

- the teardown contracts cover known state and calls, not automatic enrollment
  of future keyed stores;
- catalogue wiring needs a stable invocation boundary, but not necessarily the
  seven-boundary runtime;
- the current feature `TurnRuntime` is post-turn goal coordination, while
  `_runtimeTurns` contains handles from the separate
  `CavernoExecutionRuntime`;
- the `ThreadRuntime` cost probe used `_threadStates` as a proxy even though the
  visible thread's authority lives outside that map.

The unresolved production questions are narrower: whether detection is an
acceptable final boundary, whether a per-thread active slot reduces maps rather
than relocating them, and whether its governance cost remains bounded. H0–H2
provide the evidence needed to answer them.

## Selected next step: shared `ChatTurnHarness` foundation

The next slice is test-only and independently useful. Its executable task is
`docs/chat_turn_harness_foundation_codex_task.md`.

### H0 — selected and authorized

Extract the reusable behavior of `_SequencedToolDataSource` into
`test/support/chat_turn_harness.dart`, with:

- declarative initial and tool-result response steps;
- immutable capture of outbound messages, advertised tool definitions, and
  tool-result batches;
- deterministic barriers before a response or tool-result response completes;
- an append-only runtime-event ledger with non-destructive predicate waits;
- poison getters that fail if shared mutable completion metadata is read.

Replace the private double's existing callers with the shared implementation
and delete the private class. Strengthen one detached-turn test that already
proves a real interleaving: thread A waits for a content tool, thread B
completes, then A resumes. The migrated suite must continue to drive the real
`ChatNotifier` and existing `CavernoExecutionRuntime`; it must not create a
second orchestration path.

H0 changes no production file, renames no runtime, and makes no statement yet
about whether a thread permits one or multiple live protocol turns. It succeeds
only if the migrated suite stays green, the selected interleaving has equal or
stronger request/event assertions, and the private double is removed rather than
copied.

### H1 and H2 — follow-ups, not part of H0

- **H1:** express the two-thread pause/switch/complete/resume contract entirely
  through the shared harness and assert project root, tool definitions, request
  history, visible projection, terminal order, and teardown isolation.
- **H2:** characterize same-conversation replacement. Hold the old generation,
  start the replacement, release the old work, and determine whether the
  contract is cancellation, serialization, or supported overlap. Assert that a
  stale completion cannot terminalize or clear the replacement.

Only H2 can establish whether the Codex-style single-active-turn-per-thread slot
transfers to Caverno.

## Gate for a later `ThreadRuntime` / `ActiveTurnScope` pilot

After H0–H2 and a state-authority-by-lifetime inventory, a production pilot may
be proposed only if it can meet all of these conditions before implementation:

1. Reuse `CavernoRuntimeTurnHandle` and `TurnReleaseScope`; do not duplicate
   lifecycle events, execution ownership, or persistence release.
2. Remove at least one notifier-level owner/generation-keyed map net; adding a
   secondary generation index or scanning every thread is a failure.
3. Bind identity once at construction, and reject stale completion by exact
   instance identity or an equivalent monotonic lease token.
4. Give the active turn one cancellation root that reaches in-flight stream and
   tool work.
5. Bind advertised tools and the execution router to the same request-level
   snapshot.
6. Preserve post-turn retained evidence instead of disposing everything with
   the active turn.
7. Add no `ChatNotifier`, `Ref`, or callback capture and keep the pilot's new
   public declarations within a pre-approved budget; the proposed ceiling is
   three.
8. Pass completed, failed, cancelled, replaced, two-thread, hidden-continuation,
   and participant pause/resume scenarios through the shared harness.

If a pilot only relocates maps, needs a second lifecycle owner, or cannot meet
the public-surface budget, stop at the current audit, teardown contracts, and
`TurnReleaseScope`.

## Reproduction

```bash
fvm dart run tool/audit_chat_notifier_turn_scope.dart \
  --manifest tool/chat_notifier_decomposition_manifest.json \
  --check-baseline tool/chat_notifier_turn_scope_baseline.json
fvm flutter test \
  test/features/chat/application/runtime/turn_runtime_test.dart \
  test/features/chat/presentation/providers/turn_runtime_production_composition_test.dart \
  test/quality/chat_notifier_turn_teardown_contract_test.dart
tool/codex_verify.sh
git log --oneline 33a53cad..HEAD
```

Primary documents: `chat_notifier_architecture_renewal_plan.md`,
`chat_notifier_renewal_question_six_review.md`,
`chat_notifier_execution_runtime_port_matrix.md`,
`chat_tool_handler_catalog_unwired_findings.md`,
`turn_runtime_codex_reference_findings.md`, and
`chat_turn_harness_foundation_codex_task.md`.

`chat_notifier_turn_runtime_phase_2_design_draft.md` and
`turn_runtime_codex_reference_findings.md` remain historical evidence rather
than normative specifications until their thread/turn-only scope model is
updated to include request-step and tool-batch lifetimes and the existing
`CavernoExecutionRuntime` boundary.
