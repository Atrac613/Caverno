# ChatNotifier Decomposition Corrective Prerequisite Task Catalog

Status: P1a-P6, P12, and P14 complete. P7-P11 and P13 have completed focused
acceptance and remain in progress pending integrated full verification and the
exact-model live canary. P3 and P10 remain split into their separately reviewed
`a` and `b` slices.

The 2026-07-28 Workstream 4-8 audit found ownership, atomic-completion,
shared-policy, and size stop conditions that cannot be hidden inside
behavior-preserving extraction commits. This catalog retains 18 corrective
areas and splits P3 into P3a and P3b, for 19 focused review slices. Each heading
below is one task, one commit, and one corrected live canary.

## Current Baseline

- `chat_notifier.dart`: 9,133 physical lines; ceiling 9,133.
- Declared parts: 42 files and 13,549 physical lines.
- Same-library aggregate: 22,682 physical lines; ceiling 22,682.
- Manifest: 43 historical part records.
- Turn-scope baseline: 74 ambient reads and 64 turn-reachable reads.

Remeasure before every task. Preserve the distinction between current part
directives and historical manifest records.

## Catalog-Wide Contract

- Use `ChatTurnOwner` from P1a for every owner-keyed API. Never substitute a
  generation-only key, current conversation, visible messages, a provider
  lookup, a Zone, or an unvalidated string ID.
- Keep each task below roughly 500 changed production lines. Stop and split
  mechanical adoption from policy work if that boundary would be exceeded.
- The prerequisites do not change a decomposition part status or add a
  decomposition marker unless a task explicitly says so. Infrastructure and
  existing independent services are not falsely registered against a
  `remaining` part. Add every new or newly governed production file to the
  shrink-only file-size budget at its achieved count.
- Primary and same-library budgets never increase. Record physical deltas even
  when a task has no part transition.
- Every keyed-store test must prove that two owners, including equal synthetic
  generation values where the store API permits them, cannot read, consume,
  clear, replace, or cancel each other's state.
- Run this common gate after the focused verification named by each task:

  ```bash
  fvm flutter analyze
  fvm flutter test \
    test/quality/chat_notifier_collaborator_boundary_test.dart \
    test/quality/file_size_ratchet_test.dart \
    test/quality/thread_scoped_state_ratchet_test.dart \
    test/tool/audit_chat_notifier_turn_scope_test.dart
  fvm dart run tool/audit_chat_notifier_turn_scope.dart \
    --manifest tool/chat_notifier_decomposition_manifest.json \
    --check-baseline tool/chat_notifier_turn_scope_baseline.json
  ```

- If reviewed production exposure shrinks, continue with the canonical
  baseline workflow. Never write first merely to silence an unexplained
  failure:

  ```bash
  fvm dart run tool/audit_chat_notifier_turn_scope.dart \
    --manifest tool/chat_notifier_decomposition_manifest.json \
    --write-baseline tool/chat_notifier_turn_scope_baseline.json
  git diff -- tool/chat_notifier_turn_scope_baseline.json
  fvm dart run tool/audit_chat_notifier_turn_scope.dart \
    --manifest tool/chat_notifier_decomposition_manifest.json \
    --check-baseline tool/chat_notifier_turn_scope_baseline.json
  tool/codex_verify.sh --coverage
  git diff --check
  ```

- Check every named target in `coverage/lcov.info` at the task's minimum. Use
  the catalog assertion from the Workstream task files; a coverage report alone
  is not a numerical gate.
- Every production prerequisite runs the exact-model canary:

  ```bash
  reachable_base_url='<reachable-base-url>'
  curl -fsS "$reachable_base_url/models"
  CAVERNO_MULTI_THREAD_LIVE_CANARY=1 \
  CAVERNO_LLM_BASE_URL="$reachable_base_url" \
  CAVERNO_LLM_API_KEY=no-key \
  CAVERNO_LLM_MODEL=qwen3.6-27b-vision \
  fvm flutter test integration_test/multi_thread_plan_live_canary_test.dart \
    -d flutter-tester
  ```

  Record the reachable `/v1` endpoint, exact returned model ID, expected
  owner/generation exits, zero busy owners, and exactly one `turn_exit` per
  expected turn.

## P1a: Define ChatTurnOwner and TurnOwnerSnapshotRegistry

### Task

- Goal: define the shared composite owner type and an immutable, owner-keyed
  snapshot registry for facts that later policies must not derive from visible
  state.
- User-visible behavior: none.
- Non-goals: migrating every current consumer; P1b owns adoption.

### Files and API

- Add `lib/features/chat/domain/entities/chat_turn_owner.dart` with
  `conversationId` and `interactionGeneration` value equality.
- Add
  `lib/features/chat/presentation/providers/turn_owner_snapshot_registry.dart`.
- Update
  `lib/features/chat/presentation/providers/active_response_registry.dart` and
  `lib/features/chat/presentation/providers/chat_notifier.dart` only for
  capture/update/dispose adapters.
- Add
  `test/features/chat/presentation/providers/turn_owner_snapshot_registry_test.dart`.
- Snapshot fields: owner messages, latest user content, attachment presence,
  owning project root, `LlmSessionLogContext`, workspace/mode flag, planning
  flag, pending auto-continue workflow flag, saved task, and allowed tool
  names. Allowed names may be updated only through the same owner key after
  request preparation.
- `ActiveResponseRegistry` may still allocate globally increasing generations,
  but registry lookup must validate its conversation ID against the requested
  owner. The new snapshot registry itself must support equal generations in
  different conversations.

### Manifest, Budget, and Coverage

- No part or manifest transition; no decomposition marker.
- Add both new files to the size budget.
- Target
  `turn_owner_snapshot_registry.dart` at 100% line coverage.

### Search, Acceptance, and Verification

- Search: `_activeAllowedToolNames`, `_latestPythonInputMessage`,
  `_getEffectiveCodingProject`, `_currentLlmSessionLogContext`,
  `_isCodingWorkspaceOrMode`, `_hasPendingAutoContinueExecutionWorkflow`,
  `_savedTaskForGeneration`, and `ActiveResponseRegistry`.
- Verify:

  ```bash
  fvm dart format \
    lib/features/chat/domain/entities/chat_turn_owner.dart \
    lib/features/chat/presentation/providers/turn_owner_snapshot_registry.dart \
    lib/features/chat/presentation/providers/active_response_registry.dart \
    lib/features/chat/presentation/providers/chat_notifier.dart \
    test/features/chat/presentation/providers/turn_owner_snapshot_registry_test.dart \
    --set-exit-if-changed
  fvm flutter test --coverage \
    test/features/chat/presentation/providers/turn_owner_snapshot_registry_test.dart
  ```

- Accept only when missing/deleted/detached owners, equal synthetic
  generations, distinct projects/messages/tool sets, update-after-dispose, and
  owner mismatch are covered.
- Handoff: record API, capture/update/dispose ordering, counts, target
  coverage, poison cases, and canary identities.

### Unblocks

- P1b, P2, P3a, P3b, P5a-P5c, P6-P11, P13, WS6-1, and every later typed
  owner port.

### Completion Evidence

- Completed on 2026-07-28. `ChatTurnOwner` is the normalized composite value
  key. `TurnOwnerSnapshotRegistry` exposes exact-owner capture, lookup, message
  update, allowed-tool update, dispose, and clear operations.
  `ActiveResponseRegistry.registerWithSnapshot` couples active registration
  and snapshot capture; message and allowed-tool facts update only after exact
  owner validation; generation disposal removes the snapshot and session-log
  context before releasing active maps. The participant part received only the
  matching allowed-tool capture adapter.
- The captured immutable facts are owner messages, latest user content,
  attachment presence, project root, session-log context, coding/workspace
  mode, planning state, pending auto-continue workflow state, saved task, and
  the effective allowed-tool set. Missing or mismatched conversations capture
  no project, workflow, or saved-task facts.
- Physical counts are 43 lines for `chat_turn_owner.dart`, 261 for
  `turn_owner_snapshot_registry.dart`, 317 for
  `active_response_registry.dart`, 9,374 for `chat_notifier.dart`, and 13,526
  across the 42 declared parts. The same-library aggregate is exactly 22,900;
  P1b must create headroom rather than raise the ceiling. The manifest remains
  unchanged. Exact-owner re-resolution in direct plan generation removed one
  reviewed ambient read, lowering the baseline from 133 to 132 while
  turn-reachable reads remain 118.
- The focused registry suite passed 30 tests. Line coverage was 17/17 for
  `chat_turn_owner.dart`, 106/106 for
  `turn_owner_snapshot_registry.dart`, and 135/135 for
  `active_response_registry.dart`. Poison cases cover missing and deleted
  owners, detached lookup, equal generations in different conversations,
  distinct projects/messages/tool sets, update after dispose, and both
  snapshot-builder and conversation owner mismatch.
- Static analysis, the four structural/size/thread-scope gates, the canonical
  baseline check, and 375 existing active-response and ChatNotifier regressions
  passed. The full coverage verifier reached 4,251 passing tests and retained
  only the two pre-existing unrelated M33 release-packaging failures.
- The exact-model canary passed at `http://192.168.100.241:1234/v1`; `/models`
  reported `qwen3.6-27b-vision` loaded. Exact exits were plan
  `{e444ad5b-3358-4c51-ba23-8f52d13f5c0d: [gen-2, gen-6],
  ea8be81e-e279-4c9b-a429-b6285d839bb4: [gen-4, gen-7]}`, coding
  `{6027a4ea-54cf-48f5-ac26-c822bebece30: [gen-2],
  4cb2d7d7-4f32-4ac6-ab08-ac7dc110a431: [gen-3]}`, queued
  `{2fb1222a-6747-4484-9861-1d6a276414da: [gen-1, gen-2]}`, and handback
  `{ea8b0810-ed42-424b-88d9-23aadf56bdd7: [gen-2],
  a5f698bc-7eaf-4c8d-8e7b-a6a4e9b07078: []}`. Every expected turn emitted
  exactly one `turn_exit`, and every scenario ended with zero busy owners.

## P1b: Adopt Explicit Turn Owner Snapshots

### Task

- Goal: replace the audited ambient owner facts with P1a snapshots before
  extracting their consumers.
- User-visible behavior: owner-correct inputs with compatible single-thread
  results.
- Non-goals: moving feature policies or handlers.

### Files and Tests

- Update:
  - `lib/features/chat/presentation/providers/chat_notifier.dart`;
  - `chat_notifier_prompt_context.dart`;
  - `chat_notifier_python_handlers.dart`;
  - `chat_notifier_python_attachment_repair.dart`;
  - `chat_notifier_coding_continuation_recovery.dart`;
  - `chat_notifier_unexecuted_action_recovery.dart`;
  - the LSP and run-tests call sites in `chat_notifier_local_file_handlers.dart`.
- Add
  `test/features/chat/presentation/providers/chat_notifier_turn_owner_snapshot_adoption_test.dart`.
- Extend
  `test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart`.

### Manifest, Budget, and Coverage

- No part or manifest transition; no new production file or marker.
- Reconcile primary/aggregate deltas and lower the turn-scope baseline only
  after reviewing every removed ambient read.
- No new-file percentage. The poison tests and full gate are the acceptance
  coverage.

### Search, Acceptance, and Verification

- Search the P1a terms plus every direct caller. Stop if any migrated path
  falls back to visible state after a missing snapshot.
- Verify:

  ```bash
  fvm dart format \
    lib/features/chat/presentation/providers/chat_notifier.dart \
    lib/features/chat/presentation/providers/chat_notifier_prompt_context.dart \
    lib/features/chat/presentation/providers/chat_notifier_python_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_python_attachment_repair.dart \
    lib/features/chat/presentation/providers/chat_notifier_coding_continuation_recovery.dart \
    lib/features/chat/presentation/providers/chat_notifier_unexecuted_action_recovery.dart \
    lib/features/chat/presentation/providers/chat_notifier_local_file_handlers.dart \
    test/features/chat/presentation/providers/chat_notifier_turn_owner_snapshot_adoption_test.dart \
    test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart \
    --set-exit-if-changed
  tool/codex_verify.sh \
    --test test/features/chat/presentation/providers/chat_notifier_turn_owner_snapshot_adoption_test.dart \
    --test test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart
  ```

