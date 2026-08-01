# ChatNotifier Decomposition Workstream 8 Task Catalog

Status: task catalog ready; Slices 2a1-2a3 and 2b1-2b7 are complete. The
exact-model corrected canary passed on 2026-07-28, so Workstream 8 is unblocked
subject to each slice's corrective prerequisites. P2, P3a, and P3b are
complete, so the WS8-7 ownership gate is satisfied.

Current planning baseline after P3b: `chat_notifier.dart` is 9,213 physical
lines, 42 declared parts total 13,567 lines, and the same-library aggregate is
22,780 lines. The shrink-only ceilings match those achieved counts. The
canonical turn-scope baseline reports 78 ambient reads and 68 turn-reachable
reads. Remeasure all values at the start of every slice; these numbers are not
permission to restore removed lines.

This catalog decomposes goal continuation, participant turns, and user
questions from `docs/chat_notifier_decomposition_codex_task.md`. Each approved
section is one implementation slice and one focused review. The notifier
remains the owner of asynchronous lifecycle, persistence, UI, streaming, and
state assignment.

## Catalog-Wide Execution Contract

- Remeasure every named source part, `chat_notifier.dart`, declared part count,
  and same-library aggregate before editing.
- Confirm Slices 2a1-2a3 and 2b1-2b7 are green. In particular, do not start a
  production extraction while any Slice 2b row remains `In progress`. Stop if
  any prerequisite gate is missing or red.
- Re-inventory current source symbols and callers before editing. Line numbers
  and historical manifest entrypoints are discovery aids, not substitutes for
  the current source. Preserve historical entrypoint records even when a
  production method was renamed; change only manifest status and collaborator
  records required by the slice.
- Use an immutable owner identity carrying `conversationId` and
  `interactionGeneration`. Question results, queued work, tracker entries,
  participant messages, approvals, handoffs, and lifecycle state must never
  fall back to the visible thread.
- Collaborators may return decisions, state-machine transitions, message
  transformations, or typed side-effect requests. They must not accept
  `ChatNotifier`, `ChatState`, `Ref`, `ProviderContainer`, Zones, completers, or
  notifier-capturing callbacks.
- Keep public UI request/resolve methods, streaming callbacks, persistence,
  queue draining, and final `ChatState` writes in thin notifier adapters.
- Use the Slice 2a1 manifest and preserve every historical part record. A
  partial extraction changes `remaining` to `partial`; a whole-part extraction
  changes it to `extracted` and removes the old part.
- Append the exact collaborator record and discovery marker named by the task:
  `// ChatNotifier decomposition collaborator: <collaborator-id>`.
- Add each collaborator to the shrink-only file-size budget at achieved
  physical lines. Keep every collaborator below 500 lines.
- Calculate the achieved same-library aggregate as:

  ```text
  previous aggregate
  - physical lines removed from declared parts
  + ChatNotifier primary-file delta
  ```

  Independently imported collaborator lines are excluded. Never raise primary,
  aggregate, or collaborator budgets.
- Update `docs/large_file_refactor_plan.md` with achieved counts, manifest
  status, direct coverage, and any deferral.
- Every task runs formatting, analyze, its focused test with coverage, the
  structural/file-size/thread-scope quality gates,
  `tool/codex_verify.sh --coverage`, and `git diff --check`.
- Run the canonical turn-scope check before editing. After an intended
  production or manifest change, regenerate the baseline explicitly, review
  every changed method/read record, and then rerun the check. Never regenerate
  solely to silence an unexplained failure:

  ```bash
  fvm dart run tool/audit_chat_notifier_turn_scope.dart \
    --manifest tool/chat_notifier_decomposition_manifest.json \
    --check-baseline tool/chat_notifier_turn_scope_baseline.json
  fvm dart run tool/audit_chat_notifier_turn_scope.dart \
    --manifest tool/chat_notifier_decomposition_manifest.json \
    --write-baseline tool/chat_notifier_turn_scope_baseline.json
  fvm dart run tool/audit_chat_notifier_turn_scope.dart \
    --manifest tool/chat_notifier_decomposition_manifest.json \
    --check-baseline tool/chat_notifier_turn_scope_baseline.json
  ```

- Every task runs the corrected four-scenario live canary and records the
  reachable endpoint, exact model, and exactly one `turn_exit` per expected
  conversation and interaction generation:

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

  `<reachable-base-url>` must be the verified OpenAI-compatible `/v1` base URL
  reachable from `flutter-tester`, using a loopback relay when direct LAN
  access is unavailable. Do not substitute another model or infer success from
  a `/models` response alone.

- Assert target-file coverage from `coverage/lcov.info`:

  ```bash
  target='<target-production-file>'
  minimum='<minimum-percent>'
  awk -v target="$target" -v minimum="$minimum" '
    /^SF:/ {
      current = substr($0, 4)
      in_target = current == target
    }
    in_target && /^LF:/ { found = substr($0, 4) + 0 }
    in_target && /^LH:/ { hit = substr($0, 4) + 0 }
    in_target && /^end_of_record/ {
      rate = found == 0 ? 0 : (100.0 * hit / found)
      printf "%s: %.2f%% (%d/%d)\n", target, rate, hit, found
      checked = 1
      if (rate + 0.0001 < minimum) exit 1
      exit 0
    }
    END { if (!checked) exit 1 }
  ' coverage/lcov.info
  ```

