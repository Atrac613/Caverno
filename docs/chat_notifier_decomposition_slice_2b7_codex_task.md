# ChatNotifier Decomposition Slice 2b7: Participant-Turn Isolation

## Task

- Goal: prove and enforce that participant messages, manual approval, handoff,
  runtime projection, and terminal lifecycle remain attached to the owning turn
  while another conversation is visible.
- User-visible behavior: a background participant discussion completes in its
  own thread, surfaces approval only on that thread, preserves its handoff
  metadata, and releases exactly its own busy/runtime lifecycle.
- Destination API:
  - require `interactionGeneration` and `ownerConversationId` across participant
    stream, tool, approval, runtime, pause, completion, and failure methods;
  - route thread-visible participant state through
    `_routeThreadState(ownerConversationId, ...)`;
  - terminalize participant generations through `_completeRuntimeTurn` or
    `_failRuntimeTurn`, never by clearing only the active-response registry.
- Non-goals:
  - changing participant ordering, role prompts, handoff syntax, or tool policy;
  - redesigning participant configuration or persistence;
  - supporting multiple independently paused participant loops if that requires
    a new persisted runtime model;
  - extracting participant orchestration or adding a notifier part.

## Context

- Affected production files:
  - `lib/features/chat/presentation/providers/chat_notifier_participant_turns.dart`;
  - `lib/features/chat/presentation/providers/thread_scoped_chat_state.dart`;
  - `lib/features/chat/presentation/providers/chat_notifier_execution_runtime.dart`
    for a narrow generation-explicit approval delegate and, if needed, an
    owner-explicit runtime-start parameter;
  - `lib/features/chat/presentation/providers/chat_notifier.dart` only for
    explicit owner lookup and queue/lifecycle integration;
  - `tool/chat_notifier_turn_scope_baseline.json`, refreshed after the reviewed
    production signature and call-graph changes.
- Direct deterministic test file:
  `test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart`.
- Existing regression files:
  - `test/features/chat/presentation/providers/chat_notifier_participant_turns_part.dart`;
  - `test/features/chat/presentation/providers/chat_notifier_execution_runtime_part.dart`;
  - `test/features/chat/presentation/providers/chat_notifier_test.dart`.
- Exact source methods and current behavior:
  - `_appendParticipantPlaceholder`, `_finalizeParticipantTurnMessage`, and
    `_prepareMessagesForLLM(interactionGeneration: ...)` are already
    generation-aware for transcript content;
  - `_setParticipantTurnRuntime`, `_setParticipantToolActivity`,
    `_clearParticipantToolActivity`, `_pauseParticipantTurns`, and
    `_completeParticipantTurns` write ambient visible `state`;
  - `ThreadScopedChatState` retains participant approval but not
    `participantTurnRuntime`;
  - `_executeParticipantToolCall` and `_resolveParticipantToolApproval` do not
    receive generation or owner;
  - `continueParticipantTurns` creates and registers a new generation but does
    not call `_startRuntimeTurn`, so it cannot emit or terminalize an
    independent continued runtime;
  - `requestParticipantToolApproval` calls `_routeApproval`, but participant
    execution is not inside the `TurnThread` scope used by the normal tool
    dispatcher;
  - `requestParticipantToolApproval` calls
    `_emitRuntimeApprovalRequired`, which emits to ambient
    `_interactionGeneration`;
  - the participant stream error path calls ambient `_handleError`;
  - the no-enabled-participant, pause, and completion paths call
    `_clearActiveResponseForGeneration` directly instead of
    `_completeRuntimeTurn`, leaving the runtime handle without a terminal event
    or exact lifecycle completion;
  - `_cancelStreaming` calls `_clearAllActiveResponses()` before failing the
    selected generation and also clears the global participant pause cursor, so
    cancellation is currently application-global rather than owner-exact.
- Current test gap: every participant message, handoff, approval, pause, and
  runtime test stays on one conversation.

## Implementation Notes

- Resolve `ownerConversationId` from the active-response registry once and pass
  it with `interactionGeneration` through:
  - `_runParticipantTurnLoop`;
  - `_streamParticipantTurn`;
  - `_executeParticipantToolCall`;
  - `_resolveParticipantToolApproval`;
  - `requestParticipantToolApproval`;
  - runtime/activity setters;
  - pause, completion, and error paths.
