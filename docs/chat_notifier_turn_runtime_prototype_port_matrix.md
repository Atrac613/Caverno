# TurnRuntime Prototype Port Matrix

## Decision

Proceed to interface design for the bounded prototype, but do not extract the
entire selected part.

The clean selector at
`06903a3b38aed7af3b6425f8efc3b3337e5c20d6` chose
`chat_notifier_goal_auto_continue.dart`. That 804-line part references 26
private `ChatNotifier` members declared elsewhere. The verification manifest,
however, reserves only these production symbols for the first prototype:

- `_maybeAutoContinueCurrentGoal`
- `_recordGoalAutoContinueSessionLog`

Tracing those symbols through helpers in the same part reaches 10 of the 26
private members. It also reaches the inherited notifier surfaces `ref`, `state`,
and `sendHiddenPrompt`. The prototype boundary must cover that smaller path.
Requiring all 26 dependencies to move would silently turn a bounded diagnostic
into a complete extraction of the selected part.

## Audit Method

The audit uses two scopes:

1. **Full-part inventory:** private member references in the selected part that
   have no declaration in that part.
2. **Reserved-path trace:** external members reached transitively from the two
   symbols named by
   `tool/chat_notifier_turn_runtime_prototype_verification.json`, including
   helpers declared in the same part.

The counts describe raw dependencies, not proposed port counts. Multiple raw
members that share ownership and lifecycle belong behind one capability
boundary.

## Reserved-Path Raw Inventory

The reserved path reaches these 10 private notifier members:

| Raw member | Current purpose | Ownership |
| --- | --- | --- |
| `_buildLlmSessionLogContext` | Builds the target conversation's log context | App/logging scope |
| `_conversationForId` | Reads the owner's current conversation | Conversation scope |
| `_goalAutoContinueTrackerRegistry` | Reads and mutates cross-turn continuation history | Conversation scope |
| `_isSchedulingGoalAutoContinue` | Prevents recursive hidden scheduling | Turn runtime scope |
| `_isVoiceMode` | Supplies an immutable policy input | Turn input |
| `_pendingAskUserQuestionsByThread` | Detects a pending user-answer boundary | Thread scope |
| `_queueOwnerIsVisible` | Validates that the owner still controls visible output | Thread/owner scope |
| `_queuedChatMessages` | Detects queued user input | Thread scope |
| `_settings` | Enables or disables LLM session logging | App settings scope |
| `_threadStates` | Reads pending approvals and workflow decisions | Thread scope |

The same path also reads or writes:

- `ref`, for mounted state, conversation persistence, and log-store access;
- `state`, for loading/error input and continuation indicator projection; and
- `sendHiddenPrompt`, for continuation and completion-elicitation dispatch.

These surfaces must not be passed into `TurnRuntime` directly. Passing `ref`
would expose a service locator, and passing `state` or a `sendHiddenPrompt`
tear-off would preserve the notifier coupling under a different type.

## Capability Matrix

Seven boundary capabilities cover the raw path. Five are narrow collaborators;
two are effects returned to the existing notifier wrapper.

| Capability | Current dependencies | Direction | Prototype treatment | Scope rule |
| --- | --- | --- | --- | --- |
| Turn owner lease | `ref.mounted`, `_queueOwnerIsVisible` | Read | Narrow collaborator that answers whether an explicit `ChatTurnOwner` is current | Must not expose `ChatNotifier`, `Ref`, or thread-state maps |
| Conversation goal access | `_conversationForId`, `conversationsNotifierProvider` | Read/write | Narrow collaborator for owner-bound conversation snapshots and goal-status persistence | Conversation remains authoritative outside the runtime |
| Goal continuation tracker | `_goalAutoContinueTrackerRegistry` | Read/write | Narrow collaborator accepting an explicit owner and typed tracker deltas | Registry remains conversation-spanning and outside the runtime |
| Goal safe-boundary snapshot | `_queuedChatMessages`, `_threadStates`, `_pendingAskUserQuestionsByThread`, visible `state` fields | Read | Narrow collaborator returning one immutable `GoalAutoContinueSafeBoundary` | Queue, approval, workflow, and UI state remain thread-scoped |
| Goal continuation logging | `_settings`, `_buildLlmSessionLogContext`, `llmSessionLogStoreProvider`, conversation generations | Write | Narrow collaborator accepting a fully typed continuation log request | Settings and storage remain app-scoped; logging failure behavior stays unchanged |
| UI projection effect | continuation count, budget, notice, loading, and error fields in `state` | Returned effect | Runtime returns a typed projection instruction; wrapper applies it after owner validation | Runtime never owns `ChatState` and captures no state setter |
| Hidden-turn dispatch effect | `sendHiddenPrompt` | Returned effect | Runtime returns a typed continuation or elicitation request; wrapper performs dispatch | Runtime captures no notifier method tear-off |