## Required Ownership Prerequisites

These are separately reviewable safety gates, not work to hide inside the
named extraction slices:

- P2 (`Key TurnToolResultLedger by Owner`), P3a
  (`Key Finalization and Goal Claim State by Owner`), and P3b
  (`Key Goal Completion Evidence by Owner`) are complete for WS8-7. The result
  ledger, accepted claim, shadow outcome, and final completion evidence are
  exact-owner state. `TurnGoalCompletionEvidenceRegistry` and the typed
  `initialGoalCompletionEvidence` handoff replaced the flat latest value and
  boolean preserve flag.
- Before WS8-8, complete P10b (`Key Response Metadata and Metrics by Owner`).
  P3b freezes the visible-path goal-accounting token delta before persistence,
  preventing a later detachment from inheriting another completion's count.
  Detached-at-entry turns still contribute zero, while the pre-snapshot raw
  usage source, finish reason, and general response metrics remain shared and
  can be overwritten by another completion.
- Before WS8-9, complete WS6-1 and its P5a, P5b, P5c, and P11 prerequisites.
  Reuse its approval coordinator; a typed port over the same global
  `_conversationTaintState` or a flat pending approval does not satisfy this
  prerequisite.
- Before WS8-10, complete P13 (`Key Participant Stop and Pause Control by
  Owner`).

Create a focused task specification, direct poison tests, and a separate commit
for each prerequisite. Run the same audit, ratchet, coverage, full-verification,
and exact-model canary gates before starting the dependent extraction.

## WS8-1: Extract AskUserQuestionTurnCache

### Task

- Goal: replace the generation-only question result cache with an independently
  testable cache keyed by conversation and interaction generation.
- User-visible behavior: none; exact-question and overlapping-option reuse
  remain compatible within one owning turn.
- Non-goals: asking questions, parsing options, or changing reuse policy.

### Context

- Source: private `_AskUserQuestionTurnCache` and
  `_CachedAskUserQuestionResult` in
  `chat_notifier_ask_user_question.dart:302-401`.
- Callers:
  `_handleAskUserQuestion`, production-release approval checks, generation
  cleanup, and notifier disposal.
- Destination:
  `lib/features/chat/domain/services/ask_user_question_turn_cache.dart`.
- Direct tests:
  `test/features/chat/domain/services/ask_user_question_turn_cache_test.dart`.
- Required poison coverage: Slice 2b3.

### Implementation Notes

- Define immutable `AskUserQuestionTurnOwner(conversationId, generation)`.
- Key every find, store, predicate query, and remove by the full owner. Allow an
  explicit conversation-wide or global clear only for lifecycle disposal.
- Preserve normalized question matching, reverse-most-recent selection,
  successful overlapping-option reuse, multi-option rule, and result identity.
- Copy option-label sets and stored values defensively.
- Manifest transition:
  `ask-user-question` from `remaining` to `partial`.
- Append collaborator:
  - `id`: `ask-user-question-turn-cache`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/ask_user_question_turn_cache.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: ask-user-question-turn-cache`.

### Similar-Pattern Search

- Search `_askUserQuestionTurnCache`, `findReusable`, `anyResult`,
  `removeGeneration`, `clear`, and production release approval.
- Enumerate every lifecycle cleanup call and supply the owner explicitly.

### Acceptance Criteria

1. No cache API accepts generation without conversation identity.
2. Direct tests cover exact match, normalized wording, no match, overlapping
   options, single-option rejection, failed result rejection, recency,
   predicate lookup, owner removal, conversation/global clear, and defensive
   copies.
3. Slice 2b3 poison tests prove identical generations in two conversations do
   not share answers or cancellation.
4. Target-file line coverage is 100%.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if any caller cannot resolve the owning conversation.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/ask_user_question_turn_cache.dart \
  lib/features/chat/presentation/providers/chat_notifier_ask_user_question.dart \
  test/features/chat/domain/services/ask_user_question_turn_cache_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/ask_user_question_turn_cache_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

- Record owner-key type, every migrated caller and cleanup, Slice 2b3 cases,
  measured counts, coverage, and canary identities.

## WS8-2: Extract AskUserQuestionPolicy

### Task

- Goal: move question validation, option parsing, saved-task policy resolution,
  repeated-result formatting, and answer result mapping behind a typed question
  port.
- User-visible behavior: none; option IDs and limits, clipping, saved-task
  answer, cancellation, reuse, and output remain compatible.
- Non-goals: moving pending-question UI state, runtime events, or completers.

### Context

- Source: `chat_notifier_ask_user_question.dart` methods
  `_handleAskUserQuestion`, `_buildRepeatedAskUserQuestionResult`,
  `_parseAskUserQuestionOptions`, `_askUserQuestionOptionId`, and
  `_clipAskUserQuestionText`.
- Public `requestAskUserQuestion`, `resolveAskUserQuestion`, and
  `_dismissAllPendingAskUserQuestions` remain notifier UI bridges.
- Current registry binding:
  `_ConversationToolHandlerModule` in
  `chat_notifier_tool_handler_registry.dart:183-186`.
- Destination:
  `lib/features/chat/domain/services/ask_user_question_policy.dart`.
- Direct tests:
  `test/features/chat/domain/services/ask_user_question_policy_test.dart`.
- Prerequisite: WS8-1.

### Implementation Notes

- Define owner-aware `AskUserQuestionPort.ask(owner, request)` and use WS8-1
  for reuse and storage.
- Accept the owning saved task explicitly. Reuse
  `ToolTerminalResponsePolicy` for continuation-question recognition.
- Preserve eight-option limit, deterministic and unique IDs, text limits,
  `allow_other`, multiple selection, help and placeholder values, saved
  validation inclusion, repeated note, cancellation, and exact JSON.
- Public UI adapters must reject a stale owner before presenting or completing
  a question.
- Manifest transition: `ask-user-question` remains `partial`.
- Append collaborator:
  - `id`: `ask-user-question-policy`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/ask_user_question_policy.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: ask-user-question-policy`.

