# Multi-thread architecture study

Written 2026-07-26, after a day in which eleven separate defects turned out to
be the same mistake: turn-scoped code reading visible-thread state. The
question this note answers is not "how do we fix those" — they are fixed — but
"why were they all writable in the first place, and what shape stops the
twelfth".

## What was surveyed

- `tmp/codex` — the Codex source (Rust, `codex-rs`). Real, complete, and the
  only useful reference here.
- `tmp/claude-code` — the public distribution repo: changelog, plugins,
  examples, docs. **No agent source.** Nothing to learn about internals from
  it; do not budget time for a second pass.

## How Codex models a thread

Four types, each owning exactly what belongs to it.

| Type | File | Owns |
|---|---|---|
| `ThreadManager` | `core/src/thread_manager.rs` | `HashMap<ThreadId, Arc<CodexThread>>` plus the **shared services** (auth, models, MCP, skills, plugins, stores) |
| `CodexThread` | `core/src/codex_thread.rs` | one `Arc<Session>`, its IO channel, its rollout path |
| `Session` | `core/src/session/session.rs` | `thread_id`, `state: Mutex<SessionState>`, `input_queue`, `active_turn: Mutex<Option<ActiveTurn>>`, `tx_event` |
| `TurnState` | `core/src/state/turn.rs` | `pending_approvals`, `pending_user_input`, `pending_elicitations`, `pending_input`, per-turn tool/token accounting |

Three properties follow, and all three are the ones Caverno lacks:

1. **Thread identity is a field, not an ambient lookup.** `Session.thread_id`
   exists on the object doing the work. There is no "current thread" to read,
   so there is nothing to read wrongly.
2. **At most one turn per thread, enforced by a lock.**
   `active_turn: Mutex<Option<ActiveTurn>>`, and starting work goes through
   `try_start_turn_if_idle`, which rejects with a named reason (`Busy`,
   `PlanMode`, `PendingTriggerTurn`). Concurrency exists *between* threads, not
   inside one.
3. **Pending interactions live on the turn.** Approvals, user-input requests
   and the input queue are maps on `TurnState`/`Session`, keyed and owned. They
   cannot be "the app's pending approval".

Shared infrastructure is injected from the manager; it is never a place where
per-thread state can accumulate.

## Why Caverno produced eleven of these

`ChatNotifier` is one object serving every thread, and `ChatState` is the
*visible* thread's state. So:

- the correct value always requires an explicit question ("which thread is this
  turn?"), while the wrong value — `state.messages`, `currentConversation`,
  `_getEffectiveCodingProject()` — is free and always in scope;
- both spellings compile, look identical in review, and differ only when two
  turns overlap;
- unit tests that drive one thread cannot see the difference.

Measured exposure: ~262 `currentConversation`, ~86 `state.messages` and ~19
project-root reads in the notifier library, of which roughly 140 sit in files
that also handle a turn generation. Most are certainly fine — they run on
user-initiated, visible-thread paths. Nobody can currently say which.

The two final defects of the day are the clearest evidence: in
`_buildWorkflowProposalRequest` and `_buildTaskProposalRequest`, the system
message had already been fixed to take the turn's conversation, while the two
arguments beside it still read visible state. The bug was one line from a bug
we had already fixed, and only a live two-thread run found it.

## What the Codex shape maps to in Caverno

Riverpod expresses this without ceremony:

| Codex | Caverno |
|---|---|
| `ThreadManager` (`HashMap<ThreadId, CodexThread>`) | a family provider keyed by conversation id |
| `CodexThread` / `Session` | one notifier instance per conversation, holding that thread's state |
| `SessionState.history` | that notifier's messages — not a global `ChatState` |
| `ActiveTurn` / `TurnState` | a turn object owned by the thread notifier: pending approvals, queued input, tool results, token accounting |
| shared services on the manager | the existing MCP/settings/model providers, injected |

The decisive change is the last one in the second column: **the page selects a
thread to display; it does not own the state.** "Visible" stops being a data
authority and becomes what it should have been — a UI selection.

Every category fixed today then becomes unwritable rather than fixed:
per-thread queue, per-thread plan draft, per-thread approvals, per-turn tool
results, per-turn project resolution, per-turn history.

## Proposed path

A rewrite of a 23,000-line library in one step is not proposed, and not
needed. Three stages, each independently valuable:

1. **Inventory and freeze. — Done (ff8eae3c).** The useful classifier turned
   out to be sharper than "reachable from a background turn": a read matters
   when the method *already knows* which turn it serves — it takes an
   interaction generation or the turn's `Conversation` — and reads the visible
   thread anyway without consulting any turn-scoped accessor. Methods that do
   consult one are the deliberate "this generation is the visible thread"
   branch and are correct.

   That reduces 109 ambient reads to **21 deliberate, 73 with no turn identity
   in scope, and 14 suspect**, now frozen in
   `test/quality/thread_scoped_state_ratchet_test.dart` as a shrink-only list.
   The classifier found a live defect while being written:
   `_buildPlanningResearchContext` took the turn's conversation but scanned
   `_getActiveProjectRootPath()`, so a background draft researched the visible
   project — fixed in the same commit, which is why the list is 14 not 15.
2. **Introduce the turn object.** Give a turn an explicit owner —
   conversation id, project, history, pending interactions, tool results —
   built once at turn start. `TurnThread` and `TurnProjectRoot` (zone-scoped,
   added 2026-07-26) are the first two fields of it, arrived at by necessity.
   Migrate call sites off the ambient reads into it, shrinking the allowlist.
3. **Split the notifier per thread.** Once turns carry their own context, the
   remaining job is mechanical: the notifier stops being a singleton and
   becomes per conversation, and `ChatState` follows. Decide this on the
   evidence stage 1 produces, not now.

Stage 1 also relieves the ratchet pressure that prompted this study: the file
is large because one class holds every thread's concerns, so splitting by
thread is what actually shrinks it. Extraction has been paying interest on that
debt, not principal.

## Instrumentation note

Reviewing code did not find these defects; a live two-thread run did, twice in
one session (`tool/canaries/multi_thread_plan_live_canary_test.dart`). Whatever
stage the restructuring reaches, the canary is the thing that will say whether
it worked. Keep it green and extend it as new per-thread state appears.