- On continuation, start a fresh runtime handle for the paused conversation and
  new generation before resuming the loop. A failed start must not consume the
  paused cursor or alter a foreign visible thread.
- Keep participant lists and config as immutable snapshots
  (`List.unmodifiable` and immutable Freezed/entity values). Do not re-read the
  visible conversation after the loop begins.
- Add `participantTurnRuntime` to `ThreadScopedChatState.from`, `hasContent`, and
  `applyTo`. Route all participant runtime/activity updates to the owner so a
  switch stashes and restores the exact runtime without projecting it onto B.
- Keep transcript mutation generation-aware:
  `_activeResponseMessagesForGeneration` remains authoritative while detached,
  and `_onConversationMessagesChanged(ownerConversationId, messages)` remains
  the persistence port.
- Route manual approval with the explicit owner. Either establish
  `TurnThread.runScoped(ownerConversationId, ...)` around the participant tool
  call or call `_routeThreadState` directly; do not depend on the visible
  thread.
- Add a narrow generation-explicit runtime approval emitter for participant
  tools. Do not change all unrelated approval handlers in this slice.
- Participant success, empty-roster completion, and pause must produce exactly
  one terminal runtime event for that generation. Use `_completeRuntimeTurn`
  with an explicit participant completion/pause exit reason.
- Participant failure must update the owner's transcript/error projection and
  call `_failRuntimeTurn(interactionGeneration, ...)`; it must not call ambient
  `_handleError` for a detached turn.
- A continued participant discussion starts a new generation and terminalizes
  that generation independently.
- Treat cancellation as a separately classified application-global action
  unless an owner-exact fix fits the existing lifecycle keep set. If a poison
  case reaches cancellation, assert its scope explicitly; otherwise record the
  global clear as a deferred limitation.
- Typed side-effect ports:
  - transcript persistence:
    `_onConversationMessagesChanged(String ownerConversationId, List<Message>)`;
  - approval projection:
    `_routeThreadState(String ownerConversationId, ChatState Function(...))`;
  - runtime lifecycle:
    generation-explicit `_completeRuntimeTurn`, `_failRuntimeTurn`, and runtime
    event emission;
  - tool execution: existing `McpToolService` after owner approval.
- Generated files and migrations: none.

## Deterministic Two-Thread Cases

Use distinct A/B participant IDs, display names, roles, models, colors, message
tokens, and handoff targets:

1. Start A's first participant stream and switch to B before releasing its
   chunks. A's placeholder and chunks must remain in A; B's messages and runtime
   projection remain unchanged.
2. Complete A's first speaker with a handoff to A's reviewer while B is visible.
   The next request uses A's roster/transcript, and the finalized A message keeps
   A's handoff target metadata without the visible `Handoff:` marker.
3. Make A's reviewer request a manually approved read-only tool. B must show no
   participant approval, A must be listed as awaiting approval, and B must be
   able to complete its own turn without resolving A.
4. Switch back to A and assert the exact approval ID, participant, tool, and
   arguments are restored. Resolve it and verify only A resumes.
5. On A completion, assert exactly one runtime terminal event for A's
   generation, no A busy registration, no active participant runtime, and the
   persisted A transcript contains all attributed messages.
6. Run the same switch with participant stream failure. Only A receives the
   error and failed runtime terminal; B remains unchanged and idle.
7. Exercise pause and continue across a switch. The paused runtime belongs to A,
   and the continued generation completes independently.

Assert conversation IDs on runtime events, participant attribution, handoff
fields, pending approval ownership, persistence, terminal event count, and
`busyConversationIds`.

## Similar-Pattern Search

- Search terms:
  - `participantTurnRuntime`;
  - `_participantTurnStopRequested`;
  - `_pausedParticipantTurn`;
  - `_routeApproval`;
  - `_emitRuntimeApprovalRequired`;
  - `_clearActiveResponseForGeneration`;
  - `_completeRuntimeTurn`;
  - `_handleError`;
  - `_activeInteractionOrigin`.
- Inspect every participant terminal path: empty roster, normal completion,
  pause, continuation, denial, stream failure, and cancellation.
- Record global paused-cursor, stop-request, or interaction-origin limitations
  that require simultaneous independently paused loops as deferred findings.
  Do not widen this slice into a participant runtime redesign.

## Measurement, Manifest, and Coverage

