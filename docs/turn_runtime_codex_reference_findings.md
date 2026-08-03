# TurnRuntime: Reference Findings from the Codex Source

Read-only review completed 2026-08-03. This report records what a local codex
checkout contributes to the `TurnRuntime` proposal in
`docs/chat_notifier_architecture_renewal_plan.md`. It authorizes no migration,
deletion, or schema change, and it does not settle the renewal decision.

## Provenance

| Input | Revision | Notes |
| --- | --- | --- |
| Codex source | `61a44880a85d2fd0d8770908dea5733495e571c8` | Local checkout at `tmp/codex`. `tmp/` is gitignored (`.gitignore:15`), so this tree is not part of the repository and the line references below are anchored to that revision only. |
| Caverno source | `0118fad9234907d59790c32a32a9d6451a8a7281` | Working tree includes the selector-semantics correction described below. Counts below come from that working tree. |

All codex paths are relative to `tmp/codex/`. Re-clone at the recorded revision
before trusting any line number.

## Summary

Three findings. The second is corroborated by the integrated participant turn
planner path and does not depend on `TurnRuntime` being built. The first and
third are design and verification inputs for the renewal decision.

1. Codex has a working turn-scoped composition root, and its scoping differs
   from the shape proposed in the renewal plan: the active turn belongs to a
   session (Caverno's thread), not to the top-level notifier.
2. Codex makes turn-identity checking and turn-state access the same operation.
   Caverno performs the equivalent check separately and by hand, including in
   the now-integrated participant planner path.
3. Codex drives its real turn loop from one shared test harness against a
   scripted model, and asserts on the requests the loop produced. Caverno does
   the same thing, but re-implements the scripting and recording separately in
   each test double. This is a duplication and coverage-breadth finding, not a
   missing capability.

## Finding 1: turn-scoped state exists, scoped to the session

`codex-rs/core/src/state/turn.rs` opens with
`//! Turn-scoped state and active turn metadata scaffolding.` and defines:

```rust
/// Metadata about the currently running turn.
pub(crate) struct ActiveTurn {
    pub(crate) task: Option<RunningTask>,
    pub(crate) turn_state: Arc<Mutex<TurnState>>,
}

/// Mutable state for a single turn.
#[derive(Default)]
pub(crate) struct TurnState {
    pending_approvals: HashMap<String, oneshot::Sender<ReviewDecision>>,
    pending_user_input: HashMap<String, oneshot::Sender<RequestUserInputResponse>>,
    pending_elicitations: HashMap<(String, RequestId), oneshot::Sender<ElicitationResponse>>,
    pub(crate) pending_input: TurnInputQueue,
    mailbox_delivery_phase: MailboxDeliveryPhase,
    strict_auto_review_enabled: bool,
    pub(crate) tool_calls: u64,
    pub(crate) token_usage_at_turn_start: TokenUsage,
}
```

Per-turn state is a plain field on a single object rather than an entry in a
map keyed by a turn identifier.

`codex-rs/core/src/session/turn_context.rs:113` splits the per-turn inputs from
the per-turn mutable state: `TurnContext` ("The context needed for a single turn
of the thread") carries model, approval policy, permission profile, environment
selection and similar configuration, while `TurnState` above carries what the
turn mutates. `codex-rs/core/src/session/turn.rs:151` then takes the context by
value:

```rust
pub(crate) async fn run_turn(
    sess: Arc<Session>,
    turn_context: Arc<TurnContext>,
    ...
```

Collaborators receive the turn, rather than an identifier they must resolve.

### Scoping difference from the renewal plan

`codex-rs/core/src/session/session.rs:52` holds
`active_turn: Mutex<Option<ActiveTurn>>` — one slot per session. Codex
represents concurrent threads as multiple sessions under a thread manager, so
turn state is reachable only through the session that owns it.

The corresponding Caverno boundary is `ThreadScopedChatState`, not
`ChatNotifier`. The renewal plan's target shape has `ChatNotifier` create and
dispose `TurnRuntime` directly; the codex arrangement suggests hanging the
runtime off the thread instead. That variant removes the generation-keyed maps
and additionally makes another thread's turn state structurally unreachable,
which is the shape of the confirmed cross-thread contamination defect. This is
a design option to evaluate, not an established requirement.

### Current Caverno state, measured

```bash
grep -hoE "_[A-Za-z0-9]*(ByGeneration|ForGeneration)\b" \
  lib/features/chat/presentation/providers/chat_notifier*.dart | sort -u
```

24 distinct accessors, 284 call sites across the notifier family. Teardown is
the hand-written destructor `_clearActiveResponseForGeneration`
(`lib/features/chat/presentation/providers/chat_notifier.dart:2441`), which
performs about a dozen explicit per-turn removals. Codex's equivalent is
`TurnState::clear_pending_waiters` plus dropping the object.

Note the limits of the comparison: `AbortOnDropHandle` and `Drop`-based teardown
depend on Rust ownership and do not transfer. Dart would keep an explicit
disposal step; the claimed gain is the number of things that step must remember,
not its removal.

## Finding 2: identity check and state access are one operation

`codex-rs/core/src/session/input_queue.rs:104`:

```rust
pub(crate) async fn turn_state_for_sub_id(
    &self,
    active_turn: &Mutex<Option<ActiveTurn>>,
    sub_id: &str,
) -> Option<Arc<Mutex<TurnState>>> {
    let active = active_turn.lock().await;
    active.as_ref().and_then(|active_turn| {
        active_turn
            .task
            .as_ref()
            .is_some_and(|task| task.turn_context.sub_id == sub_id)
            .then(|| Arc::clone(&active_turn.turn_state))
    })
}
```

Turn state cannot be obtained without proving the caller is the current turn.
The check is not a separate step a caller can omit.

Caverno performs the same check as a distinct, omittable guard. The integrated
participant turn planner path retains one by hand in
`lib/features/chat/presentation/providers/chat_notifier_participant_turns.dart`:

```dart
while (_isCurrentInteractionGeneration(turn.generation)) {
  if (plan.state.owner != owner || !_ownsParticipantTurn(turn)) return;
```

That guard is correct. The point is that its correctness depends on remembering
to write it, and `_isCurrentInteractionGeneration` appears in the same role
throughout the library.

The slice collapsed the loop's turn-local variables into a single
`ParticipantTurnPlan`. The plan remains a loop-local value, so introducing a
notifier-level active-plan slot solely to add an accessor would move ownership
in the wrong direction. The useful prototype invariant is instead that runtime
state access must require the same owner match that returns the state.

The current local guard is correct but remains omittable. This is therefore a
`TurnRuntime` prototype design constraint rather than unfinished participant
planner work.

The immutable/mutable split in Finding 1 also corroborates the slice's
direction: `ParticipantTurnPlan` is the immutable half of the same separation
codex draws between `TurnContext` and `TurnState`.

## Finding 3: the harness gap

Codex drives the real turn loop against a scripted model from one shared
harness in `codex-rs/core/tests/common/` (6,703 lines across 13 files;
`test_codex.rs`, `responses.rs`, `streaming_sse.rs` are the core). A test
declares the model's behaviour as data and then asserts on what the loop sent:

```rust
let body = sse(vec![
    ev_function_call("call_sleep", "shell_command", &args),
    ev_completed("done"),
]);
let server = start_mock_server().await;
let response_mock = mount_sse_sequence(&server, vec![first_body, follow_up_body]).await;
let codex = test_codex().with_model("gpt-5.4").build(&server).await.unwrap().codex;
codex.submit(Op::UserInput { /* ... */ }).await.unwrap();
wait_for_event(&codex, |ev| matches!(ev, EventMsg::ExecCommandBegin(_))).await;
let requests = response_mock.requests();
```

`codex-rs/core/tests/suite/abort_tasks.rs` is a representative example: it
interrupts a running tool and then asserts that the *next* request to the model
contains both the original call and a synthesized aborted output.

### Measured comparison

| | Codex | Caverno |
| --- | --- | ---: |
| Shared harness | `core/tests/common/`, 6,703 lines | none; scripting and recording written per double |
| Model doubles | 1 mock server + declarative event builders | 36 `implements ChatDataSource` classes |
| Doubles concentrated in one file | — | 17, in `chat_notifier_test_doubles_part.dart` (3,592 lines) |
| Distinct request-recording fields in that file | — | 26 |
| Main loop test file | 116 suite files | `chat_notifier_test.dart`, 18,613 lines |
| Files asserting on recorded model requests | 32 | 3 |

Reproduction:

```bash
grep -rn "implements ChatDataSource" test/ --include="*.dart" | wc -l
grep -c "implements ChatDataSource" \
  test/features/chat/presentation/providers/chat_notifier_test_doubles_part.dart
grep -cE "^\s+final List<List<Message>> " \
  test/features/chat/presentation/providers/chat_notifier_test_doubles_part.dart
grep -rlnE "(initialRequests|finalAnswerRequests|toolAwareRequests|streamedRequestMessages)\b" \
  test/ --include='*.dart'
wc -l test/features/chat/presentation/providers/chat_notifier_test.dart \
      test/features/chat/presentation/providers/chat_notifier_test_doubles_part.dart
# codex side, from the recorded revision:
wc -l tmp/codex/codex-rs/core/tests/common/*.rs
ls tmp/codex/codex-rs/core/tests/suite/ | wc -l
grep -rln "response_mock.requests()\|mock.requests()" tmp/codex/codex-rs/core/tests/suite/ | wc -l
```

Both "32" and "3" are what those exact greps match, and are lower bounds on
request-level assertions rather than audited counts.

Each Caverno double re-implements the same five methods
(`streamChatCompletion`, `createChatCompletion`, `streamChatCompletionWithTools`,
`createChatCompletionWithToolResult`, `createChatCompletionWithToolResults`)
with a different script, at roughly 100-200 lines per class, and 26 of them
declare their own `List<List<Message>>` capture field. Codex writes the
scripting as data (`sse(vec![ev_function_call(...), ev_completed(...)])`) and
gets recording from the mock server for free.

### What this does and does not say about the renewal decision

It does not explain the renewal plan's recorded "largest risk". Caverno already
asserts on request bodies: `chat_notifier_test.dart` references captured
requests 30 times against 1,118 total `expect(` calls, and
`chat_notifier_ask_user_question_part.dart` and
`chat_notifier_detached_turn_project_test.dart` do the same. The capability is
present. Attributing the live-canary-only defects to its absence would be
unsupported.

What the comparison does support is narrower: request-level assertion is
available but reaches roughly 3% of the main suite's expectations, and adding it
to a new test currently means writing another double. A shared harness lowers
that cost, which is a precondition for the prototype gate being informative —
the renewal plan makes the prototype's focused test decisive, so it matters that
a passing focused test demonstrably exercised the migrated path.

`_SequencedToolDataSource`
(`test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart:783`)
is the closest existing model: it records `streamedRequestMessages` and
`toolResultBatches` and scripts initial and tool-result responses separately.

## What does not transfer

- `Drop`-based teardown (`AbortOnDropHandle`, `CancellationToken`) relies on
  Rust ownership. Dart retains an explicit disposal step.
- Codex allows one active turn per session. Caverno runs sequential participant
  turns inside one thread, so the single-slot constraint needs verification
  against the participant turn loop before it is adopted.
- The mock SSE server depends on `wiremock` and the HTTP boundary. The Dart
  equivalent is a shared `ChatDataSource` double with scripting and request
  recording; descending to the HTTP layer is not required.

## Suggested order, if the findings are accepted

1. Correct prototype selection so `Conversation` context cannot count as an
   explicit owner or generation identity. The broad audit currently mixes
   those concepts; the corrected selector measures 75 explicit identity
   entrypoints instead of 82 and keeps `chat_notifier_goal_auto_continue.dart`
   first with 13 instead of 14.
2. Promote `_SequencedToolDataSource` into a shared turn harness with
   declarative scripting and request recording, then migrate doubles
   incrementally. Independent of the `TurnRuntime` decision.
3. Re-run the clean-revision selector and gate validation, then prototype the
   selected part only if the focused and live paths demonstrably exercise its
   explicit owner-scoped entrypoints. The selected part still reports zero
   turn-reachable ambient reads, so the comparison must prove parameter and
   port value rather than relying on ambient-read reduction.

The selector correction in step 1 is implemented in the working tree. This
report does not by itself approve the shared harness or production prototype.