### Similar-Pattern Search

- Search all five source methods, `requestAskUserQuestion`,
  `PendingAskUserQuestion`, `ask_user_question`, saved-task resolution, and the
  registry binding.
- Do not move UI state or runtime question emission.

### Acceptance Criteria

1. The tool handler uses only explicit owner/task inputs, the owner-keyed cache,
   and a typed question port.
2. Direct tests cover missing question, every option representation, duplicate
   and non-ASCII labels, all clipping limits, option cap, invalid allow-other,
   saved-task resolution, exact/option reuse, answer, dismissal, stale owner,
   and exact payloads.
3. Slice 2b3 poison tests prove pending and completed questions are isolated by
   conversation and generation.
4. Target-file line coverage is at least 95% and physical size is below 500.
5. Manifest, marker, exact budget, aggregate ratchet, registry adapter,
   structural gates, and live canary pass.
6. Stop if the typed port cannot validate owner identity before UI completion.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/ask_user_question_policy.dart \
  lib/features/chat/presentation/providers/chat_notifier_ask_user_question.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_handler_registry.dart \
  test/features/chat/domain/services/ask_user_question_policy_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/ask_user_question_policy_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=95`, then the
corrected live canary.

### Handoff Notes

- Record policy/port APIs, complete option and result matrices, Slice 2b3
  cases, registry binding, measured counts, coverage, and canary identities.

## WS8-3: Extract GoalAutoContinueTrackerRegistry

### Task

- Goal: move goal continuation tracker storage, diagnostic streak handling, and
  verifier replay candidate lifecycle into an owner-aware registry.
- User-visible behavior: none; streaks, replay priority, replay-once behavior,
  and tracker resets remain compatible.
- Non-goals: making continuation decisions, executing replays, or updating UI.

### Context

- Source:
  - private `_GoalAutoContinueTracker`;
  - `_recordCommandDiagnosticStreak`, `_resetCommandDiagnosticStreak`,
    `_commandDiagnosticRepairFocusFor`, `_clearCommandDiagnosticRepairFocus`;
  - `_recordExecutedVerifierReplayCandidate`,
    `_isReplayEligibleVerifierToolCall`, `_verifierReplayPriority`, and
    `_takePostMutationVerifierReplay`;
  - `_resetGoalAutoContinueTrackerForConversation`.
- Source file:
  `chat_notifier_goal_auto_continue.dart:14-465`.
- Destination:
  `lib/features/chat/domain/services/goal_auto_continue_tracker_registry.dart`.
- Direct tests:
  `test/features/chat/domain/services/goal_auto_continue_tracker_registry_test.dart`.

### Implementation Notes

- Key durable goal tracking by conversation and key per-turn replay bookkeeping
  by interaction generation. Accept the owning conversation/task snapshot
  explicitly for each operation.
- Return immutable tracker snapshots and typed diagnostic/replay events. Keep
  mutation internal to the registry.
- Inject replay ID generation; do not call `DateTime.now()` internally without
  an injected clock or ID factory.
- Preserve eligibility, command-effect verification, priority, task-change
  reset, mutation/verification generation gates, replay-once sets, and log data.
- Replace notifier test seams with direct registry tests.
- Manifest transition:
  `goal-auto-continue` from `remaining` to `partial`.
- Append collaborator:
  - `id`: `goal-auto-continue-tracker-registry`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/goal_auto_continue_tracker_registry.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: goal-auto-continue-tracker-registry`.

### Similar-Pattern Search

- Search `_goalAutoContinueTrackers`, every named method,
  `_goalAutoContinueBudgetNotifiedConversations`, verifier test seams, and
  reset/dispose paths.
- Keep execution and persistence in the notifier.

### Acceptance Criteria