- Expected declared notifier-part delta: `0`; the count remains `42`.
- Target same-library aggregate delta: `0`; reductions are acceptable, but the
  aggregate must remain at or below the starting `22,887` physical lines.
- Manifest record `participant-turns` remains `remaining`.
  `thread_scoped_chat_state.dart` remains an existing support library, not a new
  decomposition collaborator.
- Collaborator records and discovery markers: none.
- No size budget may increase.
- Current coverage baselines:
  - `chat_notifier_participant_turns.dart`: `276/310` (`89.03%`);
  - `thread_scoped_chat_state.dart`: `92/92` (`100.00%`);
  - `chat_notifier_execution_runtime.dart`: `47/56` (`83.93%`).
- Coverage expectation:
  - participant turns remain at or above `89.03%`;
  - thread-scoped state remains `100.00%`;
  - execution runtime remains at or above `83.93%`;
  - every success, pause, approval, and failure lifecycle branch added by this
    slice is hit.

## Acceptance Criteria

1. Participant messages and handoff metadata remain in the owning transcript
   while another thread is visible.
2. Participant runtime and active-tool projection are stored and restored per
   conversation.
3. Participant approval blocks only the owner and emits its runtime approval
   event to the owning generation.
4. A foreign visible thread can complete work while the owner waits.
5. Every participant success, pause, empty-roster completion, and failure path
   terminalizes exactly its own runtime generation and releases its busy
   registration.
6. Detached failure cannot modify the visible thread's messages, loading state,
   error, or runtime.
7. Existing ordering, prompts, handoff parsing, read-only tool policy, and
   same-thread behavior remain compatible.
8. No part, manifest, marker, schema migration, generated file, or budget
   change.

## Verification

```bash
fvm dart format \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  lib/features/chat/presentation/providers/chat_notifier_participant_turns.dart \
  lib/features/chat/presentation/providers/thread_scoped_chat_state.dart \
  lib/features/chat/presentation/providers/chat_notifier_execution_runtime.dart \
  test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart \
  --set-exit-if-changed
tool/codex_verify.sh \
  --test test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart \
  --test test/features/chat/presentation/providers/chat_notifier_test.dart
fvm flutter test test/quality/file_size_ratchet_test.dart
fvm dart run tool/audit_chat_notifier_turn_scope.dart \
  --write-baseline tool/chat_notifier_turn_scope_baseline.json
git diff -- tool/chat_notifier_turn_scope_baseline.json
fvm dart run tool/audit_chat_notifier_turn_scope.dart \
  --check-baseline tool/chat_notifier_turn_scope_baseline.json
tool/codex_verify.sh --coverage
awk -v target='lib/features/chat/presentation/providers/chat_notifier_participant_turns.dart' \
  -v minimum=89.03 '
    /^SF:/ { selected = index(substr($0, 4), target) > 0 }
    selected && /^LF:/ { found = substr($0, 4) + 0 }
    selected && /^LH:/ { hit = substr($0, 4) + 0 }
    END {
      rate = 100 * hit / found
      printf "%s: %.2f%% (%d/%d)\n", target, rate, hit, found
      exit !(found > 0 && rate + 0.001 >= minimum)
    }
  ' coverage/lcov.info
awk -v target='lib/features/chat/presentation/providers/thread_scoped_chat_state.dart' \
  -v minimum=100 '
    /^SF:/ { selected = index(substr($0, 4), target) > 0 }
    selected && /^LF:/ { found = substr($0, 4) + 0 }
    selected && /^LH:/ { hit = substr($0, 4) + 0 }
    END {
      rate = 100 * hit / found
      printf "%s: %.2f%% (%d/%d)\n", target, rate, hit, found
      exit !(found > 0 && rate + 0.001 >= minimum)
    }
  ' coverage/lcov.info
awk -v target='lib/features/chat/presentation/providers/chat_notifier_execution_runtime.dart' \
  -v minimum=83.93 '
    /^SF:/ { selected = index(substr($0, 4), target) > 0 }
    selected && /^LF:/ { found = substr($0, 4) + 0 }
    selected && /^LH:/ { hit = substr($0, 4) + 0 }
    END {
      rate = 100 * hit / found
      printf "%s: %.2f%% (%d/%d)\n", target, rate, hit, found
      exit !(found > 0 && rate + 0.001 >= minimum)
    }
  ' coverage/lcov.info
git diff --check
```

