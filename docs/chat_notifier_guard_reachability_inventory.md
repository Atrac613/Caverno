# ChatNotifier Guard Reachability Inventory

Status: Phase 1 matching-build classification complete. Two orphan
proposal-parsing delegates satisfy the `dead` contract; the other 63 candidates
remain unresolved.

Classified source revision: `55efb18f51e2739f195bca0d5bd7b1669d5c0f9d`. The checked-in manifest uses
`HEAD` as its symbolic revision so the post-commit clean-source check can resolve
the exact commit without embedding a self-referential commit hash.

## Scope and method

The finite discovery contract covers:

- top-level production types under `lib/features/chat/domain/services` whose
  names end in `Guard`, `Policy`, or `Recovery`;
- members in `chat_notifier*.dart` whose names contain `guard`, `recovery`, or
  `repair`.

Every discovery result is either an inventory entry or an explicit exclusion.
Phase 0A uses lexical references and reviewable source/history proofs. It does
not use missing telemetry as evidence of death. Unresolved callback and
runtime-configuration edges remain recorded for every candidate whose static
call graph is not closed.

Reproduce the inventory check with:

```bash
python3 test/python/analyze_chat_notifier_inventory_test.py
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --check-guard-manifest tool/chat_notifier_guard_inventory.json
git diff --check
```

## Static inventory

The table combines the original static review with the clean matching-build
measurement recorded below. Unmapped or statically open candidates remain
unresolved even when the corpus contains no firing.