- Handoff: list every removed ambient read, snapshot field used, missing-owner
  behavior, counts, poison cases, and canary identities.

### Completion Evidence (2026-07-28)

- P1b adopted every `TurnOwnerSnapshot` field: `owner`, `messages`,
  `latestUserContent`, `hasAttachments`, `projectRoot`, `sessionLogContext`,
  `isCodingWorkspaceOrMode`, `isPlanning`,
  `hasPendingAutoContinueExecutionWorkflow`, `savedTask`, and
  `allowedToolNames`. Prompt construction, Python attachment repair, coding
  continuation, planning policy, project-scoped dispatch, command guardrails,
  final claim guards, saved-task validation, and goal logging now resolve from
  the registered owner instead of the visible conversation.
- The reviewed audit removed 18 ambient reads and added none. The removed
  reads were `_enforcePlanningToolPolicy.currentConversation`,
  `_getActiveProjectRootPath.effectiveCodingProject`,
  `_latestUserContentForGeneration.state.messages`,
  `_prepareMessagesForLLM.currentConversation`,
  `_prepareMessagesForLLM.state.messages`, three
  `_sendMessageNow.currentConversation` reads,
  `_hasPendingAutoContinueExecutionWorkflow.currentConversation`,
  `_isCodingWorkspaceOrMode.currentConversation`,
  `_createSystemMessage.currentConversation`,
  `_loadReferencedSpecification.effectiveCodingProject`,
  `_markPendingExecutionTaskStarted.currentConversation`,
  `_messageContentWithNarratedTranscriptClaimNotice.currentConversation`,
  `_messageContentWithUnwrittenFileClaimNotice.currentConversation`,
  `_messageContentWithUnwrittenFileClaimNotice.effectiveCodingProject`,
  `_messageContentWithVerificationClaimNotice.currentConversation`, and
  `_requestNarratedTranscriptRepairForCompletionClaim.currentConversation`.
  The canonical baseline fell from 132 to 114 ambient reads and from 118 to
  101 turn-reachable reads.
- No migrated path falls back to visible-thread state when its snapshot is
  absent. Prompt preparation throws, tool dispatch returns
  `turn_owner_snapshot_unavailable`, project dispatch uses a rootless
  fail-closed sentinel, and diagnostic-only logging uses an unassigned context.
  The sentinel also avoids eagerly constructing the coding-project provider.
- The owner poison matrix proved that A retains its messages, latest request,
  coding/workflow mode, project, session context, pending execution workflow,
  and tool allowlist while B is visible. Detached `run_tests` and LSP
  definition lookup also used A's project after B became visible. The specified
  adoption and detached suites passed 53 tests; the ordinary ChatNotifier
  suite passed 314 tests; the common boundary, size, and scope gate passed 111
  tests; analysis and the canonical baseline check passed.
- Physical counts are 9,376 lines for `chat_notifier.dart`, 13,522 across the
  42 declared parts, and 22,898 for the same-library aggregate. Both shrink-only
  ceilings remain unchanged at 9,380 and 22,900. The full coverage verifier
  reached 4,256 passing root tests and retained only the two pre-existing,
  unrelated M33 release-packaging failures.
- The exact-model canary passed all four scenarios against the loaded
  `qwen3.6-27b-vision` model at `http://192.168.100.241:1234/v1`. Exact exits
  were plan
  `{207af35a-bd9f-4ff2-9796-c1ea6e2ebc15: [gen-2, gen-6],
  f4462ba7-df4b-499e-a200-5b66d957d82d: [gen-4, gen-7]}`, coding
  `{840246b4-03e6-464b-8a0d-dd3de7177f26: [gen-2],
  5ffd10b6-02d1-40a7-8899-9f1caccbe82f: [gen-3]}`, queued
  `{f241cfe3-3675-4ea6-b1c6-5fa3f6b544a9: [gen-1, gen-2]}`, and handback
  `{e73d4d20-f45b-4287-b2ed-e4f9135f0fb8: [gen-2],
  19746075-cea3-4845-a5ed-1a704eb06765: []}`. Every expected generation
  emitted exactly one `turn_exit`, and every scenario ended with zero busy
  owners.

### Unblocks

- WS4-1, WS4-2, WS4-3, WS4-5, WS5-1, WS5-4, WS5-6, WS5-7, WS6-2, WS6-7,
  WS6-10, and WS6-18.

## P2: Key TurnToolResultLedger by Owner

### Task

- Goal: key completed results, content results, and executed commands by
  `ChatTurnOwner`.
- User-visible behavior: one turn cannot overwrite or consume another turn's
  evidence.
- Non-goals: changing result classification.

### Files, Tests, and Contract

- Update
  `lib/features/chat/presentation/providers/turn_tool_result_ledger.dart`,
  `chat_notifier.dart`, `chat_notifier_tool_loop_batch.dart`,
  `chat_notifier_tool_result_telemetry.dart`,
  `chat_notifier_goal_auto_continue.dart`,
  `chat_notifier_turn_finalization_recovery.dart`, and
  `chat_notifier_unexecuted_action_recovery.dart`.
- Add
  `test/features/chat/presentation/providers/turn_tool_result_ledger_test.dart`
  and owner poison coverage in the detached-turn test.
- Every set/add/read/take/clear/command operation requires an owner. Preserve
  loop-before-content ordering, repair revival, and owner-local disposal.

### Manifest, Budget, Coverage, and Verification

- No part or manifest transition; no marker.
- Add the existing ledger file to the size budget at its achieved count.
- Target it at 100% line coverage.
- Search: `_turnToolResults`, `completed`, `content`, `commands`, `takeAll`,
  `clearResults`, and `beginCommandGeneration`.
- Verify:

  ```bash
  fvm dart format \
    lib/features/chat/presentation/providers/turn_tool_result_ledger.dart \
    lib/features/chat/presentation/providers/chat_notifier.dart \
    lib/features/chat/presentation/providers/chat_notifier_tool_loop_batch.dart \
    lib/features/chat/presentation/providers/chat_notifier_tool_result_telemetry.dart \
    lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart \
    lib/features/chat/presentation/providers/chat_notifier_turn_finalization_recovery.dart \
    lib/features/chat/presentation/providers/chat_notifier_unexecuted_action_recovery.dart \
    test/features/chat/presentation/providers/turn_tool_result_ledger_test.dart \
    --set-exit-if-changed
  fvm flutter test --coverage \
    test/features/chat/presentation/providers/turn_tool_result_ledger_test.dart
  ```

- Handoff: record lifecycle matrix, migrated callers, counts, coverage, poison
  cases, and canary identities.

### Completion Evidence (2026-07-29)

- `TurnToolResultLedger` stores completed loop results, streamed-content
  results, and executed commands under `ChatTurnOwner`. Every operation
  requires an owner. Snapshots preserve loop-before-content ordering, result
  clears retain repair command history, and take/dispose operations affect only
  the requested owner.
- `ContentToolTurnStateRegistry` and `HiddenAssistantEvidenceRegistry` isolate
  content continuation, dedupe, and hidden response evidence. Runtime events
  carry an explicit scoped generation and fail closed when no owner exists.
  Owner project roots drive tool dedupe and mutation signatures.
- `sendMessage`, `_sendMessageNow`, and `sendHiddenPrompt` return the producing
  owner. Workflow, live harness, page, voice, terminal, and canary callers use
  that returned owner. Final saves and cancellation persistence are serialized
  by `TurnMessagePersistenceCoordinator`; cancellation admission occurs before
  terminal lease release, and queued sends observe the persisted transcript.
- Terminal success, saved validation, coding verification progress, mutation
  generations, verifier replay candidates, and diagnostic streaks now resolve
  the exact owner conversation. Switching A to B during completion cannot
  advance B's verification generation, copy A's verifier candidate, or settle
  A evidence from B.
- The direct helper matrix passed 79 tests. Executable coverage was ledger
  66/66, content state 82/82, hidden evidence 47/47, tool dedupe 22/22, fenced
  blocks 8/8, owner snapshots 102/102, scoped generation 16/16, runtime events
  29/29, persistence 57/57, and active responses 135/138.
- The 77-test detached-turn suite, 55-test caller handoff, 313-test ordinary
  ChatNotifier suite, and 124-test common boundary, size, scope, and audit gate
  passed. Full analysis and the canonical baseline check passed.
- The canonical audit fell from the P1b baseline of 114 ambient and 101
  turn-reachable reads to 86 and 76. It removed 28 ambient reads and 25
  turn-reachable reads with no additions.
- Physical counts are 9,306 lines for `chat_notifier.dart`, 13,582 across the
  42 declared parts, 22,888 for the same-library aggregate, and 151 for the
  ledger. Primary and aggregate ceilings are 9,306 and 22,888. The independent
  persistence coordinator is 156 lines.
- The fresh final-tree coverage verifier ran generation, package analysis and
  tests, and root analysis before reaching 4,354 passing root tests. Its
  only failures were the two pre-existing, unrelated M33 static packaging
  checks whose direct-S3 predicates lag the CloudFront migration.
- The exact-model four-scenario canary passed against
  `qwen3.6-27b-vision`, loaded with a 65,536-token context at
  `http://192.168.100.241:1234/v1`. Exact counts were plan
  `{alpha: 2, beta: 2}`, coding `{alpha: 1, beta: 1}`, queued `{alpha: 2}`, and
  handback `{alpha: 1, beta: 0}`. Every expected generation emitted exactly one
  `turn_exit`, every scenario ended with zero busy owners, and the generated
  owner/generation identities are recorded in the fresh P5a evidence below.
- A separate read-only audit found a pre-existing cancelled-plan late-write
  path outside P2: delayed workflow/task proposal and decision retries can
  project or persist after runtime terminalization. It requires exact-owner
  guards inside the proposal loops plus immediate cancellation cleanup before
  any dependent plan-flow extraction.

### Unblocks

- P3a, P3b, WS5-2, WS5-5, WS5-6, WS5-7, WS7-6, WS7-11, and
  WS8-7.

## P3a: Key Finalization and Goal Claim State by Owner

### Task

- Goal: move genuinely flat turn-exit, transform, and goal-claim state into one
  owner-keyed registry.
- User-visible behavior: finalization state remains compatible for the visible
  turn, while detached claims cannot complete or shadow-log another owner.
  Detached-owner claim consumption was completed by P3b finalization.
- Non-goals: narrated-repair attempt signatures, which are already a local
  `Set` threaded through the turn call chain.

### Files and API

- Add
  `lib/features/chat/presentation/providers/turn_finalization_state_registry.dart`.
- Update `chat_notifier.dart`, `chat_notifier_turn_exit.dart`,
  `chat_notifier_execution_runtime.dart`,
  `chat_notifier_response_finalization.dart`,
  `chat_notifier_tool_loop_batch.dart`,
  `chat_notifier_unexecuted_action_recovery.dart`,
  `chat_notifier_final_answer_recovery.dart`,
  `chat_notifier_coding_continuation_recovery.dart`, and
  `chat_notifier_goal_auto_continue.dart`.
- Move `_turnExitReasonHint`, `_appliedTurnTransforms`,
  `_shadowGoalToolCompletionOutcome`, and `_toolGoalCompletionClaimed`.
- Add
  `test/features/chat/presentation/providers/turn_finalization_state_registry_test.dart`.

### Manifest, Budget, Coverage, and Verification