The exact Dart names remain an implementation choice. Interface design should
optimize for these capabilities, not mirror current private member names.

## Runtime-Owned Values

The bounded runtime may own only turn-lifetime values:

- the explicit `ChatTurnOwner`;
- finalized assistant response, language code, completion evidence, and voice
  mode supplied as immutable inputs;
- `_isSchedulingGoalAutoContinue` reentrancy state; and
- pure coordination results and typed effects produced for the wrapper.

The reentrancy flag belongs to the runtime because it prevents recursive work
within this orchestration lifecycle. The goal continuation tracker does not:
its evidence and budget history deliberately span multiple hidden turns.

## Full-Part Inventory

The remaining inventory prevents adjacent dependencies from disappearing from
the cost report. `Prototype treatment` states whether a dependency is required
now or deliberately left in the existing extension.

| Private member | Ownership classification | Prototype treatment |
| --- | --- | --- |
| `_activeResponseRegistry` | Turn owner registry | Leave adjacent terminal-success behavior outside |
| `_appendRecoveredAssistantResponse` | UI/message projection | Leave adjacent terminal-success behavior outside |
| `_buildLlmSessionLogContext` | App/logging scope | Cover through continuation logging capability |
| `_contentToolCallHash` | Pure turn-dedupe helper | Leave adjacent content-tool behavior outside |
| `_contentToolTurns` | Turn-local registry | Leave adjacent content-tool behavior outside |
| `_conversationForGeneration` | Compatibility conversation lookup | Leave adjacent verifier replay outside; remove generation lookup in a later identity slice |
| `_conversationForId` | Conversation scope | Cover through conversation goal access |
| `_executeToolCalls` | Tool execution orchestration | Leave adjacent verifier replay outside |
| `_explicitTerminalSuccessSummariesByGeneration` | Turn-local summary state | Leave adjacent terminal-success behavior outside |
| `_goalAutoContinueTrackerRegistry` | Conversation-spanning registry | Cover through goal continuation tracker capability |
| `_goalCompletionEvidence` | Turn-local evidence registry | Leave adjacent goal finalization and update handling outside |
| `_interactionGeneration` | Compatibility identity getter | Leave adjacent diagnostic helper outside; never introduce it into the prototype |
| `_isSchedulingGoalAutoContinue` | Turn runtime state | Move into the bounded runtime |
| `_isVoiceMode` | Immutable turn input | Pass as a typed value |
| `_markToolCallSeenForContentDedup` | Turn-dedupe mutation | Leave adjacent content-tool behavior outside |
| `_pendingAskUserQuestionsByThread` | Thread scope | Cover through safe-boundary snapshot capability |
| `_persistToolResultForPrompt` | Tool-result persistence | Leave test adapter and adjacent tool behavior outside |
| `_queueOwnerIsVisible` | Thread/owner scope | Cover through owner lease and safe-boundary capabilities |
| `_queuedChatMessages` | Thread scope | Cover through safe-boundary snapshot capability |
| `_recordHiddenEvidence` | Turn evidence projection | Leave adjacent terminal-success behavior outside |
| `_settings` | App settings scope | Cover through continuation logging capability |
| `_threadStates` | Thread scope | Cover through safe-boundary snapshot capability |
| `_turnEnd` | Turn-local finalization registry | Leave adjacent goal finalization and update handling outside |
| `_turnOwnerForGeneration` | Compatibility owner lookup | Leave adjacent methods outside; retain explicit owner in the prototype |
| `_turnOwnerSnapshotUnavailableResult` | Compatibility error mapping | Leave adjacent update-goal handler outside |
| `_turnToolResults` | Turn-local result ledger | Leave adjacent goal finalization and update handling outside |

