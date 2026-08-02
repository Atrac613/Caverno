# ChatNotifier Decomposition Workstream 5 Task Catalog

Status: complete. WS5-1 through WS5-8 completed focused acceptance, and the
merged tree passed integrated verification and the corrected four-scenario
live canary against `qwen3.6-27b-vision` on 2026-08-01.

This catalog decomposes recovery and verification work from
`docs/chat_notifier_decomposition_codex_task.md`. Each section is one approved
slice and must remain behavior-preserving. Do not combine an extraction with a
recovery behavior fix.

## Current Preflight Baseline

The reviewed post-Slice-2b7 preflight baseline is:

- `chat_notifier.dart`: 9,364 physical lines;
- declared `part` directives: 42;
- declared-part same-library aggregate: 22,887 physical lines;
- decomposition manifest: 43 historical part records.

The 43 manifest records are intentionally historical and do not shrink when a
current `part` directive is removed. The 9,380 primary and 22,900 aggregate
ratchets are ceilings, not achieved counts. Remeasure all four values before
each slice and use the measured 9,364/42/22,887 state only while it still
matches the worktree.

## Catalog-Wide Execution Contract

- Before each task, remeasure the named part, `chat_notifier.dart`, declared
  part count, and same-library aggregate. Reconcile source drift in the task
  before editing.
- Require green Slices 2a1-2a3 and a corrected Slice 2b1 canary that closes the
  Slices 2b1-2b7 program gate. Stop if the canary did not use
  `qwen3.6-27b-vision`, did not record the reachable base URL, or did not prove
  exactly one exit for every expected conversation/generation.
- Preserve the historical manifest record. Set it to `partial` when
  orchestration remains, append the task's collaborator record, and add its
  exact discovery marker.
- Add the new production file to the shrink-only size budget at its achieved
  physical line count.
- Calculate the aggregate as:

  ```text
  new aggregate =
    previous aggregate
    - physical lines removed from declared parts
    + ChatNotifier primary-file delta
  ```

- Never raise the primary or aggregate budget. Lower every boundary that
  shrinks and update `docs/large_file_refactor_plan.md`.
- After an extraction intentionally removes or reclassifies audited notifier
  reads, review the delta, regenerate the canonical baseline, and verify it
  explicitly:

  ```bash
  fvm dart run tool/audit_chat_notifier_turn_scope.dart \
    --manifest tool/chat_notifier_decomposition_manifest.json \
    --check-baseline tool/chat_notifier_turn_scope_baseline.json
  fvm dart run tool/audit_chat_notifier_turn_scope.dart \
    --manifest tool/chat_notifier_decomposition_manifest.json \
    --write-baseline tool/chat_notifier_turn_scope_baseline.json
  git diff -- tool/chat_notifier_turn_scope_baseline.json
  fvm dart run tool/audit_chat_notifier_turn_scope.dart \
    --manifest tool/chat_notifier_decomposition_manifest.json \
    --check-baseline tool/chat_notifier_turn_scope_baseline.json
  ```

  Never accept a new ambient read merely by regenerating the baseline.
- New pure policy and formatter files require 100% executable-line coverage.
  Planner or side-effect coordinator files require at least 95%.
- Use this target-file assertion after the focused coverage run:

  ```bash
  target='<target-production-file>'
  minimum='<minimum-percent>'
  awk -v target="$target" -v minimum="$minimum" '
    /^SF:/ { in_target = substr($0, 4) == target }
    in_target && /^LF:/ { found = substr($0, 4) + 0 }
    in_target && /^LH:/ { hit = substr($0, 4) + 0 }
    in_target && /^end_of_record/ {
      rate = found == 0 ? 0 : 100.0 * hit / found
      printf "%s: %.2f%% (%d/%d)\n", target, rate, hit, found
      checked = 1
      if (rate + 0.0001 < minimum) exit 1
      exit 0
    }
    END { if (!checked) exit 1 }
  ' coverage/lcov.info
  ```

- Every task requires the corrected four-scenario live canary because it
  changes a recovery or verification path:

  ```bash
  # <reachable-base-url> is the verified OpenAI-compatible URL ending in /v1.
  reachable_base_url='<reachable-base-url>'
  curl -fsS "$reachable_base_url/models"
  CAVERNO_MULTI_THREAD_LIVE_CANARY=1 \
  CAVERNO_LLM_BASE_URL="$reachable_base_url" \
  CAVERNO_LLM_API_KEY=no-key \
  CAVERNO_LLM_MODEL=qwen3.6-27b-vision \
  fvm flutter test integration_test/multi_thread_plan_live_canary_test.dart \
    -d flutter-tester
  ```

  Record the endpoint, model, and exactly one `turn_exit` for every expected
  conversation and interaction generation.

## Safe Execution Order

After the exact-model Slice 2b gate passes, execute **WS5-8 first**. Its current
stale-`process_start` decision is already a pure explicit-input boundary and
does not depend on unresolved turn ownership. Then apply these exact gates:

- P14 (`Extract HiddenAssistantEvidenceScorer`) precedes WS5-3.
- P1b (`Adopt Explicit Turn Owner Snapshots`) precedes WS5-1, WS5-4, WS5-6,
  and WS5-7.
- P2 (`Key TurnToolResultLedger by Owner`) precedes WS5-2 and WS5-5 through
  WS5-7.
- P3a (`Key Finalization and Goal Claim State by Owner`) precedes WS5-5 through
  WS5-7.
- P4 (`Extract FileMutationEvidencePolicy`) precedes WS5-4.
- WS5-3 precedes WS5-4 so the `coding-verification-feedback` transition stays
  monotonic.