- No part or manifest transition; no marker.
- Add the registry to the size budget; target 100% line coverage.
- Search all four fields and every clear/consume call.
- Verify:

  ```bash
  fvm dart format \
    lib/features/chat/presentation/providers/turn_finalization_state_registry.dart \
    lib/features/chat/presentation/providers/chat_notifier.dart \
    lib/features/chat/presentation/providers/chat_notifier_turn_exit.dart \
    lib/features/chat/presentation/providers/chat_notifier_tool_loop_batch.dart \
    lib/features/chat/presentation/providers/chat_notifier_unexecuted_action_recovery.dart \
    lib/features/chat/presentation/providers/chat_notifier_final_answer_recovery.dart \
    lib/features/chat/presentation/providers/chat_notifier_coding_continuation_recovery.dart \
    lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart \
    test/features/chat/presentation/providers/turn_finalization_state_registry_test.dart \
    --set-exit-if-changed
  fvm flutter test --coverage \
    test/features/chat/presentation/providers/turn_finalization_state_registry_test.dart
  ```

- Accept only when consume/clear is owner-local and idempotent and transform
  order is unchanged.
- Handoff: record state schema, lifecycle, migrated calls, counts, coverage,
  poison cases, and canary identities.

### Unblocks

- WS5-5, WS5-6, and WS5-7.

### Completion Evidence

- Completed on 2026-07-29. `TurnFinalizationStateRegistry` owns
  `_turnExitReasonHint`, `_appliedTurnTransforms`,
  `_shadowGoalToolCompletionOutcome`, and `_toolGoalCompletionClaimed` under an
  exact `ChatTurnOwner`.
- `begin` registers an owner. Owner-local reset, reads, writes, and takes
  require that active state; mutations never create it. Exact `dispose` removes
  the owner and advances its per-conversation disposed-generation watermark,
  while global `clear` removes all state. The watermark rejects late writes.
  Transform IDs preserve insertion order and discard duplicates.
- The independent registry is 117 physical lines. Its four direct tests cover
  50/50 executable lines. The 80-test detached-owner suite includes
  `detached owner keeps its transform when another owner resets` and
  `detached goal claim cannot leak into visible owner finalization`. The latter
  is an isolation guard; the P3b completion below adds detached-owner claim
  consumption.
  The 313-test ordinary ChatNotifier suite, five read-only guard tests, and
  127-test common gate passed. Analysis and the canonical audit passed.
- The owner-aware audit now recognizes `ChatTurnOwner` parameters directly and
  removed four ambient `state.messages` reads. The checked-in baseline is 82
  ambient reads, 52 methods with ambient reads, 30 reads in methods with turn
  identity, 72 turn-reachable reads, and 44 accessor-bearing reads.
- The current tree is 9,219 primary lines, 13,570 declared-part lines, and
  22,789 same-library lines. No part or manifest transition and no marker were
  added; the manifest remains at 43 historical records.
- The fresh full verifier reached 4,361 passing root tests. Its only failures
  were the two known M33 release-packaging checks whose direct-S3 assumptions
  lag the CloudFront migration.
- The exact `qwen3.6-27b-vision` canary passed all four scenarios. Plan owners
  were `8ccb898e-6762-44bb-8a33-47f848230ba4` at generations 2 and 6 and
  `86277ce0-970c-4d4f-bfdc-e76752baef26` at generations 4 and 7. Concurrent
  coding owners were `55b8ced3-ac03-471f-a3b7-868fb66df7f4` at generation 2
  and `7b79adb2-aa14-4a8d-b57f-5489b8d6860b` at generation 3. Queued work used
  `f5770ced-654c-4c43-94f8-f93c8110a2df` at generations 1 and 2. Handback used
  `7cb78ec3-5d4c-434f-a00c-0c9b13cba28c` at generation 2 while
  `0799ad78-fc5f-400d-a06a-71df84c8fad1` correctly emitted no turn. Every
  expected generation emitted exactly one `turn_exit`, and every scenario
  ended with zero busy owners.

## P3b: Key Goal Completion Evidence by Owner

### Task

- Goal: replace flat `_latestGoalAutoContinueEvidence` storage with exact-owner
  state and an explicit typed handoff to a successor hidden continuation.
- User-visible behavior: unresolved completion evidence remains available to
  the intended continuation and cannot block or complete another turn.
- Non-goals: storage for exit, transform, claim, and shadow state, which P3a
  completed. P3b must still consume the detached owner's stored claim and
  shadow outcome through the exact-owner finalization path.

### Files and API

- Add
  `lib/features/chat/presentation/providers/turn_goal_completion_evidence_registry.dart`.
- Update `chat_notifier.dart`, `chat_notifier_execution_runtime.dart`,
  `chat_notifier_goal_auto_continue.dart`,
  `chat_notifier_response_finalization.dart`, and
  `chat_notifier_cancellation.dart`. Update `conversations_notifier.dart` so
  goal recording and persistence can target the exact detached conversation.
- Provide explicit `begin(owner, initialEvidence:)`, exact-owner lookup,
  replace/update, idempotent `dispose(owner)`, and global `clear`.
- Replace `preserveGoalAutoContinueEvidence` with a typed evidence seed. Capture
  the reconciled owner evidence before terminal disposal and pass that same
  immutable value to goal recording, auto-continue policy, logging, and any
  successor hidden turn. Do not add a conversation-level "latest" fallback.
- Finalize detached owners with that snapshot: consume their exact stored claim
  and shadow outcome, record the goal turn against their conversation, and
  preserve the visible owner's state.
- `TurnGoalCompletionFinalizer` must reconcile the exact owner's evidence and
  capture its one-shot claim and outcome before the first persistence await.
- Extend `recordCurrentGoalTurn` with an exact `conversationId` target while
  preserving the current-conversation default for existing callers.
- Add direct registry tests and a detached-owner poison test to
  `chat_notifier_detached_turn_project_test.dart`.

### Manifest, Budget, Coverage, and Verification

- No part or manifest transition; no marker.
- Add the independent registry to the shrink-only size budget and require 100%
  direct line coverage.
- Accept only when equal generations in different conversations remain
  isolated, cancellation/disposal affects one owner, late writes cannot
  resurrect state, and successor evidence is seeded only from the explicitly
  supplied snapshot.
- The notifier poison test must prove that failed evidence from detached owner
  A cannot prevent owner B from completing its own active goal while B is
  paused in final persistence.
- Extend detached-claim coverage so owner A's valid claim is consumed and
  completes A's goal without completing or shadow-logging owner B.
- Run analysis, direct coverage, detached and ordinary ChatNotifier suites, the
  common gate, the canonical audit, full verification, and the exact-model
  four-scenario canary.

### Unblocks

- WS8-7.

### Completion Evidence

- Completed on 2026-07-29. The 211-line
  `TurnGoalCompletionEvidenceRegistry` owns completion evidence under an exact
  `ChatTurnOwner`, with transactional `begin(owner, initialEvidence:)`,
  read-only call-time combination, producer replacement, final reconciliation,
  exact disposal, global clear, and per-conversation disposed-generation
  watermarks. Missing and disposed owners cannot be recreated by late writes.
- `TurnGoalCompletionFinalizer` reconciles the registered owner and consumes
  its P3a claim and shadow outcome before the first await. It records the goal
  against `owner.conversationId`, then forwards the captured raw outcome to the
  existing notifier shadow-log adapter. A turn that enters visible-path
  finalization freezes its goal token delta before the first persistence await,
  so later detachment cannot give it another owner's count. A turn detached
  before that boundary contributes zero. The pre-snapshot raw usage source was
  shared until P10b replaced flat response metadata with request-local capture.
- The flat `_latestGoalAutoContinueEvidence` value and
  `preserveGoalAutoContinueEvidence` boolean are removed. Hidden successors
  receive an immutable `initialGoalCompletionEvidence` seed only when the
  caller supplies the exact predecessor snapshot; no conversation-level latest
  fallback exists.
- Eleven direct tests cover all 59 executable registry/finalizer lines. The
  82-test detached suite includes failed-evidence isolation, explicit-only
  successor seeding, exact-owner accepted-claim completion without cross-owner
  shadow logging, and 11-versus-97 late-detachment goal-token isolation after
  the visible-path snapshot. The 313-test ordinary suite, 40 compatibility
  tests, 128-test common gate, analysis, and the canonical audit passed.
- The checked-in audit now reports 779 methods, 445 manifest entrypoints, 746
  reachable methods, 78 ambient reads, 49 methods with ambient reads, 30 reads
  in methods with turn identity, 68 turn-reachable reads, and 44
  accessor-bearing reads. P3b removed four `currentConversation` reads and
  added none.
- The current tree is 9,213 primary lines, 13,567 declared-part lines, and
  22,780 same-library lines. The ChatNotifier test library is 33,226 lines.
  No part or manifest transition and no marker were added; the manifest remains
  at 43 historical records.
- The fresh full verifier reached 4,375 passing root tests. Its only failures
  were the same two known M33 release-packaging checks whose direct-S3
  assumptions lag the CloudFront migration.
- The exact `qwen3.6-27b-vision` canary passed all four scenarios at
  `http://192.168.100.241:1234/v1`. Plan owners were
  `eb1bdd2f-fec2-4709-8b81-cb537a308667` at generations 2 and 6 and
  `c4b6d3f4-f16f-46b6-b41c-fe96cd735ba2` at generations 4 and 7. Concurrent
  coding owners were `8ce80db1-d1a8-44e7-a3af-41f0b64cac3a` at generation 2
  and `7ed01d64-4449-4024-93c8-c2b127048e3f` at generation 3. Queued work used
  `c0872fc5-9809-48a6-9e29-14c5905cb06c` at generations 1 and 2. Handback used
  `97e160e6-b39e-408c-8f05-dad3e9df27ad` at generation 2 while
  `4f48967c-e6bc-4c7a-ae85-7bfca100192a` correctly emitted no turn. Every
  expected generation emitted exactly one `turn_exit`, and every scenario
  ended with zero busy owners.

## P4: Extract FileMutationEvidencePolicy

### Task

- Goal: provide one independent policy for mutation tool classification,
  successful-result classification, and result/argument path extraction.
- User-visible behavior: current semantics remain byte-compatible.
- Non-goals: mutation execution, signature construction, or root selection.

### Files and API

- Add
  `lib/features/chat/domain/services/file_mutation_evidence_policy.dart`.
- Move the shared logic behind `_isFileMutationToolName`,
  `_isSuccessfulFileMutationToolResult`, and `_toolResultPayloadPath` from
  `chat_notifier.dart`.
- Update current callers in `chat_notifier.dart`,
  `chat_notifier_coding_verification_feedback.dart`,
  `chat_notifier_turn_finalization_recovery.dart`,
  `chat_notifier_command_guardrails.dart`, and
  `chat_notifier_git_handlers.dart`.
- Update the exact-name classification consumers in
  `final_answer_claim_detector.dart`, `tool_call_execution_policy.dart`,
  `tool_result_prompt_builder.dart`, `tool_terminal_response_policy.dart`,
  `unwritten_file_claim_guard.dart`, and
  `chat_notifier_terminal_tool_response_policy.dart`. Preserve their distinct
  success contracts.
- Replace the `_toolPathFromArguments` forwarding helper in
  `chat_notifier.dart`, move the already-extracted argument-path implementation
  out of `tool_dedupe_keys.dart`, and migrate its direct tests.
- Add
  `test/features/chat/domain/services/file_mutation_evidence_policy_test.dart`.
- Preserve the notifier rule that rejects `already_applied: true`; do not
  substitute the broader `FinalAnswerClaimDetector` result predicate.

### Manifest, Budget, Coverage, and Verification

- The notifier-owned helpers are in the primary file and
  `tool_dedupe_keys.dart` is not a part file, so there is no part/manifest
  transition and no decomposition marker.
- Add the policy to the size budget; target 100% line coverage.
- Search the four helper names, every mutation tool name, `already_applied`,
  and result-versus-argument path precedence.