## Construction and Capture Rule

The production wrapper may construct collaborators from narrow underlying
objects such as the conversation notifier, tracker registry, queue registry, or
log store. A collaborator fails the gate if it stores `ChatNotifier`, `Ref`, a
notifier method tear-off, or an untyped callback that closes over any of them.

Owner validation must occur before applying returned UI or dispatch effects and
again after awaited logging or persistence. This preserves the existing stale
owner protections without making the runtime aware of visible chat state.

## Prototype Boundary

The first production slice may move:

- `_maybeAutoContinueCurrentGoal` orchestration;
- `_recordGoalAutoContinueSessionLog` behind the logging capability;
- pure goal-continuation helpers required by those symbols; and
- `_isSchedulingGoalAutoContinue` into runtime-owned state.

It must leave the following in the extension:

- diagnostic streak and verifier-replay methods;
- terminal-success and verification-generation methods;
- goal-turn finalization and `update_goal` handling;
- content-tool dedupe and tool-result persistence test adapters; and
- completion-shadow handling outside the reserved call path.

This boundary removes at least the reserved identity-bearing entrypoint while
testing whether a composition root can supply honest ownership boundaries. It
does not claim that the other 16 raw dependencies are solved.

## Entry Gate for Production Editing

Production editing may begin after a review confirms all of the following:

1. The seven capability rows cover every reserved-path dependency.
2. No proposed collaborator or effect captures `ChatNotifier` or `Ref`.
3. Conversation and thread state stay outside `TurnRuntime`.
4. The wrapper applies effects only while the explicit owner remains current.
5. Adjacent selected-part methods remain outside the first slice.
6. The implementation will report ports, effects, touched files, public
   surface, and production line delta without treating line delta as a hard
   rejection gate.

The typed inputs, five collaborators, two effect families, and runtime-owned
reentrancy state are defined in
`lib/features/chat/application/runtime/turn_runtime.dart` with focused contract
tests. All five collaborators are now constructed in an owner-scoped production
composition without storing `ChatNotifier`, `Ref`, providers, or callbacks.

`TurnRuntimeGoalTrackerAdapter` holds only the existing conversation-spanning
tracker registry. `TurnRuntimeConversationGoalAdapter` and
`ConversationsNotifierGoalRuntimeStore` provide explicit conversation-ID reads
and writes. Both boundaries are now wired into the reserved continuation path.

`TurnRuntimeOwnerLeaseRegistry` now provides the third boundary and is wired
into the existing production wrapper. It stores only lifecycle, visible
conversation, and selected conversation values. Queue ownership, turn
finalization, and the reserved goal-continuation path query it without storing
`ChatNotifier`, `Ref`, callbacks, or active-response state. This preserves the
post-response continuation window, where active-response registration has
already ended.

`TurnRuntimeGoalSafeBoundaryAdapter` now provides the fourth boundary and is
wired into the existing production wrapper. It owns no notifier, `Ref`, state
setter, or callback. The wrapper supplies a narrow visible-thread projection
immediately before capture; the adapter combines it with the existing queue,
detached thread-state, pending-question, and owner-lease collaborators. Exact
approval-owner matching, including interaction generation, remains unchanged.

`TurnRuntimeGoalContinuationLogAdapter` provides the fifth boundary. It
implements the typed runtime port over `LlmSessionLogStore`, preserves
environment-aware enablement and the disabled-before-conversation-read guard,
and accepts its store and session context only when a record is emitted. The
goal continuation path no longer calls the concrete store method directly.

`TurnRuntimeProductionComposition` now creates one short-lived owner scope for
each reserved continuation invocation. This scope is intentionally independent
of normal execution-turn terminalization because continuation begins after the
active response has retired. The production slice reuses all five ports, adds
no callbacks, and reports a +109 production-line consequence; the parent file
is one line below its 8,907-line ratchet limit.