- WS5-5 precedes WS5-6 and WS5-7 so the `unexecuted-action-recovery`
  transition stays monotonic.

Within those gates, prefer WS5-3, WS5-1, WS5-2, WS5-4, WS5-5, WS5-6, and
WS5-7.

## WS5-1: Extract CodingContinuationRecoveryPolicy

### Task

- Goal: move coding-continuation detection, recovery payloads, and recovery
  prompt text into an independent policy.
- User-visible behavior: none; recovery codes, reasons, prompts, and detection
  decisions remain compatible.
- Non-goals: moving completion requests, executing tools, or changing recovery
  limits.

### Context

- Source:
  `chat_notifier_coding_continuation_recovery.dart` methods
  `_codingContinuationRecoveryCode`,
  `_hasCodingContinuationRecoveryTools`,
  `_isCodingContinuationRecoveryToolName`,
  `_looksLikeContinuationOnlyUserRequest`,
  `_looksLikeProseOnlyCodingContinuation`,
  `_buildCodingContinuationRecoveryToolResult`,
  `_buildCodingContinuationRecoveryPrompt`,
  `_codingContinuationRecoveryPartialProgressNotice`, and the five
  code-to-copy helpers.
- Callers:
  `_requestCodingContinuationRecovery` in the same part and
  `_recoverBeforeTurnFinalizationIfNeeded` in
  `chat_notifier_turn_finalization_recovery.dart`.
- Existing characterization:
  `test/features/chat/presentation/providers/chat_notifier_continuation_recovery_part.dart`.
- Destination:
  `lib/features/chat/domain/services/coding_continuation_recovery_policy.dart`.
- Direct tests:
  `test/features/chat/domain/services/coding_continuation_recovery_policy_test.dart`.

### Implementation Notes

- Define an immutable decision input with candidate response, tool definitions,
  owning-turn latest user text, `requireContinuationRequest`,
  `isCodingWorkspaceOrMode`, `hasPendingAutoContinueWorkflow`,
  `saveSkillCompletedInGeneration`, terminal-blocker acceptance, and bracketed
  tool request.
- Resolve every owner-sensitive fact from `interactionGeneration` before
  calling the policy. Do not preserve `_isCodingWorkspaceOrMode()` or
  `_hasPendingAutoContinueExecutionWorkflow()` unchanged: both currently read
  the visible conversation, while `_lastSaveSkillGeneration` is meaningful
  only when compared with the registered owner generation.
- Generate IDs through a narrow injected ID source or receive the ID explicitly
  when building a `ToolResultInfo`.
- Keep `_requestCodingContinuationRecovery` as the completion orchestration
  adapter.
- Do not pass settings, conversation state, generation maps, or helper closures.
- Manifest:
  `coding-continuation-recovery` from `remaining` to `partial`.
- Collaborator:
  - `id`: `coding-continuation-recovery-policy`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/coding_continuation_recovery_policy.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: coding-continuation-recovery-policy`.
- Part count remains unchanged.

### Similar-Pattern Search

- Search:
  `_codingContinuationRecoveryCode`,
  `prose_only_coding_continuation`,
  `bracketed_coding_tool_request`,
  `length_truncated_pending_action`, and
  `looksLikeProseOnlyCodingContinuationForTest`.
- Migrate policy assertions to direct tests and leave only orchestration tests
  in notifier fixtures.

### Acceptance Criteria

1. Every named pure method lives in the policy and both callers use it.
2. Direct tests cover all recovery codes, available/unavailable tools,
   continuation-only requests, structured deferral, save-skill completion,
   terminal blockers, partial command progress, CJK markers, and prompt text.
3. A poison case proves thread A's user request, pending workflow, and
   save-skill generation cannot be supplied from visible thread B.
4. Target coverage is 100%.
5. Manifest, marker, exact budget, aggregate ratchet, structural test,
   thread-scope ratchet, repository gate, and live canary pass.
6. Stop if preserving the decision requires the policy to read current
   conversation state or call a notifier helper. Stop earlier if the adapter
   cannot resolve workspace mode and pending workflow from the registered owner
   without a visible-thread fallback; that is a separate behavior fix.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/coding_continuation_recovery_policy.dart \
  lib/features/chat/presentation/providers/chat_notifier_coding_continuation_recovery.dart \
  lib/features/chat/presentation/providers/chat_notifier_turn_finalization_recovery.dart \
  test/features/chat/domain/services/coding_continuation_recovery_policy_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/coding_continuation_recovery_policy_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Assert the destination at `minimum=100`, then run the corrected live canary.

### Handoff Notes

- Record every migrated recovery branch and direct hit/line count.
- Record physical counts, budgets, manifest status, and unchanged part count.
- Record the poison case and canary endpoint/model/exit evidence.

### Completion Record (2026-07-31)

- The 423-line `CodingContinuationRecoveryPolicy` now owns all recovery-code,
  tool-availability, continuation-request, prose detection, recovery payload,
  partial-progress, prompt, and copy decisions.
- The notifier adapter supplies only immutable tool definitions and facts from
  the registered owner snapshot, including user text, coding mode, pending
  workflow, save-skill completion, terminal blockers, and bracketed requests.
- Twenty-two direct tests cover every recovery gate and code, immutable
  snapshots, English and CJK markers, blocker text, structured deferral,
  partial command progress, payload copy, and the owner/visible-thread poison
  case.
- The `coding-continuation-recovery` record is `partial`. Its historical part
  shrinks from 444 to 126 lines. The primary remains 9,073 lines, declared-part
  lines fall from 12,861 to 12,543, and the aggregate falls from 21,934 to
  21,616.

## WS5-2: Extract TurnFinalizationRecoveryPolicy

### Task

- Goal: isolate the pure decision that suppresses or allows coding continuation
  recovery at turn finalization.
- User-visible behavior: none; candidate selection and skip decisions remain
  compatible.
- Non-goals: moving turn finalization, active-message mutation, persistence, or
  tool-loop re-entry.

### Context

- Source:
  `chat_notifier_turn_finalization_recovery.dart` methods
  `_shouldSkipCompletedToolResultCodingContinuationRecovery`,
  `_hasSuccessfulFinalAnswerToolEvidence`,
  `_looksLikeCompletedCodingFinalAnswer`,
  `_looksLikeCodingFutureAction`,
  `_turnFinalizationCandidateText`, and
  `_contentBeforeFinalizationCandidate`.
- Callers:
  `_recoverBeforeTurnFinalizationIfNeeded`,
  `_shouldSkipCompletedToolResultFinalAnswerRecovery`, the completion-recovery
  branch in `_executeToolCalls`, and
  `_shouldSkipUnexecutedToolRequestNoticeForToolResults`.
- Destination:
  `lib/features/chat/domain/services/turn_finalization_recovery_policy.dart`.
- Direct tests:
  `test/features/chat/domain/services/turn_finalization_recovery_policy_test.dart`.

### Implementation Notes

- Accept candidate text, streamed final answer, immutable tool results, and
  explicit evidence facts for timeout, failed validation, unexecuted command,
  unexecuted file effect, current saved-validation success, file mutation, and
  command execution.
- Prerequisite: WS5-1 must be complete so finalization calls the independent
  continuation policy rather than the same-library decision.
- Resolve the tool-result snapshot for the exact owner. P2 provides
  `_turnToolResults.completed(owner)`; pass that immutable owner result list
  directly and do not reintroduce a visible-turn fallback.
- Reuse narrow independent evidence policies where available; do not accept
  boolean-producing notifier callbacks.
- Keep `_recoverBeforeTurnFinalizationIfNeeded` and
  `_prepareLastAssistantForTurnFinalizationRecovery` in the notifier library.
- Manifest:
  `turn-finalization-recovery` from `remaining` to `partial`.
- Collaborator:
  - `id`: `turn-finalization-recovery-policy`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/turn_finalization_recovery_policy.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: turn-finalization-recovery-policy`.