- Verify:

  ```bash
  fvm dart format \
    lib/features/chat/domain/services/file_mutation_evidence_policy.dart \
    lib/features/chat/domain/services/final_answer_claim_detector.dart \
    lib/features/chat/domain/services/tool_call_execution_policy.dart \
    lib/features/chat/domain/services/tool_result_prompt_builder.dart \
    lib/features/chat/domain/services/tool_terminal_response_policy.dart \
    lib/features/chat/domain/services/unwritten_file_claim_guard.dart \
    lib/features/chat/presentation/providers/chat_notifier.dart \
    lib/features/chat/presentation/providers/chat_notifier_coding_verification_feedback.dart \
    lib/features/chat/presentation/providers/chat_notifier_turn_finalization_recovery.dart \
    lib/features/chat/presentation/providers/chat_notifier_command_guardrails.dart \
    lib/features/chat/presentation/providers/chat_notifier_git_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_terminal_tool_response_policy.dart \
    lib/features/chat/presentation/providers/tool_dedupe_keys.dart \
    test/features/chat/domain/services/file_mutation_evidence_policy_test.dart \
    test/features/chat/presentation/providers/tool_dedupe_keys_test.dart \
    --set-exit-if-changed
  fvm flutter test --coverage \
    test/features/chat/domain/services/file_mutation_evidence_policy_test.dart
  ```

- Handoff: record tool/classification matrix, path cases, counts, coverage, and
  canary identities.

### Completion Evidence (2026-07-29)

- `FileMutationEvidencePolicy` is an independent domain service with no
  notifier, provider, Zone, filesystem, root-selection, signature, or
  execution dependency. It recognizes only `write_file`, `edit_file`,
  `delete_file`, and `rollback_last_file_change` after trim and lowercase
  normalization.
- The notifier success contract remains byte-compatible: empty, `error:`,
  auto-review denial, structured error, `already_applied: true`, and the three
  existing denied codes fail. Malformed text, non-object JSON, `ok: false`,
  `already_applied: false`, string `already_applied`, and unknown codes still
  succeed.
- Result payload paths take precedence over argument paths. Both sources
  require an exact string `path` key and return its trimmed non-empty value.
  Root resolution and mutation signatures remain outside the policy.
- All exact-name consumers delegate to the new policy. The broader
  `FinalAnswerClaimDetector`, stricter `ToolResultPromptBuilder`, and
  `UnwrittenFileClaimGuard` result predicates remain intentionally separate.
  The temporary presentation-layer argument-path helper and its duplicate
  tests were removed.
- The direct policy suite passed 12 tests with 33/33 executable lines covered.
  The 97-test adjacent-policy suite, 313-test ordinary ChatNotifier suite,
  125-test common boundary/size/scope/audit gate, full analysis, and canonical
  audit passed.
- Physical counts are 65 lines for the policy, 62 for `tool_dedupe_keys.dart`,
  9,258 for `chat_notifier.dart`, 13,580 across its 42 declared parts, and
  22,838 for the same-library aggregate. Matching shrink-only ceilings are
  checked in. The audit retained 86 ambient and 76 turn-reachable reads while
  lowering methods from 787 to 783 and reachable methods from 753 to 749.
- The 2026-07-29 lifecycle readiness check restored
  `qwen3.6-27b-vision` to `loaded` and left
  `qwen3.6-35b-a3b-vision` `unloaded` at
  `http://192.168.100.241:1234/v1`.
- The fresh final-tree coverage verifier ran generation, package analysis and
  tests, and root analysis before reaching 4,354 passing root tests. Its
  only failures were the two pre-existing M33 static packaging checks that
  still expect the pre-CloudFront direct-S3 configuration. Focused reruns
  reproduced both failures without any P2, P4, or P5a file in their inputs.
- The exact-model four-scenario canary passed against the loaded
  `qwen3.6-27b-vision` model at `http://192.168.100.241:1234/v1`, completing P4
  and unblocking WS5-4.

### Unblocks

- WS5-4 and later mutation-evidence consumers.

## P5a: Key ToolApprovalCache by Owner

### Task

- Goal: make cached approval and denial decisions owner-specific.
- User-visible behavior: repeated calls reuse only the same owner's decision.
- Non-goals: pending UI DTO ownership, handled by P5b/P5c.

### Files, Tests, and Contract

- Update `tool_approval_cache.dart`, `chat_notifier.dart`, approval handlers,
  the tool-handler registry, execution runtime, and every cache-capable local
  file/process/test, Git, SSH, Python, BLE, serial, and Computer Use handler.
  Browser and participant approval paths remain explicitly cache-free.
- Reuse `ChatTurnOwner`; keep normalized non-semantic arguments and state
  fingerprint behavior.
- Add owner to lookup/remember/clear, issue a revocable owner-bound capability
  at dispatch, and provide owner-local plus global disposal APIs.
- Update `test/features/chat/presentation/providers/tool_approval_cache_test.dart`
  and add detached-turn notifier poison coverage.
- Do not migrate pending approval DTO ownership or stale-resolution validation;
  those remain P5b/P5c work.

### Manifest, Budget, Coverage, and Verification

- No part/manifest transition or marker.
- Add the cache file to the size budget; target 100% line coverage.
- Search `_toolApprovalCache`, `_lookupToolApprovalResult`,
  `_rememberToolApprovalResult`, `_rememberToolApprovalDenial`, and `clear`.
- Verify:

  ```bash
  fvm dart format \
    lib/features/chat/presentation/providers/chat_notifier.dart \
    lib/features/chat/presentation/providers/tool_approval_cache.dart \
    lib/features/chat/presentation/providers/chat_notifier_approval_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_ble_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_browser_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_computer_use_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_execution_runtime.dart \
    lib/features/chat/presentation/providers/chat_notifier_git_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_local_file_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_participant_turns.dart \
    lib/features/chat/presentation/providers/chat_notifier_python_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_serial_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_ssh_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_tool_handler_registry.dart \
    test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart \
    test/features/chat/presentation/providers/tool_approval_cache_test.dart \
    test/quality/file_size_ratchet_test.dart \
    --set-exit-if-changed
  fvm flutter test --coverage \
    test/features/chat/presentation/providers/tool_approval_cache_test.dart
  fvm flutter test \
    test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart
  ```

- Handoff: record key schema, clear semantics, counts, coverage, poison cases,
  and canary identities.

### Completion Evidence (2026-07-29)

- `ToolApprovalCache` is a map from exact `ChatTurnOwner` to the existing call
  key: exact tool name, non-semantic arguments removed, nested values
  normalized, and the unchanged optional state fingerprint. Equal
  generations in different conversations and later generations in the same
  conversation cannot share entries.
- Dispatch resolves the immutable owner snapshot and explicitly passes a
  revocable `OwnerToolApprovalCache` capability to every cache-capable handler.
  A missing snapshot fails closed. Revocation prevents a late asynchronous
  handler from repopulating an owner after terminal disposal.
- Terminalization clears and revokes only its exact owner before releasing the
  snapshot. `clearMessages` and provider disposal clear every owner. Starting
  or switching turns no longer globally clears another active owner's cache.
  Full-access and bypassed flows remain uncached; grants re-execute the tool,
  while denials replay the exact cached `McpToolResult`.
- The approval-gate signature migration touched 14 production files:
  cache-capable handlers received the owner capability, while browser and
  participant paths adapted explicitly as cache-free. The resulting 567 changed
  production lines slightly exceed the catalog's approximate 500-line target,
  but splitting the mechanical migration would leave inconsistent handler
  families on a stale global contract. No P5b/P5c DTO or stale-resolution work
  entered the slice.
- The 208-line cache passed 12 direct tests with 60/60 executable lines
  covered. The 78-test detached-turn suite passed the A-approve,
  B-fresh-prompt, A-reuse, B-deny sequence. The 313-test ordinary ChatNotifier
  suite, 126-test common boundary/size/scope/audit gate, full analysis, and
  canonical baseline check passed.
- The completion tree is 9,257 primary lines, 13,566 lines across 42 declared
  parts, and 22,823 same-library lines. Matching shrink-only ceilings are
  checked in. The historical manifest remains at 43 records with no P5a marker.
  The audit reduced scanned methods from 783 to 780 and manifest entrypoints
  from 454 to 451 while retaining 749 reachable methods, 86 ambient reads, and
  76 turn-reachable reads.
- The fresh coverage verifier reached 4,354 passing root tests and retained only
  the two pre-existing, unrelated M33 static release-packaging failures. Focused
  reruns tied those failures to stale direct-S3 predicates after the CloudFront
  migration, outside every P5a input.
- The exact-model canary passed at `http://192.168.100.241:1234/v1` with
  `qwen3.6-27b-vision` loaded and `qwen3.6-35b-a3b-vision` unloaded. Exact exits
  were plan
  `{7a012726-39dd-4f59-a7a9-7a8f395976b1: [gen-2, gen-6],
  4775001a-1428-4e20-8efc-27cf8a2c9d1c: [gen-4, gen-7]}`, coding
  `{d2e65351-c945-4cb1-9498-58093b6d540c: [gen-2],
  e6bc8dea-7d4b-49cf-848e-41301357181d: [gen-3]}`, queued
  `{56b9123d-3745-48dd-814c-28a1a919eeb3: [gen-1, gen-2]}`, and handback
  `{00d4e845-a1b4-406c-b886-35a1e1bd223f: [gen-2],
  fe90beff-25f1-49a2-bb60-1cba19e47386: []}`. Every expected generation emitted
  exactly one `turn_exit`, and every scenario ended with zero busy owners.

### Unblocks

- WS6-1 after P11 is also complete.

## P5b: Key Command, File, Git, and SSH Approval Requests

### Task

- Goal: add owner identity and stale-resolution validation to command/file/Git/
  SSH approval DTOs and adapters.
- User-visible behavior: approval UI text and outcomes remain compatible.
- Non-goals: BLE, serial, browser, Computer Use, and participant approvals.

### Files and Tests

- Update `PendingSshConnect`, `PendingSshCommand`, `PendingGitCommand`,
  `PendingLocalCommand`, and `PendingFileOperation` in
  `lib/features/chat/presentation/providers/chat_state.dart`.
- Update approval request/resolve/cancel paths in
  `chat_notifier_local_file_handlers.dart`, `chat_notifier_git_handlers.dart`,
  `chat_notifier_ssh_handlers.dart`, `chat_notifier_python_handlers.dart`,
  `chat_notifier_skill_handlers.dart`, and `chat_notifier_routine_handlers.dart`.
- Add
  `test/features/chat/presentation/providers/pending_command_file_approval_ownership_test.dart`.

### Manifest, Budget, Coverage, and Verification

- No part/manifest transition, marker, new independent production file, or
  generated output. The pending DTOs are plain Dart classes; do not regenerate
  `chat_state.freezed.dart` unless the `ChatState` Freezed shape also changes.
- Record primary/aggregate deltas; never raise a budget.
- Search every named DTO, request/resolve method, completer, and cancellation
  path.
- Verify:

  ```bash
  fvm dart format \
    lib/features/chat/presentation/providers/chat_state.dart \
    lib/features/chat/presentation/providers/chat_notifier_local_file_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_git_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_ssh_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_python_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_skill_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_routine_handlers.dart \
    test/features/chat/presentation/providers/pending_command_file_approval_ownership_test.dart \
    --set-exit-if-changed
  fvm flutter test \
    test/features/chat/presentation/providers/pending_command_file_approval_ownership_test.dart
  ```

- Accept only when stale/cancelled IDs cannot execute and each owner resolves
  or clears only its own pending request.
- Handoff: record DTO schema, unchanged generated files, adapters, poison
  cases, counts, and canary identities.

### Completion Evidence (2026-07-30)