| Symbol | Source | Kind | Selection refs | Reachability impact | Telemetry | Current static state | Observed by build | Action state |
| --- | --- | --- | ---: | --- | --- | --- | --- | --- |
| `AnalysisOptionsLintEditGuard` | `analysis_options_lint_edit_guard.dart` | guard_type | 2 | silent non-fire can leave a guarded or corrective path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `AskUserQuestionPolicy` | `ask_user_question_policy.dart` | policy_type | 4 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `BackgroundProcessFollowUpPolicy` | `background_process_follow_up_policy.dart` | policy_type | 7 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `BackgroundProcessPathPolicy` | `background_process_path_policy.dart` | policy_type | 4 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `CodingContinuationRecoveryPolicy` | `coding_continuation_recovery_policy.dart` | policy_type | 8 | silent non-fire can leave a recovery path unreachable | `turn_exit.transforms:coding_continuation_recovery_*` | Unresolved | Not measured | Unresolved |
| `CodingVerificationClaimGuard` | `coding_verification_claim_guard.dart` | guard_type | 4 | silent non-fire can leave a guarded or corrective path unreachable | `tool_result.trigger:completionClaim` | Unresolved | Not measured | Unresolved |
| `CommandDiagnosticVerifierReplayGuard` | `command_diagnostic_verifier_replay_guard.dart` | guard_type | 3 | silent non-fire can leave a guarded or corrective path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `CommandDiagnosticVerifierReplayPolicy` | `command_diagnostic_verifier_replay_policy.dart` | policy_type | 2 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `ComputerUseActionPolicy` | `computer_use_action_policy.dart` | policy_type | 5 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `ContextSurgeryProtectedPathPolicy` | `context_surgery_protected_path_policy.dart` | policy_type | 3 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `ConversationGoalAutoContinuePolicy` | `conversation_goal_auto_continue_policy.dart` | policy_type | 3 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `DuplicateToolResultRecovery` | `duplicate_tool_result_recovery.dart` | recovery_type | 8 | silent non-fire can leave a recovery path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `ExecutionBudgetPolicy` | `execution_budget_policy.dart` | policy_type | 2 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `FileMutationEvidencePolicy` | `file_mutation_evidence_policy.dart` | policy_type | 12 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `FinalAnswerRecoveryPolicy` | `final_answer_recovery_policy.dart` | policy_type | 5 | silent non-fire can leave a recovery path unreachable | `turn_exit.transforms:final_answer_concise_retry` | Unresolved | Not measured | Unresolved |
| `GitTagFormatInspectionGuard` | `git_tag_format_inspection_guard.dart` | guard_type | 2 | silent non-fire can leave a guarded or corrective path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `GitWriteConfirmationPolicy` | `git_write_confirmation_policy.dart` | policy_type | 3 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `GoalValidationProbeGuard` | `goal_validation_probe_guard.dart` | guard_type | 3 | silent non-fire can leave a guarded or corrective path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `MaterialContractAssumptionGuard` | `material_contract_assumption_guard.dart` | guard_type | 4 | silent non-fire can leave a guarded or corrective path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `ModelSwitchSettingsPolicy` | `model_switch_settings_policy.dart` | policy_type | 2 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `NarratedTranscriptClaimGuard` | `narrated_transcript_claim_guard.dart` | guard_type | 5 | silent non-fire can leave a guarded or corrective path unreachable | `turn_exit.transforms:narrated_transcript_repair` | Unresolved | Not measured | Unresolved |
| `ParticipantMessageVisibilityPolicy` | `participant_message_finalizer.dart` | policy_type | 2 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `ParticipantToolPolicy` | `participant_tool_policy.dart` | policy_type | 7 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `PendingActionLengthRecoveryPolicy` | `pending_action_length_recovery_policy.dart` | policy_type | 2 | silent non-fire can leave a recovery path unreachable | `turn_exit.transforms:pending_action_length_recovery` | Unresolved | Not measured | Unresolved |
| `PlanningToolPolicy` | `planning_tool_policy.dart` | policy_type | 4 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `ProcessStartResultPolicy` | `process_start_result_policy.dart` | policy_type | 5 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `ProductionReleaseApprovalPolicy` | `production_release_approval_policy.dart` | policy_type | 1 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `PythonAttachmentRepairPolicy` | `python_attachment_repair_policy.dart` | policy_type | 8 | silent non-fire can leave a recovery path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `SavedTaskTargetScopeGuard` | `saved_task_target_scope_guard.dart` | guard_type | 4 | silent non-fire can leave a guarded or corrective path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `SavedValidationCommandGuard` | `saved_validation_command_guard.dart` | guard_type | 2 | silent non-fire can leave a guarded or corrective path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `SubagentToolPolicy` | `subagent_tool_policy.dart` | policy_type | 5 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `TimedOutCommandRetryGuard` | `timed_out_command_retry_guard.dart` | guard_type | 3 | silent non-fire can leave a guarded or corrective path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `ToolCallExecutionPolicy` | `tool_call_execution_policy.dart` | policy_type | 29 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `ToolLoopExhaustionPolicy` | `tool_loop_exhaustion_policy.dart` | policy_type | 2 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `ToolLoopRecoveryPolicy` | `tool_loop_recovery_policy.dart` | policy_type | 2 | silent non-fire can leave a recovery path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `ToolTerminalResponsePolicy` | `tool_terminal_response_policy.dart` | policy_type | 6 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `ToolTerminalSuccessPolicy` | `tool_terminal_success_policy.dart` | policy_type | 3 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `TruncatedToolCallArgumentsGuard` | `truncated_tool_call_arguments_guard.dart` | guard_type | 4 | silent non-fire can leave a guarded or corrective path unreachable | `turn_exit.transforms:truncated_tool_call_arguments_feedback` | Unresolved | Not measured | Unresolved |
| `TurnFinalizationRecoveryPolicy` | `turn_finalization_recovery_policy.dart` | policy_type | 6 | silent non-fire can leave a recovery path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `UnexecutedFileMutationBeforeCommandGuard` | `unexecuted_file_mutation_before_command_guard.dart` | guard_type | 2 | silent non-fire can leave a guarded or corrective path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `UnexecutedFinalAnswerToolRequestPolicy` | `unexecuted_final_answer_tool_request_policy.dart` | policy_type | 11 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `UnwrittenFileClaimGuard` | `unwritten_file_claim_guard.dart` | guard_type | 4 | silent non-fire can leave a guarded or corrective path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `VerificationCadencePolicy` | `verification_cadence_policy.dart` | policy_type | 2 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `VerifierReplayCandidatePolicy` | `verifier_replay_candidate_policy.dart` | policy_type | 2 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `WorkflowTaskRunLifecyclePolicy` | `workflow_task_run_lifecycle_policy.dart` | policy_type | 2 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `WorkflowTaskTurnRoutePolicy` | `workflow_task_turn_route_policy.dart` | policy_type | 3 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `_postSavedValidationEvidenceRequiresRepair` | `chat_notifier.dart` | notifier_member | 1 | silent non-fire can leave a guarded or corrective path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `_requestBackgroundProcessMonitorRepairForCompletionClaim` | `chat_notifier.dart` | notifier_member | 2 | silent non-fire can leave a recovery path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `_requestSkippedBrowserActionRepairAfterSnapshot` | `chat_notifier.dart` | notifier_member | 1 | silent non-fire can leave a recovery path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `_shouldRepairSkippedBrowserActionAfterSnapshot` | `chat_notifier.dart` | notifier_member | 1 | silent non-fire can leave a guarded or corrective path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `_hasCodingContinuationRecoveryTools` | `chat_notifier_coding_continuation_recovery.dart` | notifier_member | 2 | silent non-fire can leave a guarded or corrective path unreachable | `turn_exit.transforms:coding_continuation_recovery_*` | Unresolved | Not measured | Unresolved |
| `_requestCodingContinuationRecovery` | `chat_notifier_coding_continuation_recovery.dart` | notifier_member | 4 | silent non-fire can leave a recovery path unreachable | `turn_exit.transforms:coding_continuation_recovery_*` | Unresolved | Not measured | Unresolved |
| `_requestCodingVerificationRepairForCompletionClaim` | `chat_notifier_coding_verification_feedback.dart` | notifier_member | 2 | silent non-fire can leave a recovery path unreachable | `tool_result.trigger:completionClaim` | Unresolved | Not measured | Unresolved |
| `_buildProductionReleaseApprovalGuardResult` | `chat_notifier_command_guardrails.dart` | notifier_member | 1 | selection may enable, block, or redirect turn behavior | Not mapped | Unresolved | Not measured | Unresolved |
| `_replayVerifierAfterRepairMutation` | `chat_notifier_goal_auto_continue.dart` | notifier_member | 1 | silent non-fire can leave a recovery path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `_repairJsonCandidate` | `chat_notifier_proposal_parsing.dart` | notifier_member | 0 | silent non-fire can leave a recovery path unreachable | Not mapped | Unreachable | No contradictory observation in 4 clean matching-build records | Dead |
| `_tryRepairAndDecodeMap` | `chat_notifier_proposal_parsing.dart` | notifier_member | 0 | silent non-fire can leave a recovery path unreachable | Not mapped | Unreachable | No contradictory observation in 4 clean matching-build records | Dead |
| `_requestPythonAttachmentPathFailureRepair` | `chat_notifier_python_attachment_repair.dart` | notifier_member | 1 | silent non-fire can leave a recovery path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `_requestSkippedPythonAttachmentAnalysisRepair` | `chat_notifier_python_attachment_repair.dart` | notifier_member | 1 | silent non-fire can leave a recovery path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `_buildTruncatedToolCallArgumentsGuardResult` | `chat_notifier_tool_loop_batch.dart` | notifier_member | 1 | selection may enable, block, or redirect turn behavior | `turn_exit.transforms:truncated_tool_call_arguments_feedback` | Unresolved | Not measured | Unresolved |
| `_prepareLastAssistantForTurnFinalizationRecovery` | `chat_notifier_turn_finalization_recovery.dart` | notifier_member | 1 | silent non-fire can leave a recovery path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `_shouldSkipCompletedToolResultCodingContinuationRecovery` | `chat_notifier_turn_finalization_recovery.dart` | notifier_member | 1 | silent non-fire can leave a guarded or corrective path unreachable | `turn_exit.transforms:coding_continuation_recovery_*` | Unresolved | Not measured | Unresolved |
| `_shouldSkipCompletedToolResultFinalAnswerRecovery` | `chat_notifier_turn_finalization_recovery.dart` | notifier_member | 2 | silent non-fire can leave a guarded or corrective path unreachable | `turn_exit.guardDecisions.completedToolResultFinalAnswerRecovery` | Unresolved | Not measured | Unresolved |
| `_applyNarratedTranscriptRepairToStreamedFinalAnswer` | `chat_notifier_unexecuted_action_recovery.dart` | notifier_member | 1 | silent non-fire can leave a recovery path unreachable | `turn_exit.transforms:narrated_transcript_repair` | Unresolved | Not measured | Unresolved |
| `_requestNarratedTranscriptRepairForCompletionClaim` | `chat_notifier_unexecuted_action_recovery.dart` | notifier_member | 1 | silent non-fire can leave a recovery path unreachable | `turn_exit.transforms:narrated_transcript_repair` | Unresolved | Not measured | Unresolved |