- Part count remains unchanged.

### Similar-Pattern Search

- Search:
  `_looksLikeCompletedCodingFinalAnswer`,
  `_looksLikeCodingFutureAction`,
  `_hasSuccessfulFinalAnswerToolEvidence`,
  `_shouldSkipCompletedToolResultFinalAnswerRecovery`, and
  `_lastStreamedToolResultFinalAnswersByGeneration`.
- Do not move the generation map into the policy.

### Acceptance Criteria

1. All named decisions are independent and receive complete evidence
   explicitly.
2. Direct tests cover empty/long answers, completed and future-tense answers,
   CJK markers, successful mutation/command evidence, timeout/failure,
   unexecuted claims, saved validation, streamed-answer mismatch, and prefix
   extraction.
3. A poison case uses different streamed answers and evidence for two owners
   and proves the caller selects the owning generation.
4. Target coverage is 100%.
5. Manifest, marker, budget, aggregate ratchet, structural test, thread-scope
   ratchet, repository gate, and live canary pass.
6. Stop if WS5-1 is incomplete, if the adapter cannot provide
   generation-correct tool evidence, or if the policy would need generation
   maps, response buffers, notifier state, or persistence.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/turn_finalization_recovery_policy.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  lib/features/chat/presentation/providers/chat_notifier_turn_finalization_recovery.dart \
  test/features/chat/domain/services/turn_finalization_recovery_policy_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/turn_finalization_recovery_policy_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Assert the destination at `minimum=100`, then run the corrected live canary.

### Handoff Notes

- Record migrated call sites, decision matrix, and poison case.
- Record counts, budgets, direct coverage, and manifest status.
- Record canary endpoint/model and exact exits.

### Completion Record (2026-07-31)

- The 268-line `TurnFinalizationRecoveryPolicy` now owns final-answer and coding
  continuation skip decisions, successful-evidence classification, completed
  and future coding prose detection, candidate selection, and prefix
  extraction.
- The notifier adapter freezes the exact owner's tool results and supplies
  explicit timeout, failed-validation, unexecuted-command,
  unexecuted-file-effect, saved-validation, file-mutation, command-execution,
  and generation-correct streamed-answer facts.
- Twenty direct tests cover the decision matrix, immutable snapshots, English
  and CJK completion/future markers, the 1,600-character boundary, candidate
  cleanup, prefix extraction, and owner/visible-generation poisoning. One
  Notifier integration test proves the owning generation selects both its
  streamed answer and tool evidence.
- Direct policy coverage is 64/64 lines (100%). The
  `turn-finalization-recovery` record is `partial`; its historical part shrinks
  from 373 to 304 lines. The primary remains 9,073 lines, declared-part lines
  fall from 12,543 to 12,474, and the aggregate falls from 21,616 to 21,547.

## WS5-3: Extract CodingVerificationFeedbackPresentation

### Task

- Goal: move coding-verification summaries, stable failure signatures, and
  convergence-blocker text into an independent presentation policy.
- User-visible behavior: none; persisted summaries and repair blocker text stay
  compatible.
- Non-goals: running verification, persisting task progress, or changing repair
  limits.

### Context