- `PendingSshConnect`, `PendingSshCommand`, `PendingGitCommand`,
  `PendingLocalCommand`, and `PendingFileOperation` now require an exact
  `ChatTurnOwner`. `PendingCommandFileApprovalRegistry` owns their typed
  completers under owner and ID indexes, rejects duplicate IDs and
  owner/type mismatches, removes requests before completion, and provides
  owner-local and global cancellation with the existing safe denial values.
  `ThreadScopedChatState` remains only an owner-aware presentation projection.
- Local command, process, file, rollback, Git, SSH, Python, skill, and routine
  request paths register the exact owner. Terminal and Remote Coding adapters
  resolve IDs through the authoritative registry rather than trusting visible
  pending state. Terminalization cancels only the finishing owner;
  `clearMessages` and provider disposal settle every remaining request.
- Execution revalidates ownership after approval and at every asynchronous
  side-effect boundary. A stale owner cannot persist a remembered command
  rule, mutate a file, start or cancel a process, run Git or Python, change SSH
  credentials, issue an SSH command, or invoke a skill or routine. An SSH
  connection that becomes stale while connecting is disconnected before the
  request is denied. The shared approval gate also records an
  `owner_expired` denial when expiration occurs before or during an allowing
  audit.
- The implementation changed 1,014 production lines across 16 existing files
  (663 additions and 351 deletions), exceeding the catalog's approximate
  500-line target. The DTO, authoritative registry, lifecycle adapters,
  approval-policy revalidation, and final execution guards form one atomic
  stale-resolution contract; splitting the mechanical migration would leave
  at least one command family able to execute an already-terminal owner. No
  new independent production file, decomposition marker, or manifest
  transition was added, and no generated Freezed or serialization output
  changed.
- The new ownership suite passed 10 tests, including a real tool-loop poison
  case that approves and requests remembered permission, clears the owner
  before the continuation runs, and observes no permission persistence or MCP
  execution. Coverage is 53/53 executable registry lines and 33/33
  `ToolApprovalAutoReviewService.resolveGate` lines. Terminal stale-ID and
  clear tests, the Remote Coding suite, the 395-test ordinary ChatNotifier
  suites, the 131-test common gate, and a final 153-test ownership/adapter/
  structure gate passed with analysis and the canonical audit.
- The completion tree is 9,191 primary lines, 13,586 lines across 42 declared
  parts, and 22,777 same-library lines. Matching shrink-only ceilings are
  checked in. The audit now reports 784 methods, 445 manifest entrypoints, 751
  reachable methods, 78 ambient reads, and 68 turn-reachable reads. The
  historical manifest remains at 43 records.
- The fresh coverage verifier reached 4,395 passing root tests. Its only two
  failures were the known M33 release-packaging checks whose direct-S3
  assumptions lag the CloudFront migration; a focused rerun reproduced the
  same `sparkle_appcast_configuration`, `sparkle_s3_public_read_config`, and
  `sparkle_public_release_verifier` blockers without a P5b input.
- The exact `qwen3.6-27b-vision` canary passed all four scenarios in 2 minutes
  40 seconds at `http://192.168.100.241:1234/v1`. Plan owners were
  `bc185e77-8d8e-47f7-81e9-05589357afbd` at generations 2 and 6 and
  `d21e4165-8fa8-465c-b52d-9c2ca2ba388e` at generations 4 and 7. Concurrent
  coding owners were `9cbe94db-6465-40c4-b6ce-ff6b1f085e01` at generation 2
  and `5c847a67-7af5-4f8d-9e81-89602dfa2f25` at generation 3. Queued work used
  `f5db127f-05b0-44b3-8f6a-5c95a8f9a46d` at generations 1 and 2. Handback
  used `444194b9-e41f-47a7-a1ed-43f777525b05` at generation 2 while
  `fac96e9d-56c6-44a4-83d3-28aa25f28e1d` correctly emitted no turn. Every
  expected generation emitted exactly one `turn_exit`, and every scenario
  ended with zero busy owners.

### Unblocks

- WS6-3, WS6-4, WS6-5, WS6-6, WS6-7, WS6-8, WS6-9, WS6-10, WS6-12,
  and WS6-13.

## P5c: Key Device, Browser, Computer Use, and Participant Approvals

### Task

- Goal: add owner identity and stale-resolution validation to the remaining
  tool approval DTOs and adapters.
- User-visible behavior: approval UI text and outcomes remain compatible.
- Non-goals: generic ask-user-question storage, owned by WS8-1. P5c does not
  broaden Remote Coding approval transport; BLE, serial, browser, Computer Use,
  and participant approvals remain unsupported by the current Remote Coding
  wire protocol.

### Files and Tests

- Update `PendingComputerUseAction`, `PendingBrowserAction`,
  `PendingBleConnect`, `PendingSerialOpen`, and
  `PendingParticipantToolApproval` in `chat_state.dart`.
- Update `chat_notifier_computer_use_handlers.dart`,
  `chat_notifier_browser_handlers.dart`, `chat_notifier_ble_handlers.dart`,
  `chat_notifier_serial_handlers.dart`, and
  `chat_notifier_participant_turns.dart`.
- Add the independent
  `lib/features/chat/domain/services/ble_connect_attempt_coordinator.dart`
  when preserving pre-existing and successor BLE connections requires
  attempt-level serialization and rollback ownership.
- Update the shared lifecycle and routing adapters in `chat_notifier.dart`,
  `chat_notifier_approval_handlers.dart`, `chat_notifier_cancellation.dart`,
  `chat_notifier_execution_runtime.dart`,
  `chat_notifier_tool_handler_registry.dart`,
  `thread_scoped_chat_state.dart`, and
  `caverno_terminal_runtime_adapter.dart`.
- Mechanically adopt the unified typed approval registry in the local-file,
  Git, and SSH handlers without changing their P5b policy.
- Add
  `test/features/chat/presentation/providers/pending_device_tool_approval_ownership_test.dart`.
- Update the terminal adapter, Computer Use page, BLE, serial, participant,
  P5b ownership, and structural ratchet tests that exercise the shared
  lifecycle.

### Manifest, Budget, Coverage, and Verification

- No part/manifest transition, marker, or generated output. The pending DTOs
  are plain Dart classes; do not regenerate `chat_state.freezed.dart` unless
  the `ChatState` Freezed shape also changes. Budget any independent
  stale-side-effect coordinator at its achieved size.
- Search every named DTO, request/resolve method, public approval ID, activity
  cleanup, and cancellation path.
- Verify:

  ```bash
  fvm dart format \
    lib/features/chat/presentation/providers/chat_state.dart \
    lib/features/chat/presentation/providers/chat_notifier_computer_use_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_browser_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_ble_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_serial_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_participant_turns.dart \
    test/features/chat/presentation/providers/pending_device_tool_approval_ownership_test.dart \
    --set-exit-if-changed
  fvm flutter test \
    test/features/chat/presentation/providers/pending_device_tool_approval_ownership_test.dart
  ```

- Handoff: record DTO schema, unchanged generated files, adapters, poison
  cases, counts, and canary identities.

### Completion Evidence (2026-07-30)

- `PendingComputerUseAction`, `PendingBrowserAction`, `PendingBleConnect`,
  `PendingSerialOpen`, and `PendingParticipantToolApproval` now require an
  exact `ChatTurnOwner`. The generalized `PendingToolApprovalRegistry` owns all
  P5b and P5c typed completers under owner, ID, and type indexes. It rejects
  duplicate IDs and stale owner/type combinations, removes entries before
  completion, and settles owner-local or global cancellation with each
  request's existing safe denial value.
- Public ID resolvers are authoritative and return whether they consumed a
  current request. `ThreadScopedChatState` is only an owner-aware presentation
  projection. Terminalization clears the matching projection by identity and
  cancels only the finishing owner; `clearMessages` and provider disposal
  settle every request. The terminal adapter routes supported P5b and P5c IDs
  through the registry and deliberately forces Computer Use to a denied,
  unarmed decision.
- Browser, Computer Use, BLE, serial, and participant handlers revalidate the
  exact owner after asynchronous approval or auto-review and immediately
  before side effects. A late browser or Computer Use result cannot start a
  follow-up observation. BLE compensates an in-flight stale connection with a
  disconnect, and serial compensates an in-flight stale open with a close.
  Participant execution remains cache-free and cannot run after its parent
  turn expires.
- The independent 112-line `BleConnectAttemptCoordinator` serializes
  same-device attempts with exact owner and attempt-token identity. It
  preserves a connection that predates an expired attempt, rolls back only a
  connection created by that attempt, and releases the queue before a
  successor owner connects.
- The implementation changed 954 production lines across 17 files
  (520 additions and 434 deletions), exceeding the catalog's approximate
  500-line target. Generalizing the P5b registry, migrating all five P5c DTOs,
  routing authoritative resolution, terminal cleanup, and handler
  revalidation plus stale-side-effect compensation form one stale-resolution
  contract; splitting that migration would leave at least one approval family
  able to outlive its owner or one BLE attempt able to tear down a successor.
- The eleven-test device ownership suite covers safe cancellation for all five
  DTOs, equal-generation cross-conversation isolation, stale same-conversation
  IDs preserving a successor, duplicate/type/index cleanup, browser
  approve-then-clear with zero MCP execution, Computer Use cancellation before
  blocked-policy audit, late Computer Use success without a follow-up
  observation, pre-existing and successor BLE connections, and BLE/serial
  compensating rollback. The 17-test terminal suite covers supported ID
  routing, stale no-ops, global clearing, and forced Computer Use denial.
  The focused approval/UI suite passed 45 tests, the 395-test ordinary
  ChatNotifier suites passed, and the 132-test common gate passed with analysis
  and the canonical audit.
- No Freezed or serialization output, decomposition marker, or historical
  manifest record changed. The new independent coordinator is budgeted at 112
  lines. The completion tree is 9,191 primary lines, 13,578 lines across 42
  declared parts, and 22,769 same-library lines with matching shrink-only
  ceilings. The audit reports 787
  methods, 445 manifest entrypoints, 755 reachable methods, 78 ambient reads,
  and 68 turn-reachable reads.
- The fresh coverage verifier reached 4,412 passing root tests. Its only two
  failures were the known M33 release-packaging checks whose direct-S3
  assumptions lag the CloudFront migration. The failing predicates remained
  `sparkle_appcast_configuration`, `sparkle_s3_public_read_config`, and
  `sparkle_public_release_verifier`, with no P5c implementation file as an
  input.
- The exact `qwen3.6-27b-vision` canary passed all four scenarios in 2 minutes
  53 seconds at `http://192.168.100.241:1234/v1`. Plan owners were
  `4087205b-9dee-48e6-b50b-a4ab1320f2d8` at generations 2 and 6 and
  `d3c4b89c-c6e2-44fb-a21d-a283658320bf` at generations 4 and 7. Concurrent
  coding owners were `b865aba8-eacf-4ad8-98ba-71e8c4aca52c` at generation 2
  and `3b338bf1-c505-4b91-bc02-9f150a01516e` at generation 3. Queued work used
  `384acfe1-df73-47b4-b5b0-c2b96d41fdf5` at generations 1 and 2. Handback
  used `a2a3b861-9535-4d39-892a-24a15a0d028e` at generation 2 while
  `41b29110-a9af-4cc7-a931-63dbd06708e6` correctly emitted no turn. Every
  expected generation emitted exactly one `turn_exit`, and every scenario
  ended with zero busy owners.

### Unblocks

- WS6-11a, WS6-11b, WS6-14, WS6-16, and the approval port used by WS8-9.

## P6: Key FileRollbackCheckpointStore by Owner

### Task

- Goal: owner-key file rollback stacks and active turn checkpoints.
- User-visible behavior: none. File-mutation results, rollback previews,
  unified diffs, summaries, error text, tool names, and rollback JSON remain
  compatible.
- Non-goals: changing filesystem mutation semantics, approval policy, the
  user-visible turn-rollback behavior, or Worktree Agent rollback behavior.

