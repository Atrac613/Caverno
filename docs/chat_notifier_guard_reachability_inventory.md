# ChatNotifier Guard Reachability Inventory

Status: Phase 0A static inventory complete; dynamic observations and action
classification remain pending the manifest-driven corpus analyser.

Classified source revision: `280bc383df102dab108f51a02c772fd81ad29d1d`. The checked-in manifest uses
`HEAD` as its symbolic revision so the post-commit clean-source check can resolve
the exact commit without embedding a self-referential commit hash.

## Scope and method

The finite discovery contract covers:

- top-level production types under `lib/features/chat/domain/services` whose
  names end in `Guard`, `Policy`, or `Recovery`;
- members in `chat_notifier*.dart` whose names contain `guard`, `recovery`, or
  `repair`.

Every discovery result is either an inventory entry or an explicit exclusion.
Phase 0A uses lexical references only. It does not claim that a reference is
reachable from a production turn root, and it does not use missing telemetry as
evidence of death. The unresolved callback and runtime-configuration edges are
recorded on every entry for the later static proof pass.

Reproduce the inventory check with:

```bash
python3 test/python/analyze_chat_notifier_inventory_test.py
python3 tool/analyze_chat_notifier_inventory.py \
  --source-revision HEAD \
  --check-guard-manifest tool/chat_notifier_guard_inventory.json
git diff --check
```

## Static inventory

`currentStaticState` and `actionState` remain `unresolved` until static call-edge
review and matching-build corpus analysis are both available. `observedByBuild`
is intentionally not measured in Phase 0A.

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
| `_repairJsonCandidate` | `chat_notifier_proposal_parsing.dart` | notifier_member | 0 | silent non-fire can leave a recovery path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `_tryRepairAndDecodeMap` | `chat_notifier_proposal_parsing.dart` | notifier_member | 0 | silent non-fire can leave a recovery path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `_requestPythonAttachmentPathFailureRepair` | `chat_notifier_python_attachment_repair.dart` | notifier_member | 1 | silent non-fire can leave a recovery path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `_requestSkippedPythonAttachmentAnalysisRepair` | `chat_notifier_python_attachment_repair.dart` | notifier_member | 1 | silent non-fire can leave a recovery path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `_buildTruncatedToolCallArgumentsGuardResult` | `chat_notifier_tool_loop_batch.dart` | notifier_member | 1 | selection may enable, block, or redirect turn behavior | `turn_exit.transforms:truncated_tool_call_arguments_feedback` | Unresolved | Not measured | Unresolved |
| `_prepareLastAssistantForTurnFinalizationRecovery` | `chat_notifier_turn_finalization_recovery.dart` | notifier_member | 1 | silent non-fire can leave a recovery path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `_shouldSkipCompletedToolResultCodingContinuationRecovery` | `chat_notifier_turn_finalization_recovery.dart` | notifier_member | 1 | silent non-fire can leave a guarded or corrective path unreachable | `turn_exit.transforms:coding_continuation_recovery_*` | Unresolved | Not measured | Unresolved |
| `_shouldSkipCompletedToolResultFinalAnswerRecovery` | `chat_notifier_turn_finalization_recovery.dart` | notifier_member | 2 | silent non-fire can leave a guarded or corrective path unreachable | Not mapped | Unresolved | Not measured | Unresolved |
| `_applyNarratedTranscriptRepairToStreamedFinalAnswer` | `chat_notifier_unexecuted_action_recovery.dart` | notifier_member | 1 | silent non-fire can leave a recovery path unreachable | `turn_exit.transforms:narrated_transcript_repair` | Unresolved | Not measured | Unresolved |
| `_requestNarratedTranscriptRepairForCompletionClaim` | `chat_notifier_unexecuted_action_recovery.dart` | notifier_member | 1 | silent non-fire can leave a recovery path unreachable | `turn_exit.transforms:narrated_transcript_repair` | Unresolved | Not measured | Unresolved |

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
- 2 entries have no non-declaration lexical selection reference. They are high-priority static-edge review candidates, not dead-code findings.
- No entry is classified dead, live, or unexercised in this slice.

## Explicit unresolved items

- Resolve callers to production turn-loop roots rather than stopping at lexical
  references.
- Review callback, extension, module-registration, and runtime configuration
  edges.
- Complete Phase 0B telemetry selection before changing logging.
- Run the private, hash-pinned matching-build corpus analysis before deriving
  action states.