- Source:
  `chat_notifier_coding_verification_feedback.dart` methods
  `_codingVerificationCommandSummary`,
  `_codingVerificationProgressSummary`,
  `_codingVerificationValidationSummary`,
  `_codingVerificationCountsSummary`,
  `_shouldVerifyCodingCompletionClaim`,
  `_codingVerificationFailureSignature`,
  `_codingVerificationConvergenceBlocker`, and the data-building portion of
  `_logCodingVerificationFeedbackSummary`.
- Callers in the same part:
  lines 49, 76, 115, 127, 216, 226, and 228.
- Destination:
  `lib/features/chat/domain/services/coding_verification_feedback_presentation.dart`.
- Direct tests:
  `test/features/chat/domain/services/coding_verification_feedback_presentation_test.dart`.

### Implementation Notes

- Expose stateless functions over `CodingVerificationSnapshot`,
  `ToolResultInfo`, and an explicit maximum repair-attempt count.
- Reuse the narrow `HiddenAssistantEvidenceScorer` created by P14 for the
  completion-claim score. Do not construct `ToolTerminalResponsePolicy`, copy
  its lexical scoring, or retain the notifier-only
  `_hiddenAssistantEvidenceScore` delegate.
- Return a structured telemetry summary or formatted log line; logging stays in
  the notifier adapter.
- Preserve path relativization, failure ordering, maximum displayed failures,
  fallback messages, and JSON signature keys.
- Manifest:
  `coding-verification-feedback` from `remaining` to `partial`.
- Collaborator:
  - `id`: `coding-verification-feedback-presentation`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/coding_verification_feedback_presentation.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: coding-verification-feedback-presentation`.
- Part count remains unchanged.

### Similar-Pattern Search

- Search:
  `_codingVerificationProgressSummary`,
  `_codingVerificationFailureSignature`,
  `_codingVerificationConvergenceBlocker`,
  `Coding verification failed`, and `failing_tests`.
- Keep the execution service and progress persistence out of this task.

### Acceptance Criteria

1. All named formatting and signature logic is direct-tested independently.
2. Tests cover selected command, target fallback, pass/fail/unknown counts,
   located and unlocated failures, malformed payloads, five-failure clipping,
   empty content, completion-claim negatives, and telemetry fields.
3. The notifier performs only logging and persistence around returned values.
4. Target coverage is 100%.
5. Manifest, marker, budget, aggregate ratchet, structural test, thread-scope
   ratchet, repository gate, and live canary pass.
6. Stop if the collaborator would need settings, current conversation, a log
   store, or a persistence callback.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/coding_verification_feedback_presentation.dart \
  lib/features/chat/presentation/providers/chat_notifier_coding_verification_feedback.dart \
  test/features/chat/domain/services/coding_verification_feedback_presentation_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/coding_verification_feedback_presentation_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Assert the destination at `minimum=100`, then run the corrected live canary.

### Handoff Notes

- Record exact text/signature compatibility cases.
- Record counts, budgets, manifest status, and direct coverage.
- Record canary endpoint/model and exit evidence.

## WS5-4: Extract CodingVerificationMutationSignature

### Task

- Goal: compute coding-verification mutation signatures from explicit tool
  evidence and an owning project root.
- User-visible behavior: none; duplicate-verification suppression remains
  compatible.
- Non-goals: discovering the active project, running verification, or changing
  mutation success semantics.

### Context

- Source:
  `_codingVerificationMutationSignature` in
  `chat_notifier_coding_verification_feedback.dart`.
- Caller:
  `_requestCodingVerificationRepairForCompletionClaim` near line 79.
- Destination:
  `lib/features/chat/domain/services/coding_verification_mutation_signature.dart`.
- Direct tests:
  `test/features/chat/domain/services/coding_verification_mutation_signature_test.dart`.

### Implementation Notes

- API accepts immutable tool results and `projectRoot`.
- Prerequisites: complete P4 and WS5-3. P4 extracts an independently tested
  file-mutation evidence and path policy, while WS5-3 establishes the first
  `coding-verification-feedback` manifest transition. No current independent
  dependency preserves the required mutation semantics:
  `FinalAnswerClaimDetector` does not reject `already_applied`, while
  `_isSuccessfulFileMutationToolResult` does, and `_toolResultPayloadPath` /
  `_toolPathFromArguments` remain private notifier helpers.
- After that prerequisite, depend only on the independent file-mutation
  classification and path-extraction policy. Do not accept
  `_isFileMutationToolName`, `_isSuccessfulFileMutationToolResult`,
  `_toolResultPayloadPath`, or `_toolPathFromArguments` as callbacks.
- Preserve entry order and `id`, `name`, and resolved `path` JSON fields.
- The caller resolves project root from its interaction generation.
- Manifest:
  `coding-verification-feedback` remains `partial`.
- Collaborator:
  - `id`: `coding-verification-mutation-signature`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/coding_verification_mutation_signature.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: coding-verification-mutation-signature`.

### Similar-Pattern Search

- Search:
  `_codingVerificationMutationSignature`,
  `_changedFileMutationPaths`,
  `_toolResultPayloadPath`,
  `_toolPathFromArguments`, and `FilesystemTools.resolvePath`.
- Record shared path-policy opportunities without widening the slice.

### Acceptance Criteria

1. The collaborator never calls `_getActiveProjectRootPath` or reads a Zone.
2. Tests cover successful/failed mutations, non-Dart paths, result-vs-argument
   paths, relative/absolute paths, ordering, duplicates, and empty evidence.
3. A poison test passes roots A and B over identical relative evidence and
   proves distinct owner-correct signatures.
4. Target coverage is 100%.
5. Manifest, marker, exact budget, aggregate ratchet, structural test,
   thread-scope ratchet, repository gate, and live canary pass.