### Files and Tests

- Update the owner-keyed store and its filesystem facade:
  `lib/features/chat/data/datasources/file_rollback_checkpoint_store.dart`,
  `built_in_filesystem_tool_handler.dart`, and `mcp_tool_service.dart`.
- Update owner adoption in
  `lib/features/chat/data/datasources/best_of_n_runner.dart`,
  `lib/features/chat/presentation/providers/chat_notifier.dart`,
  `chat_notifier_local_file_handlers.dart`, and
  `chat_notifier_turn_rollback_handlers.dart`.
- Keep the checkpoint store stable across `McpToolService` rebuilds in
  `lib/features/chat/presentation/providers/mcp_tool_provider.dart`, and retire
  checkpoint state from every conversation-deletion path in
  `conversations_notifier.dart`.
- Update the confirmation handoff in
  `lib/features/chat/presentation/pages/chat_page_turn_rollback_support.dart`.
- Update direct tests for the store, built-in filesystem handler,
  `McpToolService`, and `CheckpointVerificationBestOfNRunner`.
- Update the ChatNotifier turn-rollback, detached-turn, and companion-panel
  tests, plus any shared test or canary `McpToolService` double that must
  preserve its existing synthetic file-tool behavior through the new
  owner-required entrypoint.
- Add provider-rebuild and conversation-deletion integration tests. They must
  prove that the same store spans replacement services and that retired
  conversations reject late checkpoint resurrection.
- Add the store and any new test support file to
  `test/quality/file_size_ratchet_test.dart` at their achieved counts.

### API and Ownership Contract

- Require an exact `ChatTurnOwner` for store `push`, single-change preview and
  rollback, turn-checkpoint begin/end/preview/rollback, and owner-local clear.
- Keep one `_OwnerRollbackState` per exact owner. Preserve the 20-entry
  single-change limit, the 10-entry completed-turn limit, first-entry-per-path
  capture within an active checkpoint, and failed-restore retry behavior
  independently for every owner.
- Maintain a chronological completed-owner index per conversation. Empty turns
  do not replace the latest completed owner. Successful rollback removes only
  the matching latest owner entry and reveals the preceding completed owner;
  failed rollback preserves the index.
- Give every checkpoint a store-wide monotonic token. A preview carries both
  the exact owner and token, and confirmation must reject a consumed or
  superseded token without mutating files. Owner equality alone is not a
  sufficient confirmation identity.
- Retain at most ten completed checkpoints across a conversation as well as
  the per-owner limits. Owner clear and conversation retirement leave
  tombstones that reject late asynchronous `push`, `begin`, and `end` calls.
  Provider disposal clears all retained state.
- Keep `McpToolService.executeTool` ownerless for non-chat callers. Introduce a
  separate exact-owner file-tool entrypoint for ChatNotifier mutations and
  rollback. Ownerless routine, diagnostic, and Worktree Agent mutations still
  execute but never enter chat rollback history.
- Provide `FileRollbackCheckpointStore` independently of `McpToolService`.
  Settings changes may rebuild the service, but the service before and after
  the rebuild must share the same checkpoint store.
- Begin and end the ChatNotifier checkpoint with the owner captured at
  `_sendWithTools` entry, including detached completion in `finally`.
  Mutation and single-file rollback handlers use the same owner already bound
  to their approval cache.
- Preserve the public no-argument ChatNotifier turn-preview method. It may pass
  the visible conversation ID to the data facade, which resolves the indexed
  exact completed owner; it must never synthesize an owner from the current
  interaction generation. Include that owner in the preview and require it for
  the rollback call so a checkpoint completed during confirmation cannot
  replace the target.
- Require `CheckpointVerificationBestOfNRunner` to receive an owner and use it
  for begin, end, preview, and discard.

### Acceptance and Poison Matrix

- Equal generation numbers in different conversations cannot preview,
  consume, clear, or evict each other's state.
- Different generations in one conversation may keep simultaneous active and
  completed checkpoints without replacing each other. Repeated writes to one
  path retain only that owner's first snapshot.
- Owner-local clear, the 20/10 limits, and failed single-change or turn
  rollback restoration leave every other owner's state and completed-owner
  index unchanged.
- An empty newer turn does not hide an earlier completed checkpoint. A failed
  rollback remains retryable, while a successful rollback exposes the prior
  exact owner in the same conversation.
- A newer checkpoint from the same owner cannot replace an already previewed
  target. Reusing a consumed token or confirming after a same-owner
  supersession fails without changing the filesystem.
- Rebuilding `McpToolService` between checkpoint begin, mutation, end, preview,
  and rollback does not split history. Deleting one conversation removes only
  its state, and delayed callbacks cannot recreate retired state.
- Ownerless mutations produce no chat rollback preview. Best-of-N discard
  cannot alter a checkpoint owned by another turn.
- No part or historical manifest record, decomposition marker, generated
  output, or serialization schema changes.

### Verification

- Format every touched Dart source, direct test, notifier test double, canary
  double, and size-ratchet file. The core command is:

  ```bash
  fvm dart format \
    lib/features/chat/data/datasources/file_rollback_checkpoint_store.dart \
    lib/features/chat/data/datasources/built_in_filesystem_tool_handler.dart \
    lib/features/chat/data/datasources/mcp_tool_service.dart \
    lib/features/chat/data/datasources/best_of_n_runner.dart \
    lib/features/chat/presentation/providers/chat_notifier.dart \
    lib/features/chat/presentation/providers/chat_notifier_local_file_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_turn_rollback_handlers.dart \
    lib/features/chat/presentation/providers/conversations_notifier.dart \
    lib/features/chat/presentation/providers/mcp_tool_provider.dart \
    lib/features/chat/presentation/pages/chat_page_turn_rollback_support.dart \
    test/features/chat/data/datasources/file_rollback_checkpoint_store_test.dart \
    test/features/chat/data/datasources/built_in_filesystem_tool_handler_test.dart \
    test/features/chat/data/datasources/mcp_tool_service_test.dart \
    test/features/chat/data/datasources/best_of_n_runner_test.dart \
    test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart \
    test/features/chat/presentation/providers/chat_notifier_test.dart \
    test/features/chat/presentation/providers/chat_notifier_test_doubles_part.dart \
    test/features/chat/presentation/providers/chat_notifier_pending_batch_part.dart \
    test/features/chat/presentation/providers/chat_notifier_turn_rollback_part.dart \
    test/features/chat/presentation/providers/conversations_notifier_test.dart \
    test/features/chat/presentation/providers/mcp_tool_provider_rollback_store_test.dart \
    test/features/chat/presentation/pages/chat_page_companion_panel_test.dart \
    test/support/mcp_file_tool_test_delegate.dart \
    integration_test/test_support/plan_mode_scenario_spec.dart \
    tool/canaries/coding_diagnostic_feedback_live_canary_test.dart \
    tool/canaries/coding_goal_auto_continue_todo_fixture_live_canary_test.dart \
    tool/canaries/coding_goal_live_edit_canary_test.dart \
    tool/canaries/coding_output_feedback_live_canary_test.dart \
    tool/canaries/coding_overwrite_transparency_live_canary_test.dart \
    tool/canaries/coding_verification_feedback_live_canary_test.dart \
    tool/canaries/coding_weather_code_live_canary_test.dart \
    tool/canaries/multi_thread_plan_live_canary_test.dart \
    test/quality/file_size_ratchet_test.dart \
    --set-exit-if-changed
  fvm flutter test --coverage \
    test/features/chat/data/datasources/file_rollback_checkpoint_store_test.dart \
    test/features/chat/data/datasources/built_in_filesystem_tool_handler_test.dart \
    test/features/chat/data/datasources/mcp_tool_service_test.dart \
    test/features/chat/data/datasources/best_of_n_runner_test.dart \
    test/features/chat/presentation/providers/mcp_tool_provider_rollback_store_test.dart
  fvm flutter test \
    test/features/chat/presentation/providers/chat_notifier_test.dart \
    test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart \
    test/features/chat/presentation/pages/chat_page_companion_panel_test.dart \
    test/features/chat/presentation/providers/worktree_agent_task_executor_test.dart \
    test/features/chat/presentation/providers/conversations_notifier_test.dart \
    test/quality/file_size_ratchet_test.dart
  ```

- Assert
  `lib/features/chat/data/datasources/file_rollback_checkpoint_store.dart` at
  `minimum=100` with the catalog `coverage/lcov.info` assertion. Then run the
  catalog-wide common gate, canonical audit, full coverage verifier,
  `git diff --check`, and exact-model four-scenario canary.

### Implementation Evidence (2026-07-30)

- `FileRollbackCheckpointStore` now uses exact-owner buckets plus a
  conversation-keyed chronology containing exact completed owners. All stack,
  active-checkpoint, retry, and clear operations require the owner. Store-wide
  checkpoint tokens bind confirmation to an immutable preview, while
  per-conversation retention and owner/conversation tombstones bound state and
  reject late resurrection. The final store is 442 physical lines and is
  budgeted at 442.
- `McpToolService.executeFileTool` is the exact-owner ChatNotifier file
  execution boundary. `previewFileRollback`, owner-required checkpoint
  methods, and the conversation-to-completed-owner preview adapter preserve the
  existing public UI result shapes. The preview carries the exact owner and
  checkpoint token into the rollback call, closing both cross-owner and
  same-owner preview-confirm races. Ordinary `executeTool` remains ownerless,
  so non-chat mutations do not create chat history.
- `fileRollbackCheckpointStoreProvider` owns the store independently of the
  settings-sensitive tool-service provider. Replacement services therefore
  share active and completed checkpoints. All three conversation deletion
  paths retire state before awaiting persistence, and provider disposal clears
  the store.
- ChatNotifier starts and ends the checkpoint with its captured `turnOwner`.
  Approved write, edit, delete, and single-file rollback calls use the owner
  from `OwnerToolApprovalCache`. `CheckpointVerificationBestOfNRunner` now
  requires and retains its owner.
- The implementation changes 423 production lines across ten existing files
  (323 additions and 100 deletions). `chat_notifier.dart` remains 9,191 lines;
  its 42 declared parts remain 13,578 lines and the same-library aggregate
  remains 22,769. The filesystem handler shrank from 343 to 339 lines.
  `McpToolService` is 1,191 lines and 1,283 lines with its declared part, with
  both ceilings lowered below the pre-P6 counts. The provider and conversations
  notifier are newly governed at 176 and 1,838 lines. The main notifier test is
  budgeted at 18,628 lines, the provider-rebuild test at 152 lines, the shared
  test delegate at 16 lines, and the test library aggregate at 33,220 lines.
- Direct and adoption tests now encode equal-generation cross-conversation
  isolation, same-conversation owner chronology, simultaneous active
  checkpoints, first-entry-per-path behavior, owner-local 20/10 limits and
  clear, conversation-wide retention, failure retry, immutable confirmation
  tokens, settings-driven service replacement, deletion tombstones, ownerless
  mutation isolation, and Best-of-N discard isolation. Shared test and canary
  doubles explicitly preserve their pre-existing synthetic file execution
  through the owner-required entrypoint.
- No part directive, historical manifest record, discovery marker, generated
  output, or serialization schema changed.

### Final Verification Evidence

- Formatting and `fvm flutter analyze` passed. The focused store, filesystem
  handler, `McpToolService`, Best-of-N, and provider-rebuild suite passed 133
  tests; the store recorded `LF=187` and `LH=187`, or 100% direct line
  coverage.
- The notifier, UI, real Worktree Agent, deletion lifecycle,
  provider-rebuild, and size suite passed 551 tests. The common collaborator,
  size, thread-scope, and canonical-audit gate passed 137 tests. The reviewed
  audit reports 787 methods, 445 manifest entrypoints, 755 reachable methods,
  78 ambient reads, and 68 turn-reachable reads.