1. No caller mutates tracker fields directly; all access is owner-aware.
2. Direct tests cover create/read/update/reset, two conversations, diagnostic
   same/changed signatures, focus activation/clear, replay eligibility and
   priority, task change, generation gates, replay-once behavior, deterministic
   IDs, and defensive copies.
3. Poison tests prove tracker focus and replay candidates do not cross owners.
4. Target-file line coverage is at least 95% and physical size is below 500.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if the collaborator exceeds 500 lines; split verifier replay selection
   into a pure adjacent policy.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/goal_auto_continue_tracker_registry.dart \
  lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart \
  test/features/chat/domain/services/goal_auto_continue_tracker_registry_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/goal_auto_continue_tracker_registry_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=95`, then the
corrected live canary.

### Handoff Notes

- Record key/lifecycle, immutable snapshot and event APIs, removed fields/test
  seams, poison cases, measured counts, coverage, and canary identities.

## WS8-4: Extract GoalAutoContinueSafeBoundaryBuilder

### Task

- Goal: move safe-boundary projection into a pure builder using an
  owner-specific pending-state snapshot.
- User-visible behavior: none; veto fields and first veto reason remain
  compatible.
- Non-goals: changing safe-boundary policy or pending UI state.

### Context

- Source:
  `_goalAutoContinueSafeBoundaryFromState` in
  `chat_notifier_goal_auto_continue.dart:850-872`.
- Destination:
  `lib/features/chat/domain/services/goal_auto_continue_safe_boundary_builder.dart`.
- Direct tests:
  `test/features/chat/domain/services/goal_auto_continue_safe_boundary_builder_test.dart`.
- Required poison coverage: Slices 2b3, 2b4, and 2b7.

### Implementation Notes

- Define immutable `GoalAutoContinuePendingState` containing loading, owner
  queued-input count, pending approval/question/workflow flags, participant
  runtime, and error.
- The notifier builds this snapshot from owner-keyed stores, not from visible
  `ChatState` fields.
- Preserve exact mapping to `GoalAutoContinueSafeBoundary` and veto ordering.
- Manifest transition: `goal-auto-continue` remains `partial`.
- Append collaborator:
  - `id`: `goal-auto-continue-safe-boundary-builder`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/goal_auto_continue_safe_boundary_builder.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: goal-auto-continue-safe-boundary-builder`.

### Similar-Pattern Search

- Search `_goalAutoContinueSafeBoundaryFromState`,
  `GoalAutoContinueSafeBoundary`, all pending state fields,
  `_queuedChatMessages.pendingFor`, and participant runtime.
- Enumerate the current veto field order before editing.

### Acceptance Criteria

1. The builder has no `ChatState` dependency.
2. Direct tests cover the all-clear case, each veto independently, combined
   veto ordering, whitespace error, zero/nonzero queue, and immutable input.
3. Slices 2b3, 2b4, and 2b7 poison tests prove pending questions, queued work,
   approvals, and participant runtime block only their owner.
4. Target-file line coverage is 100%.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if any pending state remains global or visible-thread-only.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/goal_auto_continue_safe_boundary_builder.dart \
  lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart \
  test/features/chat/domain/services/goal_auto_continue_safe_boundary_builder_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/goal_auto_continue_safe_boundary_builder_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

- Record the full pending snapshot and veto order, 2b3/2b4/2b7 poison cases,
  measured shrink, coverage, and canary identities.

## WS8-5: Extract GoalAutoContinueDecisionCoordinator

### Task

- Goal: move progress comparison, diagnostic signature progression, policy
  input assembly, continuation decision, and tracker delta calculation into a
  pure coordinator.
- User-visible behavior: none; continue, stop, block, repair, validation, and
  elicitation eligibility decisions remain compatible.
- Non-goals: sending hidden prompts, persisting goal state, updating UI, or
  writing logs.

### Context

- Source: pure decision portions of
  `_maybeAutoContinueCurrentGoal`, plus
  `_candidateGoalAutoContinueProgressStreak`, `_endsWithQuestionMark`,
  `_effectiveGoalAutoContinueBudget`, and `_currentVerificationCadence` in
  `chat_notifier_goal_auto_continue.dart`.
- Existing policies:
  `ConversationGoalAutoContinuePolicy`,
  `StalledDiagnosticRepairContract`, and `ExecutionSnapshotProjector`.
- Destination:
  `lib/features/chat/domain/services/goal_auto_continue_decision_coordinator.dart`.
- Direct tests:
  `test/features/chat/domain/services/goal_auto_continue_decision_coordinator_test.dart`.
- Prerequisites: WS8-3 and WS8-4.

### Implementation Notes

- Define immutable input containing owner conversation/goal, tracker snapshot,
  completion evidence, finalized response, safe boundary, language-neutral
  execution snapshot inputs, and voice/saved-workflow conditions.
- Return a typed decision plan containing policy decision, tracker delta,
  optional repair contract, capability profile, continuation limits, optional
  stop notice, elicitation eligibility, and structured reason.
- Derive verification cadence from the explicit owner conversation. Preserve
  the direct `ExecutionSnapshotProjector.verificationCadenceFor` behavior.