6. Stop until the separately approved file-mutation evidence prerequisite is
   complete. Do not silently substitute `FinalAnswerClaimDetector` or change
   `already_applied` handling to make the extraction compile.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/coding_verification_mutation_signature.dart \
  lib/features/chat/presentation/providers/chat_notifier_coding_verification_feedback.dart \
  test/features/chat/domain/services/coding_verification_mutation_signature_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/coding_verification_mutation_signature_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Assert the destination at `minimum=100`, then run the corrected live canary.

### Handoff Notes

- Record owner-root resolution and poison evidence.
- Record counts, budgets, manifest status, and direct coverage.
- Record canary endpoint/model and exits.

### Completion Record (2026-07-31)

- The 64-line `CodingVerificationMutationSignature` now freezes the supplied
  owner tool results, delegates mutation eligibility and path precedence to
  `FileMutationEvidencePolicy`, and resolves eligible Dart paths against the
  explicit owning project root.
- The Notifier resolves the project root from the interaction generation and
  retains only verification orchestration and duplicate-signature state.
- Nine direct tests cover recursively immutable JSON arguments, invalid input,
  failed and already-applied mutations, non-Dart evidence, result-over-argument
  path precedence, relative/absolute paths, source order, duplicates, and
  roots A/B over identical evidence. Direct coverage is 24/24 lines (100%).
- The `coding-verification-feedback` record remains `partial`; its historical
  part shrinks from 331 to 313 lines. The primary remains 9,073 lines,
  declared-part lines fall from 12,474 to 12,456, and the aggregate falls from
  21,547 to 21,529.

## WS5-5: Extract UnexecutedFinalAnswerToolRequestPolicy

### Task

- Goal: move final-answer embedded-tool-call recording and notice decisions
  into a pure result policy.
- User-visible behavior: none; diagnostic result payload and notice text remain
  compatible.
- Non-goals: mutating messages, setting turn exit state, or retrying tools.

### Context

- Source:
  `_appendUnexecutedToolRequestNoticeForContentIfNeeded` and
  `_recordUnexecutedFinalAnswerToolRequests` in
  `chat_notifier_unexecuted_action_recovery.dart`, plus the notice-decision
  methods `_shouldSkipUnexecutedToolRequestNoticeForToolResults`,
  `_looksLikeUnexecutedToolRequest`, `_looksLikeStructuredToolRequest`,
  `_looksLikeBracketedToolRequest`, `_bracketedToolRequestName`, and
  `_looksLikePlanOnlyFinalToolAnswer` in `chat_notifier.dart`.
- Caller:
  final-answer streaming through
  `_appendUnexecutedToolRequestNoticeForContentIfNeeded`.
- Destination:
  `lib/features/chat/domain/services/unexecuted_final_answer_tool_request_policy.dart`.
- Direct tests:
  `test/features/chat/domain/services/unexecuted_final_answer_tool_request_policy_test.dart`.

### Implementation Notes

- Return an immutable analysis containing new tool results, whether to append
  the notice, the exact notice text, optional exit reason, and transform ID.
- Accept content and immutable existing tool results. Do not mutate caller
  lists or notifier fields.
- Prerequisites: P2, P3a, and WS5-2 must be complete. WS5-2 owns the
  completed/future coding final-answer decisions used by the notice skip
  policy.
- Apply the returned exit reason and transform ID through
  `TurnFinalizationStateRegistry` under the exact `ChatTurnOwner`. P3a forbids
  reverting these values to flat notifier fields.
- The notifier applies results and message changes only after confirming the
  interaction generation still owns the turn.
- Manifest:
  `unexecuted-action-recovery` from `remaining` to `partial`.