- `tool/codex_verify.sh --coverage` completed generation, package analysis and
  tests, root analysis, and 4,433 passing root tests. Its only failures were the
  same two unrelated M33 release-packaging tests whose static direct-S3
  expectations lag the CloudFront migration; the focused rerun reproduced
  `sparkle_appcast_configuration`, `sparkle_s3_public_read_config`, and
  `sparkle_public_release_verifier` as the blocked readiness checks.
- The exact-model four-scenario canary passed in 2 minutes 27 seconds at
  `http://192.168.100.241:1234/v1` with `qwen3.6-27b-vision` loaded and the 35B
  model unloaded. Plan owners were
  `9468f205-8a7e-4d81-93a3-f18d1c545e3b` at generations 2 and 6 and
  `b32c2e7d-4ad3-4f7a-8bcf-b5d190a832dc` at generations 4 and 7. Coding used
  `678d64b6-319a-4a23-a173-b3e815d1717d` at generation 2 and
  `e1bb9d5d-f32b-4f77-bc71-9a74c6d7d6b9` at generation 3. Queued work used
  `b1c02aa6-9cd8-4104-bfba-a09b4cc1b8dd` at generations 1 and 2. Handback used
  `c9208dad-e029-4718-a978-581ed4f744aa` at generation 2 while
  `ca7e888a-471f-4fb7-b6c5-28681c77f80a` emitted no turn. Every expected
  generation emitted one `turn_exit`, every scenario ended with zero busy
  owners, and all canary tests passed.

### Unblocks

- WS4-6 and WS6-4.

## P7: Key Background Processes and Monitoring by Owner

### Task

- Goal: owner-key process jobs and monitor snapshots.
- Files:
  `background_process_tools.dart`,
  `background_process_monitor_service.dart`, and
  `built_in_local_command_tool_handler.dart`.
- Tests: their matching files under
  `test/features/chat/data/datasources/`.
- Require owner for start/status/tail/wait/cancel/list/refresh/cleanup; preserve
  output limits, stale classification, exit semantics, polling, and cleanup.
- Search `_jobs`, job-ID lookup, `refreshActiveJobs`, `refreshJobs`, and all
  process tool names.
- No part/manifest transition or marker; add both governed services to the size
  budget; target each at least 95% line coverage.
- Verify:

  ```bash
  fvm dart format \
    lib/features/chat/data/datasources/background_process_tools.dart \
    lib/features/chat/data/datasources/background_process_monitor_service.dart \
    lib/features/chat/data/datasources/built_in_local_command_tool_handler.dart \
    test/features/chat/data/datasources/background_process_tools_test.dart \
    test/features/chat/data/datasources/background_process_monitor_service_test.dart \
    test/features/chat/data/datasources/built_in_local_command_tool_handler_test.dart \
    --set-exit-if-changed
  fvm flutter test --coverage \
    test/features/chat/data/datasources/background_process_tools_test.dart \
    test/features/chat/data/datasources/background_process_monitor_service_test.dart \
    test/features/chat/data/datasources/built_in_local_command_tool_handler_test.dart
  ```

- Handoff: record key/API changes, polling lifecycle, counts, coverage, poison
  cases, and canary identities.

### Focused Acceptance Evidence (2026-07-30)

- `BackgroundProcessTools`, `BackgroundProcessMonitorService`, and the built-in
  local-command adapter now require an exact `ChatTurnOwner` for process state.
  The split leaves the tools, monitor, tool executor, completion monitor, and
  local handler at 459, 457, 206, 74, and 191 lines respectively, with matching
  shrink-only budgets for the governed files.
- Focused process, monitor, and handler tests passed. Equal-generation owners,
  identical job IDs, owner-local polling, retirement, and late startup or
  refresh completion are covered. The current coverage artifact records
  195/203 executable lines for `background_process_tools.dart` and 175/181 for
  `background_process_monitor_service.dart`, both above 95%.
- Integrated full verification and the exact-model live canary remain pending
  at tranche closure and are not claimed by this focused evidence record.

### Unblocks

- Unblocks WS6-6 and WS6-18.

## P8: Key SSH Sessions by Owner

### Task

- Goal: replace the single active SSH session with owner-validated sessions.
- Files: `lib/core/services/ssh_service.dart`,
  `lib/features/chat/presentation/providers/mcp_tool_provider.dart`, and SSH
  adapters.
- Add `test/core/services/ssh_service_test.dart`.
- Require owner for connect/command/disconnect/status/cleanup. Preserve
  within-owner replacement without disconnecting another owner.
- Search `activeSession`, connect, execute, disconnect, provider lifetime, and
  service disposal.
- No part/manifest transition or marker; add `ssh_service.dart` to the size
  budget; target at least 95% line coverage.
- Verify:

  ```bash
  fvm dart format \
    lib/core/services/ssh_service.dart \
    lib/features/chat/presentation/providers/mcp_tool_provider.dart \
    test/core/services/ssh_service_test.dart \
    --set-exit-if-changed
  fvm flutter test --coverage test/core/services/ssh_service_test.dart
  ```

- Handoff: record session key/lifecycle, reconnect and cleanup behavior,
  counts, coverage, poison cases, and canary identities.

### Focused Acceptance Evidence (2026-07-30)

- `SshService` now keeps exact-owner sessions and requires the owner for
  connect, command, disconnect, status, and cleanup. Same-owner replacement and
  reconnect do not close a peer session, while retirement fences late connector
  and authentication completions.
- The service, built-in SSH handler, and provider measure 279, 183, and 176
  lines. The focused SSH suite passed its conversation-peer and generation-peer
  poison cases, and the service reached 110/115 executable lines (95.65%).
- Integrated full verification and the exact-model live canary remain pending
  at tranche closure and are not claimed by this focused evidence record.

### Unblocks

- Unblocks WS6-9.

## P9: Key In-Memory Subagent Tasks by Owner

### Task

- Goal: owner-key Caverno's in-memory `SubagentTaskNotifier` lifecycle.
- Files:
  `lib/features/chat/domain/entities/subagent_task.dart` plus generated
  `subagent_task.freezed.dart` and `subagent_task.g.dart`,
  `lib/features/chat/presentation/providers/subagent_task_notifier.dart`,
  `lib/features/chat/domain/services/subagent_execution_service.dart`, and
  current subagent notifier adapters.
- Tests:
  `test/features/chat/presentation/providers/subagent_task_notifier_test.dart`
  plus subagent handler tests.
- Add `conversationId` defaulting to `''` and
  `interactionGeneration` defaulting to `-1` for legacy JSON. Such unowned
  values are visible only to an explicit administrative view and never match
  an active owner. Do not invent persistence or a storage migration.
- Require owner for register/complete/fail/cancel/byId/markNotified/remove/
  clearFinished and for `spawn_subagent`/`get_subagent_result`.
- Search every `SubagentTask` constructor and notifier method.
- No part/manifest transition or marker; add the notifier file to the size
  budget; target 100% line coverage.
- Verify:

  ```bash
  fvm dart run build_runner build --delete-conflicting-outputs
  fvm dart format \
    lib/features/chat/domain/entities/subagent_task.dart \
    lib/features/chat/presentation/providers/subagent_task_notifier.dart \
    lib/features/chat/domain/services/subagent_execution_service.dart \
    test/features/chat/presentation/providers/subagent_task_notifier_test.dart \
    --set-exit-if-changed
  fvm flutter test --coverage \
    test/features/chat/presentation/providers/subagent_task_notifier_test.dart
  ```

- Handoff: record schema defaults, privileged legacy behavior, lifecycle,
  generated files, counts, coverage, poison cases, and canary identities.

### Focused Acceptance Evidence (2026-07-30)

- `SubagentTask` now persists `conversationId` and
  `interactionGeneration`, with `''` and `-1` legacy defaults that remain
  administrative-only. Generated Freezed and JSON serialization outputs were
  refreshed.
- `SubagentTaskNotifier` and `SubagentExecutionService` require an exact owner
  for task lookup and lifecycle mutation. Their files measure 210 and 131
  lines, the entity measures 66 lines, and focused tests cover peer isolation,
  one-shot terminal transitions, owner-local removal, and late-callback
  retirement. Notifier coverage is 76/76 executable lines.
- Integrated full verification and the exact-model live canary remain pending
  at tranche closure and are not claimed by this focused evidence record.

### Unblocks

- Unblocks WS6-17.

## P10a: Return Atomic Terminal Metadata from Streaming Data Sources

### Task

- Goal: eliminate post-completion reads of shared `lastUsage` and
  `lastFinishReason` by returning terminal metadata from the exact request.
- User-visible behavior: streaming and non-streaming content remains
  compatible.
- Non-goals: notifier response-metric storage; P10b owns adoption.

### Files and API

- Add
  `lib/features/chat/domain/entities/chat_completion_terminal_metadata.dart`.
- Add a `StreamedChatCompletion` envelope with content stream plus terminal
  future in `lib/features/chat/data/datasources/chat_datasource.dart`.
- Update `chat_remote_datasource.dart`,
  `session_logging_chat_datasource.dart`, `demo_datasource.dart`,
  `apple_foundation_models_datasource.dart`, and their test doubles.
- `ChatCompletionResult` remains the atomic source for non-streaming and
  tool-stream completion. Plain streaming must resolve the envelope's terminal
  future before another request can overwrite compatibility-only
  `lastUsage`/`lastFinishReason`.
- Add
  `test/features/chat/data/datasources/chat_completion_terminal_metadata_test.dart`
  and extend `chat_remote_datasource_test.dart`.

### Manifest, Budget, Coverage, and Verification

- No part/manifest transition or marker.
- Add the new entity to the size budget; target it at 100% line coverage.
- Search `streamChatCompletion`, `lastUsage`, `lastFinishReason`,
  `FinishReasonAware`, every `ChatDataSource` implementation, and test doubles.
- Stop and split implementation adapters if the mechanical API migration would
  exceed the focused production-line boundary.
- Verify:

  ```bash
  fvm dart format \
    lib/features/chat/domain/entities/chat_completion_terminal_metadata.dart \
    lib/features/chat/data/datasources/chat_datasource.dart \
    lib/features/chat/data/datasources/chat_remote_datasource.dart \
    lib/features/chat/data/datasources/session_logging_chat_datasource.dart \
    lib/features/chat/data/datasources/demo_datasource.dart \
    lib/features/chat/data/datasources/apple_foundation_models_datasource.dart \
    test/features/chat/data/datasources/chat_completion_terminal_metadata_test.dart \
    test/features/chat/data/datasources/chat_remote_datasource_test.dart \
    --set-exit-if-changed
  fvm flutter test --coverage \
    test/features/chat/data/datasources/chat_completion_terminal_metadata_test.dart \
    test/features/chat/data/datasources/chat_remote_datasource_test.dart
  ```

- Handoff: record interface changes, implementation inventory, streaming/error
  terminal behavior, counts, coverage, and canary identities.

### Focused Acceptance Evidence (2026-07-30)

- `ChatDataSource.streamChatCompletion` now returns a
  `StreamedChatCompletion` whose content stream and terminal future belong to
  the same request. All data-source implementations and test doubles adopt the
  envelope; normal completion resolves exact usage and finish reason, while
  stream failure or cancellation completes the terminal future with the same
  failure.
- `chat_completion_terminal_metadata.dart` and `chat_datasource.dart` measure
  27 and 231 lines. Focused terminal-metadata and remote-data-source tests
  passed, and the new entity reached 2/2 executable lines.
- Integrated full verification and the exact-model live canary remain pending
  at tranche closure and are not claimed by this focused evidence record.

### Unblocks

- P10b.

## P10b: Key Response Metadata and Metrics by Owner

### Task

- Goal: capture the exact P10a terminal metadata and response timer under the
  request's `ChatTurnOwner`.
- Files: add
  `lib/features/chat/presentation/providers/response_metadata_registry.dart`;
  update `chat_notifier.dart`, participant completion/turn files, and response
  finalization.