- Keep `_maybeAutoContinueCurrentGoal` as an orchestration shell that validates
  the owner before and after awaits, applies the tracker delta, persists status,
  builds localized prompt text, and dispatches.
- Manifest transition: `goal-auto-continue` remains `partial`.
- Append collaborator:
  - `id`: `goal-auto-continue-decision-coordinator`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/goal_auto_continue_decision_coordinator.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: goal-auto-continue-decision-coordinator`.

### Similar-Pattern Search

- Search `_maybeAutoContinueCurrentGoal`, all four named helpers,
  `GoalAutoContinuePolicyInput`, `StalledDiagnosticRepairContract`,
  `GoalAutoContinueStopPresentation`, and tracker field writes.
- Build a before/after branch inventory; leave every await and side effect in
  the notifier.

### Acceptance Criteria

1. Policy input and tracker deltas are computed without mutable notifier state.
2. Direct tests cover non-coding/voice/saved-workflow vetoes, evidence
   improvement/no progress, diagnostic change/stall, repair outcomes,
   validation misses, question endings including full-width punctuation,
   budgets, block/stop/continue, notices, elicitation gates, repair contract,
   and capability profile.
3. Poison tests prove the visible conversation's goal, evidence, queues, and
   generations cannot alter the owner decision.
4. Target-file line coverage is 100% and physical size is below 500.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if the coordinator exceeds 500 lines or must perform an await; split
   progress and tracker-delta calculation into a pure prerequisite.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/goal_auto_continue_decision_coordinator.dart \
  lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart \
  test/features/chat/domain/services/goal_auto_continue_decision_coordinator_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/goal_auto_continue_decision_coordinator_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

- Record the input/plan/delta types, full branch matrix, residual orchestration
  lines, poison cases, measured counts, coverage, and canary identities.

## WS8-6: Extract GoalContinuationLogRecordBuilder

### Task

- Goal: move goal auto-continue and completion-shadow log record construction
  into a pure owner-input builder.
- User-visible behavior: none; session-log fields, evidence marker values, and
  shadow labels remain compatible.
- Non-goals: enabling logs, resolving log contexts, timestamps, or writing
  records.

### Context

- Source:
  - `_recordGoalAutoContinueSessionLog`;
  - `_recordGoalCompletionShadow`;
  - structured values assembled around `_logGoalAutoContinueSkip`.
- Source file:
  `chat_notifier_goal_auto_continue.dart:912-1034`.
- Existing policies:
  `GoalAutoContinueEvidenceMarker` and `GoalCompletionShadow`.
- Destination:
  `lib/features/chat/domain/services/goal_continuation_log_record_builder.dart`.
- Direct tests:
  `test/features/chat/domain/services/goal_continuation_log_record_builder_test.dart`.

### Implementation Notes

- Define pure record values for auto-continue and completion-shadow events.
- Accept explicit goal, tracker snapshot, evidence, verification cadence,
  mutation/verification generations, safe boundary, tool outcome, lexical
  outcome, decision, and reason.
- The notifier checks log enablement, resolves owner log context, injects time,
  and writes through `LlmSessionLogStore`.
- Preserve null omission, counters, stop/continue labels, evidence marker, turn
  ID, disagreement filtering, and exact shadow label.
- Manifest transition: `goal-auto-continue` remains `partial`.
- Append collaborator:
  - `id`: `goal-continuation-log-record-builder`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/goal_continuation_log_record_builder.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: goal-continuation-log-record-builder`.

### Similar-Pattern Search

- Search both source methods, `_logGoalAutoContinueSkip`,
  `recordGoalAutoContinue`, `recordGoalCompletionShadow`,
  `GoalAutoContinueEvidenceMarker`, and `GoalCompletionShadow`.
- Do not move the log store or context resolver.

### Acceptance Criteria

1. Log field construction is pure; actual writes remain owner-context adapters.
2. Direct tests cover null/non-null goal and tracker, every decision label,
   counter fields, cadence/generations, safe veto, evidence values, no
   disagreement, each disagreement, shadow labels, and exact record values.
3. Poison tests prove a delayed write uses the owner's context and generations.
4. Target-file line coverage is 100%.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if the builder receives `LlmSessionLogStore` or reads current settings.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/goal_continuation_log_record_builder.dart \
  lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart \
  test/features/chat/domain/services/goal_continuation_log_record_builder_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/goal_continuation_log_record_builder_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

- Record both record types, every migrated field, owner-context adapter,
  measured shrink, coverage, and canary identities.

## WS8-7: Extract GoalUpdateToolHandler

### Task

- Goal: move `update_goal` acknowledgement evaluation and completion-claim
  outcome construction into an independent owner-input handler.
- User-visible behavior: none; acknowledgement text, evidence checks,
  completion acceptance, and shadow outcome remain compatible.
- Non-goals: persisting goal status, finalization re-checks, or writing shadow
  logs.

### Context

