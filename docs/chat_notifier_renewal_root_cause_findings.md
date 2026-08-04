# Why the Renewal Cost What It Did

Read-only review, 2026-08-04, against the codex checkout at
`61a44880a85d2fd0d8770908dea5733495e571c8` (`tmp/codex`, gitignored — re-clone
at that revision before trusting line references).

The renewal's design was validated against codex twice
(`docs/turn_runtime_codex_reference_findings.md`) and matched it. So the useful
question is not whether the design was right. It is why the same design cost so
much here, when codex evidently runs it.

## The answer: three object levels versus one object and two keys

**codex:**

```
ThreadManager   HashMap<ThreadId, Arc<CodexThread>>
  CodexThread   { session: Arc<Session> }
    Session     { thread_id, state: SessionState, active_turn: Mutex<Option<ActiveTurn>>, … }
      ActiveTurn { task: RunningTask, turn_state: TurnState }
```

**Caverno:**

```
ChatNotifier  (one, app-wide)
  _threadStates          Map<String, ThreadScopedChatState>
  ~40 stores             Map<int|ChatTurnOwner, …>   keyed by generation or owner
```

Codex has one map, at the outermost level, keyed by thread. Below it everything
is an object: a session per thread, at most one active turn per session. Nothing
inside is keyed, because there is nothing to disambiguate — the object *is* the
scope.

Caverno collapses the same three levels into one object plus two key dimensions.
Thread identity and turn identity, which are object identities in codex, are map
keys here.

**That single difference produces every symptom the renewal was chartered to
fix:**

| Symptom | What it is under the three-level shape |
| --- | --- |
| ~40 generation/owner-keyed stores | fields on `Session` and `TurnState` |
| 21-step manual turn destructor | dropping `ActiveTurn` |
| 314 identity parameters | `&self` |
| `_isCurrentInteractionGeneration` scattered as a guard | `turn_state_for_sub_id` returning `None` |

None of these is a Dart-versus-Rust difference. `Drop` makes teardown free in
Rust, but a Dart object with a `dispose()` called at one place would also make
the 21 steps one step — which is exactly what the last slice demonstrated on a
third of them.

## The failure was the order of construction

The program built the **innermost** of the three missing levels first.

A turn object owned by the notifier is still *addressed by key*: it has to live
in a map, because the notifier serves many concurrent turns. That is why every
slice added an owner-keyed map rather than removing one — `_runtimeTurns`, and
the `_turnReleases` the last slice introduced. The turn object cannot become
`this` for its callers until something above it is already `this`.

Only a turn owned by a per-thread runtime is addressed by identity. Codex gets
that for free because `Session` exists; Caverno has `ThreadScopedChatState`,
which is **state, not a runtime** — nothing executes there, so a turn has
nowhere to be owned except the notifier.

This was visible on 2026-08-03 and recorded, then not acted on. The codex
findings said:

> The corresponding Caverno boundary is `ThreadScopedChatState`, not
> `ChatNotifier`. […] the codex arrangement suggests hanging the runtime off the
> thread instead.

It was filed as "a design option to evaluate," and the Phase 2 draft carried it
as an open question about thread scoping. The prototype went ahead against the
notifier because that is where the code already was.

## What this explains that the cost review did not

The question-six review attributed the cost to port economics and governance
overhead. Both are real, and both are downstream of this:

- **Port reuse is low (1 of 5)** because ports bridge a turn to a *notifier*.
  Bridging a turn to a *session* needs far fewer, because the session already
  holds what the turn would otherwise reach across for. Codex's `TurnContext`
  reaches `Session` directly; there is no port layer at all.
- **Identity parameters net +3** because the ports re-take the owner. With a
  session above, the owner is the session's, and the turn does not re-supply it.
- **Seven governance amendments** because the classification apparatus tracks
  *parts of `chat_notifier.dart`*. A per-thread runtime is a new object, not a
  reclassified part, and touches that apparatus far less.

## What this does not excuse

The 40 stores still need individual scope determination, and two of the ten
examined were traps that the key type did not reveal. That cost is the same
under either shape — it is a property of the existing code, not of the target.

And the estimate is unproven: no one has built a per-thread runtime here. The
claim that it would have been cheaper is inference from a working reference
implementation, not measurement.

## Consequence for the open decision

The (a)/(b)/(c) re-evaluation was framed as "continue the seven-boundary program
or not." On this reading there is a fourth option nobody costed:

**(d) Build the missing middle level first.** One per-thread runtime that owns
its turns, then let turn scope follow from it. This is the order codex is in,
and the order the renewal skipped.

It is not obviously cheaper — it touches `_threadStates` and every reader of it,
which is a larger blast radius than any slice so far. But it is the only option
under which the remaining slices get *easier* rather than each paying full
price, and the program's actual results are consistent with the theory that
turn-first is the expensive order.

**This should be costed before (a) is accepted.** The recommendation to stop was
made without it on the table.