The corrected Slice 2b1 live canary is required because this slice changes
production participant, approval, and lifecycle code. Verify the endpoint
first and record the reachable base URL, exact warmed model, per-conversation
generations, terminal event counts, and final busy IDs.

## Stop Conditions

- Stop if participant transcript code falls back to visible `state.messages`
  for a registered generation.
- Stop if approval or runtime emission cannot receive the owner generation
  without changing every unrelated approval domain.
- Stop if terminalization would split ownership away from the notifier's
  lifecycle keep set.
- Stop and record simultaneous independently paused participant loops as a
  follow-up if they require a new runtime schema or per-thread notifier design.
- Stop if the fix changes participant ordering/tool policy, requires a new
  notifier part or production extraction, or increases the aggregate budget.

## Handoff Notes

- Record A/B participant identities, generations, handoff targets, and approval
  IDs.
- Record runtime event sequences and terminal counts per conversation.
- Record persisted transcript ownership and final busy IDs.
- Record target-file coverage and aggregate line counts.
- Record deferred global participant-runtime limitations.
- Keep this slice in one focused Conventional Commit.

## Implementation Evidence

Runtime cleanup commit `24d76247` releases ownership and removes the inserted
active handle when runtime start preparation throws. Participant isolation
commit `47cf8307` carries an explicit conversation owner and interaction
generation through participant streaming, approval, tool activity, transcript
persistence, pause, continuation, failure, cancellation, usage emission, and
runtime terminalization.

The deterministic A/B fixtures use distinct generated conversation IDs and
stable participant IDs. The primary handoff fixture records
`a-primary -> a-reviewer`, preserves `a-reviewer` as the handoff target, binds
the generated approval ID to A's runtime generation, lets `b-primary` complete
independently, and emits exactly one terminal event for each conversation. The
additional poison fixtures prove:

- A's gated `read_file` activity restores the exact `activeToolName` and
  `a-active-tool` participant after an A-to-B-to-A switch, while B remains
  unchanged;
- A's manual and auto-review approval paths cannot read B's transcript, and a
  stale or cancelled approval ID cannot execute a tool;
- a paused A discussion terminalizes its first generation and resumes with a
  distinct second generation while B remains idle;
- stream failure, tool-definition setup failure, an empty enabled roster, and
  cancellation each produce one owner terminal and release the busy
  registration;
- cancellation during gated failure persistence wins over the delayed write
  and cannot project a stale error into A or B.

`tool/codex_verify.sh` passed code generation, project and package analysis, all
three package suites, and the 368-test focused ChatNotifier matrix. The
detached-turn file passed all 48 tests; the participant runner, approval widget,
and file-size ratchet matrix brought the direct focused total to 134 tests.
The full coverage run reached `+4219 -2`. Its only failures remained the
pre-existing M33 release-packaging tests:

- `M33 release packaging report validates static packaging lane`;
- `M33 release packaging CLI writes JSON and Markdown outputs`.

Those checks are outside every Slice 2b7 path and still report the separately
tracked static packaging readiness drift. Final LCOV reports participant turns
at `308/333` (`92.49%`), thread-scoped state at `95/95` (`100.00%`), execution
runtime at `49/57` (`85.96%`), and the participant completion runner at
`83/104` (`79.81%`).

The primary notifier fell from 9,374 to 9,364 physical lines, the declared part
count remains 42, and the same-library aggregate remains exactly 22,887 lines.
The reviewed audit baseline remains schema version 1 and records ambient reads
falling from 138 to 133 and turn-reachable reads falling from 122 to 118.
The refreshed baseline check, file-size ratchet, formatter, analyze, and
`git diff --check` all pass.

The remaining deferred limitations are explicit. Cancellation still advances a
global generation and clears all active registrations while terminalizing only
the selected generation. The paused cursor, participant stop flag, and
interaction origin remain notifier-global, so simultaneous independently
paused participant loops are not supported. Finish reason, token usage, and
conversation taint also remain shared data-source/notifier state. A later
per-turn metadata design must address those boundaries without broadening this
gate slice.

The exact-model corrected Slice 2b1 live canary passed on 2026-07-28 against
loaded `qwen3.6-27b-vision` at `http://192.168.100.241:1234/v1`. Its exact
per-conversation generations, terminal counts, and zero-busy-owner evidence
are recorded in the Slice 2b1 handoff. This completes Slice 2b7.