## Static unreachable proofs

### `_tryRepairAndDecodeMap`

- The only production occurrence of the private extension member is its
  declaration. There is no tear-off, callback registration, or other lexical
  selection root.
- `ProposalJsonExtractor.extractJsonMap` calls
  `ProposalParsingTextUtils.tryRepairAndDecodeMap` directly for direct, sliced,
  and trailing candidates. The user-visible repair behavior remains live
  without the wrapper.
- Commit `1140b25e` moved the call sites to `ProposalParsingTextUtils`; commit
  `e90f6643` later retained the delegate while decomposing the notifier.

### `_repairJsonCandidate`

- The only production occurrence of the private extension member is its
  declaration. `ProposalParsingTextUtils.tryRepairAndDecodeMap` calls the static
  `repairJsonCandidate` implementation directly.
- Production imports no `dart:mirrors`, and private extension members cannot be
  selected by string name. No unresolved invocation edge remains.

These proofs establish `currentStaticState: unreachable` for the two wrappers.
The matching-build measurement below supplies the required non-empty clean
corpus and contains no contradictory firing, so both wrappers are `dead`.

Reproduce the proof search with:

```bash
rg -n "_tryRepairAndDecodeMap|_repairJsonCandidate" lib
rg -n "ProposalParsingTextUtils\.(tryRepairAndDecodeMap|repairJsonCandidate)" lib test
rg -n "dart:mirrors|Function\.apply|Symbol\(" lib
git show 1140b25e^:lib/features/chat/presentation/providers/chat_notifier.dart
git show 1140b25e -- lib/features/chat
```