- Collaborator:
  - `id`: `unexecuted-final-answer-tool-request-policy`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/unexecuted_final_answer_tool_request_policy.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: unexecuted-final-answer-tool-request-policy`.

### Similar-Pattern Search

- Search:
  `final_answer_tool_request`,
  `tool_call_not_executed`,
  `unexecuted_tool_request_notice`,
  `extractCompletedToolCalls`, and
  `_looksLikeUnexecutedToolRequest`.
- Do not absorb file, command, browser, or narrated-transcript claim policies.

### Acceptance Criteria

1. The policy is immutable and contains no message/state mutation.
2. Tests cover zero/one/multiple embedded calls, duplicate signatures,
   occurrence IDs, malformed content, pre-existing notice, skip conditions,
   and exact JSON/tag-independent output.
3. The adapter applies exit reason and transforms only to the owning
   interaction generation.
4. Target coverage is 100%.
5. Manifest, marker, budget, aggregate ratchet, structural test, thread-scope
   ratchet, repository gate, and live canary pass.
6. Stop if generation ownership cannot be checked before applying the returned
   analysis, if exit/transform metadata is not generation-scoped, or if WS5-2
   is incomplete.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/unexecuted_final_answer_tool_request_policy.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  lib/features/chat/presentation/providers/chat_notifier_unexecuted_action_recovery.dart \
  test/features/chat/domain/services/unexecuted_final_answer_tool_request_policy_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/unexecuted_final_answer_tool_request_policy_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Assert the destination at `minimum=100`, then run the corrected live canary.

### Handoff Notes

- Record exact output fixtures, application ordering, and generation check.
- Record counts, budgets, direct coverage, and manifest status.
- Record canary endpoint/model and exits.

### Completion Record (2026-07-31)

- The 281-line `UnexecutedFinalAnswerToolRequestPolicy` now freezes existing
  owner results; records zero, one, or multiple completed final-answer tool
  tags; suppresses prior and in-answer duplicate signatures; and returns
  immutable new results, exact notice copy, optional exit reason, and transform
  ID without mutating messages or state.
- Structured, bracketed, fenced/raw JSON, plan-only, command, file-action,
  completed-answer, and future-action decisions now live behind the policy.
  Terminal-response, continuation-recovery, and no-evidence notice consumers
  call the independent classifier directly.
- The Notifier confirms that the interaction generation resolves to the exact
  supplied owner before analysis and again before applying new tool results,
  owner-keyed exit/transform metadata, or message content.
- Eighteen direct tests cover immutable JSON, invalid arguments, empty and
  malformed content, exact occurrence IDs and payloads, multiple and duplicate
  calls, prior signatures, tag spelling, idempotence, structured request
  shapes, every skip gate, the 1,600-character boundary, and an owner poison
  case. Direct coverage is 117/117 lines (100%).
- The `unexecuted-action-recovery` record is `partial`; its historical part
  shrinks from 564 to 521 lines. The primary shrinks from 9,073 to 8,943 lines,
  declared-part lines fall from 12,456 to 12,420, and the aggregate falls from
  21,529 to 21,363.

## WS5-6: Extract FinalAnswerClaimNoticeApplicator

### Task

- Goal: replace notifier-bound verification, narrated-transcript, and unwritten
  file claim notice facades with one explicit-input applicator and direct use
  of `FinalAnswerClaimDetector`.
- User-visible behavior: none; notice text, ordering, and transform IDs remain
  compatible.
- Non-goals: changing claim detection, repairing a response, or changing
  project-root ownership.

### Context

- Source:
  `chat_notifier_unexecuted_action_recovery.dart` methods
  `_messageContentWithVerificationClaimNotice`,
  `_messageContentWithNarratedTranscriptClaimNotice`,
  `_messageContentWithUnwrittenFileClaimNotice`, and delegate-only methods from
  `_buildUnexecutedSkippedBrowserActionToolResult` through
  `_looksLikeFutureFileSideEffectAction`.
- Sequential finalization caller:
  the nested claim-notice application in `_finishStreaming`.
- Detector callers:
  the no-tool finalization, tool-result recovery, pending-batch finalization,
  and streamed-final-answer branches in `chat_notifier.dart`.
- Destination:
  `lib/features/chat/domain/services/final_answer_claim_notice_applicator.dart`.
- Direct tests:
  `test/features/chat/domain/services/final_answer_claim_notice_applicator_test.dart`.

### Implementation Notes

- Input:
  workspace mode, candidate content, immutable tool results, executed commands,
  explicit owning project root, and explicit `offersCommandExecution`.
- Output:
  final content plus ordered transform IDs.
- Prerequisites: P1b, P2, P3a, and WS5-5 must be complete.
- Use the exact-owner snapshot, `TurnToolResultLedger`, and
  `TurnFinalizationStateRegistry` supplied by P1b, P2, and P3a for project,
  allowed-tool, command, result, and transform evidence. Do not restore any
  ambient or generation-only storage.
- Depend on existing independent claim guards and `FinalAnswerClaimDetector`.
- Replace delegate-only call sites directly. Preserve any required public test
  seam only as a thin delegate, or migrate it to the direct detector test.
- Manifest:
  `unexecuted-action-recovery` remains `partial`.
- Collaborator:
  - `id`: `final-answer-claim-notice-applicator`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/final_answer_claim_notice_applicator.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: final-answer-claim-notice-applicator`.

### Similar-Pattern Search

- Search:
  `_messageContentWithVerificationClaimNotice`,
  `_messageContentWithNarratedTranscriptClaimNotice`,
  `_messageContentWithUnwrittenFileClaimNotice`,
  `_finalAnswerClaimDetector`, and every removed delegate name.
- Update direct detector tests rather than duplicating its implementation.

### Acceptance Criteria

1. The three notice layers preserve their current order and idempotence.
   The current nested order is unwritten-file, then narrated-transcript, then
   verification.
2. All unnecessary notifier delegate methods and call sites are removed.
3. Tests cover non-coding mode, each notice independently, all three notices,
   already-present notices, successful evidence, explicit project roots, and
   unavailable command capability.
4. A poison case proves project root and tool evidence come from the owning
   turn rather than the visible turn.
5. Target coverage is 100%; manifest, marker, budget, ratchets, repository
   gate, and live canary pass.
6. Stop if generation-scoped evidence is unavailable or the applicator needs
   `ChatState`, the notifier ledger, or a root resolver callback.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/final_answer_claim_notice_applicator.dart \
  lib/features/chat/presentation/providers/chat_notifier.dart \
  lib/features/chat/presentation/providers/chat_notifier_unexecuted_action_recovery.dart \
  test/features/chat/domain/services/final_answer_claim_notice_applicator_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/final_answer_claim_notice_applicator_test.dart
fvm flutter test \
  test/features/chat/domain/services/final_answer_claim_detector_test.dart \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Assert the destination at `minimum=100`, then run the corrected live canary.

### Handoff Notes

- Record removed delegates and all direct call-site replacements.
- Record poison evidence, counts, budgets, and direct coverage.
- Record canary endpoint/model and exits.

### Completion Record (2026-07-31)

- The 136-line `FinalAnswerClaimNoticeApplicator` freezes tool-result argument
  JSON and command evidence, accepts the exact owner's workspace mode, project
  root, and command-execution capability, and returns immutable final content
  plus ordered transform IDs without reading notifier state.
- Finalization now applies unwritten-file, narrated-transcript, and
  verification notices in the established order through one explicit input,
  then records returned transforms against the same owner. Existing notice
  copy and idempotence remain unchanged.