- Source:
  - `handleUpdateGoal`;
  - `TurnGoalCompletionEvidenceRegistry.combinedToolResultsFor`;
  - exact-owner claim and shadow-outcome writes through
    `TurnFinalizationStateRegistry`;
  - `TurnGoalCompletionFinalizer` exact-owner consumption and final re-check.
- Source file:
  `chat_notifier_goal_auto_continue.dart:976-1033` and
  `turn_goal_completion_evidence_registry.dart:158-211`.
- Existing resolver:
  `GoalUpdateAckResolver`.
- Current registry binding:
  `_ConversationToolHandlerModule` in
  `chat_notifier_tool_handler_registry.dart:183-195`.
- Destination:
  `lib/features/chat/domain/services/goal_update_tool_handler.dart`.
- Direct tests:
  `test/features/chat/domain/services/goal_update_tool_handler_test.dart`.
- Prerequisite satisfied: P2, P3a, and P3b are complete.

### Implementation Notes

- Accept `ToolCallInfo`, owning `ConversationGoal?`, an explicit owner result
  list, and the exact owner's completion-evidence snapshot.
- Return a typed outcome containing `McpToolResult`, whether this is a
  completion claim, whether it is accepted, and shadow outcome.
- Recompute call-time evidence from the explicit result list with
  `ToolResultPromptBuilder`; do not depend on the owner registry directly.
- The notifier stores accepted-claim and shadow values through
  `TurnFinalizationStateRegistry` under the exact owner.
  `TurnGoalCompletionFinalizer` re-checks the matching
  `TurnGoalCompletionEvidenceRegistry` snapshot at turn end.
- Manifest transition: `goal-auto-continue` remains `partial`.
- Append collaborator:
  - `id`: `goal-update-tool-handler`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/goal_update_tool_handler.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: goal-update-tool-handler`.

### Similar-Pattern Search

- Search `handleUpdateGoal`, `TurnFinalizationStateRegistry`,
  `TurnGoalCompletionEvidenceRegistry`, `_goalCompletionEvidence`,
  `_finalizeGoalTurn`, `TurnGoalCompletionFinalizer`, and the handler binding.
- Inspect finalization claim consumption without moving it.

### Acceptance Criteria

1. The handler has no turn ledger, provider, state, or notifier dependency.
2. Direct tests cover absent/active goal, non-completion update, accepted and
   rejected completion, prior incomplete evidence, current failures,
   carry-forward behavior, result text, claim flag, and shadow outcome.
3. Poison tests prove another conversation's goal or results cannot affect the
   acknowledgement or stored claim.
4. Target-file line coverage is 100%.
5. Manifest, marker, exact budget, aggregate ratchet, registry binding,
   structural gates, and live canary pass.
6. Preserve exact-owner claim, shadow, and final completion-evidence storage.
   Stop if the extraction reintroduces a flat value, conversation-level latest
   fallback, or direct registry dependency in the handler.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/goal_update_tool_handler.dart \
  lib/features/chat/presentation/providers/chat_notifier_goal_auto_continue.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_handler_registry.dart \
  test/features/chat/domain/services/goal_update_tool_handler_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/goal_update_tool_handler_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

- Record explicit evidence inputs, outcome type, keyed claim/shadow adapter,
  registry binding, poison cases, measured counts, coverage, and canary
  identities.

## WS8-8: Extract ParticipantMessageFinalizer

### Task

- Goal: move participant assistant-message finalization, handoff extraction,
  truncation, empty-message removal, tool-name deduplication, and persistence
  plan construction into a pure transformer.
- User-visible behavior: none; visible content, handoff metadata, metrics,
  truncation notice, saved messages, and auto-read eligibility remain
  compatible.
- Non-goals: reading active response state, persisting messages, or invoking
  text-to-speech.

### Context

- Source: `chat_notifier_participant_turns.dart` methods
  `_finalizeParticipantMessage` plus its inline participant-tool-name
  normalization, handoff extraction, target lookup, truncation, metrics, and
  persistence-plan branches.
- Destination:
  `lib/features/chat/domain/services/participant_message_finalizer.dart`.
- Direct tests:
  `test/features/chat/domain/services/participant_message_finalizer_test.dart`.
- Required poison coverage: Slice 2b7.
- Prerequisite: per-request, owner-generation completion metadata is available
  without reading shared `lastFinishReason`, `lastUsage`, or notifier-global
  equivalents.

### Implementation Notes

- Accept source messages, final-turn flag, participant and participants,
  participant tool names, finish reason, response metrics, detached flag,
  settings flags, and visible-message predicate result as explicit values.
- Return immutable updated messages, content, target participant ID, whether to
  persist, messages to save, whether to auto-read, and whether metrics were
  consumed or discarded.
- Reuse `ParticipantTurnCoordinator.extractHandoffDirective` and
  `TruncationNotice`; inject any remaining visibility decision through
  precomputed booleans or a narrow independent policy, not a notifier callback.
- Preserve empty-assistant removal, tool-name order, handoff fields, final
  loading semantics, and exact content.
- Manifest transition:
  `participant-turns` from `remaining` to `partial`.
- Append collaborator:
  - `id`: `participant-message-finalizer`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/participant_message_finalizer.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: participant-message-finalizer`.