## Explicit exclusions

These matches are helpers whose owning guard or recovery entry represents the
decision. The analyser still requires every one of them to remain explicitly
excluded while the discovery rule continues to match it.

| Symbol | Source | Reason |
| --- | --- | --- |
| `_buildCodingCommandOutputGuardrailToolResult` | `chat_notifier.dart` | Construction or formatting helper; it does not select whether the guard or recovery path runs. |
| `_buildDuplicateFollowUpRecoveryPrompt` | `chat_notifier.dart` | Construction or formatting helper; it does not select whether the guard or recovery path runs. |
| `_buildDuplicateInspectionRecoveryPrompt` | `chat_notifier.dart` | Construction or formatting helper; it does not select whether the guard or recovery path runs. |
| `_buildSkippedBrowserActionRecoveryToolCall` | `chat_notifier.dart` | Construction or formatting helper; it does not select whether the guard or recovery path runs. |
| `_buildSkippedBrowserActionRepairPrompt` | `chat_notifier.dart` | Construction or formatting helper; it does not select whether the guard or recovery path runs. |
| `_buildSkippedSkillLoadRecoveryToolCall` | `chat_notifier.dart` | Construction or formatting helper; it does not select whether the guard or recovery path runs. |
| `_buildToolLoopExhaustionRecoveryPrompt` | `chat_notifier.dart` | Construction or formatting helper; it does not select whether the guard or recovery path runs. |
| `_buildToolLoopRecoveryToolResults` | `chat_notifier.dart` | Construction or formatting helper; it does not select whether the guard or recovery path runs. |
| `_logCodingCommandOutputGuardrailSummary` | `chat_notifier.dart` | Telemetry writer; it records a decision but does not select the guarded path. |
| `_codingContinuationRecoveryCode` | `chat_notifier_coding_continuation_recovery.dart` | Result-code formatter; the owning recovery policy represents the decision. |
| `_clearCommandDiagnosticRepairFocus` | `chat_notifier_goal_auto_continue.dart` | Lifecycle cleanup helper; it does not select the repair path. |
| `_commandDiagnosticRepairFocusFor` | `chat_notifier_goal_auto_continue.dart` | State lookup helper; the replay guard and replay action represent the selection. |
| `_pythonAttachmentRepairInput` | `chat_notifier_python_attachment_repair.dart` | Input adapter; the owning policy or recovery entry represents the decision. |
| `_planningJsonRepairFeedbackBinding` | `chat_notifier_tool_result_telemetry.dart` | Feedback binding helper; it does not select the JSON repair path. |
| `_turnFinalizationRecoveryInput` | `chat_notifier_turn_finalization_recovery.dart` | Input adapter; the owning policy or recovery entry represents the decision. |