- All detector-only callers now invoke `FinalAnswerClaimDetector` directly.
  The notifier read-only-inspection characterization was migrated to the
  detector, and obsolete notifier delegates and public detector seams were
  removed.
- Twelve direct tests cover non-coding mode, every independent notice, combined
  ordering, already-present notices, successful evidence, explicit roots,
  unavailable command execution, immutable inputs, invalid JSON, and an
  owner/visible-turn poison case. Direct coverage is 48/48 lines (100%).
- The `unexecuted-action-recovery` manifest record remains `partial` and now
  declares the applicator collaborator. Its historical part shrinks from 521
  to 240 lines. The primary remains at its 8,943-line ceiling, declared-part
  lines fall from 12,420 to 12,117, and the aggregate falls from 21,363 to
  21,060.
- The exact-model live canary remains part of the integrated final gate and is
  not claimed by this focused record.

## WS5-7: Extract NarratedTranscriptRepairPlanner

### Task

- Goal: move narrated-transcript repair eligibility, attempt bounding,
  signature construction, and feedback construction into an independent
  planner.
- User-visible behavior: none; repair eligibility and feedback remain
  compatible.
- Non-goals: persisting artifacts, mutating messages, calling the LLM, or
  re-entering the tool loop.

### Context

- Source:
  the planning portion of
  `_requestNarratedTranscriptRepairForCompletionClaim` in
  `chat_notifier_unexecuted_action_recovery.dart`.
- Callers:
  `_requestNarratedTranscriptRepairForCompletionClaim` and
  `_applyNarratedTranscriptRepairToStreamedFinalAnswer`.
- Destination:
  `lib/features/chat/domain/services/narrated_transcript_repair_planner.dart`.
- Direct tests:
  `test/features/chat/domain/services/narrated_transcript_repair_planner_test.dart`.
- Existing guard:
  the narrated-transcript claim guard.

### Implementation Notes

- Input:
  verification-enabled flag, workspace mode, planning flag, candidate,
  immutable evidence, executed commands, attempted signatures, maximum
  attempts, and explicit feedback ID.
- Prerequisites: P1b, P2, P3a, and WS5-5 must be complete.
- Resolve workspace and planning facts from the exact owner snapshot and pass
  `_turnToolResults.commands(owner)` explicitly. The planner must not read the
  visible conversation or an ambient command ledger.
- Return either no plan or an immutable plan containing signature, assessment,
  and `ToolResultInfo`.
- The notifier owns signature-set mutation only after confirming the plan's
  owner generation is current.
- Keep persistence, transform application, `<think>` handling, completion
  request, and tool-loop re-entry in the notifier.
- Manifest:
  `unexecuted-action-recovery` remains `partial`.
- Collaborator:
  - `id`: `narrated-transcript-repair-planner`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/narrated_transcript_repair_planner.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: narrated-transcript-repair-planner`.

### Similar-Pattern Search

- Search:
  `_requestNarratedTranscriptRepairForCompletionClaim`,
  `narrated_transcript_check`,
  `attemptedSignatures`,
  `_maxNarratedTranscriptRepairAttempts`, and
  `narrated_transcript_repair`.
- Keep coding-verification repair planning separate.

### Acceptance Criteria

1. Planner decisions require no notifier state or mutation.
2. Tests cover disabled/non-coding/planning states, no unexecuted commands,
   repeated signature, attempt limit, successful plan, exact payload, and
   deterministic explicit IDs.
3. A poison case gives two owners separate attempted-signature sets and proves
   one cannot suppress the other's first repair.
4. Target coverage is 100%.
5. Manifest, marker, budget, aggregate ratchet, structural test, thread-scope
   ratchet, repository gate, and live canary pass.
6. Stop if owner-scoped command evidence is unavailable, or if the planner must
   persist artifacts or receive a completion callback.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/narrated_transcript_repair_planner.dart \
  lib/features/chat/presentation/providers/chat_notifier_unexecuted_action_recovery.dart \
  test/features/chat/domain/services/narrated_transcript_repair_planner_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/narrated_transcript_repair_planner_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Assert the destination at `minimum=100`, then run the corrected live canary.

### Handoff Notes

- Record planner input/output shape and application ordering.
- Record poison evidence, counts, budgets, and coverage.
- Record canary endpoint/model and exits.

### Completion Record (2026-07-31)

- The 179-line `NarratedTranscriptRepairPlanner` freezes the exact owner's tool
  results, commands, and attempted signatures, classifies every no-plan
  reason, and returns an immutable owner-bound signature, assessment, and
  explicit-ID feedback result without mutating notifier state.
- The Notifier resolves coding and planning facts from the exact owner
  snapshot and passes `_turnToolResults.commands(owner)` explicitly. It checks
  that same owner before adding the planned signature, after artifact
  persistence, and before removing the streamed think marker.
- Ten direct tests cover immutable JSON and collections, invalid arguments,
  disabled/non-coding/planning gates, fully executed transcripts, repeated
  signatures, attempt limits, exact payload and deterministic IDs,
  equal-generation owner poisoning, and peer command-evidence isolation.
  Direct coverage is 39/39 lines (100%).
- Three existing Notifier integration scenarios prove disabled annotation,
  declined repair replacement, and tool-loop revival remain compatible.
- The `unexecuted-action-recovery` record remains `partial` and now declares
  the planner collaborator. Its historical part shrinks from 240 to 228 lines.
  The primary shrinks from 8,943 to 8,942 lines, declared-part lines fall from
  12,117 to 12,105, and the aggregate falls from 21,060 to 21,047.
- The exact-model live canary remains part of the integrated final gate and is
  not claimed by this focused record.

## WS5-8: Extract ProcessStartResultPolicy

### Task

- Goal: move stale `process_start` result detection and diagnostic payload
  construction into an independent result policy.
- Execution order: implement this as the first Workstream 5 slice after the
  exact-model Slice 2b gate passes.
- User-visible behavior: none; stale/fresh classification and result payload
  remain compatible.
- Non-goals: executing a process, registering monitoring, or changing stale
  timing.

### Context

- Source:
  `_buildStaleProcessStartGuardResult` and its value conversion helper in
  `chat_notifier_tool_loop_batch.dart`.
- Caller:
  the dispatch-result normalization branch in `_executeToolLoopBatch`.
- Destination:
  `lib/features/chat/domain/services/process_start_result_policy.dart`.
- Direct tests:
  `test/features/chat/domain/services/process_start_result_policy_test.dart`.

### Implementation Notes

- API accepts `ToolCallInfo`, `McpToolResult`, and `dispatchedAt`.
- Preserve the five-second tolerance, duplicate-existing exception, timestamp
  parsing, copied fields, error message, and required action.
- Use an independent JSON decoder; do not accept `_tryDecodeMap` as a callback.
- Manifest:
  `tool-loop-batch` from `remaining` to `partial`.
- Collaborator:
  - `id`: `process-start-result-policy`;
  - `path` and `sizeBudgetKey`:
    `lib/features/chat/domain/services/process_start_result_policy.dart`.
- Marker:
  `// ChatNotifier decomposition collaborator: process-start-result-policy`.
