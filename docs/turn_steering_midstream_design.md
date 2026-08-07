# Mid-stream steering: closing the window the user actually reacts in

Status: implemented and live-verified 3/3. One scoping claim below was wrong
and is corrected in place; see "Correction". Three defects found afterwards by
reading the path this document flagged as unverified; see "What the unverified
plain-chat arm was hiding".

## The measurement that motivates this

Session log `70b6f8f6-6740-43d4-8e01-b1f1b00607e8`, build `48df29da` (clean), a
plain LAN-scan chat turn:

| Time | Event |
|---|---|
| 18:33:41 | tool-aware opening request |
| 18:35:04 | tool-result continuation — steering window |
| 18:35:22 | tool-result continuation — **last** steering window |
| **18:35:25** | **user submits the follow-up** |
| 18:35:30 | final answer stream starts |
| 18:35:54 | final answer ends, turn exits, queue drains |

Two separate failures, and the second is the one that matters.

The app log shows `Queued user message while a response is in flight` and **no**
`[Steering]` line, so the message was sent with plain Enter and never reached
the steering branch at all. That is the shipped `Cmd/Ctrl+Enter` fix.

But the timing says the fix is not enough. The submission landed three seconds
*after* the last continuation request went out. Even pressed on the interrupt
button, the steer would have registered against a turn with no request left to
build, gone out uncarried, and come back through the queue — the exact observed
outcome. The tool loop offered three windows across 100 seconds; the user
reacted during the 24 seconds of final answer, when every window was shut.

This is the general shape, not an unlucky run: **people interrupt because of
what they are reading, and what they are reading is the final answer.** Steering
that only lands between requests is structurally aimed at the wrong moment.

## What has to change

The final answer is streamed, so the turn must be able to abandon a stream it is
already consuming, keep its identity, and issue one more request.

The invariant is unchanged and remains the whole point: **the interaction
generation must not advance.** Advancing it is cancellation, which discards the
turn's owner, tool results and registrations. This restarts a request inside a
turn that stays alive.

## Two stream consumption styles, only one of which needs work

| Site | Style | Needs restart? |
|---|---|---|
| `_sendWithTools` (`chat_notifier.dart:4087`) | `await for` | **Yes** — see Correction |
| `_sendWithoutTools` (`:3712`) | `.listen()` | **Yes** — plain chat, one request per turn |
| `_sendWithEmbeddedToolTagFallback` (`:3795`) | `.listen()` | Yes |
| `_continueAfterContentToolResults` (`:8702`) | `.listen()` | **Yes** — this is the request the measured run died on |

Scoping to the three `.listen()` sites covers both plain chat and the observed
failure, and leaves the `await for` loop untouched.

## The strand risk this must not create

`_finishStreamedCompletionInBackground` is invoked *from* `onDone`. Cancelling
the subscription means `onDone` never fires, so `_finishStreaming` never runs
and the turn stays registered and loading forever. A restart therefore has to
take over finalization responsibility at the moment it cancels — this is the
one place where getting it wrong strands a thread under a spinner, which this
codebase has already been bitten by once.

## Proposed shape

`_restartTurnForSteering(ChatTurnOwner owner)`, invoked from
`_registerTurnSteering` when the owner currently holds a `_streamSubscription`:

1. Refuse unless there is a live subscription, the owner is current, and the
   restart budget for this turn is unspent.
2. `await _streamSubscription!.cancel()`, then null it. Cancellation propagates
   into the datasource's `async*` generator and closes the HTTP stream, so the
   server slot is released rather than left generating.
3. Finalize the partial assistant message in place: `isStreaming: false`, keep
   whatever text arrived, and drop the message entirely when it holds no visible
   content. This is the same treatment `_cancelStreaming` gives a partial, minus
   the generation bump.
4. Cache through `_activeResponseRegistry.cacheMessagesForOwner`, which also
   refreshes the owner snapshot the next request reads.
5. Append a fresh streaming assistant placeholder, exactly as
   `_continueAfterContentToolResults` does before its own request.
6. Re-issue through the turn's normal path for its mode. `_prepareMessagesForLLM`
   then commits the pending steer on its own, so no special injection is needed:
   the partial answer is already finalized, so the steer lands *after* it and the
   transcript reads `user → assistant(partial) → user(steer) → assistant(new)`.

The existing `TurnSteeringPolicy.insertIndex` produces that order without
modification, because it skips only trailing *streaming* messages.

## Budget

A restart must be capped per turn the way content-tool continuations are
(`_maxContentToolContinuations`). Without it, a user typing three corrections in
ten seconds restarts the same turn three times, and a model that keeps drifting
invites an unbounded loop. Proposed: two restarts per turn, then further steers
fall back to the queue with the existing notice.

## What this does not fix

A steer arriving after the final chunk but before finalization still misses.
That window is milliseconds and not worth machinery.

## Verification plan

The existing canary generalizes: add a third arm whose interrupt fires from a
**stream chunk** rather than from a tool execution, asserting the redirected
file exists, the original does not, and `turnCount` stays 1. The delivery
assertion (`directiveCarriedInRequests` non-empty) is what separates "restarted
and ignored" from "never restarted", and stays mandatory.

Plain chat also needs its own live arm: every current live evidence run used
`WorkspaceMode.coding`.