- Tests: add
  `test/features/chat/presentation/providers/response_metadata_registry_test.dart`
  and extend detached participant tests.
- Capture terminal metadata from the returned result/envelope, never from
  shared data-source getters. Consume/discard exactly once. Cancellation and
  error clear only the owner.
- Search `_latestTokenUsage`, `_latestFinishReason`,
  `_responseMetricTimersByGeneration`, `_takeResponseMetricsForGeneration`,
  participant completion, and finalization.
- No part/manifest transition or marker; add the registry to the size budget;
  target 100% line coverage.
- Verify:

  ```bash
  fvm dart format \
    lib/features/chat/presentation/providers/response_metadata_registry.dart \
    lib/features/chat/presentation/providers/chat_notifier.dart \
    lib/features/chat/presentation/providers/chat_notifier_participant_turns.dart \
    lib/features/chat/presentation/providers/chat_notifier_response_finalization.dart \
    test/features/chat/presentation/providers/response_metadata_registry_test.dart \
    --set-exit-if-changed
  fvm flutter test --coverage \
    test/features/chat/presentation/providers/response_metadata_registry_test.dart \
    test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart
  ```

- Accept only with streaming, non-streaming, participant, interleaved,
  cancellation, and error cases.
- Handoff: record capture/consume lifecycle, migrated getters, counts,
  coverage, poison cases, and canary identities.

### Focused Acceptance Evidence (2026-07-30)

- The 107-line `ResponseMetadataRegistry` owns the response timer, usage, and
  finish reason under the exact request owner. Streaming, non-streaming,
  tool-aware, and participant paths capture request-local P10a metadata;
  consume and discard are one-shot, and cancellation or failure retires only
  that owner. Notifier and participant completion paths no longer read shared
  terminal getters or generation-keyed timers.
- Registry coverage is 47/47 executable lines. The 92-test registry and
  detached-turn suite and the 157-test participant-runner, size, collaborator,
  and turn-scope gate passed; focused analysis was clean.
- Integrated full verification and the exact-model live canary remain pending
  at tranche closure and are not claimed by this focused evidence record.

### Unblocks

- Unblocks WS8-8.

## P11: Key Conversation Taint State by Owner

### Task

- Goal: owner-key taint recording, snapshots, reads, clear, and terminal
  cleanup.
- Files: `lib/core/security/conversation_taint_state.dart`,
  `lib/features/chat/domain/services/tool_result_taint_recorder.dart`,
  `chat_notifier_tool_loop_batch.dart`,
  `chat_notifier_approval_handlers.dart`, and participant execution.
- Tests: `test/core/security/conversation_taint_state_test.dart` and
  `test/features/chat/domain/services/tool_result_taint_recorder_test.dart`.
- Preserve taint ordering, severity aggregation, audit fields, and logging.
- Search `_conversationTaintState`, every recorder/snapshot/clear, approval
  audit, and participant result.
- No part/manifest transition or marker; add the state file to the size budget;
  target 100% line coverage.
- Verify:

  ```bash
  fvm dart format \
    lib/core/security/conversation_taint_state.dart \
    lib/features/chat/domain/services/tool_result_taint_recorder.dart \
    lib/features/chat/presentation/providers/chat_notifier_tool_loop_batch.dart \
    lib/features/chat/presentation/providers/chat_notifier_approval_handlers.dart \
    lib/features/chat/presentation/providers/chat_notifier_participant_turns.dart \
    test/core/security/conversation_taint_state_test.dart \
    test/features/chat/domain/services/tool_result_taint_recorder_test.dart \
    --set-exit-if-changed
  fvm flutter test --coverage \
    test/core/security/conversation_taint_state_test.dart \
    test/features/chat/domain/services/tool_result_taint_recorder_test.dart
  ```

- Handoff: record key/lifecycle, audit compatibility, counts, coverage, poison
  cases, and canary identities.

### Focused Acceptance Evidence (2026-07-30)

- `ConversationTaintState` now accumulates ordered trust evidence under an
  exact `ChatTurnOwner`; snapshots, untrusted-influence reads, clearing, and
  terminal cleanup are owner-local. Retired owners cannot be resurrected by a
  late tool result, and existing approval-audit fields remain unchanged.
- The state and recorder measure 82 and 18 lines. Their focused suites passed
  equal-generation peer isolation and retirement poison cases, with 29/29 and
  4/4 executable lines covered.
- Integrated full verification and the exact-model live canary remain pending
  at tranche closure and are not claimed by this focused evidence record.

### Unblocks

- Unblocks WS6-1 and WS8-9.

## P12: Split CodingCommandOutputGuardrailService Below 500 Lines

### Task

- Goal: split the existing 715-line independent service into cohesive files
  before WS7-8 adopts it.
- User-visible behavior: classification and feedback remain byte-compatible.
- Non-goals: removing the notifier wrapper; WS7-8 owns adoption.

### Files and API

- Add
  `lib/features/chat/domain/services/coding_command_output_issue_detector.dart`
  for decoded command-output issues and feedback signatures.
- Add
  `lib/features/chat/domain/services/coding_command_preflight_issue_detector.dart`
  for masked exit status and Dart command preflight parsing.
- Keep
  `coding_command_output_guardrail_service.dart` as a sub-500-line
  compatibility facade.
- Split the existing direct test into matching detector tests while retaining
  `coding_command_output_guardrail_service_test.dart`.

### Manifest, Budget, Coverage, and Verification

- Do not change `command-guardrails` from `remaining` and do not add
  decomposition markers in P12. WS7-8 registers the adopted collaborators
  after the part validly becomes `partial`.
- Add all three governed files to exact shrink-only budgets; each must be below
  500 lines. Target both new detectors at 100% line coverage.
- Search every static service method and all current independent callers;
  duplicate logic is forbidden.
- Verify:

  ```bash
  fvm dart format \
    lib/features/chat/domain/services/coding_command_output_guardrail_service.dart \
    lib/features/chat/domain/services/coding_command_output_issue_detector.dart \
    lib/features/chat/domain/services/coding_command_preflight_issue_detector.dart \
    test/features/chat/domain/services/coding_command_output_guardrail_service_test.dart \
    test/features/chat/domain/services/coding_command_output_issue_detector_test.dart \
    test/features/chat/domain/services/coding_command_preflight_issue_detector_test.dart \
    --set-exit-if-changed
  fvm flutter test --coverage \
    test/features/chat/domain/services/coding_command_output_guardrail_service_test.dart \
    test/features/chat/domain/services/coding_command_output_issue_detector_test.dart \
    test/features/chat/domain/services/coding_command_preflight_issue_detector_test.dart
  ```

- Handoff: record method inventory, file counts/budgets, compatibility calls,
  coverage, and canary identities.
- Unblocks WS7-8.

## P13: Key Participant Stop and Pause Control by Owner

### Task

- Goal: replace notifier-global participant stop and paused-turn cursor state
  with an owner-keyed registry.
- Files: add
  `lib/features/chat/presentation/providers/participant_turn_control_registry.dart`;
  update `chat_notifier.dart` and `chat_notifier_participant_turns.dart`.
- Tests: add
  `test/features/chat/presentation/providers/participant_turn_control_registry_test.dart`
  and extend detached participant tests.
- Move `_participantTurnStopRequested` and every
  `_pausedParticipantTurn*` field. Require owner for request stop, pause,
  resume, consume cursor, clear, and dispose.
- Search those fields plus `stopParticipantTurns`,
  `continueParticipantTurns`, `_sendWithParticipantTurns`, and runtime
  projection.
- No part/manifest transition or marker; add the registry to the size budget;
  target 100% line coverage.
- Verify:

  ```bash
  fvm dart format \
    lib/features/chat/presentation/providers/participant_turn_control_registry.dart \
    lib/features/chat/presentation/providers/chat_notifier.dart \
    lib/features/chat/presentation/providers/chat_notifier_participant_turns.dart \
    test/features/chat/presentation/providers/participant_turn_control_registry_test.dart \
    test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart \
    --set-exit-if-changed
  fvm flutter test --coverage \
    test/features/chat/presentation/providers/participant_turn_control_registry_test.dart \
    test/features/chat/presentation/providers/chat_notifier_detached_turn_project_test.dart
  ```

- Accept only when two active or paused owners can stop/resume/complete without
  clearing or advancing each other.
- Handoff: record control state machine, public adapter behavior, counts,
  coverage, poison cases, and canary identities.

### Focused Acceptance Evidence (2026-07-30)

- The 129-line `ParticipantTurnControlRegistry` now owns stop requests, pause
  snapshots, resume claims, cursor consumption, clearing, and retirement under
  an exact `ChatTurnOwner`. The public adapters resolve a paused owner by
  conversation without letting one owner stop, resume, advance, or clear a
  peer.
- Focused registry and detached-participant tests passed two-active-owner,
  two-paused-owner, one-shot resume, and late-generation poison cases. Registry
  coverage is 51/51 executable lines.
- Integrated full verification and the exact-model live canary remain pending
  at tranche closure and are not claimed by this focused evidence record.

### Unblocks

- Unblocks WS8-10.

## P14: Extract HiddenAssistantEvidenceScorer

### Task

- Goal: expose the pure hidden-assistant evidence score without constructing
  `ToolTerminalResponsePolicy` and its ten callback dependencies.
- Files: add
  `lib/features/chat/domain/services/hidden_assistant_evidence_scorer.dart`;
  update `tool_terminal_response_policy.dart` to delegate.
- Tests: add
  `test/features/chat/domain/services/hidden_assistant_evidence_scorer_test.dart`
  and
  `test/features/chat/domain/services/tool_terminal_response_policy_test.dart`.
- Preserve score precedence and exact values for empty, hidden, visible,
  successful, failed, and conflicting evidence.
- Search `hiddenAssistantEvidenceScore`, all consumers, and constructor callback
  bags.
- The source policy is already independent, so no part/manifest transition or
  marker. Add the scorer to the size budget; target 100% line coverage.
- Verify:

  ```bash
  fvm dart format \
    lib/features/chat/domain/services/hidden_assistant_evidence_scorer.dart \
    lib/features/chat/domain/services/tool_terminal_response_policy.dart \
    test/features/chat/domain/services/hidden_assistant_evidence_scorer_test.dart \
    test/features/chat/domain/services/tool_terminal_response_policy_test.dart \
    --set-exit-if-changed
  fvm flutter test --coverage \
    test/features/chat/domain/services/hidden_assistant_evidence_scorer_test.dart \
    test/features/chat/domain/services/tool_terminal_response_policy_test.dart
  ```

- Handoff: record score matrix, caller inventory, counts, coverage, and canary
  identities.
- Unblocks WS5-3.

## Dependency Summary

- P1a precedes every other owner-keyed prerequisite. P1b precedes the
  owner-sensitive Workstream 4/5/6 extractions named above.
- P2 precedes P3a, and P3a precedes P3b. P2 and P3a precede the named recovery
  consumers; P3b precedes the final goal consumer in WS8-7.
  P3b is complete, so the WS8-7 completion-evidence start gate is satisfied.
- P5a, P5b, P5c, and P11 precede WS6-1. Individual approval families also
  precede the handlers listed in their `Unblocks` sections.
- P6, P7, P8, and P9 run before the store/session/task consumers they name.
- P10a precedes P10b; P10b precedes WS8-8.
- P11 precedes WS8-9, and WS6-1 must also be complete before WS8-9 can reuse
  `TurnToolApprovalCoordinator`.
- P12 precedes WS7-8. P13 precedes WS8-10. P14 precedes WS5-3.
- WS8-1 remains the approved owner-keyed question-cache prerequisite for WS7-7
  and WS8-2; it is not duplicated here.

Update `docs/chat_notifier_decomposition_task_index.md` in the same focused
commit that changes a prerequisite status.