- Part count remains unchanged.

### Similar-Pattern Search

- Search:
  `_buildStaleProcessStartGuardResult`,
  `background_process_start_stale_result`,
  `duplicate_existing`, `started_at`, and
  `_recordBackgroundProcessStartResult`.
- Do not move process monitoring in this task.

### Acceptance Criteria

1. Direct tests cover non-process tools, failures, malformed JSON, missing or
   invalid timestamp, duplicate result, boundary time, stale time, and copied
   metadata.
2. The caller applies the policy before recording execution and replay state.
3. The policy has no clock, process monitor, notifier, state, provider, or Zone
   dependency.
4. Target coverage is 100%.
5. Manifest, marker, exact budget, aggregate ratchet, structural test,
   thread-scope ratchet, repository gate, and live canary pass.
6. Stop if moving the policy would also move background-process registration
   or tool-result persistence.

### Verification

```bash
fvm dart format \
  lib/features/chat/domain/services/process_start_result_policy.dart \
  lib/features/chat/presentation/providers/chat_notifier_tool_loop_batch.dart \
  test/features/chat/domain/services/process_start_result_policy_test.dart \
  --set-exit-if-changed
fvm flutter analyze
fvm flutter test --coverage \
  test/features/chat/domain/services/process_start_result_policy_test.dart
fvm flutter test \
  test/quality/chat_notifier_collaborator_boundary_test.dart \
  test/quality/file_size_ratchet_test.dart \
  test/quality/thread_scoped_state_ratchet_test.dart
tool/codex_verify.sh --coverage
git diff --check
```

Assert the destination at `minimum=100`, then run the corrected live canary.

### Handoff Notes

- Record stale-boundary fixtures and exact payload compatibility.
- Record counts, budgets, manifest status, and coverage.
- Record canary endpoint/model and exits.

### Completion Record (2026-07-31)

- The 73-line `ProcessStartResultPolicy` now receives the exact tool call,
  dispatch result, and dispatch timestamp before execution/replay state is
  recorded.
- Eight direct tests cover non-process and failed results, malformed payloads,
  explicit success, timestamp validation, duplicate jobs, exact five-second
  tolerance, fresh results, and complete stale-result metadata.
- The `tool-loop-batch` record is `partial`. Its historical part shrinks from
  738 to 685 lines, while the primary remains 9,073 lines.
- The focused tree retains 38 declared parts with 12,861 part lines and lowers
  the same-library aggregate from 21,987 to 21,934 lines.

## Deferred Boundaries

The following are not approved Workstream 5 extraction slices:

- `_executeToolLoopBatch`: it combines candidate deduplication, twelve
  guardrails, approval, dispatch, replay, persistence, mutation generation,
  failure reduction, diagnostics, and lifecycle cancellation. Revisit only
  after Workstreams 6 and 7 move those dependencies. Then specify candidate
  planning, guarded execution, and result reduction separately.
- `_persistToolResultForPrompt`: owns artifact persistence, taint, command
  ledger, process monitoring, and edit telemetry around an interaction
  generation.
- `_recordCodingVerificationValidationProgress` and
  `_buildCodingVerificationFeedbackRun`: they persist the visible conversation.
  They require an owner-aware validation-progress port and a separate behavior
  review before extraction.
- `_requestCodingVerificationRepairForCompletionClaim`: retains artifact
  persistence, response-buffer mutation, completion calls, and generation
  cancellation.
- `_streamToolResultAnswerWithContextRetry`: owns streaming response buffers,
  timeout recovery, compact retry, final message replacement, and generation
  lifecycle. `FinalAnswerRecoveryPolicy` already owns its pure decision.
- `_recoverBeforeTurnFinalizationIfNeeded` and
  `_prepareLastAssistantForTurnFinalizationRecovery`: retain active-response
  registration, detached buffers, state writes, tool-loop re-entry, and
  lifecycle.
- `_applyNarratedTranscriptRepairToStreamedFinalAnswer`: retains tool-loop
  re-entry and generation-scoped response application.

Keep each historical manifest record `partial` or `remaining` as appropriate
and record these reasons. Do not disguise orchestration as a collaborator by
passing a large callback bag.