### Similar-Pattern Search

- Search `_finalizeParticipantMessage`, `_streamParticipantTurn`,
  `participantToolNames`, `extractHandoffDirective`,
  `_shouldKeepVisibleMessage`, response metrics, handoff fields, and auto-read.
- Keep actual persistence and TTS in the notifier.

### Acceptance Criteria

1. Message transformation is deterministic from explicit inputs.
2. Direct tests cover stale/empty inputs, visible/invisible content,
   truncation, valid/invalid/self handoff, duplicate/blank tool names,
   detached/attached, final/non-final, metrics consume/discard, saved-message
   filtering, and auto-read eligibility.
3. Slice 2b7 poison tests prove detached owner messages and handoff metadata are
   finalized and persisted to the owner while another thread is visible.
4. Target-file line coverage is 100% and physical size is below 500.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if the transformer requires a persistence or state mutation callback,
   or if finish reason or usage still comes from shared completion state.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/participant_message_finalizer.dart \
  lib/features/chat/presentation/providers/chat_notifier_participant_turns.dart \
  test/features/chat/domain/services/participant_message_finalizer_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/participant_message_finalizer_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

- Record transformer input/output contracts, complete branch matrix, Slice 2b7
  detached-owner cases, measured shrink, coverage, and canary identities.

## WS8-9: Extract ParticipantToolExecutor

### Task

- Goal: move participant tool-definition filtering, policy enforcement,
  approval routing, execution, taint event construction, and review arguments
  behind owner-aware ports.
- User-visible behavior: none; allowed tools, approval mode, denial text,
  activity, execution results, and taint behavior remain compatible.
- Non-goals: moving approval UI, participant streaming, or the MCP service.

### Context

- Source: `chat_notifier_participant_turns.dart` methods
  `_toolDefinitionsFor`, `_executeParticipantToolCall`,
  `_resolveParticipantToolApproval`, `_requestParticipantToolApproval`, and
  `_setParticipantToolActivity`, plus the inline auto-review argument and
  taint-recording branches.
- Public `resolveParticipantToolApproval` remains the notifier UI adapter.
  Exact-owner terminal cancellation through the unified pending-approval
  registry remains the notifier lifecycle adapter. Activity routing remains a
  narrow owner-validating adapter.
- Existing policies:
  `ParticipantToolPolicy` and the Workstream 6 approval coordinator.
- Destination:
  `lib/features/chat/domain/services/participant_tool_executor.dart`.
- Direct tests:
  `test/features/chat/domain/services/participant_tool_executor_test.dart`.
- Required poison coverage: Slice 2b7.
- Prerequisite: the owner-keyed conversation-taint gate above is complete.

### Implementation Notes

- Define owner-aware `ParticipantToolApprovalPort`,
  `ParticipantToolExecutionPort`, `ParticipantToolActivityPort`, and
  `ParticipantToolTaintPort`.
- Accept immutable available definitions and tool-aware support. Filter with
  `ParticipantToolPolicy` without reading MCP services.
- Reuse `TurnToolApprovalCoordinator` for auto-review/full-access/manual gates.
- Preserve policy denial, unavailable service, review argument keys, manual
  denial JSON, activity start/finally-clear ordering, taint-after-result, and
  exact result forwarding.
- Manifest transition: `participant-turns` remains `partial`.
- Append collaborator:
  - `id`: `participant-tool-executor`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/participant_tool_executor.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: participant-tool-executor`.

### Similar-Pattern Search

- Search all current source methods, approval/activity adapters,
  `ParticipantToolPolicy`, `_resolveToolApprovalGate`,
  `_buildAutoReviewRequest`, `ToolResultTaintRecorder`, and MCP execution.
- Do not move participant runtime UI fields.

### Acceptance Criteria

1. Execution receives explicit owner, participant, call, definitions, and typed
   ports; no MCP service or notifier crosses the boundary.
2. Direct tests cover tools disabled/unsupported, definition filtering, policy
   deny, missing execution port, every approval mode and outcome, execution
   success/error, activity ordering and finally cleanup, taint event, review
   arguments, and exact denial payload.
3. Slice 2b7 poison tests prove approval, activity, result, and taint remain
   attached to the participant owner while another thread is visible.
4. Target-file line coverage is at least 95% and physical size is below 500.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if an approval or activity port cannot validate conversation,
   generation, and participant ID, or if the taint port writes global state.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/participant_tool_executor.dart \
  lib/features/chat/presentation/providers/chat_notifier_participant_turns.dart \
  test/features/chat/domain/services/participant_tool_executor_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/participant_tool_executor_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=95`, then the
corrected live canary.

### Handoff Notes

- Record all four ports, policy and approval matrices, call ordering, Slice 2b7
  cases, measured counts, coverage, and canary identities.

## WS8-10: Extract ParticipantTurnPlanner

### Task

- Goal: move participant normalization, next-speaker progression, handoff
  preference, stop/pause/completion transition selection, and runtime
  projection into an independent state machine.