The normal continuation branch now calls
`TurnRuntime.beginGoalContinuationDispatch`, which returns an owner-bound
progress UI effect and hidden-turn request. The wrapper validates ownership
before each effect, preserves the existing dispatch arguments, and ends runtime
scheduling at the synchronous handoff. This adds no port, callback, provider
capture, or ambient read; the reported production-line consequence is +80 and
the 8,906-line parent file is unchanged.

Completion elicitation now returns a clear UI effect and an `update_goal`-only
hidden-turn request from the runtime. Every clear and stop-notice projection in
the reserved orchestration method also uses an owner-bound runtime effect, so a
stale owner cannot clear or replace the current owner's UI. Both hidden-turn
kinds and all reserved-path UI projections are typed effects. The reported
production-line consequence is +32; `chat_notifier.dart` remains at 8,906 lines
and its goal-auto-continue part falls from 806 to 804 lines.

`TurnRuntime.coordinateGoalContinuation` now owns the exact conversation
lookup, tracker snapshot, safe-boundary capture, and existing decision
coordinator invocation. A sealed unavailable/ready result returns the captured
values and plan to the wrapper. Missing conversations exit before tracker or
safe-boundary reads. The reported production-line consequence is +54;
`chat_notifier.dart` remains at 8,906 lines and its goal-auto-continue part
falls from 804 to 800 lines.

`TurnRuntime.applyGoalTrackerTransition` now applies tracker deltas and
conditionally reserves the one-time budget notice through the owner-scoped
tracker port. The typed result preserves the runtime owner, updated snapshot,
notice outcome, and delayed-removal request. The wrapper invokes it at the
original block, stop, and continue points, so tracker removal still occurs only
after blocked-status persistence. This adds no port, callback, provider
capture, or ambient read. The reported production-line consequence is +25;
`chat_notifier.dart` remains at 8,906 lines and its goal-auto-continue part
falls from 800 to 795 lines.

Persisted-block and failed-dispatch finalization are now explicit runtime
operations. Requested tracker removal occurs only after the wrapper completes
blocked-status persistence, cross-owner transitions are rejected, and repair
state is cleared only from the hidden-dispatch failure path. The wrapper no
longer invokes tracker cleanup methods directly. This adds no port, callback,
provider capture, or ambient read. The reported production-line consequence is
+46; `chat_notifier.dart` remains at 8,906 lines and its goal-auto-continue
part falls from 795 to 793 lines.

The production composition now shares an owner-scoped active continuation
runtime across recursive entries. Each runtime owns its scheduling state, the
shared lifecycle serializes only the synchronous hidden-dispatch handoff, and
release occurs before awaiting the continuation. Cancellation and message
reset clear the exact active runtime. The duplicate notifier flag is absent
from production. This adds no port, callback, provider capture, or ambient
read. The reported production-line consequence is +49;
`chat_notifier.dart` falls from 8,906 to 8,904 lines and its
goal-auto-continue part falls from 793 to 792 lines.

The prototype measurement tool now implements `compare`. The validated
selection revision predates a squash merge, so the tool proves that its
selected source is byte identical at the `0bac2bc0` production comparison base
and records that relation explicitly. The current comparison covers 15
production files and reports +708 lines, one migrated identity parameter
removed, a -1 turn-reachable ambient-read delta, one introduced port method,
two clock callback surfaces, 19 public declarations, and zero new callbacks
capturing `ChatNotifier`. All three automated structural gates pass.

Phase 1.5 is closed with a Go to Phase 2 design. The exact focused gate passed;
analysis and all 6,638 repository tests passed with 79.39% line coverage; and
the clean `fc12a1f2` live canary passed 1/1 with readiness `ready`, two ordered
continuations, and diagnostic progression `2 -> 1`. The `+708` production-line
delta and 19 public declarations require a Phase 2 reuse and public-surface
budget before Phase 3. Production catalogue wiring remains No-Go pending I2
and WS6-19. See `docs/chat_notifier_turn_runtime_phase_1_5_decision.md`.