## Phase 0A findings

- 65 decision candidates are represented and 15 helper matches are explicitly excluded (80 total discovery results).
- 13 candidates have a directly mapped structured firing event; the remaining 52 require Phase 0B telemetry review.
- 2 orphan delegates are statically unreachable and now classified `dead` by the matching-build measurement.
- The other 63 candidates remain statically unresolved; none is classified dead, live, or unexercised in this slice.

## Phase 0B telemetry selection

The checked-in `tool/chat_notifier_guard_telemetry_selection.json` retains all
52 entries that lacked a mapped structured event when Phase 0B began. The
analyser joins it to this guard inventory by stable ID and enforces a first-
slice limit of one:

- 0 `instrument`.
- 1 `covered`:
  `_shouldSkipCompletedToolResultFinalAnswerRecovery`.
- 51 `defer`, each with an explicit prerequisite.

The selected decision now reuses the existing `turn_exit` boundary and records
only `not_evaluated`, `skip_recovery`, or `allow_recovery`. The matching-build
corpus observed `allow_recovery` once. Because the candidate's static graph is
still unresolved, its action state remains unresolved.

## Matching-build measurement

The private corpus contains one schema-v2 session-log file with four records,
one complete schema-v1 catalogue snapshot with 169 definitions, one
configuration segment, and one normalized tool-result submission. Its logged
range is `2026-08-02T07:20:18.999154Z` through
`2026-08-02T07:20:34.700120Z`, inclusive. The represented build is clean
revision `55efb18f51e2739f195bca0d5bd7b1669d5c0f9d`.

| Artifact | SHA-256 |
| --- | --- |
| Private corpus manifest | `7b5ea1933c3e1189ee79251f5b0908eb9ed69fe79d8c4de50cf2ef7573a30035` |
| Private catalogue snapshot | `2f32d0b009ed737f9e18a645571c4531f0c10614f77d203800af0dbe63a2adf4` |
| Private deterministic measurement | `d5680bce8befb158a0dbef22022a4a58343301f5d2ee42e61e03f88ec84f4d9d` |

Two analyser runs produced byte-identical output. The result contains 2 `dead`,
0 `live`, 0 `unexercised`, and 63 `unresolved` candidates. Private paths,
session identifiers, prompts, dynamic tool names, arguments, and results remain
excluded from this report.

Validate the selection with:

```bash
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --guard-manifest tool/chat_notifier_guard_inventory.json \
  --check-telemetry-selection \
  tool/chat_notifier_guard_telemetry_selection.json
```

## Explicit unresolved items

- Resolve the remaining callers to production turn-loop roots rather than
  stopping at lexical references.
- Review callback, extension, module-registration, and runtime configuration
  edges for the remaining candidates.
- Select at most one second Phase 0B telemetry event only after closing its
  production-root and runtime-configuration prerequisites.