- User-visible behavior: none; participant order, rounds, handoffs, stop
  behavior, and runtime labels remain compatible.
- Non-goals: streaming completions, persisting participants/messages, queue
  draining, or mutating `ChatState`.

### Context

- Source: decision portions of
  `_sendWithParticipantTurns`, `_runParticipantTurnLoop`,
  `_setParticipantTurnRuntime`, the inline `listEquals` participant comparison,
  and paused-turn cursor setup in
  `chat_notifier_participant_turns.dart`.
- Existing coordinator:
  `ParticipantTurnCoordinator`.
- Destination:
  `lib/features/chat/domain/services/participant_turn_planner.dart`.
- Direct tests:
  `test/features/chat/domain/services/participant_turn_planner_test.dart`.
- Required poison coverage: Slice 2b7.

### Implementation Notes

- Define immutable planner state containing owner, normalized participants,
  config, cursor, preferred and last speaker IDs, completed content, and stop
  request.
- Return one typed step: no participants, stream participant, pause, or
  complete, plus next planner state and `ParticipantTurnRuntime` projection.
- Reuse `ParticipantTurnCoordinator.nextSpeaker` and normalization. Do not
  expose streaming or persistence callbacks.
- The notifier loop validates owner generation, executes one stream request,
  feeds the completion/handoff back into the planner, and applies typed pause or
  completion effects.
- Preserve max-round clamping, preferred handoff one-shot behavior, last
  speaker, final-turn precedence over stop, and participant equality.
- Preserve the current single paused-participant-turn limitation. Do not claim
  support for simultaneous independently paused owners; keep that limitation
  as an explicit deferred boundary unless a separate owner-keyed pause registry
  is approved.
- Manifest transition: `participant-turns` remains `partial`.
- Append collaborator:
  - `id`: `participant-turn-planner`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/participant_turn_planner.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: participant-turn-planner`.

### Similar-Pattern Search

- Search the current source methods, `listEquals`, paused cursor fields,
  `_participantTurnStopRequested`, `ParticipantTurnCoordinator.nextSpeaker`,
  and runtime projection.
- Draw the existing transition table before editing; do not move any await.

### Acceptance Criteria

1. The planner is a deterministic state machine with no callbacks or mutable
   notifier state.
2. Direct tests cover participant normalization changed/unchanged, none
   enabled, single/multi-round, max-round clamping, preferred handoff,
   last-speaker behavior, stop before/final turn, pause/resume state, complete,
   and exact runtime projection.
3. Slice 2b7 poison tests prove participant cursor, handoff, stop, and runtime
   remain with the owner during a visible-thread switch.
4. Target-file line coverage is 100% and physical size is below 500.
5. Manifest, marker, exact budget, aggregate ratchet, structural gates, and
   live canary pass.
6. Stop if planner progression requires an asynchronous callback; emit a typed
   step and keep the await in the notifier.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/participant_turn_planner.dart \
  lib/features/chat/presentation/providers/chat_notifier_participant_turns.dart \
  test/features/chat/domain/services/participant_turn_planner_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/participant_turn_planner_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Run the coverage assertion with the destination and `minimum=100`, then the
corrected live canary.

### Handoff Notes

- Record the planner state/step schema, complete transition table, residual
  notifier loop, Slice 2b7 cases, measured counts, coverage, and canary
  identities.

## Deferred Workstream 8 Boundaries
The following are not approved implementation slices in this catalog:

- `requestAskUserQuestion`, `resolveAskUserQuestion`, and
  `_dismissAllPendingAskUserQuestions` UI/completer orchestration. They remain
  owner-validating notifier adapters. Any future UI coordinator needs a
  separate cancellation and lifecycle specification.
- `_streamParticipantTurn`, placeholder insertion, response metrics, live
  chunk callbacks, message persistence, auto-read, pause/complete side effects,
  queue draining, public stop/continue methods, and final `ChatState` writes.
  WS8-8 through WS8-10 provide pure decisions and typed effects only.
- `_maybeAutoContinueCurrentGoal` awaits and side effects: goal status
  persistence, indicator updates, hidden prompt dispatch, completion
  elicitation dispatch, error handling, and queue checks before dispatch. The
  method remains a thin owner-validating orchestration shell after WS8-5.
- Terminal success persistence, successful verification generation writes,
  final evidence reconciliation, and content-tool dedupe test seams. P2 and
  P3a key the ledger, claim, and shadow values. P3b now keys final completion
  evidence and seeds continuations explicitly; WS8-7 must preserve those
  boundaries.
- Participant configuration persistence and participant completion transport.
  They remain existing independent services or notifier adapters, not part of
  this decomposition.

## Cross-Workstream Ordering Note

WS8-1 must complete before WS7-7
(`ProductionReleaseApprovalPolicy`) so release approval never depends on the
current generation-only question cache.

WS6-19 (`ChatToolHandlerCatalog`) must run only after WS8-2 and WS8-7 are
complete. Those slices remove the last `ask_user_question` and `update_goal`
notifier-bound registry entries. WS6-17 already removes the subagent entry.