## Correction

The table originally excluded the tool-aware `await for` stream on the grounds
that "a tool-aware response is always followed by a continuation". That holds
only when the model *calls a tool*. When it answers directly — the ordinary
chat reply, and the one users interrupt — that stream is the entire turn and
nothing later carries the interruption.

The loop owns its stream and holds no subscription, so it cannot be interrupted
from outside; it checks `_steeringRestartWanted` per chunk and breaks, which
cancels the stream on its own, then re-enters the shared re-issue.

A second wrong assumption showed up in the canary rather than the product:
firing the interrupt on the first streamed chunk runs inside the same
synchronous frame as `listen()`, before the notifier has stored the
subscription. The harness now defers by one microtask. A wall-clock delay is
worse — a short answer from a fast model has already finished by then, which is
the same closed window this milestone exists to reopen.

## The tool-free re-issue was a regression, not a limit

The first implementation issued the restarted request directly as a bare
`streamChatCompletion`, and this document called the resulting text-only answer
a limit. Session log `2ef1ca19-a82e-4066-879f-3c6bc1488234` (build `0f21ded2`)
showed it was worse than that:

```
20:47:10  [Tool] Sending in tool-aware mode (MCP)
20:47:28  [Steering] Restarted generation 1 mid-stream (restart 1 of 2)
20:47:29  streamChatCompletion            <- tools gone
```

The turn began tool-aware, the user interrupted 18 seconds in, and the restart
handed it back tool-free. The model could no longer run the LAN scan it had
been running and wrote a Python script *about* scanning instead. Interrupting
downgraded a working agentic turn, at exactly the moment the user was already
dissatisfied.

The canary had shown the same symptom (`betaCreated: false`) and it was filed
as a known limit rather than chased. The real-usage log is what made it legible
as a defect.

Fixed by re-entering `_sendWithTools` instead of issuing a stream directly, so
the restarted request keeps the turn's tools and its tool-call handling. Safe
on the same generation: `beginFileTurnCheckpoint` is keyed by generation and
returns without touching an open checkpoint, and `_sendWithTools` falls back to
the tool-free path by itself when a turn has no tools. Live 3/3 with the file
created.

## What the unverified plain-chat arm was hiding

The verification plan below ends with a line that turned out to be the most
useful sentence in this document: *plain chat also needs its own live arm,
because every live evidence run used `WorkspaceMode.coding`*. Reading that path
instead of running it found three defects, all downstream of one cause.

`_streamSubscription` was a single notifier-wide field that nothing owned.
`onDone` never cleared it, and no site checked whose stream it was. So the
restart trigger — "is a subscription present?" — answered a question nobody had
asked. What it actually meant was *some `.listen()` ran at some point and
nothing has cleaned up after it*.

1. **A finished stream restarted a turn that was not streaming.** A completed
   tool-free turn leaves its subscription behind. The next tool-aware turn
   consumes its stream through `await for` and stores no subscription, so the
   leftover one is still what the trigger sees. Interrupting during a tool
   execution — the LAN scan in the measurement above — therefore issued a second
   opening request while the first tool loop was still running, on the same
   generation. The steer was supposed to wait for the request that loop was
   already going to build, which is the original between-requests design.
2. **Another thread's stream could be cancelled by an interruption aimed
   elsewhere.** With two threads running, the field belongs to whichever
   streamed last. Cancelling it takes `onDone` with it, and the restart then
   finalizes the *interrupting* turn — leaving the other one registered and
   loading forever. That is the strand risk named above, applied to the wrong
   turn.
3. **A turn the user ran with tools off came back with tools on.** The re-issue
   called `_sendWithTools` unconditionally. `mcpEnabled` is enforced at the send
   call site, not in the catalog: `getOpenAiToolDefinitions()` filters only the
   per-tool disabled list, and the service is always provided so built-ins stay
   available. The `allTools.isEmpty` fallback therefore never fires in
   production. This is the mirror of the tool-free regression above — an
   interruption is not consent to a setting the user switched off.

The fix binds the subscription to its turn (`TurnStreamBindingRegistry`), which
makes the trigger ask the question it meant to ask, and re-issues through the
turn's own mode rather than assuming tool-aware. Binding and releasing are one
call on the registry, because the three listen sites had proved that a release
they each have to remember is a release one of them will forget.

**The unit tests were green because the harness avoided the production
arrangement.** The mid-stream test injects `toolService: null` — the single
configuration in which defect 3 cannot occur — and the tool-execution test runs
as the first turn of its container, so no leftover subscription exists to expose
defect 1. Both now have counterparts that fail on the pre-fix code.

A live plain-chat arm is still not the right instrument for this, which is worth
recording so it is not filed as remaining work. The canary reads its verdict
from the filesystem, and a tool-free turn writes nothing. What was wrong here is
a harness property — *which* request the restart issues — and that is decided
before any model sees it. The deterministic tests are where it belongs; live
runs remain for obedience, which needs tools to be observable at all.

## The canary's turn counter stopped meaning turns

Counting `streamChatCompletionWithTools` calls was a fine proxy for turns until
the restart began issuing one inside an existing turn. The mid-stream arm now
discriminates on the turn owner the interruption reports joining, which is the
thing actually being claimed and cannot be confused by an extra request.
