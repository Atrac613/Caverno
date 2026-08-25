import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:caverno_content_protocol/caverno_content_protocol.dart';
import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/services/agents_md_loader.dart';
import '../../../../core/services/ble_service.dart';
import '../../../../core/services/serial_port_service.dart';
import '../../../../core/services/browser_session_service.dart';
import '../../../../core/services/browser_tool_policy.dart';
import '../../../../core/services/macos_computer_use_audit_log.dart';
import '../../../../core/services/macos_computer_use_tool_policy.dart';
import '../../../../core/services/notification_providers.dart';
import '../../../../core/services/ssh_config.dart';
import '../../../../core/services/ssh_credentials_manager.dart';
import '../../../../core/services/ssh_service.dart';
import '../../../../core/services/tool_approval_audit_log.dart';
import 'chat_ssh_tool_runtime.dart';
import 'ssh_host_key_prompting_transport.dart';
import '../../../../core/services/voice_providers.dart';
import '../../../../core/types/assistant_mode.dart';
import '../../../../core/types/workspace_mode.dart';
import '../../../../core/utils/logger.dart';
import '../../data/repositories/chat_memory_repository.dart';
import '../../data/repositories/tool_result_artifact_store.dart';
import '../../application/runtime/turn_release_scope.dart';
import '../../application/runtime/turn_runtime.dart';
import '../../application/runtime/turn_runtime_owner_lease_registry.dart';
import '../../application/runtime/tool_outcome_shadow_observer.dart';
import '../../domain/services/printed_tool_call_recovery.dart';
import '../../domain/services/ask_user_question_turn_cache.dart';
import '../../domain/services/conversation_goal_suggestion_service.dart';
import '../../domain/services/conversation_plan_document_builder.dart';
import '../../domain/services/conversation_planning_prompt_service.dart';
import '../../domain/services/system_prompt_builder.dart';
import '../../domain/services/session_memory_service.dart';
import '../../domain/services/secondary_completion_router.dart';
import '../../domain/services/skill_prompt_index_builder.dart';
import '../../../routines/presentation/providers/routines_notifier.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/domain/services/llm_provider_capabilities.dart';
import '../../../settings/domain/services/llm_request_temperature_policy.dart';
import '../../../settings/domain/services/external_tool_hook_service.dart';
import '../../../settings/presentation/providers/local_model_lifecycle_provider.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/ask_user_question_runtime_adapter.dart';
import '../../../settings/presentation/providers/mesh_endpoint_provider.dart';
import '../../data/datasources/chat_datasource.dart';
import '../../data/datasources/chat_remote_datasource.dart';
import '../../data/datasources/create_routine_tool_runtime_adapter.dart';
import '../../data/datasources/mesh_secondary_completion_runner.dart';
import '../../data/datasources/participant_completion_runner.dart';
import '../../data/datasources/participant_tool_production_ports.dart';
import '../../data/datasources/demo_datasource.dart';
import '../../data/datasources/background_process_completion_monitor.dart';
import '../../data/datasources/background_process_monitor_service.dart';
import '../../data/datasources/execution_snapshot_log_runtime_adapter.dart';
import '../../data/datasources/file_rollback_checkpoint_store.dart';
import '../../data/datasources/file_mutation_tool_runtime_adapter.dart';
import '../../data/datasources/filesystem_tools.dart';
import '../../data/datasources/git_tools.dart';
import '../../data/datasources/local_shell_git_write_guard.dart';
import '../../data/datasources/local_shell_tools.dart';
import '../../data/datasources/lsp_go_to_definition_runtime_adapter.dart';
import '../../data/datasources/mcp_tool_service.dart';
import '../../data/datasources/project_scoped_tool_argument_resolver.dart';
import '../../data/datasources/project_read_tool_authorizer.dart';
import '../../data/datasources/turn_project_root.dart';
import '../../data/datasources/python_script_tool_runtime_adapter.dart';
import '../../data/datasources/save_skill_tool_runtime_adapter.dart';
import '../../data/datasources/llm_session_log_store.dart';
import '../../data/datasources/session_logging_chat_datasource.dart';
import 'chat_data_source_provider.dart';
import 'goal_update_notifier_runtime_coordinator.dart';
import 'python_script_approval_cache_runtime_adapter.dart';
import 'primary_turn_route_runtime.dart';

export 'chat_data_source_provider.dart'
    show chatDataSourceFactoryProvider, chatRemoteDataSourceProvider;
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/coding_project.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_compaction_artifact.dart';
import '../../domain/entities/conversation_goal.dart';
import '../../domain/entities/conversation_participant.dart';
import '../../domain/entities/model_usage_role.dart';
import '../../domain/entities/conversation_plan_artifact.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/skill.dart';
import '../../domain/entities/turn_diff.dart';
import '../../domain/entities/subagent_task.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../../domain/services/content_tool_continuation_prompt_builder.dart';
import '../../domain/services/content_tool_formatters.dart';
import '../../domain/services/turn_steering_policy.dart';
import '../../domain/services/turn_steering_prompt_builder.dart';
import '../../domain/services/context_surgery_observation_accumulator.dart';
import '../../domain/services/create_routine_tool_handler.dart';
import '../../domain/services/conversation_compaction_service.dart';
import '../../domain/services/conversation_goal_auto_continue_policy.dart';
import '../../domain/services/duplicate_tool_result_recovery.dart';
import '../../domain/services/fenced_tool_name_blocks.dart';
import '../../domain/services/goal_auto_continue_prompt_builder.dart';
import '../../domain/services/goal_auto_continue_tracker_registry.dart';
import '../../domain/services/goal_continuation_log_record_builder.dart';
import '../../domain/services/tool_approval_auto_review_service.dart';
import '../../../../core/security/conversation_taint_state.dart';
import '../../domain/services/tool_call_execution_policy.dart';
import '../../domain/services/sticky_tool_result_policy.dart';
import '../../domain/services/tool_loop_context_digest.dart';
import '../../domain/services/out_of_root_command_paths.dart';
import '../../domain/services/outside_root_read_grants.dart';
import '../../domain/services/assistant_stream_delta.dart';
import '../../domain/services/tool_loop_exit_reason.dart';
import '../../domain/services/truncated_tool_call_arguments_guard.dart';
import 'tool_argument_json.dart';
import 'turn_final_message.dart';
import '../../domain/services/chat_command_guardrail_collaborators.dart';
import '../../domain/services/context_surgery_protected_path_policy.dart';
import '../../domain/services/goal_validation_probe_guard.dart';
import '../../domain/services/git_write_confirmation_policy.dart';
import '../../domain/services/material_contract_assumption_guard.dart';
import '../../domain/services/model_switch_handoff_registry.dart';
import '../../domain/services/model_switch_settings_policy.dart';
import '../../domain/services/saved_task_target_scope_guard.dart';
import '../../domain/services/saved_validation_command_guard.dart';
import '../../domain/services/timed_out_command_retry_guard.dart';
import '../../domain/services/uninspected_commit_guard.dart';
import '../../domain/services/tool_loop_exhaustion_policy.dart';
import '../../domain/services/unexecuted_file_mutation_before_command_guard.dart';
import '../../domain/services/coding_diagnostic_feedback_service.dart';
import '../../domain/services/coding_verification_feedback_presentation.dart';
import '../../domain/services/coding_verification_feedback_service.dart';
import '../../domain/services/command_diagnostic_verifier_replay_guard.dart';
import '../../domain/services/chat_tool_dispatcher.dart';
import '../../domain/services/turn_finalization_recovery_policy.dart';
import '../../domain/services/conversation_plan_execution_coordinator.dart';
import '../../domain/services/verification_cadence_policy.dart';
import '../../domain/services/execution_budget_policy.dart';
import '../../domain/services/referenced_specification_loader.dart';
import '../../domain/services/short_prompt_contract_builder.dart';
import '../../domain/services/dart_project_tooling.dart';
import '../../domain/services/lsp_diagnostic_feedback_provider.dart';
import '../../domain/services/final_answer_claim_detector.dart';
import '../../domain/services/final_answer_claim_notice_applicator.dart';
import '../../domain/services/final_answer_message_notice_service.dart';
import '../../domain/services/final_answer_recovery_policy.dart';
import '../../domain/services/duplicate_recovery_prompt_builder.dart';
import '../../domain/services/file_mutation_evidence_policy.dart';
import '../../domain/services/file_mutation_tool_handler.dart';
import '../../domain/services/file_turn_rollback_service.dart';
import '../../application/runtime/goal_completion_boundary_coordinator.dart';
import '../../domain/services/coding_continuation_recovery_policy.dart';
import '../../domain/services/coding_verification_mutation_signature.dart';
import '../../domain/services/pending_action_length_recovery_policy.dart';
import '../../domain/services/process_start_result_policy.dart';
import '../../domain/services/python_attachment_repair_policy.dart';
import '../../domain/services/request_tool_observation_collector.dart';
import '../../domain/services/runtime_sampler_feedback_recorder.dart';
import '../../domain/services/successful_read_result_replay_cache.dart';
import '../../domain/services/memory_extraction_coordinator.dart';
import '../../domain/services/narrated_transcript_repair_planner.dart';
import '../../domain/services/participant_message_finalizer.dart';
import '../../domain/services/participant_turn_planner.dart';
import '../../domain/services/secondary_call_budget.dart';
import '../../domain/services/planning_research_collector.dart';
import '../../domain/services/cjk_response_markers.dart';
import '../../domain/services/code_unit_text_scan.dart';
import '../../domain/services/planning_retry_context_builder.dart';
import '../../domain/services/skipped_skill_load_text.dart';
import '../../domain/services/ble_connect_attempt_coordinator.dart';
import '../../domain/services/blocked_production_release_retry_policy.dart';
import '../../domain/services/fenced_tool_arguments_detector.dart';
import '../../domain/services/turn_tool_catalog_cache.dart';
import '../../domain/services/turn_tool_catalog_source.dart';
import '../../domain/services/unexecuted_command_action_retry_policy.dart';
import '../../domain/services/production_release_approval_coordinator.dart';
import '../../domain/services/proposal_option_extraction.dart';
import '../../domain/services/background_process_follow_up_policy.dart';
import '../../domain/services/proposal_parsing_text_utils.dart';
import '../../domain/services/task_proposal_parser.dart';
import '../../domain/services/workflow_proposal_parser.dart';
import '../../domain/services/planning_executor_profile.dart';
import '../../domain/services/planning_tool_policy.dart';
import '../../domain/services/temporal_context_builder.dart';
import '../../domain/services/tool_definition_search_service.dart';
import '../../domain/services/tool_execution_scheduler.dart';
import '../../domain/services/tool_failure_classifier.dart';
import '../../domain/services/tool_loop_abort_notice.dart';
import '../../domain/services/tool_loop_recovery_policy.dart';
import '../../domain/services/tool_result_prompt_builder.dart';
import '../../domain/services/tool_result_taint_recorder.dart';
import '../../domain/services/tool_terminal_response_policy.dart';
import '../../domain/services/tool_terminal_success_policy.dart';
import '../../domain/services/turn_diff_service.dart';
import '../../domain/services/unexecuted_final_answer_tool_request_policy.dart';
import '../../domain/services/subagent_execution_service.dart';
import '../../domain/services/subagent_tool_policy.dart';
import '../../domain/services/stalled_diagnostic_repair_contract.dart';
import '../../domain/services/workflow_task_proposal_quality_service.dart';
import '../../../settings/domain/services/local_command_permission_service.dart';
import 'active_response_registry.dart';
import 'chat_error_message_builder.dart';
import 'chat_state.dart';
import 'hidden_prompt_launch_options.dart';
import 'chat_tool_execution_log_formatter.dart';
import 'coding_projects_notifier.dart';
import 'content_tool_turn_state_registry.dart';
import 'conversations_notifier_goal_runtime_store.dart';
import 'caverno_execution_runtime_provider.dart';
import 'conversations_notifier.dart';
import 'html_preview_provider.dart';
import 'create_routine_notifier_runtime_store.dart';
import 'hidden_assistant_evidence_registry.dart';
import 'file_mutation_approval_cache_runtime_adapter.dart';
import 'macos_computer_use_approval_copy.dart';
import 'mcp_tool_provider.dart';
import 'model_edit_apply_telemetry_runtime_adapter.dart';
import 'participant_turn_control_registry.dart';
import 'repo_map_precompute_cache_provider.dart';
import 'response_metadata_registry.dart';
import 'runtime_turn_event_publisher.dart';
import 'runtime_turn_evidence_publisher.dart';
import 'skills_notifier.dart';
import 'save_skill_notifier_runtime_store.dart';
import 'thread_scoped_chat_state.dart';
import 'thread_scoped_message_queue.dart';
import 'tool_approval_cache.dart';
import 'tool_dedupe_keys.dart';
import 'tool_loop_batch_execution_result.dart';
import 'turn_coding_project_resolver.dart';
import 'turn_context_retry_coordinator.dart';
import 'turn_runtime_goal_safe_boundary_adapter.dart';
import 'turn_runtime_production_composition.dart';
import 'turn_message_persistence_coordinator.dart';
import 'turn_finalization_state_registry.dart';
import 'turn_goal_completion_evidence_registry.dart';
import 'turn_thread_scope.dart';
import 'turn_tool_result_ledger.dart';
import 'turn_owner_snapshot_registry.dart';
import 'turn_steering_registry.dart';
import 'turn_stream_binding_registry.dart';
import 'subagent_task_notifier.dart';

part 'chat_notifier_approval_handlers.dart';
part 'chat_notifier_ask_user_question.dart';
part 'chat_notifier_ble_handlers.dart';
part 'chat_notifier_browser_handlers.dart';
part 'chat_notifier_cancellation.dart';
part 'chat_notifier_coding_continuation_recovery.dart';
part 'chat_notifier_computer_use_handlers.dart';
part 'chat_notifier_context_surgery.dart';
part 'chat_notifier_error_handling.dart';
part 'chat_notifier_execution_runtime.dart';
part 'chat_notifier_final_answer_recovery.dart';
part 'chat_notifier_git_handlers.dart';
part 'chat_notifier_local_file_handlers.dart';
part 'chat_notifier_participant_turns.dart';
part 'chat_notifier_serial_handlers.dart';
part 'chat_notifier_ssh_handlers.dart';
part 'chat_notifier_subagent_handlers.dart';
part 'chat_notifier_python_attachment_repair.dart';
part 'chat_notifier_unexecuted_action_recovery.dart';
part 'chat_notifier_coding_verification_feedback.dart';
part 'chat_notifier_planning_research.dart';
part 'chat_notifier_workflow_proposal_parser.dart';
part 'chat_notifier_prompt_context.dart';
part 'chat_notifier_tool_result_telemetry.dart';
part 'chat_notifier_tool_handler_registry.dart';
part 'chat_notifier_turn_rollback_handlers.dart';
part 'chat_notifier_turn_finalization_recovery.dart';
part 'chat_notifier_turn_exit.dart';
part 'chat_notifier_response_finalization.dart';
part 'chat_notifier_goal_auto_continue.dart';
part 'chat_notifier_task_proposal_quality.dart';
part 'chat_notifier_terminal_tool_response_policy.dart';
part 'chat_notifier_tool_loop_batch.dart';
part 'chat_notifier_task_proposal_parser.dart';

final sessionMemoryServiceProvider = Provider<SessionMemoryService>((ref) {
  final repository = ref.watch(chatMemoryRepositoryProvider);
  return SessionMemoryService(repository);
});

final lspJsonRpcSessionRegistryProvider = Provider<LspJsonRpcSessionRegistry>((
  ref,
) {
  final registry = LspJsonRpcSessionRegistry();
  ref.onDispose(() {
    unawaited(registry.close());
  });
  return registry;
});

final codingDiagnosticFeedbackServiceProvider =
    Provider<CodingDiagnosticFeedbackService>((ref) {
      final lspRegistry = ref.watch(lspJsonRpcSessionRegistryProvider);
      return CodingDiagnosticFeedbackService(
        provider: LanguageDiagnosticsBridgeFallbackProvider(
          primary: LspDiagnosticFeedbackProvider(
            client: lspRegistry,
            readinessProbe: lspRegistry,
          ),
          fallback: DartAnalyzerDiagnosticFeedbackProvider(),
        ),
      );
    });

final codingVerificationFeedbackServiceProvider =
    Provider<CodingVerificationFeedbackService>((ref) {
      final settings = ref.watch(settingsNotifierProvider);
      return CodingVerificationFeedbackService(
        timeout: Duration(
          seconds: settings.effectiveCodingVerificationTimeoutSeconds,
        ),
        maxFailures: settings.effectiveCodingVerificationMaxFailures,
      );
    });

final chatNotifierProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);

final class _WorkflowProposalCancelled implements Exception {
  const _WorkflowProposalCancelled();

  @override
  String toString() => 'workflow proposal generation was cancelled';
}

class ChatNotifier extends Notifier<ChatState> {
  late CavernoExecutionRuntime _executionRuntime;
  late ChatDataSource _dataSource;
  late MeshSecondaryCompletionRunner<ChatDataSource> _meshRunner;
  late ParticipantCompletionRunner _participantCompletionRunner;
  McpToolService? _mcpToolService;
  late SessionMemoryService _memoryService;
  late AppSettings _settings;
  bool _hasLoadedSettings = false;
  late CodingDiagnosticFeedbackService _codingDiagnosticFeedbackService;
  late CodingVerificationFeedbackService _codingVerificationFeedbackService;
  late BackgroundProcessMonitorService _backgroundProcessMonitorService;
  late SshService _sshService;
  final _toolLoopRecoveryPolicy = const ToolLoopRecoveryPolicy();
  final _toolCallExecutionPolicy = const ToolCallExecutionPolicy();
  final _claims = const FinalAnswerClaimDetector();
  final _claimNotices = const FinalAnswerClaimNoticeApplicator();
  final _messageNotices = const FinalAnswerMessageNoticeService();
  final _memoryExtraction = const MemoryExtractionCoordinator();
  final _finalAnswerRecoveryPolicy = const FinalAnswerRecoveryPolicy();
  final _fileMutationEvidencePolicy = const FileMutationEvidencePolicy();
  final _pendingActions = const PendingActionLengthRecoveryPolicy();
  final _transcriptRepairs = const NarratedTranscriptRepairPlanner();
  final _blockedReleaseRetries = const BlockedProductionReleaseRetryPolicy();
  late final _productionReleaseApprovals = ProductionReleaseApprovalCoordinator(
    activeConversationId: _activeResponseConversationIdForGeneration,
    ownerForGeneration: _turnOwnerForGeneration,
    questionResults: _askUserQuestionTurnCache,
  );
  final _unexecutedCommandRetries = const UnexecutedCommandActionRetryPolicy();

  final _outsideRootReadGrants = OutsideRootReadGrants();
  final _unexecutedCommandRetryOwners = <String>{};
  final _blockedReleaseRetrySignatures = <String>{};
  final _planningToolPolicy = const PlanningToolPolicy();
  final _toolLoopContextDigest = const ToolLoopContextDigest();
  final _runtimeTurns = <int, CavernoRuntimeTurnHandle>{};
  final _turnReleases = <ChatTurnOwner, TurnReleaseScope>{};
  (List<String>, List<String>)? _lastTurnRelease;
  late final _runtimeEvents = RuntimeTurnEventPublisher(_runtimeTurns);
  final _runtimeFailureClassifier = const CavernoRuntimeFailureClassifier();
  late final _pythonScriptRuntime = _buildPythonScriptRuntimeAdapter();
  late final _fileMutationRuntime = _buildFileMutationRuntimeAdapter();
  late final _askUserQuestionRuntime = _buildAskUserQuestionRuntime();
  final _conversationTaintState = ConversationTaintState();
  final _turnRuntimeOwnerLease = TurnRuntimeOwnerLeaseRegistry();
  final _goalContinuationLifecycle = TurnRuntimeGoalContinuationLifecycle();
  late final TurnRuntimeProductionComposition _turnRuntimeComposition;
  late final _turnRuntimeGoalSafeBoundary = TurnRuntimeGoalSafeBoundaryAdapter(
    ownerLease: _turnRuntimeOwnerLease,
    queuedMessages: _queuedChatMessages,
    threadStates: _threadStates,
    pendingQuestions: _pendingAskUserQuestionsByThread,
  );
  String? _conversationId, _activeTurnUserPrompt;
  String? get conversationId => _conversationId;
  set conversationId(String? value) {
    _conversationId = value;
    _turnRuntimeOwnerLease.updateVisibleConversation(value);
  }

  String _languageCode = 'en';
  String? _sessionMemoryContext, _temporalReferenceContext;
  Message? _hiddenPrompt;
  bool _isVoiceMode = false;
  AssistantMode? _assistantModeOverride;
  final _contextSurgeryObservations = ContextSurgeryObservationAccumulator();
  final _modelSwitchHandoffs = ModelSwitchHandoffRegistry(clock: DateTime.now);
  // Parsing helpers may run before build, so telemetry starts null.
  ModelEditApplyTelemetryRuntimeAdapter? _modelEditTelemetry;
  final _turnToolResults = TurnToolResultLedger();
  final _contentToolTurns = ContentToolTurnStateRegistry();
  final _hiddenAssistantEvidence = HiddenAssistantEvidenceRegistry();
  final _turnEnd = TurnFinalizationStateRegistry();
  final _pendingTurnDiffFiles = <TurnDiffFile>[];
  late ToolResultArtifactStore _toolResultArtifactStore;
  DateTime? _activeTurnStartedAt;
  double get _agenticRequestTemperature =>
      LlmRequestTemperaturePolicy.forSettings(_settings).agenticTemperature;
  static const int _maxRepeatedCodingVerificationRepairAttempts = 2;
  static const int _maxNarratedTranscriptRepairAttempts = 2;
  @override
  ChatState build() {
    _executionRuntime = ref.read(cavernoExecutionRuntimeProvider);
    _settings = ref.read(settingsNotifierProvider);
    _modelEditTelemetry = ModelEditApplyTelemetryRuntimeAdapter(
      ref.read(settingsNotifierProvider.notifier),
    );
    _hasLoadedSettings = true;
    _dataSource = _withChatSessionLogging(
      ref.read(chatRemoteDataSourceProvider),
      _settings,
    );
    _meshRunner = MeshSecondaryCompletionRunner<ChatDataSource>(
      router: ref.read(meshEndpointRouterProvider),
      health: ref.read(endpointHealthTrackerProvider),
      buildEndpointDataSource: (baseUrl, apiKey) => _withChatSessionLogging(
        ChatRemoteDataSource(
          baseUrl: baseUrl,
          apiKey: apiKey,
          reasoningEffort: _settings.reasoningEffort.apiValue,
        ),
        _settings,
      ),
    );
    _participantCompletionRunner = ParticipantCompletionRunner(
      meshRunner: _meshRunner,
    );
    _mcpToolService = ref.read(mcpToolServiceProvider);
    _memoryService = ref.read(sessionMemoryServiceProvider);
    _toolResultArtifactStore = ref.read(toolResultArtifactStoreProvider);
    _codingDiagnosticFeedbackService = ref.read(
      codingDiagnosticFeedbackServiceProvider,
    );
    _codingVerificationFeedbackService = ref.read(
      codingVerificationFeedbackServiceProvider,
    );
    _backgroundProcessMonitorService = ref.read(
      backgroundProcessMonitorServiceProvider,
    );
    _sshService = ref.read(sshServiceProvider);
    _mcpToolService?.connect();
    final conversationsState = ref.read(conversationsNotifierProvider);
    final initialMessages =
        conversationsState.currentConversation?.messages ?? const <Message>[];
    conversationId = conversationsState.currentConversation?.id;
    _turnRuntimeOwnerLease.mount(
      visibleConversationId: conversationId,
      selectedConversationId: conversationsState.currentConversation?.id,
    );
    _turnRuntimeComposition = _buildTurnRuntimeComposition(
      ref.read(conversationsNotifierProvider.notifier),
    );
    ref.listen<AppSettings>(settingsNotifierProvider, (previous, next) {
      _updateConnectionSettings(next);
    });

    ref.listen<McpToolService?>(mcpToolServiceProvider, (previous, next) {
      updateMcpToolService(next);
    });

    ref.listen<CodingVerificationFeedbackService>(
      codingVerificationFeedbackServiceProvider,
      (previous, next) {
        _codingVerificationFeedbackService = next;
      },
    );

    ref.listen<BackgroundProcessMonitorService>(
      backgroundProcessMonitorServiceProvider,
      (previous, next) {
        _backgroundProcessMonitorService = next;
      },
    );

    ref.listen<ConversationsState>(conversationsNotifierProvider, (
      previous,
      next,
    ) {
      syncConversation(
        conversationId: next.currentConversation?.id,
        messages: next.currentConversation?.messages ?? const [],
      );
      final nextProjectId = next.activeProjectId;
      if (nextProjectId != null && nextProjectId != previous?.activeProjectId) {
        unawaited(_prewarmProjectAccess(nextProjectId));
      }
    });

    // Warm bookmark access for the initially-active project so the very first
    // system-prompt build (and AGENTS.md read) does not race the bookmark
    // restore.
    final initialProjectId = conversationsState.activeProjectId;
    if (initialProjectId != null) {
      unawaited(_prewarmProjectAccess(initialProjectId));
    }

    ref.onDispose(() {
      _turnRuntimeOwnerLease.retire();
      _turnStream.cancelAll();
      _cancelAllPendingToolApprovals();
      _failAllRuntimeTurns(
        code: 'notifier_disposed',
        message: 'The chat notifier was disposed before the turn completed.',
        exitCode: 130,
        recordExit: false,
      );
      _contentToolTurns.clear();
      _hiddenAssistantEvidence.clear();
      _turnEnd.clear();
      _goalCompletionEvidence.clear();
      _toolApprovalCache.clearAll();
      _queuedChatMessages.clear();
      _turnToolResults.clear();
      _contextSurgeryObservations.clear();
      _modelEditTelemetry?.clear();
      _disposeAllParticipantTurnControls();
      _conversationTaintState.dispose();
    });

    return initialMessages.isEmpty
        ? ChatState.initial()
        : ChatState.initial().copyWith(messages: initialMessages);
  }

  void _persistCurrentNonStreamingMessages() {
    final messagesToSave = state.messages
        .where((message) => !message.isStreaming)
        .where(_messagePersistence.shouldKeepVisibleMessage)
        .toList(growable: false);
    unawaited(_messagePersistence.persistCurrentMessages(messagesToSave));
  }

  Future<void> _persistActiveResponseCheckpoint(int generation) async {
    final owner = _turnOwnerForGeneration(generation);
    final messages = _activeResponseMessagesForGeneration(generation);
    if (owner == null || messages == null || messages.isEmpty) return;

    final checkpoint = messages
        .map((message) {
          if (!message.isStreaming) return message;
          var content = message.content;
          if (content.endsWith('<think>')) {
            content = content.substring(0, content.length - '<think>'.length);
          } else {
            final parsed = ContentParser.parse(content);
            if (parsed.hasIncompleteTag &&
                parsed.incompleteTagType == 'thinking') {
              content = '$content</think>';
            }
          }
          return message.copyWith(content: content, isStreaming: false);
        })
        .where(_messagePersistence.shouldKeepVisibleMessage)
        .toList(growable: false);
    if (checkpoint.isEmpty) return;
    await _messagePersistence.persistMessages(owner.conversationId, checkpoint);
  }

  void _onAutoRead(String content) {
    final result = ContentParser.parse(content);
    final buffer = StringBuffer();
    for (final segment in result.segments) {
      if (segment.type == ContentType.text) {
        buffer.write(segment.content);
      }
    }
    final readableText = buffer.toString().trim();
    if (readableText.isEmpty) return;

    final ttsService = ref.read(ttsServiceProvider);
    ttsService.setSpeechRate(_settings.speechRate);
    ttsService.speak(readableText);
  }

  void _onSendStarted() {
    ref.read(backgroundTaskServiceProvider).beginBackgroundTask();
  }

  void _onResponseCompleted(String content) {
    ref.read(backgroundTaskServiceProvider).endBackgroundTask();

    if (content.isEmpty) return;
    final lifecycleService = ref.read(appLifecycleServiceProvider);
    if (!lifecycleService.isInBackground) return;

    final parsed = ContentParser.parse(content);
    final buffer = StringBuffer();
    for (final segment in parsed.segments) {
      if (segment.type == ContentType.text) {
        buffer.write(segment.content);
      }
    }
    final plainText = buffer.toString().trim();
    if (plainText.isEmpty) return;

    final firstNewline = plainText.indexOf('\n');
    final String title;
    final String body;
    if (firstNewline > 0 && firstNewline <= 80) {
      title = plainText.substring(0, firstNewline).trim();
      body = plainText.substring(firstNewline + 1).trim();
    } else {
      title = 'Caverno';
      body = plainText;
    }

    ref
        .read(notificationServiceProvider)
        .showResponseCompleteNotification(title, body);
  }

  LlmSessionLogContext _buildLlmSessionLogContext({
    String? targetConversationId,
  }) {
    final currentConversation = targetConversationId == null
        ? ref.read(conversationsNotifierProvider).currentConversation
        : _conversationForId(targetConversationId);
    return TurnOwnerSnapshot.buildSessionLogContext(
      conversation: currentConversation,
      targetConversationId: targetConversationId,
      fallbackConversationId: conversationId,
      configuredAssistantMode: _settings.assistantMode,
      hasHiddenPrompt: _hiddenPrompt != null,
      isRemoteInteraction: _isRemoteInteraction,
    );
  }

  Conversation? _conversationForId(String conversationId) => ref
      .read(conversationsNotifierProvider)
      .conversations
      .where((conversation) => conversation.id == conversationId)
      .firstOrNull;

  LlmSessionLogContext? _currentLlmSessionLogContext() =>
      _buildLlmSessionLogContext();

  LlmSessionLogContext _llmSessionLogContextForGeneration(int generation) =>
      _turnOwnerSnapshotForGeneration(generation)?.sessionLogContext ??
      const LlmSessionLogContext(
        workspaceMode: WorkspaceMode.chat,
        sessionId: 'unassigned',
        conversationId: 'unassigned',
        phase: 'unassigned_turn',
      );

  /// Main-loop requests bill to [ModelUsageRole.chat]; secondary roles started
  /// from inside a turn re-stamp themselves in [SecondaryCompletionRouter],
  /// which nests inside this zone and therefore wins.
  T _runWithLlmSessionLogContextForGeneration<T>(
    int generation,
    T Function() body, {
    String? requestLabel,
    ModelUsageRole usageRole = ModelUsageRole.chat,
  }) => usageRole.runWith(
    () => LlmSessionLogContext.run(
      _llmSessionLogContextForGeneration(
        generation,
      ).withRequestLabel(requestLabel),
      body,
    ),
  );

  ChatDataSource _withChatSessionLogging(
    ChatDataSource dataSource,
    AppSettings settings,
  ) {
    final loggingEnabled = LlmSessionLogStore.isEnabled(
      settingsEnabled: settings.enableLlmSessionLogs,
    );
    if (!loggingEnabled ||
        settings.demoMode ||
        dataSource is DemoDataSource ||
        dataSource is! ChatRemoteDataSource) {
      return dataSource;
    }
    return SessionLoggingChatDataSource(
      delegate: dataSource,
      logStore: ref.read(llmSessionLogStoreProvider),
      contextProvider: _currentLlmSessionLogContext,
    );
  }

  void updateMcpToolService(McpToolService? mcpToolService) {
    if (identical(_mcpToolService, mcpToolService)) return;
    _mcpToolService = mcpToolService;
    _mcpToolService?.connect();
  }

  void syncConversation({
    required String? conversationId,
    required List<Message> messages,
  }) {
    _turnRuntimeOwnerLease.updateSelectedConversation(conversationId);
    final sameConversation = this.conversationId == conversationId;
    final sameMessages = listEquals(state.messages, messages);
    if (sameConversation && sameMessages) {
      return;
    }

    if (sameConversation && state.isLoading) {
      return;
    }

    final preservingActiveResponse = !sameConversation && _hasActiveResponse;
    final visibleActiveGeneration = _activeResponseGenerationForConversation(
      this.conversationId,
    );
    if (!sameConversation &&
        state.isLoading &&
        visibleActiveGeneration != null) {
      _cacheActiveResponseMessagesForGeneration(
        visibleActiveGeneration,
        state.messages,
      );
    }

    if (!sameConversation && !preservingActiveResponse) {
      _beginInteractionGeneration();
      _clearAllActiveResponses(preservePausedParticipantTurn: true);
    }

    if (!preservingActiveResponse) {
      _turnStream.cancelAll();
      _clearTurnDiffCapture();
      _sessionMemoryContext = null;
      _temporalReferenceContext = null;
    }

    final restoredActiveGeneration = _activeResponseGenerationForConversation(
      conversationId,
    );
    final restoredActiveMessages = restoredActiveGeneration == null
        ? null
        : _activeResponseMessagesForGeneration(restoredActiveGeneration);
    // Restore an active snapshot only until its finalized save ends loading.
    final shouldRestoreActiveResponse =
        restoredActiveMessages != null &&
        (!sameConversation || state.isLoading);
    final restoredPendingQuestion = conversationId == null
        ? null
        : _pendingAskUserQuestionsByThread[conversationId];
    final restoredMessages = shouldRestoreActiveResponse
        ? restoredActiveMessages
        : messages;
    final restoredLoading = shouldRestoreActiveResponse;

    ThreadScopedChatState.remember(_threadStates, this.conversationId, state);
    this.conversationId = conversationId;
    state = ThreadScopedChatState.take(_threadStates, conversationId).applyTo(
      approvalThreads: ThreadScopedChatState.awaitingApproval(_threadStates),
      ChatState(
        messages: restoredMessages,
        queuedMessages: _queuedChatMessages.forThread(conversationId),
        steeringMessages: [
          for (final entry in _turnSteering.pendingForConversation(
            conversationId ?? '',
          ))
            entry.message,
        ],
        isLoading: restoredLoading,
        busyConversationIds: _activeResponseRegistry.activeConversationIds,
        error: null,
        pendingAskUserQuestion: restoredPendingQuestion,
      ),
    );
    _refreshContextTokenPressureFromState();
    if (conversationId != null) {
      unawaited(_drainQueuedChatMessagesForThreadIfIdle(conversationId));
    }
  }

  void _beginTurnDiffCapture(String userPrompt) {
    _pendingTurnDiffFiles.clear();
    _activeTurnUserPrompt = userPrompt;
    _activeTurnStartedAt = DateTime.now();
  }

  void _clearTurnDiffCapture() {
    _pendingTurnDiffFiles.clear();
    _activeTurnUserPrompt = null;
    _activeTurnStartedAt = null;
  }

  Future<void> _persistPendingTurnDiffForAssistant(
    String assistantMessageId,
  ) async {
    final userPrompt = _activeTurnUserPrompt;
    if (userPrompt == null || _pendingTurnDiffFiles.isEmpty) {
      _clearTurnDiffCapture();
      return;
    }

    final turnDiff = TurnDiffService.buildTurnDiff(
      assistantMessageId: assistantMessageId,
      userPrompt: userPrompt,
      files: _pendingTurnDiffFiles,
      source: TurnDiffSource.tool,
      timestamp: _activeTurnStartedAt,
    );
    _clearTurnDiffCapture();
    if (!turnDiff.hasChanges) {
      return;
    }

    await ref
        .read(conversationsNotifierProvider.notifier)
        .recordCurrentTurnDiff(turnDiff);
    ref.read(htmlPreviewWorkspaceEpochProvider.notifier).bump();
  }

  String? _buildSkillsPromptContext(List<String> toolNames) {
    if (!toolNames.contains('load_skill') ||
        _settings.disabledBuiltInToolsSet.contains('load_skill')) {
      return null;
    }
    try {
      final skills = ref.read(skillsNotifierProvider).enabledSkills;
      return SkillPromptIndexBuilder.build(skills);
    } catch (_) {
      return null;
    }
  }

  ToolCallInfo? _buildSkippedSkillLoadRecoveryToolCall({
    required ChatCompletionResult result,
    required String streamedAssistantContent,
    required List<Map<String, dynamic>> allTools,
    required int interactionGeneration,
  }) {
    if (result.hasToolCalls ||
        _settings.disabledBuiltInToolsSet.contains('load_skill') ||
        !ToolDefinitionSearchService.toolNamesFromDefinitions(
          allTools,
        ).contains('load_skill')) {
      return null;
    }

    final latestUserContent = _latestUserContentForGeneration(
      interactionGeneration,
    );
    if (!SkippedSkillLoadText.mentionsSkill(latestUserContent)) {
      return null;
    }

    final skill = _findEnabledSkillNamedInText(latestUserContent);
    if (skill == null) {
      return null;
    }

    final responseContent =
        (streamedAssistantContent.isNotEmpty
                ? streamedAssistantContent
                : result.content)
            .trim();
    if (responseContent.isNotEmpty &&
        !SkippedSkillLoadText.looksLikeSkippedLoad(responseContent)) {
      return null;
    }

    return ToolCallInfo(
      id: 'recovered_load_skill_${DateTime.now().microsecondsSinceEpoch}',
      name: 'load_skill',
      arguments: {'id': skill.id, 'name': skill.normalizedName},
    );
  }

  ToolCallInfo? _buildSkippedBrowserActionRecoveryToolCall({
    required ChatCompletionResult result,
    required List<Map<String, dynamic>> allTools,
    required int interactionGeneration,
  }) {
    if (result.hasToolCalls ||
        _settings.disabledBuiltInToolsSet.contains('browser_snapshot')) {
      return null;
    }

    final availableToolNames =
        ToolDefinitionSearchService.toolNamesFromDefinitions(allTools).toSet();
    if (!availableToolNames.contains('browser_snapshot')) {
      return null;
    }

    final latestUserContent = _latestUserContentForGeneration(
      interactionGeneration,
    );
    if (!_claims.looksLikeBrowserActionRequest(latestUserContent)) {
      return null;
    }

    return ToolCallInfo(
      id: 'recovered_browser_snapshot_${DateTime.now().microsecondsSinceEpoch}',
      name: 'browser_snapshot',
      arguments: const {'max_elements': 80},
    );
  }

  Future<ChatCompletionResult?>
  _requestSkippedBrowserActionRepairAfterSnapshot({
    required String candidateResponse,
    required List<ToolResultInfo> batchToolResults,
    required List<Map<String, dynamic>> tools,
    required int interactionGeneration,
  }) async {
    if (!_shouldRepairSkippedBrowserActionAfterSnapshot(
      candidateResponse: candidateResponse,
      batchToolResults: batchToolResults,
      interactionGeneration: interactionGeneration,
    )) {
      return null;
    }

    appLog('[Tool] Requesting browser action repair after recovered snapshot');
    List<Message> buildRepairMessages(bool forceCompaction) {
      final messages = _prepareMessagesForLLM(
        forceCompaction: forceCompaction,
        toolDefinitionsOverride: tools,
        interactionGeneration: interactionGeneration,
      );
      messages.add(
        Message(
          id: 'browser_action_repair_${DateTime.now().millisecondsSinceEpoch}',
          role: MessageRole.user,
          content: _buildSkippedBrowserActionRepairPrompt(
            interactionGeneration,
          ),
          timestamp: DateTime.now(),
        ),
      );
      return messages;
    }

    return _createToolResultCompletionWithContextRetry(
      logLabel: 'browser-action repair',
      interactionGeneration: interactionGeneration,
      buildMessages: buildRepairMessages,
      toolResults: batchToolResults,
      assistantContent: candidateResponse.isNotEmpty ? candidateResponse : null,
      tools: tools,
    );
  }

  bool _shouldRepairSkippedBrowserActionAfterSnapshot({
    required String candidateResponse,
    required List<ToolResultInfo> batchToolResults,
    required int interactionGeneration,
  }) {
    if (candidateResponse.trim().isEmpty) {
      return false;
    }
    if (!_claims.hasRecoveredBrowserSnapshot(batchToolResults)) {
      return false;
    }
    final latestUserContent = _latestUserContentForGeneration(
      interactionGeneration,
    );
    return _claims.looksLikeBrowserActionRequest(latestUserContent);
  }

  String _buildSkippedBrowserActionRepairPrompt(int interactionGeneration) {
    final latestUserContent = _latestUserContentForGeneration(
      interactionGeneration,
    );
    final missingToolName = _claims.browserActionToolNameForText(
      latestUserContent,
    );
    return [
      'The latest user request still requires a browser action.',
      'The application only executed a recovered browser_snapshot so far.',
      'Do not claim the browser action is complete in prose.',
      'If the snapshot contains a safe target, call $missingToolName now using the latest snapshot ref or selector.',
      'If no safe target exists, answer briefly that $missingToolName remains unexecuted.',
    ].join('\n');
  }

  String _latestUserContentForGeneration(int generation) =>
      _turnOwnerSnapshotForGeneration(generation)?.latestUserContent ?? '';

  Skill? _findEnabledSkillNamedInText(String text) {
    final normalizedText = text.toLowerCase();
    if (normalizedText.isEmpty) {
      return null;
    }
    try {
      final skills = ref.read(skillsNotifierProvider).enabledSkills;
      for (final skill in skills) {
        final name = skill.normalizedName.trim();
        if (name.isEmpty) {
          continue;
        }
        if (normalizedText.contains(name.toLowerCase())) {
          return skill;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  AssistantMode _resolveAssistantMode({Conversation? currentConversation}) {
    final override = _assistantModeOverride;
    if (override != null) {
      return override;
    }
    if (currentConversation?.isPlanningSession ?? false) {
      return AssistantMode.plan;
    }
    return switch (_settings.assistantMode) {
      AssistantMode.plan => AssistantMode.coding,
      final mode => mode,
    };
  }

  bool _shouldAutoEnterPlanningSession(Conversation? currentConversation) {
    if (currentConversation == null ||
        currentConversation.workspaceMode != WorkspaceMode.coding ||
        currentConversation.isPlanningSession) {
      return false;
    }
    if (_settings.assistantMode != AssistantMode.plan) {
      return false;
    }
    return currentConversation.messages.isEmpty &&
        !currentConversation.hasWorkflowContext;
  }

  TurnCodingProjectResolver get _codingProjects => TurnCodingProjectResolver(
    () => ref.read(codingProjectsNotifierProvider),
    ref.read(conversationsNotifierProvider),
  );
  String? _getActiveProjectRootPath() {
    final scoped = TurnProjectRoot.current;
    if (scoped != null) return scoped.rootPath;
    return _codingProjects.effective?.rootPath.trim();
  }

  /// The project a dispatching turn resolves its relative paths against.

  void _dispatchExternalToolHook(
    String event, {
    String? userMessage,
    String? assistantMessage,
    String? error,
  }) {
    final hooks = _settings.enabledExternalToolHooksFor(event);
    if (hooks.isEmpty || !ref.mounted) {
      return;
    }

    final conversationsState = ref.read(conversationsNotifierProvider);
    final currentConversation = conversationsState.currentConversation;
    final projectRoot = _getActiveProjectRootPath();
    final payload = <String, dynamic>{
      'hook_event_name': event,
      'event': event,
      'source_agent': 'caverno',
      'session_id': currentConversation?.id ?? conversationId ?? '',
      'conversation_id': currentConversation?.id ?? conversationId ?? '',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'model': _settings.effectiveModel,
      'base_url': _settings.baseUrl,
      'assistant_mode': _resolveAssistantMode(
        currentConversation: currentConversation,
      ).name,
      if (currentConversation != null)
        'workspace_mode': currentConversation.workspaceMode.name,
      if (projectRoot != null && projectRoot.isNotEmpty) 'cwd': projectRoot,
      'prompt': ?userMessage,
      'assistant_response': ?assistantMessage,
      'error': ?error,
    };

    unawaited(
      ref
          .read(externalToolHookServiceProvider)
          .dispatch(settings: _settings, event: event, payload: payload),
    );
  }

  Future<void> _prewarmProjectAccess(String projectId) async {
    final notifier = ref.read(codingProjectsNotifierProvider.notifier);
    await notifier.ensureProjectAccess(projectId);
    // Drop any stale cached AGENTS.md for the new project so the next
    // system-prompt build re-reads it under the freshly restored bookmark.
    final rootPath = ref
        .read(codingProjectsNotifierProvider)
        .findById(projectId)
        ?.rootPath;
    ref.read(agentsMdLoaderProvider).invalidate(rootPath);
  }

  List<Message> _buildWorkflowProposalMessages({
    required Conversation currentConversation,
    required String languageCode,
    PlanningResearchContext researchContext = const PlanningResearchContext(),
    List<WorkflowPlanningDecisionAnswer> decisionAnswers = const [],
    String? additionalPlanningContext,
    bool compact = false,
  }) {
    final now = DateTime.now();
    return [
      _createSystemMessage(
        conversation: currentConversation,
      ).copyWith(id: 'workflow_proposal_system', timestamp: now),
      Message(
        id: 'workflow_proposal_user',
        role: MessageRole.user,
        timestamp: now,
        content: ConversationPlanningPromptService.buildWorkflowProposalRequest(
          currentConversation: currentConversation,
          messages: currentConversation.messages,
          languageCode: languageCode,
          project: _codingProjectForTurn(currentConversation),
          researchContextBlock: researchContext.hasContent
              ? researchContext.toPromptBlock()
              : null,
          selectedDecisionLines: decisionAnswers
              .map((answer) => '${answer.question}: ${answer.optionLabel}')
              .toList(growable: false),
          additionalPlanningContext: additionalPlanningContext,
          executorProfile: PlanningExecutorProfile.fromSettings(_settings),
          compact: compact,
        ),
      ),
    ];
  }

  List<Message> _buildTaskProposalMessages({
    required Conversation currentConversation,
    required String languageCode,
    PlanningResearchContext researchContext = const PlanningResearchContext(),
    ConversationWorkflowStage? workflowStageOverride,
    ConversationWorkflowSpec? workflowSpecOverride,
    String? additionalPlanningContext,
    bool compact = false,
  }) {
    final now = DateTime.now();
    return [
      _createSystemMessage(
        conversation: currentConversation,
      ).copyWith(id: 'task_proposal_system', timestamp: now),
      Message(
        id: 'task_proposal_user',
        role: MessageRole.user,
        timestamp: now,
        content: ConversationPlanningPromptService.buildTaskProposalRequest(
          currentConversation: currentConversation,
          messages: currentConversation.messages,
          languageCode: languageCode,
          project: _codingProjectForTurn(currentConversation),
          researchContextBlock: researchContext.hasContent
              ? researchContext.toPromptBlock()
              : null,
          workflowStageOverride: workflowStageOverride,
          workflowSpecOverride: workflowSpecOverride,
          additionalPlanningContext: additionalPlanningContext,
          executorProfile: PlanningExecutorProfile.fromSettings(_settings),
          compact: compact,
        ),
      ),
    ];
  }

  Future<WorkflowProposalDraft> _requestWorkflowProposal({
    required Conversation currentConversation,
    required String languageCode,
    PlanningResearchContext researchContext = const PlanningResearchContext(),
    String? additionalPlanningContext,
  }) async {
    final decisionAnswers = <WorkflowPlanningDecisionAnswer>[];
    WorkflowProposalDraft? latestProposal;
    var latestOutstandingDecisions = const <WorkflowPlanningDecision>[];
    const maxDecisionRounds = 3;

    for (var round = 0; round < maxDecisionRounds; round++) {
      if (ref.mounted) {
        _routeThreadState(
          currentConversation.id,
          (s) => s.copyWith(
            isLoading: true,
            isGeneratingWorkflowProposal: true,
            workflowProposalError: null,
            pendingWorkflowDecision: null,
          ),
        );
      }

      final result = await _requestWorkflowProposalAttempt(
        currentConversation: currentConversation,
        languageCode: languageCode,
        researchContext: researchContext,
        decisionAnswers: decisionAnswers,
        additionalPlanningContext: additionalPlanningContext,
      );

      if (result case WorkflowProposalParsedDraft(:final proposal)) {
        final sanitizedProposal =
            PlanningDecisionPromotion.removeAnsweredOpenQuestions(
              proposal,
              decisionAnswers,
            );
        latestProposal = sanitizedProposal;
        final promotedDecisions =
            PlanningDecisionPromotion.promoteOpenQuestionsToPlanningPrompts(
              sanitizedProposal.workflowSpec.openQuestions,
              decisionAnswers: decisionAnswers,
            );
        latestOutstandingDecisions = promotedDecisions;
        if (promotedDecisions.isEmpty) {
          return sanitizedProposal;
        }
        final resolvedAnswers = await _collectWorkflowDecisionAnswers(
          promotedDecisions,
        );
        if (resolvedAnswers == null) {
          throw const _WorkflowProposalCancelled();
        }
        PlanningDecisionPromotion.mergeWorkflowDecisionAnswers(
          decisionAnswers,
          resolvedAnswers,
        );
        continue;
      }

      if (result case WorkflowProposalParsedDecisions(:final decisions)) {
        final unresolvedDecisions =
            PlanningDecisionPromotion.filterUnansweredWorkflowDecisions(
              decisions,
              decisionAnswers: decisionAnswers,
            );
        latestOutstandingDecisions = unresolvedDecisions;
        if (unresolvedDecisions.isEmpty) {
          final fallbackProposal = _buildWorkflowProposalFallback(
            latestProposal: latestProposal,
            outstandingDecisions: decisions,
          );
          if (fallbackProposal != null) {
            return fallbackProposal;
          }
          continue;
        }
        final resolvedAnswers = await _collectWorkflowDecisionAnswers(
          unresolvedDecisions,
        );
        if (resolvedAnswers == null) {
          throw const _WorkflowProposalCancelled();
        }
        PlanningDecisionPromotion.mergeWorkflowDecisionAnswers(
          decisionAnswers,
          resolvedAnswers,
        );
      }
    }

    final fallbackProposal = _buildWorkflowProposalFallback(
      latestProposal: latestProposal,
      outstandingDecisions: latestOutstandingDecisions,
    );
    if (fallbackProposal != null) {
      appLog(
        '[Workflow] Using fallback proposal after repeated planning decision rounds',
      );
      return fallbackProposal;
    }

    throw const FormatException('workflow proposal could not stabilize');
  }

  Future<WorkflowProposalParseResult> _requestWorkflowProposalAttempt({
    required Conversation currentConversation,
    required String languageCode,
    PlanningResearchContext researchContext = const PlanningResearchContext(),
    required List<WorkflowPlanningDecisionAnswer> decisionAnswers,
    String? additionalPlanningContext,
  }) async {
    final projectLooksEmpty = PlanningRetryContextBuilder.projectLooksEmpty(
      researchContext,
    );
    final attempts = <({bool compact, int maxTokens, bool minimalRetry})>[
      if (projectLooksEmpty) ...[
        (
          compact: true,
          maxTokens: SecondaryCallBudget.resolve(_settings.maxTokens, 1100),
          minimalRetry: false,
        ),
        (
          compact: true,
          maxTokens: SecondaryCallBudget.resolve(_settings.maxTokens, 800),
          minimalRetry: true,
        ),
        (
          compact: true,
          maxTokens: SecondaryCallBudget.resolve(_settings.maxTokens, 650),
          minimalRetry: true,
        ),
      ] else ...[
        (
          compact: false,
          maxTokens: SecondaryCallBudget.resolve(_settings.maxTokens, 1600),
          minimalRetry: false,
        ),
        (
          compact: true,
          maxTokens: SecondaryCallBudget.resolve(_settings.maxTokens, 900),
          minimalRetry: true,
        ),
        (
          compact: true,
          maxTokens: SecondaryCallBudget.resolve(_settings.maxTokens, 700),
          minimalRetry: true,
        ),
      ],
    ];

    String? lastError;
    for (var index = 0; index < attempts.length; index++) {
      final attempt = attempts[index];
      final result = await _secondaryCompletionRouter.runPlanning(
        primaryDataSource: _dataSource,
        route: _settings._planningCompletionRoute,
        operation: (dataSource, model) => dataSource.createChatCompletion(
          messages: _buildWorkflowProposalMessages(
            currentConversation: currentConversation,
            languageCode: languageCode,
            researchContext: researchContext,
            decisionAnswers: decisionAnswers,
            additionalPlanningContext: _planningRetryContext
                .forWorkflowProposal(
                  additionalPlanningContext,
                  minimalRetry: attempt.minimalRetry,
                  projectLooksEmpty: projectLooksEmpty,
                ),
            compact: attempt.compact,
          ),
          model: model,
          temperature: 0.1,
          maxTokens: attempt.maxTokens,
        ),
      );

      final response = _workflowProposalParser.parseWithFallback(
        result.content,
      );
      if (response != null) {
        if (index > 0) {
          appLog('[Workflow] Workflow proposal recovered on retry');
        }
        return response;
      }

      final truncated = ProposalParsingTextUtils.isCompletionTruncated(
        result.finishReason,
      );
      if (truncated) {
        final fallbackProposal = _buildWorkflowProposalTruncationFallback(
          currentConversation: currentConversation,
          rawContent: result.content,
          decisionAnswers: decisionAnswers,
        );
        if (fallbackProposal != null) {
          appLog(
            '[Workflow] Workflow proposal recovered from truncated reasoning fallback',
          );
          return WorkflowProposalParsedDraft(fallbackProposal);
        }
      }

      final preview = ProposalParsingTextUtils.proposalPreview(result.content);
      appLog(
        '[Workflow] Workflow proposal parse failed (attempt ${index + 1}/${attempts.length}, truncated: $truncated): $preview',
      );
      lastError = truncated
          ? 'workflow proposal was truncated: $preview'
          : 'workflow proposal parse failed: $preview';
    }

    throw FormatException(lastError ?? 'workflow proposal parse failed');
  }

  Future<List<WorkflowPlanningDecisionAnswer>?> _collectWorkflowDecisionAnswers(
    List<WorkflowPlanningDecision> decisions,
  ) async {
    if (decisions.isEmpty) {
      return const <WorkflowPlanningDecisionAnswer>[];
    }

    final answers = <WorkflowPlanningDecisionAnswer>[];
    for (final decision in decisions) {
      final answer = await requestWorkflowDecision(decision: decision);
      if (answer == null) {
        return null;
      }
      answers.add(answer);
    }
    return answers;
  }

  Future<WorkflowTaskProposalDraft> _requestTaskProposal({
    required Conversation currentConversation,
    required String languageCode,
    PlanningResearchContext researchContext = const PlanningResearchContext(),
    ConversationWorkflowStage? workflowStageOverride,
    ConversationWorkflowSpec? workflowSpecOverride,
    String? additionalPlanningContext,
  }) async {
    final projectLooksEmpty = PlanningRetryContextBuilder.projectLooksEmpty(
      researchContext,
    );
    WorkflowTaskProposalDraft? bestRetryCandidate;
    final attempts = <({bool compact, int maxTokens, bool minimalRetry})>[
      (
        compact: false,
        maxTokens: SecondaryCallBudget.resolve(_settings.maxTokens, 1800),
        minimalRetry: false,
      ),
      (
        compact: true,
        maxTokens: SecondaryCallBudget.resolve(_settings.maxTokens, 1200),
        minimalRetry: true,
      ),
      (
        compact: true,
        maxTokens: SecondaryCallBudget.resolve(_settings.maxTokens, 900),
        minimalRetry: true,
      ),
    ];

    String? lastError;
    final workflowSpec =
        workflowSpecOverride ?? currentConversation.effectiveWorkflowSpec;
    for (var index = 0; index < attempts.length; index++) {
      final attempt = attempts[index];
      final result = await _secondaryCompletionRouter.runPlanning(
        primaryDataSource: _dataSource,
        route: _settings._planningCompletionRoute,
        operation: (dataSource, model) => dataSource.createChatCompletion(
          messages: _buildTaskProposalMessages(
            currentConversation: currentConversation,
            languageCode: languageCode,
            researchContext: researchContext,
            workflowStageOverride: workflowStageOverride,
            workflowSpecOverride: workflowSpecOverride,
            additionalPlanningContext: _planningRetryContext.forTaskProposal(
              additionalPlanningContext,
              minimalRetry: attempt.minimalRetry,
              projectLooksEmpty: projectLooksEmpty,
              workflowSpec: workflowSpec,
            ),
            compact: attempt.compact,
          ),
          model: model,
          temperature: 0.1,
          maxTokens: attempt.maxTokens,
        ),
      );

      final proposal = _taskProposalParser.parseWithFallback(result.content);
      if (proposal != null) {
        final finalizedProposal = _finalizeTaskProposalDraft(
          proposal,
          researchContext: researchContext,
        );
        if (_taskProposalQualityService.taskProposalNeedsRetryForWorkflow(
          proposal,
          finalizedProposal,
          projectLooksEmpty,
          workflowSpec,
        )) {
          final preview = finalizedProposal.tasks
              .map((task) => task.title)
              .join(' | ');
          appLog(
            '[Workflow] Task proposal quality gate requested retry (attempt ${index + 1}/${attempts.length}): $preview',
          );
          bestRetryCandidate = _preferTaskProposalRetryCandidate(
            current: bestRetryCandidate,
            candidate: finalizedProposal,
          );
          lastError = 'task proposal quality gate rejected the generated tasks';
          continue;
        }
        if (index > 0) {
          appLog('[Workflow] Task proposal recovered on retry');
        }
        return finalizedProposal;
      }

      final preview = ProposalParsingTextUtils.proposalPreview(result.content);
      final truncated = ProposalParsingTextUtils.isCompletionTruncated(
        result.finishReason,
      );
      if (truncated) {
        final fallbackProposal = _buildTaskProposalTruncationFallback(
          currentConversation: currentConversation,
          rawContent: result.content,
          projectLooksEmpty: projectLooksEmpty,
          workflowSpecOverride: workflowSpecOverride,
        );
        if (fallbackProposal != null) {
          final finalizedFallback = _finalizeTaskProposalDraft(
            fallbackProposal,
            researchContext: researchContext,
          );
          if (!_taskProposalQualityService.taskProposalNeedsRetryForWorkflow(
            fallbackProposal,
            finalizedFallback,
            projectLooksEmpty,
            workflowSpec,
          )) {
            appLog(
              '[Workflow] Task proposal recovered from truncated reasoning fallback',
            );
            return finalizedFallback;
          }
          bestRetryCandidate = _preferTaskProposalRetryCandidate(
            current: bestRetryCandidate,
            candidate: finalizedFallback,
          );
        }
      }
      appLog(
        '[Workflow] Task proposal parse failed (attempt ${index + 1}/${attempts.length}, truncated: $truncated): $preview',
      );
      lastError = truncated
          ? 'task proposal was truncated: $preview'
          : 'task proposal parse failed: $preview';
      if (!truncated && index == 0) {
        continue;
      }
    }

    if (bestRetryCandidate != null &&
        !_taskProposalQualityService.taskProposalNeedsRetryForWorkflow(
          bestRetryCandidate,
          bestRetryCandidate,
          projectLooksEmpty,
          workflowSpec,
        )) {
      appLog(
        '[Workflow] Task proposal recovered from the best retry candidate',
      );
      return bestRetryCandidate;
    }

    final qualityGateFallback = _buildTaskProposalQualityGateFallback(
      currentConversation: currentConversation,
      projectLooksEmpty: projectLooksEmpty,
      researchContext: researchContext,
      bestRetryCandidate: bestRetryCandidate,
      workflowSpecOverride: workflowSpecOverride,
    );
    if (qualityGateFallback != null) {
      appLog('[Workflow] Task proposal recovered from quality gate fallback');
      return qualityGateFallback;
    }

    // Preserve the best reviewable plan when every fallback fails the gate;
    // rejecting the only usable draft otherwise leaves the user no plan.
    if (bestRetryCandidate != null) {
      appLog(
        '[Workflow] Task proposal quality gate exhausted; presenting the best '
        'rejected candidate for review',
      );
      return bestRetryCandidate;
    }

    throw FormatException(lastError ?? 'task proposal parse failed');
  }

  WorkflowTaskProposalDraft? _buildTaskProposalQualityGateFallback({
    required Conversation currentConversation,
    required bool projectLooksEmpty,
    required PlanningResearchContext researchContext,
    WorkflowTaskProposalDraft? bestRetryCandidate,
    ConversationWorkflowSpec? workflowSpecOverride,
  }) {
    final workflowSpec =
        workflowSpecOverride ?? currentConversation.effectiveWorkflowSpec;
    final rawGoal = workflowSpec.goal.trim().isNotEmpty
        ? workflowSpec.goal.trim()
        : _workflowProposalParser.deriveWorkflowFallbackGoalFromConversation(
            currentConversation,
          );
    if (rawGoal == null || rawGoal.isEmpty) {
      return null;
    }

    if (bestRetryCandidate != null &&
        !_taskProposalQualityService.taskProposalNeedsRetryForWorkflow(
          bestRetryCandidate,
          bestRetryCandidate,
          projectLooksEmpty,
          workflowSpec,
        )) {
      return bestRetryCandidate;
    }

    final contextLines = <String>[
      rawGoal,
      ...workflowSpec.constraints,
      ...workflowSpec.acceptanceCriteria,
      ...workflowSpec.openQuestions,
    ];
    if (bestRetryCandidate != null) {
      for (final task in bestRetryCandidate.tasks) {
        contextLines.add(task.title);
        contextLines.add(task.notes);
        contextLines.add(task.validationCommand);
        contextLines.addAll(task.targetFiles);
      }
    }

    final fallbackProposal = WorkflowTaskProposalDraft(
      tasks: _buildHeuristicTaskProposalFallbackTasks(
        contextLines: contextLines,
        projectLooksEmpty: projectLooksEmpty,
      ),
    );
    if (fallbackProposal.tasks.isEmpty) {
      return null;
    }

    final finalizedFallback = _finalizeTaskProposalDraft(
      fallbackProposal,
      researchContext: researchContext,
    );
    if (_taskProposalQualityService.taskProposalNeedsRetryForWorkflow(
      fallbackProposal,
      finalizedFallback,
      projectLooksEmpty,
      workflowSpec,
    )) {
      return null;
    }
    return finalizedFallback;
  }

  @visibleForTesting
  WorkflowProposalDraft? parseWorkflowProposalForTest(String rawContent) {
    final response = _workflowProposalParser.parseWithFallback(rawContent);
    return switch (response) {
      WorkflowProposalParsedDraft(:final proposal) => proposal,
      _ => null,
    };
  }

  @visibleForTesting
  List<WorkflowPlanningDecision>? parseWorkflowDecisionsForTest(
    String rawContent,
  ) {
    final response = _workflowProposalParser.parseWithFallback(rawContent);
    return switch (response) {
      WorkflowProposalParsedDecisions(:final decisions) => decisions,
      _ => null,
    };
  }

  @visibleForTesting
  List<WorkflowPlanningDecision> promoteOpenQuestionsForTest(
    List<String> openQuestions, {
    List<WorkflowPlanningDecisionAnswer> decisionAnswers = const [],
  }) {
    return PlanningDecisionPromotion.promoteOpenQuestionsToPlanningPrompts(
      openQuestions,
      decisionAnswers: decisionAnswers,
    );
  }

  @visibleForTesting
  WorkflowTaskProposalDraft? parseTaskProposalForTest(String rawContent) {
    return _taskProposalParser.parseWithFallback(rawContent);
  }

  @visibleForTesting
  WorkflowTaskProposalDraft? buildTaskProposalTruncationFallbackForTest({
    required Conversation currentConversation,
    required String rawContent,
    required bool projectLooksEmpty,
    ConversationWorkflowSpec? workflowSpecOverride,
  }) {
    return _buildTaskProposalTruncationFallback(
      currentConversation: currentConversation,
      rawContent: rawContent,
      projectLooksEmpty: projectLooksEmpty,
      workflowSpecOverride: workflowSpecOverride,
    );
  }

  @visibleForTesting
  WorkflowTaskProposalDraft finalizeTaskProposalForTest(
    WorkflowTaskProposalDraft proposal, {
    required bool projectLooksEmpty,
  }) {
    return WorkflowTaskProposalDraft(
      tasks: _reorderTaskProposalTasks(
        _taskProposalQualityService.sanitizeTaskProposalTasks(proposal.tasks),
        projectLooksEmpty: projectLooksEmpty,
      ),
    );
  }

  @visibleForTesting
  bool taskProposalNeedsRetryForTest(
    WorkflowTaskProposalDraft original,
    WorkflowTaskProposalDraft finalized,
    bool projectLooksEmpty,
  ) {
    return _taskProposalQualityService.taskProposalNeedsRetry(
      original,
      finalized,
      projectLooksEmpty,
    );
  }

  @visibleForTesting
  bool taskProposalNeedsRetryForWorkflowForTest(
    WorkflowTaskProposalDraft original,
    WorkflowTaskProposalDraft finalized,
    bool projectLooksEmpty,
    ConversationWorkflowSpec workflowSpec,
  ) {
    return _taskProposalQualityService.taskProposalNeedsRetryForWorkflow(
      original,
      finalized,
      projectLooksEmpty,
      workflowSpec,
    );
  }

  @visibleForTesting
  String? buildTaskProposalRetryContextForTest(
    String? additionalPlanningContext, {
    required bool minimalRetry,
    required bool projectLooksEmpty,
    ConversationWorkflowSpec? workflowSpec,
  }) {
    return _planningRetryContext.forTaskProposal(
      additionalPlanningContext,
      minimalRetry: minimalRetry,
      projectLooksEmpty: projectLooksEmpty,
      workflowSpec: workflowSpec,
    );
  }

  @visibleForTesting
  WorkflowTaskProposalDraft? buildTaskProposalQualityGateFallbackForTest({
    required Conversation currentConversation,
    required bool projectLooksEmpty,
    WorkflowTaskProposalDraft? bestRetryCandidate,
    ConversationWorkflowSpec? workflowSpecOverride,
  }) {
    return _buildTaskProposalQualityGateFallback(
      currentConversation: currentConversation,
      projectLooksEmpty: projectLooksEmpty,
      researchContext: const PlanningResearchContext(),
      bestRetryCandidate: bestRetryCandidate,
      workflowSpecOverride: workflowSpecOverride,
    );
  }

  @visibleForTesting
  String buildDuplicateFollowUpRecoveryPromptForTest(
    List<ToolCallInfo> toolCalls, {
    List<ToolResultInfo> previousToolResults = const [],
    bool hasSavedTask = true,
  }) {
    return _buildDuplicateFollowUpRecoveryPrompt(
      toolCalls,
      previousToolResults: previousToolResults,
      hasSavedTask: hasSavedTask,
    );
  }

  @visibleForTesting
  String buildDuplicateInspectionRecoveryPromptForTest(
    List<ToolCallInfo> toolCalls, {
    List<ToolResultInfo> previousToolResults = const [],
    bool hasSavedTask = true,
  }) {
    return _buildDuplicateInspectionRecoveryPrompt(
      toolCalls,
      previousToolResults: previousToolResults,
      hasSavedTask: hasSavedTask,
    );
  }

  @visibleForTesting
  String buildToolLoopExhaustionRecoveryPromptForTest(
    List<ToolCallInfo> toolCalls, {
    List<ToolResultInfo> previousToolResults = const [],
  }) {
    return _buildToolLoopExhaustionRecoveryPrompt(
      toolCalls,
      previousToolResults: previousToolResults,
    );
  }

  @visibleForTesting
  String buildSkippedPythonAttachmentAnalysisRepairPromptForTest() =>
      PythonAttachmentRepairPolicy.buildSkippedPythonAttachmentAnalysisRepairPrompt();

  @visibleForTesting
  String buildPythonAttachmentPathFailureRepairPromptForTest() =>
      PythonAttachmentRepairPolicy.buildPythonAttachmentPathFailureRepairPrompt();

  @visibleForTesting
  List<ToolResultInfo> buildToolLoopRecoveryToolResultsForTest({
    required List<ToolResultInfo> currentToolResults,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolCallInfo> pendingToolCalls,
    String? projectRoot,
  }) {
    return _buildToolLoopRecoveryToolResults(
      currentToolResults: currentToolResults,
      executedToolResults: executedToolResults,
      pendingToolCalls: pendingToolCalls,
      projectRoot: projectRoot,
    );
  }

  @visibleForTesting
  List<ToolResultInfo> buildDuplicateRecoveryToolResultsForTest({
    required List<ToolCallInfo> currentToolCalls,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolResultInfo> fallbackToolResults,
    String? projectRoot,
  }) => const DuplicateToolResultRecovery().recover(
    DuplicateToolResultRecoveryInput(
      currentToolCalls: currentToolCalls,
      executedToolResults: executedToolResults,
      fallbackToolResults: fallbackToolResults,
      projectRoot: projectRoot,
    ),
  );

  @visibleForTesting
  bool assistantMessageHasVisibleContentForTest(String content) =>
      TurnFinalMessage.hasVisibleContent(content);

  @visibleForTesting
  WorkflowProposalDraft? buildWorkflowProposalFallbackForTest({
    WorkflowProposalDraft? latestProposal,
    required List<WorkflowPlanningDecision> decisions,
    List<WorkflowPlanningDecisionAnswer> decisionAnswers = const [],
  }) {
    final unresolvedDecisions =
        PlanningDecisionPromotion.filterUnansweredWorkflowDecisions(
          decisions,
          decisionAnswers: decisionAnswers,
        );
    return _buildWorkflowProposalFallback(
      latestProposal: latestProposal,
      outstandingDecisions: unresolvedDecisions,
    );
  }

  @visibleForTesting
  WorkflowProposalDraft? buildWorkflowProposalTruncationFallbackForTest({
    required Conversation currentConversation,
    required String rawContent,
    List<WorkflowPlanningDecisionAnswer> decisionAnswers = const [],
  }) {
    return _buildWorkflowProposalTruncationFallback(
      currentConversation: currentConversation,
      rawContent: rawContent,
      decisionAnswers: decisionAnswers,
    );
  }

  @visibleForTesting
  Map<String, dynamic> normalizeWriteFileArgumentsForTest(
    Map<String, dynamic> arguments,
  ) {
    return ProjectScopedToolArgumentResolver.normalizeWriteFileArguments(
      arguments,
    );
  }

  @visibleForTesting
  Map<String, dynamic> resolveProjectScopedArgumentsForTest(
    String toolName,
    Map<String, dynamic> arguments,
  ) {
    return _resolveProjectScopedArguments(toolName, arguments);
  }

  Map<String, dynamic> _resolveProjectScopedArguments(
    String toolName,
    Map<String, dynamic> arguments,
  ) {
    return ProjectScopedToolArgumentResolver.resolve(
      toolName: toolName,
      arguments: arguments,
      loadProjectRoot: _getActiveProjectRootPath,
    );
  }

  List<Message> _prepareMessagesForLLM({
    bool forceCompaction = false,
    List<Map<String, dynamic>>? toolDefinitionsOverride,
    required int interactionGeneration,
    String? participantRolePrompt,
  }) {
    // Before the snapshot is read, because committing is what puts an
    // interruption where that read finds it.
    _commitPendingTurnSteering(interactionGeneration);
    final ownerSnapshot = _turnOwnerSnapshotForGeneration(
      interactionGeneration,
    );
    if (ownerSnapshot == null) {
      throw StateError(
        'Turn owner snapshot unavailable: $interactionGeneration',
      );
    }
    final currentConversation = _conversationForId(
      ownerSnapshot.owner.conversationId,
    );
    final hiddenPrompt = ownerSnapshot.hiddenPrompt;
    final temporalReferenceContext = ownerSnapshot.temporalReferenceContext;
    final sourceMessages = ownerSnapshot.messages;
    final messages =
        ConversationPlanExecutionCoordinator.filterSupersededTaskExecutionTurns(
              messages: sourceMessages.where((message) => !message.isStreaming),
              currentExecutionPrompt: hiddenPrompt?.content,
            )
            .map(_messagePersistence.sanitizeMessageForModelHistory)
            .where(_messagePersistence.shouldKeepMessageForModelHistory)
            .toList();
    final modelSwitchHandoffBrief = _modelSwitchHandoffs.take(
      ownerSnapshot.owner,
    );
    final shouldForceCompaction = _modelSwitchHandoffs.consumePromptCompaction(
      owner: ownerSnapshot.owner,
      forceCompaction: forceCompaction,
      hasModelSwitchHandoff: modelSwitchHandoffBrief != null,
    );
    final promptMessages = <Message>[
      _createSystemMessage(
        conversation: currentConversation,
        ownerSnapshot: ownerSnapshot,
        participantRolePrompt: participantRolePrompt,
        toolNamesOverride: toolDefinitionsOverride == null
            ? null
            : ToolDefinitionSearchService.toolNamesFromDefinitions(
                toolDefinitionsOverride,
              ).toList(),
      ),
    ];
    if (temporalReferenceContext != null) {
      promptMessages.add(
        Message(
          id: 'system_temporal',
          content: temporalReferenceContext,
          role: MessageRole.system,
          timestamp: DateTime.now(),
        ),
      );
    }
    final modelSwitchHandoffMessage = _modelSwitchHandoffs.createPromptMessage(
      modelSwitchHandoffBrief,
    );
    if (modelSwitchHandoffMessage != null) {
      promptMessages.add(modelSwitchHandoffMessage);
    }
    final compactionArtifact = _resolvePromptCompactionArtifact(
      currentConversation: currentConversation,
      messages: messages,
      forceCompaction: shouldForceCompaction,
    );
    if (compactionArtifact?.hasContent ?? false) {
      promptMessages.add(
        Message(
          id: 'system_compaction',
          content:
              'Earlier conversation summary for omitted turns:\n'
              '${compactionArtifact!.normalizedSummary!}\n\n'
              'Treat this summary as context for the trimmed transcript that follows.',
          role: MessageRole.system,
          timestamp: DateTime.now(),
        ),
      );
    }
    final retainedMessages = ConversationCompactionService.retainMessages(
      messages: messages,
      artifact: compactionArtifact,
    );
    final result = [...promptMessages, ...retainedMessages];
    if (hiddenPrompt != null) {
      result.add(hiddenPrompt);
    }
    // Last, so an interruption is not read as one more remark filed behind the
    // work already in flight.
    final steeringDirective = _turnSteeringDirectiveMessage(
      ownerSnapshot.owner,
    );
    if (steeringDirective != null) {
      result.add(steeringDirective);
    }
    _updateContextTokenPressureState(
      pressure: ConversationCompactionService.assessTokenPressure(
        messages: result,
      ),
      compactionActive: compactionArtifact?.hasContent ?? false,
    );
    return result;
  }

  ConversationCompactionArtifact? _resolvePromptCompactionArtifact({
    required Conversation? currentConversation,
    required List<Message> messages,
    bool forceCompaction = false,
  }) {
    final freshArtifact = ConversationCompactionService.buildArtifact(
      messages: messages,
      planDocument: currentConversation?.displayPlanDocument(
        isPlanning: currentConversation.isPlanningSession,
      ),
      now: currentConversation?.effectiveCompactionArtifact.updatedAt,
      force: forceCompaction,
    );
    if (freshArtifact != null) {
      return freshArtifact;
    }
    final persistedArtifact = currentConversation?.compactionArtifact;
    if (persistedArtifact?.hasContent ?? false) {
      return persistedArtifact;
    }
    return null;
  }

  void _updateContextTokenPressureState({
    required ConversationTokenPressure pressure,
    required bool compactionActive,
  }) {
    if (!ref.mounted) return;
    final nextLevel = switch (pressure.level) {
      ConversationTokenPressureLevel.normal => ContextTokenPressureLevel.normal,
      ConversationTokenPressureLevel.warning =>
        ContextTokenPressureLevel.warning,
      ConversationTokenPressureLevel.critical =>
        ContextTokenPressureLevel.critical,
    };
    if (state.estimatedPromptTokens == pressure.estimatedPromptTokens &&
        state.contextTokenPressureLevel == nextLevel &&
        state.promptCompactionActive == compactionActive) {
      return;
    }
    state = state.copyWith(
      estimatedPromptTokens: pressure.estimatedPromptTokens,
      contextTokenPressureLevel: nextLevel,
      promptCompactionActive: compactionActive,
    );
  }

  void _refreshContextTokenPressureFromState() {
    _updateContextTokenPressureState(
      pressure: ConversationCompactionService.assessTokenPressure(
        messages: state.messages,
      ),
      compactionActive: state.promptCompactionActive,
    );
  }

  final _uuid = const Uuid();
  final _turnStream = TurnStreamBindingRegistry();
  final _queuedChatMessages = ThreadScopedMessageQueue();
  final _turnSteering = TurnSteeringRegistry();

  /// Plan drafting survives leaving the thread, so returning to it presents
  /// the review sheet instead of looking idle.
  final _threadStates = <String, ThreadScopedChatState>{};
  final ToolApprovalCache _toolApprovalCache = ToolApprovalCache();
  final _pendingToolApprovals = PendingToolApprovalRegistry();

  /// Local-command approvals awaiting an answer on any thread.
  ///
  /// A turn running on a thread the user is not reading stashes its prompt for
  /// that thread, so a test driving two threads at once cannot reach it
  /// through `state`; the registry holds it either way.
  @visibleForTesting
  Iterable<PendingLocalCommand> get pendingLocalCommandsAcrossThreads =>
      _pendingToolApprovals.pendingOfType<PendingLocalCommand>();
  final _bleConnectAttempts = BleConnectAttemptCoordinator();
  final _successfulReadResultReplayCache = SuccessfulReadResultReplayCache();
  static const int _maxContentToolContinuations = 5;
  final Set<int> _turnFinalizationRecoveryGenerations = {};
  // Generations with a classified exit; the terminal funnel fills any gap.
  final Set<int> _classifiedTurnExitGenerations = <int>{};
  // Tool calls whose arguments were truncated; report the specific cause so
  // the model reissues them instead of treating them as malformed calls.
  Set<String> _lengthTruncatedToolCallIds = const <String>{};
  late final _messagePersistence = TurnMessagePersistenceCoordinator(
    writeConversationMessages: _writeConversationMessages,
    currentConversationId: () =>
        ref.read(conversationsNotifierProvider).currentConversationId,
  );
  late final _goalAutoContinueTrackerRegistry = GoalAutoContinueTrackerRegistry(
    replayIdFactory: (mutationGeneration) =>
        'post_mutation_verifier_${mutationGeneration}_'
        '${DateTime.now().microsecondsSinceEpoch}',
  );
  final _goalCompletionEvidence = TurnGoalCompletionEvidenceRegistry();
  // A successful save_skill suppresses false continuation recovery.
  int? _lastSaveSkillGeneration;
  final _activeResponseRegistry = ActiveResponseRegistry();
  final _lastStreamedToolResultFinalAnswersByGeneration = <int, String>{};
  final Set<int> _pendingActionLengthRecoveryGenerations = <int>{};
  final _explicitTerminalSuccessSummariesByGeneration = <int, String>{};
  final _askUserQuestionTurnCache = AskUserQuestionTurnCache();
  final ResponseMetadataRegistry _responseMetadata = ResponseMetadataRegistry();
  final _pendingAskUserQuestionsByThread = <String, PendingAskUserQuestion>{};
  final _participantTurnControls = ParticipantTurnControlRegistry();
  ChatInteractionOrigin _activeInteractionOrigin = ChatInteractionOrigin.local;
  String? _activeRemoteDeviceId;

  bool get _isRemoteInteraction =>
      _activeInteractionOrigin == ChatInteractionOrigin.remote;

  bool resolveRemoteApproval({required String id, required bool approved}) =>
      resolveFileOperation(id: id, approved: approved) ||
      resolveGitCommand(id: id, approved: approved) ||
      resolveLocalCommand(
        id: id,
        approval: LocalCommandApproval(approved: approved),
      );

  int get _interactionGeneration => _activeResponseRegistry.currentGeneration;
  String? get _activeResponseConversationId =>
      _activeResponseRegistry.currentConversationId;
  int _beginInteractionGeneration() =>
      _activeResponseRegistry.beginGeneration();

  bool _isCurrentInteractionGeneration(int generation) =>
      ref.mounted && _activeResponseRegistry.isCurrentOrRegistered(generation);

  void _routeThreadState(String threadId, ChatState Function(ChatState) apply) {
    state = ThreadScopedChatState.routeToThread(
      byThread: _threadStates,
      turnThread: threadId,
      visibleThread: conversationId,
      current: state,
      apply: apply,
    );
  }

  bool get _hasActiveResponse => _activeResponseRegistry.hasActiveResponse;

  int? _activeResponseGenerationForConversation(String? targetConversationId) =>
      _activeResponseRegistry.generationForConversation(targetConversationId);

  String? _activeResponseConversationIdForGeneration(int generation) =>
      _activeResponseRegistry.conversationIdForGeneration(generation);

  List<Message>? _activeResponseMessagesForGeneration(int generation) =>
      _activeResponseRegistry.messagesForGeneration(generation);

  TurnOwnerSnapshot? _turnOwnerSnapshotForGeneration(int generation) =>
      _activeResponseRegistry.snapshotForGeneration(generation);

  ChatTurnOwner? _turnOwnerForGeneration(int generation) =>
      _turnOwnerSnapshotForGeneration(generation)?.owner;

  McpToolResult _turnOwnerSnapshotUnavailableResult(String toolName) =>
      McpToolResult(
        toolName: toolName,
        result: '{"ok":false,"code":"turn_owner_snapshot_unavailable"}',
        isSuccess: false,
        errorMessage: 'Turn owner snapshot unavailable',
      );

  bool _isActiveResponseDetachedForGeneration(int generation) =>
      _activeResponseRegistry.isDetachedForGeneration(
        generation: generation,
        visibleConversationId: conversationId,
      );

  void _trackActiveResponse(
    int generation,
    String? targetConversationId, {
    Message? turnUserMessage,
    Message? hiddenPrompt,
    bool persistHiddenPromptAssistantResponse = false,
    String? temporalReferenceContext,
    AssistantMode? assistantModeOverride,
    List<Message>? ownerMessages,
  }) {
    final sessionLogContext = _buildLlmSessionLogContext(
      targetConversationId: targetConversationId,
    );
    final ownerConversation = targetConversationId == null
        ? null
        : _conversationForId(targetConversationId);
    _activeResponseRegistry.registerWithSnapshot(
      generation: generation,
      targetConversationId: targetConversationId,
      messages: ownerMessages ?? state.messages,
      turnUserMessage: turnUserMessage,
      projectRoot: ownerConversation == null
          ? null
          : _codingProjects.forConversation(ownerConversation)?.rootPath,
      sessionLogContext: sessionLogContext,
      conversation: ownerConversation,
      hiddenPrompt: hiddenPrompt,
      persistHiddenPromptAssistantResponse:
          persistHiddenPromptAssistantResponse,
      temporalReferenceContext: temporalReferenceContext,
      assistantModeOverride: assistantModeOverride ?? _assistantModeOverride,
      configuredAssistantMode: _settings.assistantMode,
    );
    final owner = _turnOwnerForGeneration(generation);
    if (owner != null) _modelEditTelemetry?.activateOwner(owner);
    _syncBusyConversationIds();
  }

  void _denyTools(int g) => _activeResponseRegistry.denyTools(g);

  void _syncBusyConversationIds() {
    if (!ref.mounted) return;
    final active = _activeResponseRegistry.activeConversationIds;
    if (setEquals(active, state.busyConversationIds)) return;
    state = state.copyWith(busyConversationIds: active);
  }

  void _cacheActiveResponseMessagesForGeneration(
    int generation,
    List<Message> messages,
  ) => _activeResponseRegistry.cacheMessages(generation, messages);

  /// Clears what a generation registered, and nothing owner-scoped.
  ///
  /// The six owner-keyed releases that used to live here now belong to the
  /// turn's [TurnReleaseScope]. They were reached by looking the owner back up
  /// from the generation, which meant a turn was torn down through two
  /// destructors keyed differently, and this one straddled both.
  void _clearActiveResponseForGeneration(int generation) {
    _activeResponseRegistry.clearGeneration(generation);
    _lastStreamedToolResultFinalAnswersByGeneration.remove(generation);
    _pendingActionLengthRecoveryGenerations.remove(generation);
    _explicitTerminalSuccessSummariesByGeneration.remove(generation);
    _productionReleaseApprovals.clearGeneration(generation);
    _turnFinalizationRecoveryGenerations.remove(generation);
    _syncBusyConversationIds();
  }

  void _clearAllActiveResponses({bool preservePausedParticipantTurn = false}) {
    if (!preservePausedParticipantTurn) {
      _disposeAllParticipantTurnControls();
    }
    for (final owner in _responseMetadata.owners) {
      _responseMetadata.dispose(owner);
    }
    _activeResponseRegistry.clearAll();
    _turnSteering.clear();
    _lastStreamedToolResultFinalAnswersByGeneration.clear();
    _pendingActionLengthRecoveryGenerations.clear();
    _explicitTerminalSuccessSummariesByGeneration.clear();
    _askUserQuestionTurnCache.clear();
    _productionReleaseApprovals.clearAll();
    _blockedReleaseRetrySignatures.clear();
    _unexecutedCommandRetryOwners.clear();
    _turnFinalizationRecoveryGenerations.clear();
    _modelSwitchHandoffs.clearPromptCompactions();
    _contextSurgeryObservations.clear();
    _modelEditTelemetry?.clear();
    _syncBusyConversationIds();
  }

  Future<ChatTurnOwner?> sendHiddenPrompt(
    String instruction, {
    HiddenPromptLaunchOptions options = const HiddenPromptLaunchOptions(),
    bool isVoiceMode = false,
    String languageCode = 'en',
    bool persistAssistantResponse = false,
    ToolResultCompletionEvidence? initialGoalCompletionEvidence,
    bool replayVerifierImmediatelyAfterMutation = false,
    bool verifierOnlyContinuation = false,
    Set<String>? allowedToolNames,
  }) async {
    if (!ref.mounted) return null;
    var ownerConversationId = options.targetConversationId?.trim() ?? '';
    if (ownerConversationId.isNotEmpty &&
        _conversationForId(ownerConversationId) == null) {
      return null;
    }
    if (ownerConversationId.isEmpty) {
      final hiddenConversation = ref
          .read(conversationsNotifierProvider.notifier)
          .ensureCurrentConversation();
      if (hiddenConversation == null) return null;
      ownerConversationId = hiddenConversation.id;
      conversationId ??= ownerConversationId;
    }
    if (isConversationBusy(ownerConversationId)) return null;
    _temporalReferenceContext = null;
    _isVoiceMode = isVoiceMode;
    _languageCode = languageCode;
    final interactionGeneration = _beginInteractionGeneration();
    final startedRuntime = await _startRuntimeTurn(
      generation: interactionGeneration,
      ownerConversationId: ownerConversationId,
      hidden: true,
      origin: ChatInteractionOrigin.local,
      initialGoalCompletionEvidence:
          initialGoalCompletionEvidence ?? const ToolResultCompletionEvidence(),
    );
    if (startedRuntime == null) return null;
    final turnOwner = startedRuntime;
    try {
      _clearTurnDiffCapture();
      final hiddenPrompt = Message(
        id: _uuid.v4(),
        content: instruction,
        role: MessageRole.user,
        timestamp: DateTime.now(),
      );
      final normalizedVisibleContent = options.visibleUserContent?.trim() ?? '';
      final turnUserMessage = normalizedVisibleContent.isEmpty
          ? hiddenPrompt
          : Message(
              id: _uuid.v4(),
              content: normalizedVisibleContent,
              role: MessageRole.user,
              timestamp: DateTime.now(),
            );
      _hiddenPrompt = hiddenPrompt;
      final assistantMessage = Message(
        id: _uuid.v4(),
        content: '',
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
        isStreaming: true,
      );
      final ownerMessages = ownerConversationId == conversationId
          ? state.messages
          : _conversationForId(ownerConversationId)?.messages ??
                const <Message>[];
      final responseMessages = [
        ...ownerMessages,
        if (normalizedVisibleContent.isNotEmpty) turnUserMessage,
        assistantMessage,
      ];
      if (ownerConversationId == conversationId) {
        state = state.copyWith(
          messages: responseMessages,
          isLoading: true,
          error: null,
        );
      }
      _trackActiveResponse(
        interactionGeneration,
        ownerConversationId,
        turnUserMessage: turnUserMessage,
        hiddenPrompt: hiddenPrompt,
        persistHiddenPromptAssistantResponse: persistAssistantResponse,
        ownerMessages: responseMessages,
      );
      if (normalizedVisibleContent.isNotEmpty) {
        unawaited(
          _messagePersistence.persistMessages(
            ownerConversationId,
            responseMessages.where((message) => !message.isStreaming).toList(),
          ),
        );
        if (ownerConversationId == conversationId) {
          _dispatchExternalToolHook(
            'UserPromptSubmit',
            userMessage: normalizedVisibleContent,
          );
        }
      }
      if (!_responseMetadata.start(turnOwner)) {
        throw StateError('Response metadata state could not be initialized.');
      }

      _onSendStarted();
      if (!_isCurrentInteractionGeneration(interactionGeneration)) {
        return turnOwner;
      }

      if (allowedToolNames?.isEmpty == true) {
        _denyTools(interactionGeneration);
        await _sendWithoutTools(
          interactionGeneration: interactionGeneration,
          options: options,
        );
      } else if (_mcpToolService != null &&
          _settings.mcpEnabled &&
          _supportsToolAwareRequests) {
        appLog('[Tool] Sending hidden prompt in tool-aware mode');
        await _sendWithTools(
          interactionGeneration: interactionGeneration,
          allowedToolNames: allowedToolNames,
          replayVerifierImmediatelyAfterMutation:
              replayVerifierImmediatelyAfterMutation,
          verifierOnlyContinuation: verifierOnlyContinuation,
        );
      } else {
        appLog('[Tool] Sending hidden prompt in normal mode');
        _denyTools(interactionGeneration);
        await _sendWithoutTools(
          interactionGeneration: interactionGeneration,
          options: options,
        );
      }
      return turnOwner;
    } catch (error) {
      _failRuntimeTurn(
        interactionGeneration,
        code: 'hidden_prompt_failed',
        message: error.toString(),
      );
      _turnToolResults.dispose(turnOwner);
      _routeRuntimeStartFailure(ownerConversationId, error.toString());
      return null;
    }
  }

  Future<ChatTurnOwner?> sendMessage(
    String content, {
    String? imageBase64,
    String? imageMimeType,
    String? originalImagePath,
    String? originalImageMimeType,
    VideoAttachmentDraft? video,
    String languageCode = 'en',
    bool isVoiceMode = false,
    bool bypassPlanMode = false,
    ChatInteractionOrigin origin = ChatInteractionOrigin.local,
    String? remoteDeviceId,
    // Join the running turn instead of waiting behind it. Ignored when the
    // thread is idle, when something is already queued for it, or when the
    // message carries what steering cannot (see [_isSteerableMessage]); all
    // three fall back to the queue rather than dropping the message.
    bool interrupt = false,
  }) async {
    final hasBody = content.trim().isNotEmpty || imageBase64 != null;
    if (!hasBody && video == null) return null;
    if (!ref.mounted) return null;
    final wasLoading = state.isLoading;
    var ownerConversationId = conversationId;
    if (wasLoading && ownerConversationId?.isNotEmpty != true) {
      ownerConversationId = ref
          .read(conversationsNotifierProvider.notifier)
          .ensureCurrentConversation()
          ?.id;
      conversationId = ownerConversationId;
    }
    if (ownerConversationId != null) {
      _dismissPendingAskUserQuestionForConversation(ownerConversationId);
    }
    final queue = _queuedChatMessages;
    final queuedMessage = QueuedChatMessage(
      id: _uuid.v4(),
      content: content,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      originalImagePath: originalImagePath,
      originalImageMimeType: originalImageMimeType,
      video: video,
      languageCode: languageCode,
      isVoiceMode: isVoiceMode,
      bypassPlanMode: bypassPlanMode,
      origin: origin,
      remoteDeviceId: origin == ChatInteractionOrigin.remote
          ? remoteDeviceId?.trim()
          : null,
      conversationId: ownerConversationId,
    );
    // Only when the user asked to interrupt. Queueing stays the default
    // because "run this after" is a different intent from "do this instead",
    // and the queue is what carries the owner receipt for the former.
    //
    // Not for a thread with something already queued: jumping that queue would
    // reorder what the user typed.
    if (interrupt &&
        wasLoading &&
        !queue.shouldEnqueue(ownerConversationId) &&
        _isSteerableMessage(queuedMessage)) {
      final steerableOwner = _steerableTurnOwner(ownerConversationId);
      if (steerableOwner != null) {
        return _registerTurnSteering(steerableOwner, queuedMessage);
      }
    }
    if (wasLoading || queue.shouldEnqueue(ownerConversationId)) {
      if (ownerConversationId?.isNotEmpty != true) return null;
      final participantRuntime = state.participantTurnRuntime;
      if (participantRuntime != null && !participantRuntime.paused) {
        requestParticipantTurnStop();
      }
      final queuedTurnOwner = queue.add(queuedMessage);
      _syncQueuedChatMessagesState();
      appLog(
        '[ChatNotifier] Queued user message while a response is in flight '
        '(${_queuedChatMessages.length} pending)',
      );
      unawaited(_drainQueuedChatMessagesForThreadIfIdle(ownerConversationId!));
      return queuedTurnOwner;
    }
    return _sendMessageNow(queuedMessage);
  }

  Future<ChatTurnOwner?> _sendMessageNow(
    QueuedChatMessage queuedMessage, {
    bool fromQueue = false,
  }) async {
    if (!ref.mounted) return null;
    final queue = _queuedChatMessages;
    if (!queue.canStart(queuedMessage, conversationId, fromQueue)) return null;
    ChatTurnOwner? turnOwner;
    var runtimeStarted = false;
    try {
      final content = queuedMessage.content;
      final imageBase64 = queuedMessage.imageBase64;
      final imageMimeType = queuedMessage.imageMimeType;
      final originalImagePath = queuedMessage.originalImagePath;
      final originalImageMimeType = queuedMessage.originalImageMimeType;
      final languageCode = queuedMessage.languageCode;
      final isVoiceMode = queuedMessage.isVoiceMode;
      final bypassPlanMode = queuedMessage.bypassPlanMode;
      final conversationsNotifier = ref.read(
        conversationsNotifierProvider.notifier,
      );
      var conversationsState = ref.read(conversationsNotifierProvider);
      var currentConversation = conversationsState.currentConversation;
      var draftMessages = const <Message>[];
      if (currentConversation == null) {
        draftMessages = state.messages
            .where((message) => !message.isStreaming)
            .toList(growable: false);
        currentConversation = conversationsNotifier.ensureCurrentConversation();
      }
      final effectiveOwner = queue.ownerFor(
        queuedMessage,
        conversationId,
        currentConversation?.id,
      );
      if (effectiveOwner == null) return null;
      conversationId = effectiveOwner;
      if (draftMessages.isNotEmpty) {
        await conversationsNotifier.updateConversationMessages(
          effectiveOwner,
          draftMessages,
        );
        if (!_turnRuntimeOwnerLease.isConversationCurrent(effectiveOwner)) {
          return _restoreQueuedMessageForRetry(
            queuedMessage,
            effectiveOwner,
            fromQueue: fromQueue,
          );
        }
      }
      conversationsState = ref.read(conversationsNotifierProvider);
      _activeInteractionOrigin = queuedMessage.origin;
      _activeRemoteDeviceId = queuedMessage.remoteDeviceId;
      final interactionGeneration = _beginInteractionGeneration();
      turnOwner = ChatTurnOwner(
        conversationId: effectiveOwner,
        interactionGeneration: interactionGeneration,
      );
      _productionReleaseApprovals.captureProof(
        generation: interactionGeneration,
        conversation: queuedMessage.conversationId == null
            ? currentConversation
            : _conversationForId(queuedMessage.conversationId!),
        submittedContent: queuedMessage.content,
      );
      _hiddenPrompt = null;
      _languageCode = languageCode;
      _isVoiceMode = isVoiceMode;
      _beginTurnDiffCapture(content);
      final temporalReferenceContext = TemporalContextBuilder.build(
        now: DateTime.now(),
        userInput: content,
      );
      _temporalReferenceContext = temporalReferenceContext;
      final shouldUseTemporalTool = temporalReferenceContext != null;
      currentConversation = conversationsState.currentConversation;
      conversationId = currentConversation?.id;
      final startedRuntime = await _startRuntimeTurn(
        generation: interactionGeneration,
        ownerConversationId: effectiveOwner,
        hidden: false,
        origin: queuedMessage.origin,
      );
      if (startedRuntime == null) {
        _clearActiveResponseForGeneration(interactionGeneration);
        if (!_turnRuntimeOwnerLease.isConversationCurrent(effectiveOwner)) {
          return _restoreQueuedMessageForRetry(
            queuedMessage,
            effectiveOwner,
            fromQueue: fromQueue,
          );
        }
        _syncQueuedChatMessagesState();
        return null;
      }
      turnOwner = startedRuntime;
      runtimeStarted = true;
      if (!_turnRuntimeOwnerLease.isConversationCurrent(effectiveOwner)) {
        _failRuntimeTurn(
          interactionGeneration,
          code: 'queue_owner_changed',
          message: 'The queued message owner changed before execution started.',
          exitCode: 130,
        );
        return _restoreQueuedMessageForRetry(
          queuedMessage,
          effectiveOwner,
          fromQueue: fromQueue,
        );
      }
      currentConversation = _conversationForId(effectiveOwner);
      conversationId = effectiveOwner;
      _resetGoalAutoContinueTrackerForConversation(conversationId);
      final shouldAutoEnterPlanning =
          !bypassPlanMode &&
          _shouldAutoEnterPlanningSession(currentConversation);
      if (shouldAutoEnterPlanning) {
        await conversationsNotifier.enterPlanningSession();
        if (!_isCurrentInteractionGeneration(interactionGeneration)) {
          _failRuntimeTurn(
            interactionGeneration,
            code: 'turn_cancelled_before_start',
            message: 'Cancelled while entering the planning session.',
            exitCode: 130,
          );
          return turnOwner;
        }
        currentConversation = _conversationForId(effectiveOwner);
      }
      currentConversation = _conversationForId(effectiveOwner);
      final ownerMessagesBeforeTurn = effectiveOwner == conversationId
          ? state.messages
          : currentConversation?.messages ?? const <Message>[];

      final isFirstTurn = state.messages.isEmpty;
      if (isFirstTurn) {
        _sessionMemoryContext = _memoryService.buildPromptContext(
          currentUserInput: content.trim(),
          currentConversationId: conversationId ?? '',
        );
        if (_sessionMemoryContext != null) {
          appLog('[Memory] Injecting context for new session');
        }
      }

      final userMessage = Message(
        id: _uuid.v4(),
        content: content.trim(),
        role: MessageRole.user,
        timestamp: DateTime.now(),
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
        originalImagePath: originalImagePath,
        originalImageMimeType: originalImageMimeType,
      ).withVideoAttachment(queuedMessage.video);

      if (!ref.mounted) return turnOwner;
      state = state.copyWith(
        messages: [...state.messages, userMessage],
        isLoading: true,
        error: null,
        goalAutoContinueCount: 0,
        goalAutoContinueBudget: 0,
        goalAutoContinueNotice: null,
      );
      _refreshContextTokenPressureFromState();
      _trackActiveResponse(
        interactionGeneration,
        effectiveOwner,
        turnUserMessage: userMessage,
        temporalReferenceContext: temporalReferenceContext,
        assistantModeOverride: bypassPlanMode ? AssistantMode.coding : null,
        ownerMessages: [...ownerMessagesBeforeTurn, userMessage],
      );
      _persistCurrentNonStreamingMessages();
      if (isFirstTurn) {
        _dispatchExternalToolHook(
          'SessionStart',
          userMessage: userMessage.content,
        );
      }
      _dispatchExternalToolHook(
        'UserPromptSubmit',
        userMessage: userMessage.content,
      );

      await conversationsNotifier.ensureCurrentPlanArtifactBackfilled(
        conversationId: effectiveOwner,
      );
      if (!_isCurrentInteractionGeneration(interactionGeneration)) {
        return turnOwner;
      }
      currentConversation = _conversationForId(effectiveOwner);
      await _ensureShortPromptExecutionContract(
        projectRoot: _projectRootForGeneration(interactionGeneration),
        currentConversation: currentConversation,
        userMessage: userMessage,
        conversationsNotifier: conversationsNotifier,
      );
      if (!_isCurrentInteractionGeneration(interactionGeneration)) {
        return turnOwner;
      }
      await _markPendingExecutionTaskStarted(
        conversation: _conversationForId(effectiveOwner),
        conversationsNotifier: conversationsNotifier,
        bypassPlanMode: bypassPlanMode,
        interactionGeneration: interactionGeneration,
      );
      if (!_isCurrentInteractionGeneration(interactionGeneration)) {
        return turnOwner;
      }
      currentConversation = _conversationForId(effectiveOwner);
      await _capturePrimaryTurnRoute(
        owner: startedRuntime,
        conversation: currentConversation,
        bypassPlanMode: bypassPlanMode,
      );
      if (!_isCurrentInteractionGeneration(interactionGeneration)) {
        return turnOwner;
      }
      final shouldInterceptForPlanMode =
          !bypassPlanMode &&
          (currentConversation?.isPlanningSession ?? false) &&
          currentConversation?.workspaceMode == WorkspaceMode.coding;

      if (shouldInterceptForPlanMode) {
        _denyTools(interactionGeneration);
        await _messagePersistence.persistCurrentMessages(
          state.messages.where((message) => !message.isStreaming).toList(),
        );
        if (currentConversation == null) {
          state = state.copyWith(isLoading: false);
          _failRuntimeTurn(
            interactionGeneration,
            code: 'conversation_unavailable',
            message: 'No conversation is available for Plan Mode execution.',
          );
          return turnOwner;
        }
        currentConversation = ref
            .read(conversationsNotifierProvider)
            .currentConversation;
        conversationId = currentConversation?.id;
        if (currentConversation == null) {
          state = state.copyWith(isLoading: false);
          _failRuntimeTurn(
            interactionGeneration,
            code: 'conversation_unavailable',
            message: 'No conversation is available for Plan Mode execution.',
          );
          return turnOwner;
        }
        await _runPlanProposalFlow(
          currentConversation: currentConversation,
          languageCode: languageCode,
          interactionGeneration: interactionGeneration,
        );
        return turnOwner;
      }

      if (currentConversation != null &&
          currentConversation.workspaceMode == WorkspaceMode.chat &&
          currentConversation.participants.isNotEmpty) {
        _onSendStarted();
        _assistantModeOverride = bypassPlanMode ? AssistantMode.coding : null;
        try {
          await _sendWithParticipantTurns(
            interactionGeneration: interactionGeneration,
            currentConversation: currentConversation,
            conversationsNotifier: conversationsNotifier,
          );
        } finally {
          _assistantModeOverride = null;
          _activeInteractionOrigin = ChatInteractionOrigin.local;
          _activeRemoteDeviceId = null;
        }
        return turnOwner;
      }

      final assistantMessage = Message(
        id: _uuid.v4(),
        content: '',
        role: MessageRole.assistant,
        timestamp: DateTime.now(),
        isStreaming: true,
      );

      if (!ref.mounted) return turnOwner;
      if (_isActiveResponseDetachedForGeneration(interactionGeneration)) {
        final activeMessages =
            _activeResponseMessagesForGeneration(interactionGeneration) ??
            const <Message>[];
        _cacheActiveResponseMessagesForGeneration(interactionGeneration, [
          ...activeMessages,
          assistantMessage,
        ]);
      } else {
        state = state.copyWith(messages: [...state.messages, assistantMessage]);
        _cacheActiveResponseMessagesForGeneration(
          interactionGeneration,
          state.messages,
        );
      }

      if (!_responseMetadata.start(turnOwner)) {
        throw StateError('Response metadata state could not be initialized.');
      }

      _onSendStarted();

      _assistantModeOverride = bypassPlanMode ? AssistantMode.coding : null;

      try {
        if (_mcpToolService != null &&
            (_settings.mcpEnabled || shouldUseTemporalTool) &&
            _supportsToolAwareRequests) {
          final mode = _settings.mcpEnabled ? 'MCP' : 'TemporalOnly';
          appLog('[Tool] Sending in tool-aware mode ($mode)');
          await _sendWithTools(interactionGeneration: interactionGeneration);
        } else {
          appLog(
            '[Tool] Sending in normal mode (mcpToolService: ${_mcpToolService != null}, enabled: ${_settings.mcpEnabled})',
          );
          _denyTools(interactionGeneration);
          await _sendWithoutTools(interactionGeneration: interactionGeneration);
        }
      } finally {
        _assistantModeOverride = null;
        _activeInteractionOrigin = ChatInteractionOrigin.local;
        _activeRemoteDeviceId = null;
      }
      return turnOwner;
    } catch (error) {
      final failedOwner = turnOwner;
      turnOwner = null;
      if (runtimeStarted && failedOwner != null) {
        _failRuntimeTurn(
          failedOwner.interactionGeneration,
          code: 'message_send_failed',
          message: error.toString(),
        );
      }
      if (failedOwner != null) _turnToolResults.dispose(failedOwner);
      final owner = failedOwner?.conversationId ?? queuedMessage.conversationId;
      if (owner != null) _routeRuntimeStartFailure(owner, error.toString());
      _assistantModeOverride = null;
      _activeInteractionOrigin = ChatInteractionOrigin.local;
      _activeRemoteDeviceId = null;
      appLog('[ChatNotifier] Message send failed: $error');
      return null;
    }
  }

  void removeQueuedMessage(String id) {
    if (_removePendingTurnSteering(id)) return;
    if (!_queuedChatMessages.remove(id)) return;
    _syncQueuedChatMessagesState();
    appLog(
      '[ChatNotifier] Removed queued user message '
      '(${_queuedChatMessages.length} remaining)',
    );
  }

  void _syncQueuedChatMessagesState() {
    if (!ref.mounted) return;
    state = state.copyWith(
      queuedMessages: _queuedChatMessages.forThread(conversationId),
    );
  }

  Future<ChatTurnOwner?> _restoreQueuedMessageForRetry(
    QueuedChatMessage message,
    String owner, {
    required bool fromQueue,
  }) {
    final receipt = _queuedChatMessages.restoreFirstForThread(message, owner);
    _syncQueuedChatMessagesState();
    unawaited(_drainQueuedChatMessagesForThreadIfIdle(owner));
    return fromQueue ? Future<ChatTurnOwner?>.value() : receipt;
  }

  bool _canDrainQueuedMessagesForThread(String ownerConversationId) =>
      ref.mounted &&
      ownerConversationId.isNotEmpty &&
      ownerConversationId == conversationId &&
      !state.isLoading &&
      _activeResponseGenerationForConversation(ownerConversationId) == null;

  Future<void> _drainQueuedChatMessagesForThreadIfIdle(String owner) async {
    if (!_canDrainQueuedMessagesForThread(owner) ||
        !_queuedChatMessages.beginDrain(owner)) {
      return;
    }
    try {
      await _executionRuntime.ownershipSettled;
      if (!_canDrainQueuedMessagesForThread(owner) ||
          _queuedChatMessages.pendingFor(owner) == 0) {
        return;
      }
      while (_canDrainQueuedMessagesForThread(owner)) {
        final queuedMessage = _queuedChatMessages.takeNextForThread(owner);
        if (queuedMessage == null) break;
        _syncQueuedChatMessagesState();
        appLog(
          '[ChatNotifier] Sending queued user message '
          '(${_queuedChatMessages.length} remaining)',
        );
        try {
          final turnOwner = await _sendMessageNow(
            queuedMessage,
            fromQueue: true,
          );
          if (_queuedChatMessages.contains(queuedMessage)) break;
          _queuedChatMessages.completeTurnOwner(queuedMessage, turnOwner);
        } catch (error) {
          _queuedChatMessages.completeTurnOwner(queuedMessage, null);
          _routeRuntimeStartFailure(owner, error.toString());
          appLog('[ChatNotifier] Queued message failed: $error');
          break;
        }
      }
    } finally {
      _queuedChatMessages.endDrain(owner);
    }
  }

  Future<void> generateWorkflowProposal({String languageCode = 'en'}) async {
    if (!ref.mounted || state.isGeneratingWorkflowProposal) return;

    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) return;

    // Routed, not assigned: drafting outlives the user's attention, and a bare
    // `state = state.copyWith(...)` after the await lands the plan on whichever
    // thread is visible when the model returns rather than the one that asked.
    final draftingThread = currentConversation.id;
    _routeThreadState(
      draftingThread,
      (s) => s.copyWith(
        isGeneratingWorkflowProposal: true,
        workflowProposalDraft: null,
        workflowProposalError: null,
        pendingWorkflowDecision: null,
      ),
    );

    try {
      final researchContext = await _buildPlanningResearchContext(
        currentConversation: currentConversation,
      );
      final proposal = await _requestWorkflowProposal(
        currentConversation: currentConversation,
        languageCode: languageCode,
        researchContext: researchContext,
      );
      if (!ref.mounted) return;

      _routeThreadState(
        draftingThread,
        (s) => s.copyWith(
          isGeneratingWorkflowProposal: false,
          workflowProposalDraft: proposal,
          workflowProposalError: null,
        ),
      );
    } on _WorkflowProposalCancelled {
      if (!ref.mounted) return;
      _routeThreadState(
        draftingThread,
        (s) => s.copyWith(
          isGeneratingWorkflowProposal: false,
          workflowProposalDraft: null,
          workflowProposalError: null,
          pendingWorkflowDecision: null,
        ),
      );
    } catch (error) {
      if (!ref.mounted) return;
      _routeThreadState(
        draftingThread,
        (s) => s.copyWith(
          isGeneratingWorkflowProposal: false,
          workflowProposalDraft: null,
          workflowProposalError: error.toString(),
        ),
      );
    }
  }

  Future<ConversationGoalSuggestion> suggestCurrentGoal({
    String languageCode = 'en',
    String? pendingUserMessage,
    String? clarificationQuestion,
    String? clarificationAnswer,
  }) async {
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null ||
        !ConversationGoalSuggestionService.hasUsefulContext(
          currentConversation,
          pendingUserMessage: pendingUserMessage,
          clarificationQuestion: clarificationQuestion,
          clarificationAnswer: clarificationAnswer,
        )) {
      return const ConversationGoalSuggestion.needsClarification();
    }

    try {
      final result = await _secondaryCompletionRouter.run(
        primaryDataSource: _dataSource,
        route: _settings._goalSuggestionCompletionRoute,
        operation: (dataSource, model) => dataSource.createChatCompletion(
          messages: ConversationGoalSuggestionService.buildMessages(
            conversation: currentConversation,
            languageCode: languageCode,
            pendingUserMessage: pendingUserMessage,
            clarificationQuestion: clarificationQuestion,
            clarificationAnswer: clarificationAnswer,
          ),
          model: model,
          temperature: 0.1,
          maxTokens: SecondaryCallBudget.resolve(_settings.maxTokens, 600),
        ),
      );
      final suggestion = ConversationGoalSuggestionService.parse(
        result.content,
      );
      if (suggestion != null) {
        final validatedSuggestion =
            ConversationGoalSuggestionService.validateSuggestion(
              suggestion: suggestion,
              conversation: currentConversation,
              pendingUserMessage: pendingUserMessage,
              clarificationQuestion: clarificationQuestion,
              clarificationAnswer: clarificationAnswer,
            );
        appLog(
          '[Goal] Suggested goal response: '
          '${ConversationGoalSuggestionService.encodeForDebug(validatedSuggestion)}',
        );
        return validatedSuggestion;
      }
      appLog('[Goal] Failed to parse goal suggestion response.');
    } catch (error) {
      appLog('[Goal] Goal suggestion failed: $error');
    }

    return const ConversationGoalSuggestion.needsClarification();
  }

  Future<void> generatePlanProposal({String languageCode = 'en'}) async {
    await generatePlanProposalWithContext(languageCode: languageCode);
  }

  List<ToolResultInfo> takeLatestToolResults(ChatTurnOwner owner) =>
      _turnToolResults.takeAndDispose(owner);

  String? takeLatestHiddenAssistantResponse(ChatTurnOwner? owner) =>
      owner == null ? null : _hiddenAssistantEvidence.take(owner);

  void _recordHiddenEvidence(ChatTurnOwner owner, String? response) =>
      _hiddenAssistantEvidence.record(
        owner,
        response,
        evidenceScore: _terminalToolResponsePolicy.hiddenAssistantEvidenceScore,
      );

  void _appendRecoveredAssistantResponse(
    String response, {
    int? interactionGeneration,
  }) {
    final candidate = response.trim();
    final generation = interactionGeneration ?? _interactionGeneration;
    final activeMessages =
        _activeResponseMessagesForGeneration(generation) ?? state.messages;
    if (candidate.isEmpty || activeMessages.isEmpty) {
      return;
    }

    final existingContent = activeMessages.last.content;
    if (existingContent.contains(candidate)) {
      return;
    }
    if (existingContent.isNotEmpty && !existingContent.endsWith('\n')) {
      _appendToLastMessageForGeneration(generation, '\n', scanForTools: false);
    }
    _appendToLastMessageForGeneration(
      generation,
      candidate,
      scanForTools: false,
    );
  }

  Future<void> generatePlanProposalWithContext({
    String languageCode = 'en',
    String? additionalPlanningContext,
  }) async {
    if (!ref.mounted ||
        state.isGeneratingWorkflowProposal ||
        state.isGeneratingTaskProposal) {
      return;
    }

    var currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) return;
    final ownerConversationId = currentConversation.id;
    conversationId = ownerConversationId;
    final interactionGeneration = _beginInteractionGeneration();
    _trackActiveResponse(interactionGeneration, ownerConversationId);
    if (await _startRuntimeTurn(
          generation: interactionGeneration,
          ownerConversationId: ownerConversationId,
          hidden: false,
          origin: ChatInteractionOrigin.local,
        ) ==
        null) {
      _clearActiveResponseForGeneration(interactionGeneration);
      return;
    }
    currentConversation = _conversationForId(ownerConversationId);
    if (currentConversation == null) {
      _failRuntimeTurn(
        interactionGeneration,
        code: 'conversation_unavailable',
        message: 'The selected conversation is no longer available.',
        exitCode: 65,
      );
      return;
    }
    _denyTools(interactionGeneration);

    await _runPlanProposalFlow(
      currentConversation: currentConversation,
      languageCode: languageCode,
      interactionGeneration: interactionGeneration,
      additionalPlanningContext: additionalPlanningContext,
    );
  }

  Future<void> generateTaskProposal({String languageCode = 'en'}) async {
    if (!ref.mounted || state.isGeneratingTaskProposal) return;

    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null ||
        !currentConversation.effectiveWorkflowSpec.hasContent) {
      return;
    }

    // Routed for the same reason as generateWorkflowProposal above: the draft
    // belongs to the thread that asked, not to whichever one is visible when
    // the model returns.
    final draftingThread = currentConversation.id;
    _routeThreadState(
      draftingThread,
      (s) => s.copyWith(
        isGeneratingTaskProposal: true,
        taskProposalDraft: null,
        taskProposalError: null,
      ),
    );

    try {
      final researchContext = await _buildPlanningResearchContext(
        currentConversation: currentConversation,
      );
      final proposal = await _requestTaskProposal(
        currentConversation: currentConversation,
        languageCode: languageCode,
        researchContext: researchContext,
      );
      if (!ref.mounted) return;

      _routeThreadState(
        draftingThread,
        (s) => s.copyWith(
          isGeneratingTaskProposal: false,
          taskProposalDraft: proposal,
          taskProposalError: null,
        ),
      );
    } catch (error) {
      if (!ref.mounted) return;
      _routeThreadState(
        draftingThread,
        (s) => s.copyWith(
          isGeneratingTaskProposal: false,
          taskProposalDraft: null,
          taskProposalError: error.toString(),
        ),
      );
    }
  }

  void dismissWorkflowProposal() {
    if (!ref.mounted) return;
    state = state.copyWith(
      workflowProposalDraft: null,
      workflowProposalError: null,
      isGeneratingWorkflowProposal: false,
      pendingWorkflowDecision: null,
    );
  }

  void dismissPlanProposal() {
    dismissWorkflowProposal();
    dismissTaskProposal();
  }

  void dismissTaskProposal() {
    if (!ref.mounted) return;
    state = state.copyWith(
      taskProposalDraft: null,
      taskProposalError: null,
      isGeneratingTaskProposal: false,
    );
  }

  Future<WorkflowPlanningDecisionAnswer?> requestWorkflowDecision({
    required WorkflowPlanningDecision decision,
  }) {
    final completer = Completer<WorkflowPlanningDecisionAnswer?>();
    final pending = PendingWorkflowDecision(
      id: const Uuid().v4(),
      decision: decision,
      completer: completer,
    );
    // Route to the drafting thread so a visible-thread transition cannot clear
    // an unreachable decision and leave its background turn alive.
    _routeApproval(
      (s) => s.copyWith(
        isLoading: false,
        isGeneratingWorkflowProposal: false,
        isGeneratingTaskProposal: false,
        pendingWorkflowDecision: pending,
      ),
    );
    _runtimeEvents.emitRuntimeQuestionRequired(
      _runtimeEventGeneration,
      CavernoRuntimeQuestionRequest(
        id: pending.id,
        prompt: decision.question,
        options: decision.options
            .map((option) => option.label)
            .toList(growable: false),
      ),
    );
    return completer.future;
  }

  void resolveWorkflowDecision({
    required String id,
    WorkflowPlanningDecisionAnswer? answer,
  }) {
    final pending = state.pendingWorkflowDecision;
    if (pending == null || pending.id != id) return;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(answer);
    }
    state = state.copyWith(pendingWorkflowDecision: null);
  }

  Future<void> _runPlanProposalFlow({
    required Conversation currentConversation,
    required String languageCode,
    required int interactionGeneration,
    String? additionalPlanningContext,
  }) async {
    if (!ref.mounted) return;

    _routeThreadState(
      currentConversation.id,
      (s) => s.copyWith(
        isLoading: true,
        error: null,
        isGeneratingWorkflowProposal: true,
        isGeneratingTaskProposal: true,
        workflowProposalDraft: null,
        taskProposalDraft: null,
        workflowProposalError: null,
        taskProposalError: null,
        pendingWorkflowDecision: null,
      ),
    );

    final researchContext = await _buildPlanningResearchContext(
      currentConversation: currentConversation,
      interactionGeneration: interactionGeneration,
    );

    WorkflowProposalDraft? workflowDraft;
    try {
      workflowDraft =
          await _runWithLlmSessionLogContextForGeneration<
            Future<WorkflowProposalDraft>
          >(
            interactionGeneration,
            // Plan drafting raises its decision prompt several frames down, so
            // it needs the same thread identity tool dispatch carries.
            () => TurnGeneration.runScoped(
              interactionGeneration,
              () => TurnThread.runScoped(
                currentConversation.id,
                () => _requestWorkflowProposal(
                  currentConversation: currentConversation,
                  languageCode: languageCode,
                  researchContext: researchContext,
                  additionalPlanningContext: additionalPlanningContext,
                ),
              ),
            ),
          );
      if (!ref.mounted) return;
      _routeThreadState(
        currentConversation.id,
        (s) => s.copyWith(
          isGeneratingWorkflowProposal: false,
          workflowProposalDraft: workflowDraft,
          workflowProposalError: null,
        ),
      );
      appLog('[Workflow] Workflow proposal ready');
      await _persistPlanArtifactDraft(
        workflowStage: workflowDraft.workflowStage,
        workflowSpec: workflowDraft.workflowSpec,
        planConversationId: currentConversation.id,
      );
      appLog('[Workflow] Workflow plan artifact draft persisted');
    } on _WorkflowProposalCancelled {
      if (!ref.mounted) return;
      _routeThreadState(
        currentConversation.id,
        (s) => s.copyWith(
          isLoading: false,
          isGeneratingWorkflowProposal: false,
          isGeneratingTaskProposal: false,
          workflowProposalDraft: null,
          taskProposalDraft: null,
          workflowProposalError: null,
          taskProposalError: null,
          pendingWorkflowDecision: null,
        ),
      );
      _failRuntimeTurn(
        interactionGeneration,
        code: 'workflow_proposal_cancelled',
        message: 'Workflow proposal generation was cancelled.',
        exitCode: 130,
      );
      return;
    } catch (error) {
      if (!ref.mounted) return;
      _routeThreadState(
        currentConversation.id,
        (s) => s.copyWith(
          isLoading: false,
          isGeneratingWorkflowProposal: false,
          isGeneratingTaskProposal: false,
          workflowProposalDraft: null,
          taskProposalDraft: null,
          workflowProposalError: error.toString(),
          pendingWorkflowDecision: null,
        ),
      );
      _failRuntimeTurn(
        interactionGeneration,
        code: 'workflow_proposal_failed',
        message: error.toString(),
      );
      return;
    }

    // Promotion does not survive capture by the closure below.
    final resolvedWorkflowDraft = workflowDraft;

    try {
      final taskDraft = await _runWithLlmSessionLogContextForGeneration(
        interactionGeneration,
        () => _requestTaskProposal(
          currentConversation: currentConversation,
          languageCode: languageCode,
          researchContext: researchContext,
          workflowStageOverride: resolvedWorkflowDraft.workflowStage,
          workflowSpecOverride: resolvedWorkflowDraft.workflowSpec,
          additionalPlanningContext: additionalPlanningContext,
        ),
      );
      if (!ref.mounted) return;
      appLog('[Workflow] Task proposal ready');
      await _persistPlanArtifactDraft(
        workflowStage: resolvedWorkflowDraft.workflowStage,
        workflowSpec: resolvedWorkflowDraft.workflowSpec,
        tasks: taskDraft.tasks,
        planConversationId: currentConversation.id,
      );
      appLog('[Workflow] Task plan artifact draft persisted');
      if (!ref.mounted) return;
      _routeThreadState(
        currentConversation.id,
        (s) => s.copyWith(
          isLoading: false,
          isGeneratingTaskProposal: false,
          taskProposalDraft: taskDraft,
          taskProposalError: null,
        ),
      );
      _runtimeEvents.emitRuntimeWorkflowTransition(
        generation: interactionGeneration,
        stage: taskDraft.tasks.isEmpty ? 'tasks' : 'implement',
        taskStatus: 'proposal_ready',
      );
      final planMarkdown = ConversationPlanDocumentBuilder.build(
        workflowStage: resolvedWorkflowDraft.workflowStage,
        workflowSpec: resolvedWorkflowDraft.workflowSpec,
        tasks: taskDraft.tasks,
      );
      _completeRuntimeTurn(
        interactionGeneration,
        content: planMarkdown,
        exitReason: ChatNotifierTurnExit.planDraftedExitReason,
      );
    } catch (error) {
      if (!ref.mounted) return;
      _routeThreadState(
        currentConversation.id,
        (s) => s.copyWith(
          isLoading: false,
          isGeneratingTaskProposal: false,
          taskProposalDraft: null,
          taskProposalError: error.toString(),
        ),
      );
      _failRuntimeTurn(
        interactionGeneration,
        code: 'task_proposal_failed',
        message: error.toString(),
      );
    }
  }

  Future<void> _persistPlanArtifactDraft({
    required ConversationWorkflowStage workflowStage,
    required ConversationWorkflowSpec workflowSpec,
    required String planConversationId,
    List<ConversationWorkflowTask> tasks = const [],
  }) async {
    final planConversation = _conversationForId(planConversationId);
    if (planConversation == null) {
      return;
    }

    final existingArtifact =
        planConversation.planArtifact ?? const ConversationPlanArtifact();
    final markdown = ConversationPlanDocumentBuilder.build(
      workflowStage: workflowStage,
      workflowSpec: workflowSpec,
      tasks: tasks,
    );
    final updatedAt = DateTime.now();
    final nextArtifact = existingArtifact
        .copyWith(draftMarkdown: markdown, updatedAt: updatedAt)
        .recordRevision(
          markdown: markdown,
          kind: ConversationPlanRevisionKind.draft,
          label: 'Generated draft plan document',
          createdAt: updatedAt,
        );

    await ref
        .read(conversationsNotifierProvider.notifier)
        .updateCurrentPlanArtifact(
          planArtifact: nextArtifact.hasContent ? nextArtifact : null,
          clearPlanArtifact: !nextArtifact.hasContent,
          conversationId: planConversationId,
        );
  }

  Future<void> _sendWithoutTools({
    bool allowContextRetry = true,
    int? interactionGeneration,
    HiddenPromptLaunchOptions? options,
  }) async {
    if (!ref.mounted) return;
    final generation = interactionGeneration ?? _interactionGeneration;
    final turnOwner = _turnOwnerForGeneration(generation);
    if (turnOwner == null) {
      await _handleTurnOwnerSnapshotUnavailable(generation);
      return;
    }
    try {
      _runWithLlmSessionLogContextForGeneration(generation, () {
        final stream =
            (options?.dataSource ?? _primaryDataSourceForGeneration(generation))
                .streamChatCompletion(
                  messages: _prepareMessagesForLLM(
                    interactionGeneration: generation,
                  ),
                  model:
                      options?.model ?? _primaryModelForGeneration(generation),
                  temperature: _primaryAssistantTemperatureForGeneration(
                    generation,
                  ),
                  maxTokens: _settings.maxTokens,
                );

        _turnStream.listen(
          turnOwner,
          stream,
          onChunk: (chunk) {
            if (!_isCurrentInteractionGeneration(generation)) return;
            _appendToLastMessageForGeneration(generation, chunk);
          },
          onError: (error, stackTrace) {
            if (!_isCurrentInteractionGeneration(generation)) return;
            appLog(
              '[ChatNotifier] _sendWithoutTools stream onError: ${error.runtimeType}: $error',
            );
            appLog('[ChatNotifier] stackTrace: $stackTrace');
            if (allowContextRetry) {
              unawaited(
                _retryAfterContextLengthError(
                  error,
                  () => _sendWithoutTools(
                    allowContextRetry: false,
                    interactionGeneration: generation,
                    options: options,
                  ),
                  owner: turnOwner,
                ).then((retried) {
                  if (!_isCurrentInteractionGeneration(generation)) return;
                  if (!retried) {
                    unawaited(_handleError(error, owner: turnOwner));
                  }
                }),
              );
              return;
            }
            unawaited(_handleError(error, owner: turnOwner));
          },
          onDone: () =>
              _finishStreamedCompletionInBackground(turnOwner, stream.terminal),
        );
      }, usageRole: options?.usageRole ?? ModelUsageRole.chat);
    } catch (e, stackTrace) {
      appLog('[ChatNotifier] _sendWithoutTools catch: ${e.runtimeType}: $e');
      appLog('[ChatNotifier] stackTrace: $stackTrace');
      if (allowContextRetry &&
          await _retryAfterContextLengthError(
            e,
            () => _sendWithoutTools(
              allowContextRetry: false,
              interactionGeneration: generation,
              options: options,
            ),
            owner: turnOwner,
          )) {
        return;
      }
      if (!_isCurrentInteractionGeneration(generation)) return;
      await _handleError(e, owner: turnOwner);
    }
  }

  Future<void> _sendWithEmbeddedToolTagFallback({
    required List<Map<String, dynamic>> toolDefinitions,
    bool allowContextRetry = true,
    required int interactionGeneration,
  }) async {
    if (!ref.mounted) return;
    final turnOwner = _turnOwnerForGeneration(interactionGeneration);
    if (turnOwner == null) {
      await _handleTurnOwnerSnapshotUnavailable(interactionGeneration);
      return;
    }
    _resetStreamingAssistantForRetry(turnOwner);
    try {
      _runWithLlmSessionLogContextForGeneration(interactionGeneration, () {
        final messages = _prepareMessagesForLLM(
          toolDefinitionsOverride: toolDefinitions,
          interactionGeneration: interactionGeneration,
        );
        messages.add(_embeddedToolTagFallbackInstructionMessage());

        final stream = _primaryDataSourceForGeneration(interactionGeneration)
            .streamChatCompletion(
              messages: messages,
              model: _primaryModelForGeneration(interactionGeneration),
              temperature: _primaryAgenticTemperatureForGeneration(
                interactionGeneration,
              ),
              maxTokens: _settings.maxTokens,
            );

        _turnStream.listen(
          turnOwner,
          stream,
          onChunk: (chunk) {
            if (!_isCurrentInteractionGeneration(interactionGeneration)) {
              return;
            }
            _appendToLastMessageForGeneration(interactionGeneration, chunk);
          },
          onError: (error, stackTrace) {
            if (!_isCurrentInteractionGeneration(interactionGeneration)) {
              return;
            }
            appLog(
              '[Tool] Embedded tool-tag fallback stream error: '
              '${error.runtimeType}: $error',
            );
            appLog('[Tool] stackTrace: $stackTrace');
            if (allowContextRetry) {
              unawaited(
                _retryAfterContextLengthError(
                  error,
                  () => _sendWithEmbeddedToolTagFallback(
                    toolDefinitions: toolDefinitions,
                    allowContextRetry: false,
                    interactionGeneration: interactionGeneration,
                  ),
                  owner: turnOwner,
                ).then((retried) {
                  if (!_isCurrentInteractionGeneration(interactionGeneration)) {
                    return;
                  }
                  if (!retried) {
                    unawaited(_handleError(error, owner: turnOwner));
                  }
                }),
              );
              return;
            }
            unawaited(_handleError(error, owner: turnOwner));
          },
          onDone: () =>
              _finishStreamedCompletionInBackground(turnOwner, stream.terminal),
        );
      });
    } catch (error, stackTrace) {
      appLog(
        '[Tool] Embedded tool-tag fallback setup error: '
        '${error.runtimeType}: $error',
      );
      appLog('[Tool] stackTrace: $stackTrace');
      if (allowContextRetry &&
          await _retryAfterContextLengthError(
            error,
            () => _sendWithEmbeddedToolTagFallback(
              toolDefinitions: toolDefinitions,
              allowContextRetry: false,
              interactionGeneration: interactionGeneration,
            ),
            owner: turnOwner,
          )) {
        return;
      }
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      await _handleError(error, owner: turnOwner);
    }
  }

  Message _embeddedToolTagFallbackInstructionMessage() {
    return Message(
      id:
          'system_embedded_tool_tag_fallback_'
          '${DateTime.now().millisecondsSinceEpoch}',
      content:
          'The previous native tool-call stream failed before any trusted tool '
          'result was available. For this retry, use Caverno textual tool-call '
          'tags instead of native OpenAI tool calls. When a tool is needed, '
          'emit exactly one complete '
          '<tool_call>{"name":"tool_name","arguments":{...}}</tool_call> '
          'block with valid JSON and no surrounding prose. The application '
          'will execute that tag and provide trusted results. Do not describe '
          'future file, command, browser, or git actions instead of emitting '
          'the required tool-call tag.',
      role: MessageRole.system,
      timestamp: DateTime.now(),
    );
  }

  Future<bool> _retryAfterContextLengthError(
    Object error,
    Future<void> Function() retry, {
    required ChatTurnOwner owner,
  }) => TurnContextRetryCoordinator.retry(
    error: error,
    ownerMessages: _activeResponseRegistry.messagesForOwner(owner),
    ownerConversation: _conversationForId(owner.conversationId),
    markForceCompaction: () =>
        _modelSwitchHandoffs.requestPromptCompaction(owner),
    applyReset: (messages) =>
        _applyStreamingAssistantRetryReset(owner, messages),
    sendAgain: retry,
  );

  void _resetStreamingAssistantForRetry(ChatTurnOwner owner) {
    if (!ref.mounted) return;
    TurnContextRetryCoordinator.reset(
      ownerMessages: _activeResponseRegistry.messagesForOwner(owner),
      apply: (messages) => _applyStreamingAssistantRetryReset(owner, messages),
    );
  }

  void _applyStreamingAssistantRetryReset(
    ChatTurnOwner owner,
    List<Message> messages,
  ) {
    _activeResponseRegistry.cacheMessagesForOwner(owner, messages);
    if (conversationId == owner.conversationId) {
      state = state.copyWith(messages: messages, error: null);
    }
  }

  bool _hasCompactablePromptHistory(ChatTurnOwner owner) =>
      TurnContextRetryCoordinator.hasCompactableHistory(
        ownerMessages: _activeResponseRegistry.messagesForOwner(owner),
        ownerConversation: _conversationForId(owner.conversationId),
      );

  Future<ChatCompletionResult> _createToolResultCompletionWithContextRetry({
    required String logLabel,
    required int interactionGeneration,
    required List<Message> Function(bool forceCompaction) buildMessages,
    required List<ToolResultInfo> toolResults,
    required String? assistantContent,
    required List<Map<String, dynamic>> tools,
  }) async {
    final observationOwner = _turnOwnerForGeneration(interactionGeneration);
    final protectedPaths = const ContextSurgeryProtectedPathPolicy()
        .protectedPathsFor(_conversationForGeneration(interactionGeneration));
    Future<ChatCompletionResult> send({
      required bool forceCompaction,
      required ToolResultPromptBudgetMode budgetMode,
    }) async {
      final contentBeforeRequest =
          _lastMessageContentForGeneration(interactionGeneration) ?? '';
      final contentWithoutPlaceholder = contentBeforeRequest.endsWith('<think>')
          ? contentBeforeRequest.substring(
              0,
              contentBeforeRequest.length - '<think>'.length,
            )
          : contentBeforeRequest;
      var isStreamingThinking = false;
      var finishedStreamingThinking = false;
      final result = await _runWithLlmSessionLogContextForGeneration(
        interactionGeneration,
        requestLabel: logLabel,
        () async {
          final dataSource = _primaryDataSourceForGeneration(
            interactionGeneration,
          );
          final requestMessages = buildMessages(forceCompaction);
          final budgetedToolResults = _budgetToolResultsForPrompt(
            toolResults,
            mode: budgetMode,
            protectedPaths: protectedPaths,
            observationOwner: observationOwner,
          );
          final streamingResult =
              dataSource is StreamingToolResultsChatDataSource
              ? (dataSource as StreamingToolResultsChatDataSource)
                    .streamChatCompletionWithToolResults(
                      messages: requestMessages,
                      toolResults: budgetedToolResults,
                      assistantContent: assistantContent,
                      tools: tools,
                      model: _primaryModelForGeneration(interactionGeneration),
                      temperature: _primaryAgenticTemperatureForGeneration(
                        interactionGeneration,
                      ),
                      maxTokens: _settings.maxTokens,
                    )
              : StreamWithToolsResult(
                  stream: const Stream.empty(),
                  completion: dataSource.createChatCompletionWithToolResults(
                    messages: requestMessages,
                    toolResults: budgetedToolResults,
                    assistantContent: assistantContent,
                    tools: tools,
                    model: _primaryModelForGeneration(interactionGeneration),
                    temperature: _primaryAgenticTemperatureForGeneration(
                      interactionGeneration,
                    ),
                    maxTokens: _settings.maxTokens,
                  ),
                );
          try {
            await for (final chunk in streamingResult.stream) {
              if (!_isCurrentInteractionGeneration(interactionGeneration) ||
                  finishedStreamingThinking) {
                continue;
              }
              var reasoningChunk = chunk;
              if (!isStreamingThinking) {
                final start = reasoningChunk.indexOf('<think>');
                if (start < 0) continue;
                reasoningChunk = reasoningChunk.substring(start);
                isStreamingThinking = true;
                _replaceLastMessageContentForGeneration(
                  interactionGeneration,
                  contentWithoutPlaceholder,
                );
              }
              final end = reasoningChunk.indexOf('</think>');
              if (end >= 0) {
                reasoningChunk = reasoningChunk.substring(
                  0,
                  end + '</think>'.length,
                );
                finishedStreamingThinking = true;
              }
              if (reasoningChunk.isNotEmpty) {
                _appendToLastMessageForGeneration(
                  interactionGeneration,
                  reasoningChunk,
                  scanForTools: false,
                );
              }
            }
            return await streamingResult.completion;
          } catch (_) {
            if (_isCurrentInteractionGeneration(interactionGeneration)) {
              _replaceLastMessageContentForGeneration(
                interactionGeneration,
                contentBeforeRequest,
              );
            }
            rethrow;
          }
        },
      );
      await _persistActiveResponseCheckpoint(interactionGeneration);
      final owner = _turnOwnerForGeneration(interactionGeneration);
      if (owner != null) {
        _responseMetadata.captureResult(owner, result);
      }
      return result;
    }

    try {
      return await send(
        forceCompaction: false,
        budgetMode: ToolResultPromptBudgetMode.normal,
      );
    } catch (error) {
      final retryOwner = _turnOwnerForGeneration(interactionGeneration);
      final hasCompactableHistory =
          retryOwner != null && _hasCompactablePromptHistory(retryOwner);
      final hasToolResultBudget = _hasAdditionalCompactToolResultBudget(
        toolResults,
        protectedPaths: protectedPaths,
        interactionGeneration: interactionGeneration,
      );
      if (!ConversationCompactionService.isContextLengthError(
            error.toString(),
          ) ||
          (!hasCompactableHistory && !hasToolResultBudget)) {
        rethrow;
      }
      appLog(
        '[Compaction] Retrying $logLabel after context-length error with '
        '${hasCompactableHistory ? 'forced prompt compaction' : 'unchanged prompt history'} '
        'and compact tool results',
      );
      return send(
        forceCompaction: hasCompactableHistory,
        budgetMode: ToolResultPromptBudgetMode.compact,
      );
    }
  }

  Future<void> _sendWithTools({
    bool allowContextRetry = true,
    int? interactionGeneration,
    Set<String>? allowedToolNames,
    bool replayVerifierImmediatelyAfterMutation = false,
    bool verifierOnlyContinuation = false,
  }) async {
    if (!ref.mounted) return;
    final generation = interactionGeneration ?? _interactionGeneration;
    final turnSnapshot = _turnOwnerSnapshotForGeneration(generation);
    final turnOwner = turnSnapshot?.owner;
    if (turnOwner == null) {
      await _handleTurnOwnerSnapshotUnavailable(generation);
      return;
    }
    var nativeToolFallbackDefinitions = const <Map<String, dynamic>>[];
    if (!_supportsToolAwareRequests) {
      appLog(
        '[Tool] Tool-aware requests are unavailable for the selected provider; '
        'falling back to normal mode',
      );
      _denyTools(generation);
      await _sendWithoutTools(
        allowContextRetry: allowContextRetry,
        interactionGeneration: generation,
      );
      return;
    }
    final fileTools = _mcpToolService?..beginChatFileTurnCheckpoint(turnOwner);
    try {
      final allTools = _toolDefinitionsAllowedBy(allowedToolNames);
      _activeResponseRegistry.setTools(
        generation,
        ToolDefinitionSearchService.toolNamesFromDefinitions(allTools).toSet(),
      );
      if (allTools.isEmpty) {
        // Fall back to normal streaming when no tools are available.
        await _sendWithoutTools(
          allowContextRetry: allowContextRetry,
          interactionGeneration: generation,
        );
        return;
      }
      _logAllowedToolDefinitions(allTools);

      final prefixStableToolLoop = _settings.enablePrefixStableToolLoop;
      final initialToolSelection = prefixStableToolLoop
          ? ToolDefinitionSearchSelection(
              toolSearchEnabled: false,
              toolDefinitions: allTools,
              selectedToolNames:
                  ToolDefinitionSearchService.toolNamesFromDefinitions(
                    allTools,
                  ),
            )
          : ToolDefinitionSearchService.buildInitialSelection(allTools);
      if (prefixStableToolLoop) {
        appLog(
          '[Tool] Prefix-stable tool loop enabled; using a fixed full tool list',
        );
      }
      if (initialToolSelection.toolSearchEnabled) {
        appLog(
          '[ToolSearch] Enabled dynamic tool loading. Initial tools: '
          '${ToolDefinitionSearchService.toolNamesFromDefinitions(initialToolSelection.toolDefinitions).toList()}',
        );
      }
      nativeToolFallbackDefinitions = initialToolSelection.toolDefinitions;
      final stableLoopToolDefinitions =
          prefixStableToolLoop || allowedToolNames != null
          ? initialToolSelection.toolDefinitions
          : null;
      final streamedMessages =
          _activeResponseMessagesForGeneration(generation) ?? state.messages;
      final streamedMessageIndex = streamedMessages.isEmpty
          ? -1
          : streamedMessages.length - 1;
      final streamedContentStart = streamedMessageIndex >= 0
          ? streamedMessages[streamedMessageIndex].content.length
          : 0;

      final streamResult = _runWithLlmSessionLogContextForGeneration(
        generation,
        requestLabel: 'turn opening request',
        () => _primaryDataSourceForGeneration(generation)
            .streamChatCompletionWithTools(
              messages: _prepareMessagesForLLM(
                toolDefinitionsOverride: initialToolSelection.toolDefinitions,
                interactionGeneration: generation,
              ),
              tools: initialToolSelection.toolDefinitions,
              model: _primaryModelForGeneration(generation),
              temperature: _primaryAgenticTemperatureForGeneration(generation),
              maxTokens: _settings.maxTokens,
            ),
      );

      await for (final chunk in streamResult.stream) {
        if (!_isCurrentInteractionGeneration(generation)) return;
        if (!ref.mounted) return;
        // Leaving the loop cancels this stream. Checked here because the loop
        // owns it directly: when the model answers without calling a tool,
        // this stream is the whole reply and no later request exists to carry
        // an interruption.
        if (_steeringRestartWanted(turnOwner)) {
          await _restartTurnForSteeringFromToolLoop(turnOwner);
          return;
        }
        _appendToLastMessageForGeneration(generation, chunk);
      }

      final result = await streamResult.completion;

      if (!_isCurrentInteractionGeneration(generation)) return;
      if (!ref.mounted) return;
      if (!_responseMetadata.captureResult(turnOwner, result)) return;
      await _persistActiveResponseCheckpoint(generation);
      appLog(
        '[Tool] LLM response - finishReason: ${result.finishReason}, hasToolCalls: ${result.hasToolCalls}',
      );
      appLog(
        '[Tool] toolCalls: ${result.toolCalls?.map((t) => t.name).toList()}',
      );

      if (result.hasToolCalls) {
        _lengthTruncatedToolCallIds = _truncationCasualties(result);
        await _executeToolCalls(
          result.toolCalls!,
          assistantContent: result.content.isNotEmpty ? result.content : null,
          toolSearchEnabled: initialToolSelection.toolSearchEnabled,
          selectedToolNames: initialToolSelection.selectedToolNames,
          stableToolDefinitions: stableLoopToolDefinitions,
          interactionGeneration: generation,
          replayVerifierImmediatelyAfterMutation:
              replayVerifierImmediatelyAfterMutation,
          verifierOnlyContinuation: verifierOnlyContinuation,
        );
      } else {
        final streamedAssistantContent = _extractAssistantStreamDelta(
          messageIndex: streamedMessageIndex,
          startingLength: streamedContentStart,
        );
        final recoveredSkillToolCall = _buildSkippedSkillLoadRecoveryToolCall(
          result: result,
          streamedAssistantContent: streamedAssistantContent,
          allTools: allTools,
          interactionGeneration: generation,
        );
        if (recoveredSkillToolCall != null) {
          appLog(
            '[Tool] Recovering skipped explicit skill load: '
            '${recoveredSkillToolCall.arguments}',
          );
          await _executeToolCalls(
            [recoveredSkillToolCall],
            assistantContent: result.content.isNotEmpty ? result.content : null,
            toolSearchEnabled: initialToolSelection.toolSearchEnabled,
            selectedToolNames: {
              ...initialToolSelection.selectedToolNames,
              'load_skill',
            },
            stableToolDefinitions: stableLoopToolDefinitions,
            interactionGeneration: generation,
            replayVerifierImmediatelyAfterMutation:
                replayVerifierImmediatelyAfterMutation,
            verifierOnlyContinuation: verifierOnlyContinuation,
          );
          return;
        }
        final recoveredBrowserToolCall =
            _buildSkippedBrowserActionRecoveryToolCall(
              result: result,
              allTools: allTools,
              interactionGeneration: generation,
            );
        if (recoveredBrowserToolCall != null) {
          appLog(
            '[Tool] Recovering skipped browser action with browser_snapshot',
          );
          _removeAssistantStreamDeltaForGeneration(
            generation: generation,
            messageIndex: streamedMessageIndex,
            startingLength: streamedContentStart,
          );
          await _executeToolCalls(
            [recoveredBrowserToolCall],
            toolSearchEnabled: initialToolSelection.toolSearchEnabled,
            selectedToolNames: {
              ...initialToolSelection.selectedToolNames,
              ..._claims.browserToolNamesFromDefinitions(allTools),
            },
            stableToolDefinitions: stableLoopToolDefinitions,
            interactionGeneration: generation,
            replayVerifierImmediatelyAfterMutation:
                replayVerifierImmediatelyAfterMutation,
            verifierOnlyContinuation: verifierOnlyContinuation,
          );
          return;
        }
        appLog('[Tool] No tool calls, response already streamed');
        final hiddenAssistantEvidence = streamedAssistantContent.isNotEmpty
            ? streamedAssistantContent
            : result.content;
        var hiddenAssistantEvidenceRecorded = false;
        void recordHiddenAssistantEvidenceOnce() {
          if (hiddenAssistantEvidenceRecorded) {
            return;
          }
          _recordHiddenEvidence(turnOwner, hiddenAssistantEvidence);
          hiddenAssistantEvidenceRecorded = true;
        }

        final codingContinuationRecoveryResult =
            await _requestCodingContinuationRecovery(
              candidateResponse: hiddenAssistantEvidence,
              tools: initialToolSelection.toolDefinitions,
              interactionGeneration: generation,
              requireContinuationRequest: true,
            );
        if (!_isCurrentInteractionGeneration(generation)) return;
        if (!ref.mounted) return;
        if (codingContinuationRecoveryResult != null) {
          recordHiddenAssistantEvidenceOnce();
          if (codingContinuationRecoveryResult.hasToolCalls) {
            appLog('[Tool] Coding continuation recovery requested tool calls');
            _removeAssistantStreamDeltaForGeneration(
              generation: generation,
              messageIndex: streamedMessageIndex,
              startingLength: streamedContentStart,
            );
            final recoveredToolNames = codingContinuationRecoveryResult
                .toolCalls!
                .map((toolCall) => toolCall.name);
            await _executeToolCalls(
              codingContinuationRecoveryResult.toolCalls!,
              assistantContent:
                  codingContinuationRecoveryResult.content.isNotEmpty
                  ? codingContinuationRecoveryResult.content
                  : hiddenAssistantEvidence,
              toolSearchEnabled: initialToolSelection.toolSearchEnabled,
              selectedToolNames: {
                ...initialToolSelection.selectedToolNames,
                ...recoveredToolNames,
              },
              stableToolDefinitions: stableLoopToolDefinitions,
              interactionGeneration: generation,
              replayVerifierImmediatelyAfterMutation:
                  replayVerifierImmediatelyAfterMutation,
              verifierOnlyContinuation: verifierOnlyContinuation,
            );
            return;
          }
          _recordHiddenEvidence(
            turnOwner,
            codingContinuationRecoveryResult.content,
          );
        }
        recordHiddenAssistantEvidenceOnce();
        final releaseRetryResult = await _requestBlockedProductionReleaseRetry(
          candidateResponse: hiddenAssistantEvidence,
          executedToolResults: _turnToolResults.all(turnOwner).toList(),
          batchToolResults: <ToolResultInfo>[],
          tools: initialToolSelection.toolDefinitions,
          interactionGeneration: generation,
        );
        if (!_isCurrentInteractionGeneration(generation)) return;
        if (!ref.mounted) return;
        if (releaseRetryResult != null && releaseRetryResult.hasToolCalls) {
          appLog('[ReleaseRetry] No-tool answer retry requested tool calls');
          _removeAssistantStreamDeltaForGeneration(
            generation: generation,
            messageIndex: streamedMessageIndex,
            startingLength: streamedContentStart,
          );
          await _executeToolCalls(
            releaseRetryResult.toolCalls!,
            assistantContent: releaseRetryResult.content.isNotEmpty
                ? releaseRetryResult.content
                : hiddenAssistantEvidence,
            toolSearchEnabled: initialToolSelection.toolSearchEnabled,
            selectedToolNames: {
              ...initialToolSelection.selectedToolNames,
              ...releaseRetryResult.toolCalls!.map((toolCall) => toolCall.name),
            },
            stableToolDefinitions: stableLoopToolDefinitions,
            interactionGeneration: generation,
          );
          return;
        }
        if (releaseRetryResult != null &&
            releaseRetryResult.content.trim().isNotEmpty) {
          _recordHiddenEvidence(turnOwner, releaseRetryResult.content);
        }
        final recoveredContentToolArtifact =
            _recoverContentToolArtifactsBeforeNoToolFinalization(
              interactionGeneration: generation,
            );
        if (recoveredContentToolArtifact) {
          await _finishStreaming(interactionGeneration: generation);
          return;
        }
        _stripToolArtifactsFromLastAssistantMessage(
          interactionGeneration: generation,
        );
        _appendUnexecutedToolRequestNoticeIfNeeded(
          interactionGeneration: generation,
        );
        if (const FencedToolArgumentsDetector().detect(
              hiddenAssistantEvidence,
            ) !=
            null) {
          final fencedRetryResult = await _requestUnexecutedCommandActionRetry(
            candidateResponse: hiddenAssistantEvidence,
            executedToolResults: <ToolResultInfo>[],
            batchToolResults: <ToolResultInfo>[],
            allowedToolNames: turnSnapshot!.allowedToolNames,
            tools: initialToolSelection.toolDefinitions,
            interactionGeneration: generation,
          );
          if (!_isCurrentInteractionGeneration(generation)) return;
          if (!ref.mounted) return;
          if (fencedRetryResult != null && fencedRetryResult.hasToolCalls) {
            appLog('[UnexecutedCommand] Fenced-arguments retry issued calls');
            _removeAssistantStreamDeltaForGeneration(
              generation: generation,
              messageIndex: streamedMessageIndex,
              startingLength: streamedContentStart,
            );
            await _executeToolCalls(
              fencedRetryResult.toolCalls!,
              assistantContent: fencedRetryResult.content.isNotEmpty
                  ? fencedRetryResult.content
                  : hiddenAssistantEvidence,
              toolSearchEnabled: initialToolSelection.toolSearchEnabled,
              selectedToolNames: {
                ...initialToolSelection.selectedToolNames,
                ...fencedRetryResult.toolCalls!.map(
                  (toolCall) => toolCall.name,
                ),
              },
              stableToolDefinitions: stableLoopToolDefinitions,
              interactionGeneration: generation,
            );
            return;
          }
          if (fencedRetryResult != null &&
              fencedRetryResult.content.trim().isNotEmpty) {
            _recordHiddenEvidence(turnOwner, fencedRetryResult.content);
          }
        }
        final unexecutedCommandAction =
            _toolCallExecutionPolicy.offersCommandExecution(
              turnSnapshot!.allowedToolNames,
            )
            ? _claims.buildUnexecutedCommandActionToolResult(
                candidateResponse: hiddenAssistantEvidence,
                toolResults: const [],
              )
            : null;
        if (unexecutedCommandAction != null) {
          _turnToolResults.setCompleted(turnOwner, [unexecutedCommandAction]);
          _goalCompletionEvidence.replaceWithToolResults(
            turnOwner,
            _turnToolResults.completed(turnOwner),
          );
          // This is the shape the corpus is full of: a turn that answers a
          // user's reply by describing a run, with no tool call at all. Ask
          // for the call before settling for the notice.
          final commandRetryToolResults = <ToolResultInfo>[
            unexecutedCommandAction,
          ];
          final commandRetryResult = await _requestUnexecutedCommandActionRetry(
            candidateResponse: hiddenAssistantEvidence,
            executedToolResults: commandRetryToolResults,
            batchToolResults: <ToolResultInfo>[],
            allowedToolNames: turnSnapshot.allowedToolNames,
            tools: initialToolSelection.toolDefinitions,
            interactionGeneration: generation,
          );
          if (!_isCurrentInteractionGeneration(generation)) return;
          if (!ref.mounted) return;
          if (commandRetryResult != null && commandRetryResult.hasToolCalls) {
            appLog('[UnexecutedCommand] No-tool answer retry issued calls');
            _removeAssistantStreamDeltaForGeneration(
              generation: generation,
              messageIndex: streamedMessageIndex,
              startingLength: streamedContentStart,
            );
            await _executeToolCalls(
              commandRetryResult.toolCalls!,
              assistantContent: commandRetryResult.content.isNotEmpty
                  ? commandRetryResult.content
                  : hiddenAssistantEvidence,
              toolSearchEnabled: initialToolSelection.toolSearchEnabled,
              selectedToolNames: {
                ...initialToolSelection.selectedToolNames,
                ...commandRetryResult.toolCalls!.map(
                  (toolCall) => toolCall.name,
                ),
              },
              stableToolDefinitions: stableLoopToolDefinitions,
              interactionGeneration: generation,
            );
            return;
          }
          if (commandRetryResult != null &&
              commandRetryResult.content.trim().isNotEmpty) {
            _recordHiddenEvidence(turnOwner, commandRetryResult.content);
          }
          _appendUnexecutedCommandActionNoticeIfNeeded(
            toolResults: [unexecutedCommandAction],
            owner: turnOwner,
          );
        } else {
          final unverifiedInspectionClaim = _claims
              .buildUnverifiedReadOnlyInspectionClaimToolResult(
                candidateResponse: hiddenAssistantEvidence,
                toolResults: const [],
              );
          if (unverifiedInspectionClaim != null) {
            _turnToolResults.setCompleted(turnOwner, [
              unverifiedInspectionClaim,
            ]);
            _appendUnverifiedReadOnlyInspectionClaimNoticeIfNeeded(
              toolResults: [unverifiedInspectionClaim],
              owner: turnOwner,
            );
          }
        }
        await _finishStreaming(interactionGeneration: generation);
      }
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      appLog('[Tool] Error occurred: $e');

      if (allowContextRetry &&
          await _retryAfterContextLengthError(
            e,
            () => _sendWithTools(
              allowContextRetry: false,
              interactionGeneration: generation,
              allowedToolNames: allowedToolNames,
              verifierOnlyContinuation: verifierOnlyContinuation,
            ),
            owner: turnOwner,
          )) {
        return;
      }

      if (!_isCurrentInteractionGeneration(generation)) return;

      if (_shouldFallbackFoundationModelsToolBridgeAfterContextError(e)) {
        appLog(
          '[Tool] Foundation Models tool bridge exceeded the context window; '
          'falling back to normal mode',
        );
        _resetStreamingAssistantForRetry(turnOwner);
        await _sendWithoutTools(
          allowContextRetry: allowContextRetry,
          interactionGeneration: generation,
        );
        return;
      }

      if (nativeToolFallbackDefinitions.isNotEmpty &&
          ChatRemoteDataSource.isNativeToolStreamFormatError(e)) {
        appLog(
          '[Tool] Native tool stream format failed; retrying with embedded '
          'tool-call tags',
        );
        await _sendWithEmbeddedToolTagFallback(
          toolDefinitions: nativeToolFallbackDefinitions,
          allowContextRetry: allowContextRetry,
          interactionGeneration: generation,
        );
        return;
      }

      if (errorStr.contains('formatexception') ||
          errorStr.contains('expecting value') ||
          errorStr.contains('empty') ||
          errorStr.contains('json') ||
          errorStr.contains('decode') ||
          errorStr.contains('parse') ||
          errorStr.contains('unexpected') ||
          errorStr.contains('invalid') ||
          errorStr.contains('500') ||
          errorStr.contains('server error')) {
        appLog('[Tool] LLM may not support tools, falling back to normal mode');
        await _sendWithoutTools(
          allowContextRetry: allowContextRetry,
          interactionGeneration: generation,
        );
        return;
      }
      if (!_isCurrentInteractionGeneration(generation)) return;
      await _handleError(e, owner: turnOwner);
    } finally {
      fileTools?.endFileTurnCheckpoint(turnOwner);
    }
  }

  bool _shouldFallbackFoundationModelsToolBridgeAfterContextError(
    Object error,
  ) =>
      _settings.llmProvider == LlmProvider.appleFoundationModels &&
      ConversationCompactionService.isContextLengthError(error.toString());

  bool get _supportsToolAwareRequests => true;

  bool _summaryFirstToolResultsEnabled(int? generation) =>
      _primaryHarnessConfigForGeneration(
        generation,
      )?.summaryFirstToolResultsEnabled ??
      false;

  List<ToolResultInfo> _budgetToolResultsForPrompt(
    List<ToolResultInfo> toolResults, {
    ToolResultPromptBudgetMode mode = ToolResultPromptBudgetMode.normal,
    required Set<String> protectedPaths,
    required ChatTurnOwner? observationOwner,
  }) {
    final budgetedToolResults = ToolResultPromptBuilder.budgetToolResults(
      toolResults,
      mode: mode,
      protectedPaths: mode == ToolResultPromptBudgetMode.compact
          ? protectedPaths
          : const <String>{},
      summaryFirst: _summaryFirstToolResultsEnabled(
        observationOwner?.interactionGeneration,
      ),
    );
    if (observationOwner != null) {
      _updateContextSurgeryObservation(
        owner: observationOwner,
        toolResults: budgetedToolResults,
      );
    }
    return budgetedToolResults;
  }

  bool _hasAdditionalCompactToolResultBudget(
    List<ToolResultInfo> toolResults, {
    required Set<String> protectedPaths,
    required int interactionGeneration,
  }) => ToolResultPromptBuilder.hasAdditionalCompactBudgetReduction(
    toolResults,
    protectedPaths: protectedPaths,
    summaryFirst: _summaryFirstToolResultsEnabled(interactionGeneration),
  );

  /// Resolves only the registered owner; visible state is unsafe for an
  /// untracked or background generation.
  Conversation? _conversationForGeneration(int generation) {
    final threadId = _activeResponseConversationIdForGeneration(generation);
    return threadId == null ? null : _conversationForId(threadId);
  }

  ({Conversation conversation, String projectRoot})? _codingTurnContext(
    int generation,
  ) {
    final snapshot = _turnOwnerSnapshotForGeneration(generation);
    final projectRoot = snapshot?.projectRoot?.trim();
    if (snapshot == null ||
        !snapshot.isCodingWorkspaceOrMode ||
        snapshot.isPlanning ||
        projectRoot == null ||
        projectRoot.isEmpty) {
      return null;
    }
    final conversation = _conversationForId(snapshot.owner.conversationId);
    if (conversation == null) return null;
    return (conversation: conversation, projectRoot: projectRoot);
  }

  Future<ToolResultInfo?> _buildCodingDiagnosticFeedbackToolResult(
    List<ToolResultInfo> toolResults, {
    required int interactionGeneration,
    CodingDiagnosticFeedbackBaseline? baseline,
  }) async {
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return null;
    }
    final turn = _codingTurnContext(interactionGeneration);
    if (turn == null) {
      return null;
    }
    final projectRoot = turn.projectRoot;

    final changedPaths = _changedFileMutationPaths(
      toolResults,
      dartOnly: false,
    );
    if (changedPaths.isEmpty) {
      return null;
    }

    try {
      final feedback = await _codingDiagnosticFeedbackService
          .buildFeedbackToolResult(
            projectRoot: projectRoot,
            changedPaths: changedPaths,
            baseline: baseline,
          );
      if (feedback != null) {
        appLog(
          '[CodingDiagnostics] Added diagnostic feedback for '
          '${changedPaths.length} changed file(s)',
        );
        _logCodingDiagnosticFeedbackSummary(feedback);
      }
      await _refreshRepoMapLspSymbols(
        projectRoot: projectRoot,
        changedPaths: changedPaths,
        interactionGeneration: interactionGeneration,
      );
      return feedback;
    } catch (error, stackTrace) {
      appLog(
        '[CodingDiagnostics] Failed to collect diagnostic feedback: $error',
      );
      appLog('[CodingDiagnostics] stackTrace: $stackTrace');
      return null;
    }
  }

  /// Runs one baseline-free analyzer pass before the final answer so surviving
  /// diagnostics cannot be hidden by a later batch's relative baseline.
  Future<ToolResultInfo?> _buildFinalCodingDiagnosticFeedbackToolResult(
    List<ToolResultInfo> toolResults, {
    required int interactionGeneration,
  }) {
    return _buildCodingDiagnosticFeedbackToolResult(
      toolResults,
      interactionGeneration: interactionGeneration,
      baseline: null,
    );
  }

  Future<CodingDiagnosticFeedbackBaseline?>
  _captureCodingDiagnosticFeedbackBaseline(
    List<ToolCallInfo> toolCalls, {
    required int interactionGeneration,
  }) async {
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return null;
    }
    final turn = _codingTurnContext(interactionGeneration);
    if (turn == null) {
      return null;
    }
    final projectRoot = turn.projectRoot;

    final changedPaths = _changedFileMutationCallPaths(
      toolCalls,
      dartOnly: false,
    );
    if (changedPaths.isEmpty) {
      return null;
    }

    try {
      return await _codingDiagnosticFeedbackService.captureBaseline(
        projectRoot: projectRoot,
        changedPaths: changedPaths,
      );
    } catch (error, stackTrace) {
      appLog('[CodingDiagnostics] Failed to capture analyzer baseline: $error');
      appLog('[CodingDiagnostics] stackTrace: $stackTrace');
      return null;
    }
  }

  Future<void> _refreshRepoMapLspSymbols({
    required String projectRoot,
    required Iterable<String> changedPaths,
    required int interactionGeneration,
  }) async {
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return;
    }
    try {
      final symbols = await ref
          .read(lspJsonRpcSessionRegistryProvider)
          .collectDocumentSymbols(
            projectRoot: projectRoot,
            changedPaths: changedPaths,
          );
      if (!_isCurrentInteractionGeneration(interactionGeneration) ||
          symbols == null) {
        return;
      }
      ref
          .read(repoMapLspSymbolCacheProvider)
          .updateFromLsp(
            projectRoot: projectRoot,
            changedPaths: changedPaths,
            symbols: symbols,
          );
      ref.read(repoMapPrecomputeCacheProvider).invalidate(projectRoot);
      if (symbols.isNotEmpty) {
        appLog(
          '[RepoMap] Refreshed LSP symbols for '
          '${changedPaths.length} changed file(s)',
        );
      }
    } catch (error, stackTrace) {
      appLog('[RepoMap] Failed to refresh LSP symbols: $error');
      appLog('[RepoMap] stackTrace: $stackTrace');
    }
  }

  void _logCodingDiagnosticFeedbackSummary(ToolResultInfo feedback) {
    final decoded = ProposalParsingTextUtils.tryDecodeMap(feedback.result);
    if (decoded == null) {
      return;
    }
    final telemetry = decoded['telemetry'];
    final telemetryMap = telemetry is Map<String, dynamic> ? telemetry : null;
    final summary = <String, Object?>{
      'toolName': feedback.name,
      'provider': decoded['provider'],
      'diagnosticCount':
          decoded['new_diagnostic_count'] ?? decoded['diagnostic_count'],
      'currentDiagnosticCount': decoded['current_diagnostic_count'],
      'baselineDiagnosticCount': decoded['baseline_diagnostic_count'],
      'baselineApplied': decoded['baseline_applied'],
      'files': decoded['changed_paths'],
      if (telemetryMap != null) ...{
        'durationMs': telemetryMap['duration_ms'],
        'commandAttemptCount': telemetryMap['command_attempt_count'],
        'fallbackCommandCount': telemetryMap['fallback_command_count'],
        'timedOutCommandCount': telemetryMap['timed_out_command_count'],
        'startErrorCommandCount': telemetryMap['start_error_command_count'],
      },
    };
    appLog(
      '[CodingDiagnostics] Analyzer feedback summary: ${jsonEncode(summary)}',
    );
  }

  Future<ToolResultInfo?> _buildCodingCommandOutputGuardrailToolResult(
    List<ToolResultInfo> toolResults, {
    required int interactionGeneration,
  }) async {
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return null;
    }
    final conversation = _conversationForGeneration(interactionGeneration);
    if (conversation?.workspaceMode != WorkspaceMode.coding ||
        (conversation?.isPlanningSession ?? false)) {
      return null;
    }

    try {
      final feedback = const CodingCommandOutputGuardrailService()
          .buildFeedbackToolResult(toolResults: toolResults);
      if (feedback != null) {
        appLog(
          '[CodingOutputGuardrail] Added command output feedback for '
          '${toolResults.length} tool result(s)',
        );
        _logCodingCommandOutputGuardrailSummary(feedback);
      }
      return feedback;
    } catch (error, stackTrace) {
      appLog(
        '[CodingOutputGuardrail] Failed to inspect command outputs: $error',
      );
      appLog('[CodingOutputGuardrail] stackTrace: $stackTrace');
      return null;
    }
  }

  void _logCodingCommandOutputGuardrailSummary(ToolResultInfo feedback) {
    final decoded = ProposalParsingTextUtils.tryDecodeMap(feedback.result);
    if (decoded == null) {
      return;
    }
    final issues = decoded['issues'];
    final issueList = issues is List ? issues : const [];
    final summary = <String, Object?>{
      'toolName': feedback.name,
      'provider': decoded['provider'],
      'validationStatus': decoded['validation_status'],
      'issueCount': issueList.length,
      'commands': issueList
          .whereType<Map>()
          .map((issue) => issue['command']?.toString())
          .whereType<String>()
          .where((command) => command.trim().isNotEmpty)
          .toList(growable: false),
    };
    appLog('[CodingOutputGuardrail] Feedback summary: ${jsonEncode(summary)}');
  }

  Future<ChatCompletionResult?>
  _requestBackgroundProcessMonitorRepairForCompletionClaim({
    required String candidateResponse,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolResultInfo> batchToolResults,
    required List<Map<String, dynamic>> tools,
    required int interactionGeneration,
    void Function()? onBlockingFeedbackPrepared,
  }) async {
    if (!_looksLikeBackgroundProcessCompletionClaim(candidateResponse)) {
      return null;
    }
    final owner = _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) {
      return null;
    }
    final feedback = await _buildBackgroundProcessMonitorFeedbackToolResult(
      owner: owner,
      candidateResponse: candidateResponse,
      toolResults: executedToolResults,
    );
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return null;
    }
    if (feedback == null) {
      return null;
    }

    final promptFeedback = await _persistToolResultForPrompt(
      feedback,
      interactionGeneration: interactionGeneration,
    );
    if (promptFeedback == null) {
      return null;
    }
    batchToolResults.add(promptFeedback);
    executedToolResults.add(promptFeedback);
    onBlockingFeedbackPrepared?.call();

    appLog(
      '[BackgroundProcess] Completion claim blocked by background process '
      'monitor feedback',
    );
    _appendToLastMessageForGeneration(interactionGeneration, '<think>');
    try {
      return await _createToolResultCompletionWithContextRetry(
        logLabel: 'background process monitor feedback',
        interactionGeneration: interactionGeneration,
        buildMessages: (forceCompaction) => _prepareMessagesForLLM(
          forceCompaction: forceCompaction,
          toolDefinitionsOverride: tools,
          interactionGeneration: interactionGeneration,
        ),
        toolResults: [promptFeedback],
        assistantContent: candidateResponse,
        tools: tools,
      );
    } finally {
      if (_isCurrentInteractionGeneration(interactionGeneration)) {
        _removeTrailingThinkTagForGeneration(interactionGeneration);
      }
    }
  }

  Future<ToolResultInfo?> _buildBackgroundProcessMonitorFeedbackToolResult({
    required ChatTurnOwner owner,
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) async {
    final partialFailureFeedback =
        _buildBackgroundProcessPartialFailureFeedbackToolResult(
          candidateResponse: candidateResponse,
          toolResults: toolResults,
        );
    if (partialFailureFeedback != null) {
      return partialFailureFeedback;
    }
    if (_hasSuccessfulBackgroundProcessCompletionToolResult(toolResults)) {
      return null;
    }
    final processFeedback = await _buildBackgroundProcessMonitorToolResult(
      owner: owner,
      candidateResponse: candidateResponse,
      toolResults: toolResults,
    );
    if (processFeedback != null) {
      return processFeedback;
    }
    return _buildSubagentMonitorFeedbackToolResult(
      owner: owner,
      candidateResponse: candidateResponse,
      toolResults: toolResults,
    );
  }

  ToolResultInfo? _buildBackgroundProcessPartialFailureFeedbackToolResult({
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) {
    final failedResults = toolResults
        .where(_toolResultContainsReleaseFailureMarker)
        .toList(growable: false);
    if (failedResults.isEmpty) {
      return null;
    }
    final jobIds = _backgroundProcessJobIdsFromResults(failedResults);
    return ToolResultInfo(
      id: 'background_process_partial_failure_${DateTime.now().microsecondsSinceEpoch}',
      name: 'background_process_monitor',
      arguments: {
        if (jobIds.isNotEmpty) 'job_ids': jobIds,
        'source': 'tool_result_output',
      },
      result: jsonEncode({
        'ok': false,
        'code': 'background_process_partial_failure',
        'error':
            'A background process output contains a release failure marker, '
            'so an exit code 0 is not enough to verify full completion.',
        if (jobIds.isNotEmpty) 'job_ids': jobIds,
        'failed_tool_results': failedResults
            .map(
              (result) => {
                'tool_name': result.name,
                'arguments': result.arguments,
                'result_excerpt': _claims.clipForDiagnostic(result.result),
              },
            )
            .toList(growable: false),
        'claimedResponse': _claims.clipForDiagnostic(candidateResponse),
        'required_action':
            'Report the partial failure explicitly. Do not claim the release, '
            'upload, or export completed successfully until a later command '
            'result proves the failed lane was retried and succeeded.',
      }),
    );
  }

  bool _hasSuccessfulBackgroundProcessCompletionToolResult(
    List<ToolResultInfo> toolResults,
  ) {
    final relevantJobIds = _backgroundProcessJobIdsFromResults(toolResults);
    if (relevantJobIds.isEmpty) {
      return false;
    }
    final successfulJobIds = <String>{};
    for (final result in toolResults) {
      final name = result.name.trim().toLowerCase();
      if (name != 'process_status' &&
          name != 'process_wait' &&
          name != 'process_start') {
        continue;
      }
      if (!_toolCallExecutionPolicy.toolResultHasSuccessfulExit(result)) {
        continue;
      }
      final decoded = ProposalParsingTextUtils.tryDecodeMap(result.result);
      final jobId = decoded?['job_id']?.toString().trim();
      if (jobId != null && jobId.isNotEmpty) {
        successfulJobIds.add(jobId);
      }
    }
    return relevantJobIds.every(successfulJobIds.contains);
  }

  bool _toolResultContainsReleaseFailureMarker(ToolResultInfo result) {
    if (!_toolCallExecutionPolicy.isCommandExecutionTool(result.name)) {
      return false;
    }
    final normalized = result.result.toLowerCase();
    return _containsAny(normalized, const [
          'overall: partial_failure',
          'encountered error while creating the ipa',
          'error: exportarchive',
          'the bundle version must be higher',
          'upload failed',
          'ipatool failed',
        ]) ||
        RegExp(r'itms-\d+').hasMatch(normalized);
  }

  Future<ToolResultInfo?> _buildBackgroundProcessMonitorToolResult({
    required ChatTurnOwner owner,
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) async {
    final jobIds = _backgroundProcessJobIdsFromResults(toolResults);
    return BackgroundProcessCompletionMonitor(
      monitor: _backgroundProcessMonitorService,
    ).buildFeedback(
      owner: owner,
      jobIds: jobIds,
      claimedResponse: _claims.clipForDiagnostic(candidateResponse),
    );
  }

  ToolResultInfo? _buildSubagentMonitorFeedbackToolResult({
    required ChatTurnOwner owner,
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) {
    final runningTaskIds = <String>[];
    final failedTaskIds = <String>[];
    final blockedTasks = <Map<String, dynamic>>[];
    final notifier = ref.read(subagentTaskNotifierProvider.notifier);

    for (final result in toolResults) {
      final name = result.name.trim().toLowerCase();
      if (name != 'spawn_subagent' && name != 'get_subagent_result') {
        continue;
      }
      final decoded = ProposalParsingTextUtils.tryDecodeMap(result.result);
      final taskId = decoded?['task_id']?.toString().trim();
      if (taskId == null || taskId.isEmpty) {
        continue;
      }
      if (runningTaskIds.contains(taskId) || failedTaskIds.contains(taskId)) {
        continue;
      }

      final rawStatus = decoded?['status']?.toString().toLowerCase() ?? '';
      final task = notifier.byId(owner, taskId);
      final status = task?.status ?? _statusFromSubagentTaskResult(rawStatus);
      final description =
          decoded?['description']?.toString() ??
          task?.description ??
          'background subagent task';

      if (status == SubagentTaskStatus.completed) {
        continue;
      }
      if (status == SubagentTaskStatus.failed ||
          status == SubagentTaskStatus.cancelled) {
        failedTaskIds.add(taskId);
        blockedTasks.add({
          'task_id': taskId,
          'status': status == SubagentTaskStatus.failed
              ? 'failed'
              : 'cancelled',
          'description': description,
          'error': decoded?['error']?.toString() ?? task?.error,
        });
        continue;
      }
      if (status == SubagentTaskStatus.pending ||
          status == SubagentTaskStatus.running) {
        runningTaskIds.add(taskId);
        blockedTasks.add({
          'task_id': taskId,
          'status': status == SubagentTaskStatus.pending
              ? 'pending'
              : 'running',
          'description': description,
        });
        continue;
      }
      if (status == null) {
        if (rawStatus == 'running' ||
            rawStatus == 'pending' ||
            rawStatus == 'started') {
          runningTaskIds.add(taskId);
          blockedTasks.add({
            'task_id': taskId,
            'status': rawStatus,
            'description': description,
          });
        } else if (rawStatus == 'failed') {
          failedTaskIds.add(taskId);
          blockedTasks.add({
            'task_id': taskId,
            'status': rawStatus,
            'description': description,
            'error': decoded?['error']?.toString(),
          });
        }
      }
    }

    if (blockedTasks.isEmpty) {
      return null;
    }

    final running = blockedTasks
        .where(
          (task) => task['status'] == 'running' || task['status'] == 'pending',
        )
        .toList(growable: false);
    final failed = blockedTasks
        .where(
          (task) => task['status'] == 'failed' || task['status'] == 'cancelled',
        )
        .toList(growable: false);
    final code = running.isNotEmpty
        ? 'subagent_still_running'
        : failed.isNotEmpty
        ? 'subagent_failed'
        : 'subagent_status_unverified';
    final error = running.isNotEmpty
        ? 'One or more background subagent tasks are still running, so the completion claim is not verified yet.'
        : failed.isNotEmpty
        ? 'One or more background subagent tasks failed, so the completion claim is not verified.'
        : 'One or more background subagent tasks could not be verified, so the completion claim is not verified.';

    return ToolResultInfo(
      id: 'subagent_monitor_${DateTime.now().microsecondsSinceEpoch}',
      name: 'get_subagent_result',
      arguments: {
        'task_ids': blockedTasks
            .map((task) => task['task_id'])
            .whereType<String>()
            .toList(growable: false),
      },
      result: jsonEncode({
        'ok': false,
        'code': code,
        'error': error,
        'tasks': blockedTasks,
        'claimedResponse': _claims.clipForDiagnostic(candidateResponse),
        'required_action':
            'Call get_subagent_result for each pending task_id until the status becomes completed, and do not claim completion until every relevant background subagent task finishes successfully.',
      }),
    );
  }

  SubagentTaskStatus? _statusFromSubagentTaskResult(String rawStatus) {
    switch (rawStatus) {
      case 'pending':
        return SubagentTaskStatus.pending;
      case 'running':
        return SubagentTaskStatus.running;
      case 'completed':
        return SubagentTaskStatus.completed;
      case 'failed':
        return SubagentTaskStatus.failed;
      case 'cancelled':
        return SubagentTaskStatus.cancelled;
      default:
        return null;
    }
  }

  List<String> _backgroundProcessJobIdsFromResults(
    List<ToolResultInfo> toolResults,
  ) {
    final jobIds = <String>[];
    for (final result in toolResults) {
      final name = result.name.trim().toLowerCase();
      if (name != 'process_start' &&
          (name != 'local_execute_command' ||
              !_asBool(result.arguments['background'])) &&
          name != 'process_status' &&
          name != 'process_wait') {
        continue;
      }
      final decoded = ProposalParsingTextUtils.tryDecodeMap(result.result);
      final jobId = decoded?['job_id']?.toString().trim();
      if (jobId != null && jobId.isNotEmpty) {
        jobIds.add(jobId);
      }
    }
    return jobIds.toSet().toList(growable: false);
  }

  bool _looksLikeBackgroundProcessCompletionClaim(String response) {
    final candidate = response.trim();
    if (candidate.isEmpty) {
      return false;
    }
    final normalized = candidate.toLowerCase();
    if (_containsAny(normalized, const [
      'not complete',
      'not completed',
      'not done',
      'still running',
      'still in progress',
      'waiting',
      'pending',
      'not yet',
      'unverified',
      'failed',
      'failure',
      'error',
      'non-zero',
      'nonzero',
      'exit code 1',
      'exit code 2',
      'exit code 64',
      'exit code 65',
    ])) {
      return false;
    }
    if (CodeUnitTextScan.containsAny(candidate, const [
      [0x5931, 0x6557],
      [0x30a8, 0x30e9, 0x30fc],
      [0x7570, 0x5e38, 0x7d42, 0x4e86],
    ])) {
      return false;
    }
    return _terminalToolResponsePolicy.hiddenAssistantEvidenceScore(
              candidate,
            ) >=
            2 ||
        _containsAny(normalized, const [
          'complete',
          'completed',
          'done',
          'finished',
          'succeeded',
          'successful',
          'passed',
          'released',
          'uploaded',
          'deployed',
        ]) ||
        CodeUnitTextScan.containsAny(candidate, const [
          [0x5b8c, 0x4e86],
          [0x6210, 0x529f],
          [0x7d42, 0x4e86],
        ]);
  }

  List<String> _changedFileMutationCallPaths(
    List<ToolCallInfo> toolCalls, {
    bool dartOnly = true,
  }) {
    final paths = <String>[];
    final seen = <String>{};
    for (final toolCall in toolCalls) {
      if (!_fileMutationEvidencePolicy.isMutationToolName(toolCall.name)) {
        continue;
      }
      final path = _fileMutationEvidencePolicy.argumentPath(toolCall.arguments);
      if (path == null || (dartOnly && !path.toLowerCase().endsWith('.dart'))) {
        continue;
      }
      final resolved = FilesystemTools.resolvePath(
        path,
        defaultRoot: _getActiveProjectRootPath(),
      );
      final normalized = resolved ?? path;
      if (seen.add(normalized)) {
        paths.add(normalized);
      }
    }
    return paths;
  }

  List<String> _changedFileMutationPaths(
    List<ToolResultInfo> toolResults, {
    bool dartOnly = true,
  }) {
    final paths = <String>[];
    final seen = <String>{};
    for (final toolResult in toolResults) {
      if (!_fileMutationEvidencePolicy.isMutationToolName(toolResult.name)) {
        continue;
      }
      if (!_fileMutationEvidencePolicy.isSuccessfulResult(toolResult)) {
        continue;
      }
      final path = _fileMutationEvidencePolicy.pathForResult(toolResult);
      if (path == null || (dartOnly && !path.toLowerCase().endsWith('.dart'))) {
        continue;
      }
      final resolved = FilesystemTools.resolvePath(
        path,
        defaultRoot: _getActiveProjectRootPath(),
      );
      final normalized = resolved ?? path;
      if (seen.add(normalized)) {
        paths.add(normalized);
      }
    }
    return paths;
  }

  bool _isPostSavedValidationEvidenceToolCall(ToolCallInfo toolCall) {
    final effect = const ToolCapabilityClassifier()
        .classify(toolCall.name, arguments: toolCall.arguments)
        .commandEffect;
    return effect == ToolCommandEffect.inspection ||
        effect == ToolCommandEffect.verification;
  }

  bool _postSavedValidationEvidenceRequiresRepair(
    List<ToolResultInfo> toolResults,
  ) {
    for (final result in toolResults) {
      if (result.name == CodingCommandOutputGuardrailService.toolName) {
        final payload = ProposalParsingTextUtils.tryDecodeMap(result.result);
        if (payload?['success'] == false ||
            payload?['validation_status'] == 'failed') {
          return true;
        }
      }
      final effect = const ToolCapabilityClassifier()
          .classify(result.name, arguments: result.arguments)
          .commandEffect;
      if (effect != ToolCommandEffect.verification) {
        continue;
      }
      if (!_toolCallExecutionPolicy.toolResultHasSuccessfulExit(result)) {
        return true;
      }
      final output = _toolCallExecutionPolicy
          .toolResultOutputText(result)
          .toLowerCase();
      if (output.contains('unhandled exception') ||
          output.contains('stack trace') ||
          output.contains('traceback (most recent call last)') ||
          output.contains('assertionerror') ||
          output.contains('validation failed') ||
          output.contains('validation failure')) {
        return true;
      }
    }
    return false;
  }

  List<Message> _buildToolResultAnswerMessages(
    List<ToolResultInfo> toolResults, {
    ToolResultPromptBudgetMode budgetMode = ToolResultPromptBudgetMode.normal,
    ToolResultCompletionEvidence? completionEvidence,
    required Set<String> protectedPaths,
    required ChatTurnOwner observationOwner,
  }) {
    final budgetedToolResults = _budgetToolResultsForPrompt(
      toolResults,
      mode: budgetMode,
      protectedPaths: protectedPaths,
      observationOwner: observationOwner,
    );
    final timestamp = DateTime.now();
    final messages = <Message>[
      Message(
        id: 'tool_result_${timestamp.microsecondsSinceEpoch}',
        isSynthesizedPrompt: true,
        content: ToolResultPromptBuilder.buildAnswerPrompt(
          budgetedToolResults,
          descriptionsByName:
              ToolResultPromptBuilder.descriptionsByNameFromDefinitions(
                _mcpToolService?.getOpenAiToolDefinitions() ?? const [],
              ),
          completionEvidence: completionEvidence,
        ),
        role: MessageRole.user,
        timestamp: timestamp,
      ),
    ];

    for (var i = 0; i < budgetedToolResults.length; i++) {
      final toolResult = budgetedToolResults[i];
      final decoded = ProposalParsingTextUtils.tryDecodeMap(toolResult.result);
      if (decoded == null) {
        continue;
      }
      final imageBase64 = decoded['imageBase64'];
      if (imageBase64 is! String || imageBase64.isEmpty) {
        continue;
      }

      final metadata = Map<String, dynamic>.from(decoded)
        ..remove('imageBase64');
      messages.add(
        Message(
          id: 'tool_image_${timestamp.microsecondsSinceEpoch}_$i',
          content:
              'Visual observation from ${toolResult.name}. '
              'Use this screenshot and any actionProposalPolicy metadata to '
              'answer the user and decide any next computer-use action. '
              'Preserve required target metadata, exact text, and public '
              'action boundaries when proposing actions. '
              'Metadata: ${jsonEncode(metadata)}',
          role: MessageRole.user,
          timestamp: timestamp,
          imageBase64: imageBase64,
          imageMimeType: decoded['imageMimeType'] as String? ?? 'image/png',
        ),
      );
    }

    return messages;
  }

  void _logScheduledToolLifecycleEvent(
    ToolExecutionLifecycleEvent event, {
    required int generation,
    required int loopIndex,
  }) {
    _runtimeEvents.emitRuntimeToolLifecycle(
      generation: generation,
      toolCallId: event.toolCall.id,
      toolName: event.toolCall.name,
      state: _runtimeEvents.runtimeToolLifecycleState(event.state),
      loopIndex: loopIndex,
      schedulerClass: event.schedulerMode.name,
      resultStatus: event.resultStatus,
      durationMs: event.durationMs,
    );
    appLog(
      ChatToolExecutionLogFormatter.lifecycleLineForEvent(
        event,
        loopIndex: loopIndex,
      ),
    );
  }

  void _logToolLifecycleEvent({
    required int generation,
    required ToolCallInfo toolCall,
    required String lifecycleState,
    required int loopIndex,
    ToolExecutionBatchMode? schedulerMode,
    String? resultStatus,
    String? skipReason,
    int? durationMs,
  }) {
    final runtimeState = switch (lifecycleState) {
      'queued' => CavernoRuntimeToolLifecycleState.queued,
      'started' => CavernoRuntimeToolLifecycleState.started,
      _ => CavernoRuntimeToolLifecycleState.completed,
    };
    _runtimeEvents.emitRuntimeToolLifecycle(
      generation: generation,
      toolCallId: toolCall.id,
      toolName: toolCall.name,
      state: runtimeState,
      loopIndex: loopIndex,
      schedulerClass: schedulerMode?.name,
      resultStatus: resultStatus,
      skipReason: skipReason,
      durationMs: durationMs,
    );
    appLog(
      ChatToolExecutionLogFormatter.lifecycleLine(
        toolCall: toolCall,
        lifecycleState: lifecycleState,
        loopIndex: loopIndex,
        schedulerMode: schedulerMode,
        resultStatus: resultStatus,
        skipReason: skipReason,
        durationMs: durationMs,
      ),
    );
  }

  /// Executes bounded tool calls and resends results for model compatibility.
  Future<void> _executeToolCalls(
    List<ToolCallInfo> toolCalls, {
    String? assistantContent,
    bool toolSearchEnabled = false,
    Set<String> selectedToolNames = const <String>{},
    List<Map<String, dynamic>>? stableToolDefinitions,
    Map<String, int>? completionVerificationFailureCounts,
    Set<String>? narratedTranscriptRepairSignatures,
    bool replayVerifierImmediatelyAfterMutation = false,
    bool verifierOnlyContinuation = false,
    required int interactionGeneration,
  }) async {
    final turnSnapshot = _turnOwnerSnapshotForGeneration(interactionGeneration);
    final turnOwner = turnSnapshot?.owner;
    if (turnOwner == null) {
      await _handleTurnOwnerSnapshotUnavailable(interactionGeneration);
      return;
    }
    var currentToolCalls = toolCalls;
    var currentAssistantContent = assistantContent;
    var maxIterations =
        _primaryHarnessConfigForGeneration(
          interactionGeneration,
        )?.resolveToolLoopMaxIterations(
          PlanningExecutorProfile.defaultToolLoopMaxIterations,
        ) ??
        PlanningExecutorProfile.defaultToolLoopMaxIterations;
    const executionBudgetPolicy = ExecutionBudgetPolicy();
    var totalExtensionGranted = 0;
    void requestBudgetExtension(
      ExecutionBudgetExtensionReason reason, {
      int requestedIterations = 2,
      bool madeProgress = true,
    }) {
      final decision = executionBudgetPolicy.requestExtension(
        totalExtensionGranted: totalExtensionGranted,
        requestedIterations: requestedIterations,
        reason: reason,
        madeProgress: madeProgress,
      );
      maxIterations += decision.grantedIterations;
      totalExtensionGranted += decision.grantedIterations;
      appLog(
        '[ExecutionBudget] reason=${reason.name}; '
        'requested=$requestedIterations; '
        'granted=${decision.grantedIterations}; '
        'totalExtension=$totalExtensionGranted; cap=$maxIterations',
      );
    }

    var iteration = 0;
    var hasTextResponse = false;
    final executedToolCallKeys = <String>{};
    final toolFailureCounts = <String, int>{};
    final executedToolResults = <ToolResultInfo>[];
    var commandRetryGeneration = 0;
    var stateChangeGeneration = 0;
    var attemptedDuplicateInspectionRecovery = false;
    var attemptedDuplicateFollowUpRecovery = false;
    var attemptedToolLoopExhaustionRecovery = false;
    var attemptedSkippedPythonAttachmentRepair = false;
    var attemptedPythonAttachmentPathRepair = false;
    var forcedBackgroundProcessFollowUpCount = 0;
    var attemptedCodingContinuationRecovery = false;
    var savedValidationSucceededInLoop = false;
    final attemptedCompletionVerificationMutationSignatures = <String>{};
    final verificationFailureCounts =
        completionVerificationFailureCounts ?? <String, int>{};
    final transcriptRepairSignatures =
        narratedTranscriptRepairSignatures ?? <String>{};
    var lastNonEmptyBatchToolResults = const <ToolResultInfo>[];
    final activeToolNames = <String>{...selectedToolNames};

    // One catalogue per selection for this loop; see TurnToolCatalogCache for
    // why rebuilding it per request let tools vanish mid-turn.
    final toolCatalogCache = TurnToolCatalogCache();
    final toolCatalogSource = TurnToolCatalogSource();

    List<Map<String, dynamic>> selectedDefinitionsFor(
      McpToolService mcpToolService,
    ) {
      final stableDefinitions = stableToolDefinitions;
      if (stableDefinitions != null) {
        return stableDefinitions;
      }
      return toolCatalogCache.resolve(
        selection: activeToolNames,
        compute: () => ToolDefinitionSearchService.definitionsForSelectedTools(
          toolCatalogSource.read(mcpToolService.getOpenAiToolDefinitions),
          selectedToolNames: activeToolNames,
          toolSearchEnabled: toolSearchEnabled,
        ),
      );
    }

    while (currentToolCalls.isNotEmpty && iteration < maxIterations) {
      iteration++;
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      if (!ref.mounted) return;

      if (const GitWriteConfirmationPolicy().shouldBlock(
        GitWriteConfirmationInput(
          owner: turnOwner,
          currentAssistantContent: currentAssistantContent,
          pendingToolCalls: currentToolCalls,
        ),
      )) {
        appLog(
          '[Tool] Blocking git write tool calls because the assistant asked '
          'for user confirmation',
        );
        _turnEnd.setHint(turnOwner, ToolLoopExitReason.userConfirmationBlock);
        currentToolCalls = [];
        hasTextResponse = true;
        break;
      }

      appLog('[Tool] Tool loop [$iteration/$maxIterations]');
      final batchResult = await _executeToolLoopBatch(
        currentToolCalls: currentToolCalls,
        currentAssistantContent: currentAssistantContent,
        executedToolResults: executedToolResults,
        executedToolCallKeys: executedToolCallKeys,
        toolFailureCounts: toolFailureCounts,
        commandRetryGeneration: commandRetryGeneration,
        stateChangeGeneration: stateChangeGeneration,
        iteration: iteration,
        interactionGeneration: interactionGeneration,
        verifierOnlyContinuation: verifierOnlyContinuation,
      );
      if (batchResult.didCancel) return;
      commandRetryGeneration = batchResult.commandRetryGeneration;
      stateChangeGeneration = batchResult.stateChangeGeneration;
      final batchToolResults = batchResult.batchToolResults;
      final pendingBatchCalls = batchResult.pendingBatchCalls;
      final terminalSuccessMessage = batchResult.terminalSuccessMessage;
      if (await _finishExplicitTerminalSuccess(
        terminalSuccessMessage,
        interactionGeneration: interactionGeneration,
      )) {
        hasTextResponse = true;
        break;
      }
      if (replayVerifierImmediatelyAfterMutation &&
          await _replayVerifierAfterRepairMutation(
            executedToolResults: executedToolResults,
            verificationFailureCounts: verificationFailureCounts,
            transcriptRepairSignatures: transcriptRepairSignatures,
            owner: turnOwner,
          )) {
        return;
      }
      if (batchResult.hasTextResponse) {
        hasTextResponse = true;
        break;
      }
      if (batchToolResults.isEmpty) {
        if (pendingBatchCalls.isEmpty && currentToolCalls.isNotEmpty) {
          final recovered = const DuplicateToolResultRecovery().recover(
            DuplicateToolResultRecoveryInput(
              currentToolCalls: currentToolCalls,
              executedToolResults: executedToolResults,
              fallbackToolResults: lastNonEmptyBatchToolResults,
              projectRoot: _projectRootForGeneration(interactionGeneration),
            ),
          );
          if (_containsOnlyPreviouslySuccessfulCurrentSavedValidationToolCalls(
            currentToolCalls,
            executedToolResults,
            interactionGeneration,
          )) {
            appLog(
              '[Tool] Duplicate saved validation command already succeeded',
            );
            const fallbackResponse =
                'The saved validation command already succeeded for the current saved task, so the current saved task is complete.';
            currentToolCalls = [];
            _recordHiddenEvidence(turnOwner, fallbackResponse);
            _appendRecoveredAssistantResponse(
              fallbackResponse,
              interactionGeneration: interactionGeneration,
            );
            currentAssistantContent = fallbackResponse;
            hasTextResponse = true;
            break;
          }
          if (_toolCallExecutionPolicy
              .containsOnlyPreviouslySuccessfulCommandToolCalls(
                currentToolCalls,
                executedToolResults,
              )) {
            appLog(
              '[Tool] Duplicate command follow-up already has a successful result',
            );
            final fallbackResponse = currentAssistantContent?.trim() ?? '';
            final previousOutput = _toolCallExecutionPolicy
                .previousSuccessfulCommandOutputForDuplicateCalls(
                  currentToolCalls,
                  recovered.isNotEmpty ? recovered : executedToolResults,
                );
            if (_toolCallExecutionPolicy
                    .shouldUsePreviousOutputForDuplicateCommandCalls(
                      currentToolCalls,
                    ) &&
                previousOutput.isNotEmpty &&
                (fallbackResponse.isEmpty ||
                    _looksLikePendingToolActionResponse(fallbackResponse))) {
              currentToolCalls = [];
              _recordHiddenEvidence(turnOwner, previousOutput);
              _appendRecoveredAssistantResponse(
                previousOutput,
                interactionGeneration: interactionGeneration,
              );
              currentAssistantContent = previousOutput;
              hasTextResponse = true;
              break;
            }
            if (fallbackResponse.isNotEmpty &&
                !_looksLikePendingToolActionResponse(fallbackResponse)) {
              currentToolCalls = [];
              _recordHiddenEvidence(turnOwner, fallbackResponse);
              _appendRecoveredAssistantResponse(
                fallbackResponse,
                interactionGeneration: interactionGeneration,
              );
              currentAssistantContent = fallbackResponse;
              hasTextResponse = true;
              break;
            }
          }
          if (batchToolResults.isEmpty &&
              !attemptedDuplicateInspectionRecovery &&
              _containsOnlyReadOnlyInspectionToolCalls(currentToolCalls) &&
              recovered.isNotEmpty) {
            attemptedDuplicateInspectionRecovery = true;
            appLog(
              '[Tool] Duplicate read-only follow-up tool calls detected, requesting bounded recovery',
            );
            _appendToLastMessageForGeneration(interactionGeneration, '<think>');
            final mcpToolService = _mcpToolService;
            if (mcpToolService == null) {
              _turnToolResults.setCompleted(turnOwner, executedToolResults);
              await _sendWithoutTools(
                interactionGeneration: interactionGeneration,
              );
              return;
            }
            final tools = selectedDefinitionsFor(mcpToolService);
            List<Message> buildRecoveryMessages(bool forceCompaction) {
              final messages = _prepareMessagesForLLM(
                forceCompaction: forceCompaction,
                toolDefinitionsOverride: tools,
                interactionGeneration: interactionGeneration,
              );
              messages.add(
                Message(
                  id: 'tool_recovery_${DateTime.now().millisecondsSinceEpoch}',
                  isSynthesizedPrompt: true,
                  role: MessageRole.user,
                  content: _buildDuplicateInspectionRecoveryPrompt(
                    currentToolCalls,
                    previousToolResults: recovered,
                    hasSavedTask: _hasSavedTaskForGeneration(
                      interactionGeneration,
                    ),
                  ),
                  timestamp: DateTime.now(),
                ),
              );
              return messages;
            }

            final recoveryResult =
                await _createToolResultCompletionWithContextRetry(
                  logLabel: 'duplicate inspection recovery',
                  interactionGeneration: interactionGeneration,
                  buildMessages: buildRecoveryMessages,
                  toolResults: recovered,
                  assistantContent: currentAssistantContent,
                  tools: tools,
                );
            if (!_isCurrentInteractionGeneration(interactionGeneration)) {
              return;
            }
            if (!ref.mounted) return;
            _removeTrailingThinkTagForGeneration(interactionGeneration);
            if (recoveryResult.hasToolCalls) {
              appLog(
                '[Tool] Duplicate inspection recovery requested additional tool calls',
              );
              currentToolCalls = recoveryResult.toolCalls!;
              _recordHiddenEvidence(turnOwner, recoveryResult.content);
              if (recoveryResult.content.isNotEmpty) {
                currentAssistantContent = recoveryResult.content;
              }
              continue;
            }
            appLog(
              '[Tool] Duplicate inspection recovery returned final text response',
            );
            currentToolCalls = [];
            final fallbackResponse = recoveryResult.content.trim();
            _recordHiddenEvidence(turnOwner, fallbackResponse);
            if (_terminalToolResponsePolicy
                .shouldAcceptRecoveryFinalTextResponse(fallbackResponse)) {
              _appendRecoveredAssistantResponse(
                fallbackResponse,
                interactionGeneration: interactionGeneration,
              );
              currentAssistantContent = fallbackResponse;
              hasTextResponse = true;
              break;
            }
            break;
          }
          if (batchToolResults.isEmpty &&
              !attemptedDuplicateFollowUpRecovery &&
              recovered.isNotEmpty) {
            attemptedDuplicateFollowUpRecovery = true;
            appLog(
              '[Tool] Duplicate follow-up tool calls detected, requesting bounded recovery',
            );
            _appendToLastMessageForGeneration(interactionGeneration, '<think>');
            final mcpToolService = _mcpToolService;
            if (mcpToolService == null) {
              _turnToolResults.setCompleted(turnOwner, executedToolResults);
              await _sendWithoutTools(
                interactionGeneration: interactionGeneration,
              );
              return;
            }
            final tools = selectedDefinitionsFor(mcpToolService);
            List<Message> buildRecoveryMessages(bool forceCompaction) {
              final messages = _prepareMessagesForLLM(
                forceCompaction: forceCompaction,
                toolDefinitionsOverride: tools,
                interactionGeneration: interactionGeneration,
              );
              messages.add(
                Message(
                  id: 'tool_followup_recovery_${DateTime.now().millisecondsSinceEpoch}',
                  isSynthesizedPrompt: true,
                  role: MessageRole.user,
                  content: _buildDuplicateFollowUpRecoveryPrompt(
                    currentToolCalls,
                    previousToolResults: recovered,
                    hasSavedTask: _hasSavedTaskForGeneration(
                      interactionGeneration,
                    ),
                  ),
                  timestamp: DateTime.now(),
                ),
              );
              return messages;
            }

            final recoveryResult =
                await _createToolResultCompletionWithContextRetry(
                  logLabel: 'duplicate follow-up recovery',
                  interactionGeneration: interactionGeneration,
                  buildMessages: buildRecoveryMessages,
                  toolResults: recovered,
                  assistantContent: currentAssistantContent,
                  tools: tools,
                );
            if (!_isCurrentInteractionGeneration(interactionGeneration)) {
              return;
            }
            if (!ref.mounted) return;
            _removeTrailingThinkTagForGeneration(interactionGeneration);
            if (recoveryResult.hasToolCalls) {
              appLog(
                '[Tool] Duplicate follow-up recovery requested additional tool calls',
              );
              currentToolCalls = recoveryResult.toolCalls!;
              _recordHiddenEvidence(turnOwner, recoveryResult.content);
              if (recoveryResult.content.isNotEmpty) {
                currentAssistantContent = recoveryResult.content;
              }
              continue;
            }
            appLog(
              '[Tool] Duplicate follow-up recovery returned final text response',
            );
            currentToolCalls = [];
            final fallbackResponse = recoveryResult.content.trim();
            _recordHiddenEvidence(turnOwner, fallbackResponse);
            if (_terminalToolResponsePolicy
                .shouldAcceptRecoveryFinalTextResponse(fallbackResponse)) {
              _appendRecoveredAssistantResponse(
                fallbackResponse,
                interactionGeneration: interactionGeneration,
              );
              currentAssistantContent = fallbackResponse;
              hasTextResponse = true;
              break;
            }
            break;
          }
          if (batchToolResults.isEmpty) {
            appLog(
              '[Tool] Skipped duplicate follow-up tool calls, falling back to prior tool results',
            );
          }
        }
        if (batchToolResults.isEmpty) {
          currentToolCalls = [];
          break;
        }
      }

      appLog(
        '[Tool] Retrieved ${batchToolResults.length} tool result(s) in this loop',
      );
      lastNonEmptyBatchToolResults = List<ToolResultInfo>.unmodifiable(
        batchToolResults,
      );
      if (toolSearchEnabled) {
        final discoveredToolNames =
            ToolDefinitionSearchService.discoveredToolNamesFromResults(
              batchToolResults,
            );
        if (discoveredToolNames.isNotEmpty) {
          activeToolNames.addAll(discoveredToolNames);
          appLog(
            '[ToolSearch] Discovered tools: ${discoveredToolNames.toList()}',
          );
        }
      }

      _appendToLastMessageForGeneration(interactionGeneration, '<think>');

      final mcpToolService = _mcpToolService;
      if (mcpToolService == null) {
        _turnToolResults.setCompleted(turnOwner, executedToolResults);
        await _sendWithoutTools(interactionGeneration: interactionGeneration);
        return;
      }
      final tools = selectedDefinitionsFor(mcpToolService);
      final followUpToolResults = _stickyToolResultPolicy.resolve(
        batchToolResults: batchToolResults,
        executedToolResults: executedToolResults,
      );
      final savedValidationSucceeded =
          _toolResultsContainSuccessfulCurrentSavedValidation(
            batchToolResults,
            interactionGeneration,
          );
      final validationEvidenceRequiresRepair =
          _postSavedValidationEvidenceRequiresRepair(batchToolResults);
      final followUpTools =
          savedValidationSucceeded && !validationEvidenceRequiresRepair
          ? const <Map<String, dynamic>>[]
          : tools;
      if (followUpTools.isEmpty && tools.isNotEmpty) {
        appLog(
          '[Tool] Withholding tool definitions after saved validation success',
        );
      }
      final contextDigest = _toolLoopContextDigest.build(executedToolResults);
      final trimmedAssistantContent = currentAssistantContent?.trim();
      final followUpAssistantContent = contextDigest.isEmpty
          ? currentAssistantContent
          : [
              if (trimmedAssistantContent != null &&
                  trimmedAssistantContent.isNotEmpty)
                trimmedAssistantContent,
              contextDigest,
            ].join('\n\n');
      final nextResult = await _createToolResultCompletionWithContextRetry(
        logLabel: 'tool-result follow-up',
        interactionGeneration: interactionGeneration,
        buildMessages: (forceCompaction) => _prepareMessagesForLLM(
          forceCompaction: forceCompaction,
          toolDefinitionsOverride: followUpTools,
          interactionGeneration: interactionGeneration,
        ),
        toolResults: followUpToolResults,
        assistantContent: followUpAssistantContent,
        tools: followUpTools,
      );

      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      if (!ref.mounted) return;

      _removeTrailingThinkTagForGeneration(interactionGeneration);

      _lengthTruncatedToolCallIds = _truncationCasualties(nextResult);

      if (validationEvidenceRequiresRepair) {
        savedValidationSucceededInLoop = false;
        appLog('[Tool] Validation evidence exposed a repair requirement');
      } else if (savedValidationSucceeded) {
        savedValidationSucceededInLoop = true;
        appLog('[Tool] Saved validation command succeeded');
      }
      final gitLifecycleSucceeded = _toolResultsSatisfyCurrentGoalGitLifecycle(
        executedToolResults,
      );
      if (gitLifecycleSucceeded) {
        _turnEnd.markGoalClaimed(turnOwner);
        appLog('[Tool] Current git lifecycle goal already succeeded');
      }

      if (nextResult.hasToolCalls) {
        var nextToolCalls = nextResult.toolCalls!;
        final fallbackResponse = nextResult.content.trim();
        if (savedValidationSucceededInLoop) {
          final evidenceToolCalls = nextToolCalls
              .where(_isPostSavedValidationEvidenceToolCall)
              .toList(growable: false);
          if (evidenceToolCalls.isNotEmpty) {
            if (evidenceToolCalls.length != nextToolCalls.length) {
              appLog(
                '[Tool] Ignoring non-evidence follow-up tool calls after saved validation success',
              );
            }
            appLog('[Tool] Continuing post-validation evidence tool calls');
            nextToolCalls = evidenceToolCalls;
          } else {
            appLog(
              '[Tool] Ignoring follow-up tool calls after saved validation success',
            );
            currentToolCalls = [];
            final completionResponse = fallbackResponse.isNotEmpty
                ? fallbackResponse
                : 'The saved validation command succeeded for the current saved task, so the current saved task is complete.';
            _recordHiddenEvidence(turnOwner, completionResponse);
            _appendRecoveredAssistantResponse(
              completionResponse,
              interactionGeneration: interactionGeneration,
            );
            currentAssistantContent = completionResponse;
            hasTextResponse = true;
            break;
          }
        }
        if (gitLifecycleSucceeded) {
          appLog(
            '[Tool] Ignoring follow-up tool calls after git lifecycle success',
          );
          currentToolCalls = [];
          final completionResponse =
              _terminalToolResponsePolicy.shouldAcceptRecoveryFinalTextResponse(
                fallbackResponse,
              )
              ? fallbackResponse
              : _buildGitLifecycleCompletionResponse(executedToolResults);
          _recordHiddenEvidence(turnOwner, completionResponse);
          _appendRecoveredAssistantResponse(
            completionResponse,
            interactionGeneration: interactionGeneration,
          );
          currentAssistantContent = completionResponse;
          hasTextResponse = true;
          break;
        }
        if (_containsOnlyReadOnlyInspectionToolCalls(nextToolCalls) &&
            _shouldAcceptTerminalToolRoleFinalTextResponse(fallbackResponse)) {
          appLog(
            '[Tool] Ignoring read-only follow-up after terminal completion text',
          );
          currentToolCalls = [];
          _recordHiddenEvidence(turnOwner, fallbackResponse);
          _appendRecoveredAssistantResponse(
            fallbackResponse,
            interactionGeneration: interactionGeneration,
          );
          currentAssistantContent = fallbackResponse;
          hasTextResponse = true;
          break;
        }
        if (_shouldAcceptConstrainedSkillResponseBeforeFollowUpTools(
          fallbackResponse,
          batchToolResults,
          nextToolCalls,
        )) {
          appLog(
            '[Tool] Ignoring follow-up tool calls after constrained skill response',
          );
          currentToolCalls = [];
          final normalizedSkillResponse = _terminalToolResponsePolicy
              .normalizeTerminalSkillToolRoleResponse(
                fallbackResponse,
                batchToolResults,
              );
          _recordHiddenEvidence(turnOwner, normalizedSkillResponse);
          _appendRecoveredAssistantResponse(
            normalizedSkillResponse,
            interactionGeneration: interactionGeneration,
          );
          currentAssistantContent = normalizedSkillResponse;
          hasTextResponse = true;
          break;
        }
        appLog('[Tool] LLM requested additional tool calls');
        final assistantPreambleContent =
            _terminalToolResponsePolicy.hasSuccessfulLoadSkillResult(
                  batchToolResults,
                ) &&
                _terminalToolResponsePolicy
                    .looksLikeSkillContinuationWorkIntent(fallbackResponse)
            ? _terminalToolResponsePolicy
                  .normalizeTerminalSkillToolRoleResponse(
                    fallbackResponse,
                    batchToolResults,
                  )
            : nextResult.content;
        _appendAssistantToolPreambleIfPresent(
          assistantPreambleContent,
          interactionGeneration: interactionGeneration,
        );
        currentToolCalls = nextToolCalls;
        _recordHiddenEvidence(turnOwner, nextResult.content);
        currentAssistantContent = nextResult.content.isNotEmpty
            ? nextResult.content
            : currentAssistantContent;
        // Keep declared mutations instead of replaying stale recovery results.
        if (const ToolLoopExhaustionPolicy().shouldRequestRecovery(
          ToolLoopExhaustionDecisionInput(
            iteration: iteration,
            maxIterations: maxIterations,
            recoveryAlreadyAttempted: attemptedToolLoopExhaustionRecovery,
            hasPendingToolCalls: currentToolCalls.isNotEmpty,
            hasCurrentBatchToolResults: batchToolResults.isNotEmpty,
            hasPendingFileMutation: currentToolCalls.any(
              (toolCall) =>
                  _fileMutationEvidencePolicy.isMutationToolName(toolCall.name),
            ),
            hasPendingWriteGitCommand: currentToolCalls.any(
              const GitWriteConfirmationPolicy().isWriteGitCommandToolCall,
            ),
          ),
        )) {
          attemptedToolLoopExhaustionRecovery = true;
          appLog(
            '[Tool] Tool loop exhausted with pending tool calls, requesting bounded recovery',
          );
          _appendToLastMessageForGeneration(interactionGeneration, '<think>');
          final mcpToolService = _mcpToolService;
          if (mcpToolService == null) {
            _turnToolResults.setCompleted(turnOwner, executedToolResults);
            await _sendWithoutTools(
              interactionGeneration: interactionGeneration,
            );
            return;
          }
          final tools = selectedDefinitionsFor(mcpToolService);
          final recoveryToolResults = _buildToolLoopRecoveryToolResults(
            currentToolResults: batchToolResults,
            executedToolResults: executedToolResults,
            pendingToolCalls: currentToolCalls,
            projectRoot: _projectRootForGeneration(interactionGeneration),
          );
          List<Message> buildRecoveryMessages(bool forceCompaction) {
            final messages = _prepareMessagesForLLM(
              forceCompaction: forceCompaction,
              toolDefinitionsOverride: tools,
              interactionGeneration: interactionGeneration,
            );
            messages.add(
              Message(
                id: 'tool_loop_exhaustion_recovery_${DateTime.now().millisecondsSinceEpoch}',
                role: MessageRole.user,
                content: _buildToolLoopExhaustionRecoveryPrompt(
                  currentToolCalls,
                  previousToolResults: recoveryToolResults,
                ),
                timestamp: DateTime.now(),
              ),
            );
            return messages;
          }

          final recoveryResult =
              await _createToolResultCompletionWithContextRetry(
                logLabel: 'tool-loop exhaustion recovery',
                interactionGeneration: interactionGeneration,
                buildMessages: buildRecoveryMessages,
                toolResults: recoveryToolResults,
                assistantContent: currentAssistantContent,
                tools: tools,
              );
          if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
          if (!ref.mounted) return;
          _removeTrailingThinkTagForGeneration(interactionGeneration);
          if (recoveryResult.hasToolCalls) {
            appLog(
              '[Tool] Tool loop exhaustion recovery requested additional tool calls',
            );
            currentToolCalls = recoveryResult.toolCalls!;
            _recordHiddenEvidence(turnOwner, recoveryResult.content);
            currentAssistantContent = recoveryResult.content.isNotEmpty
                ? recoveryResult.content
                : currentAssistantContent;
            final editMismatch = _toolResultsContainEditMismatch(
              recoveryToolResults,
            );
            requestBudgetExtension(
              editMismatch
                  ? ExecutionBudgetExtensionReason.editMismatchRecovery
                  : ExecutionBudgetExtensionReason.toolLoopExhaustion,
              requestedIterations: editMismatch ? 4 : 2,
            );
          } else {
            appLog(
              '[Tool] Tool loop exhaustion recovery returned final text response',
            );
            currentToolCalls = [];
            final fallbackResponse = recoveryResult.content.trim();
            _recordHiddenEvidence(turnOwner, fallbackResponse);
            if (_terminalToolResponsePolicy
                .shouldAcceptRecoveryFinalTextResponse(fallbackResponse)) {
              _appendRecoveredAssistantResponse(
                fallbackResponse,
                interactionGeneration: interactionGeneration,
              );
              currentAssistantContent = fallbackResponse;
              hasTextResponse = true;
              break;
            }
          }
        }
      } else {
        // End the loop on a text response, but delay rendering it.
        appLog('[Tool] LLM returned final text response (via tool role)');
        currentToolCalls = [];
        final fallbackResponse = nextResult.content.trim();
        _recordHiddenEvidence(turnOwner, fallbackResponse);
        final browserActionRepairResult =
            await _requestSkippedBrowserActionRepairAfterSnapshot(
              candidateResponse: fallbackResponse,
              batchToolResults: batchToolResults,
              tools: tools,
              interactionGeneration: interactionGeneration,
            );
        if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
        if (!ref.mounted) return;
        if (browserActionRepairResult != null) {
          if (browserActionRepairResult.hasToolCalls) {
            appLog(
              '[Tool] Browser action repair requested follow-up tool calls',
            );
            currentToolCalls = browserActionRepairResult.toolCalls!;
            _recordHiddenEvidence(turnOwner, browserActionRepairResult.content);
            currentAssistantContent =
                browserActionRepairResult.content.isNotEmpty
                ? browserActionRepairResult.content
                : fallbackResponse;
            continue;
          }

          final unexecutedBrowserAction = _claims
              .buildUnexecutedSkippedBrowserActionToolResult(
                candidateResponse: browserActionRepairResult.content.isNotEmpty
                    ? browserActionRepairResult.content
                    : fallbackResponse,
                batchToolResults: batchToolResults,
                latestUserContent: turnSnapshot!.latestUserContent,
              );
          if (unexecutedBrowserAction != null) {
            executedToolResults.add(unexecutedBrowserAction);
            _recordHiddenEvidence(turnOwner, browserActionRepairResult.content);
          }
        }
        if (!attemptedPythonAttachmentPathRepair) {
          attemptedPythonAttachmentPathRepair = true;
          final pythonAttachmentPathRepairResult =
              await _requestPythonAttachmentPathFailureRepair(
                candidateResponse: fallbackResponse,
                batchToolResults: batchToolResults,
                executedToolResults: executedToolResults,
                tools: tools,
                interactionGeneration: interactionGeneration,
              );
          if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
          if (!ref.mounted) return;
          if (pythonAttachmentPathRepairResult != null) {
            if (pythonAttachmentPathRepairResult.hasToolCalls) {
              appLog(
                '[Tool] Python attachment path repair requested tool calls',
              );
              currentToolCalls = pythonAttachmentPathRepairResult.toolCalls!;
              _recordHiddenEvidence(
                turnOwner,
                pythonAttachmentPathRepairResult.content,
              );
              currentAssistantContent =
                  pythonAttachmentPathRepairResult.content.isNotEmpty
                  ? pythonAttachmentPathRepairResult.content
                  : fallbackResponse;
              continue;
            }
            _recordHiddenEvidence(
              turnOwner,
              pythonAttachmentPathRepairResult.content,
            );
          }
        }
        if (!attemptedSkippedPythonAttachmentRepair) {
          attemptedSkippedPythonAttachmentRepair = true;
          final pythonAttachmentRepairResult =
              await _requestSkippedPythonAttachmentAnalysisRepair(
                candidateResponse: fallbackResponse,
                batchToolResults: batchToolResults,
                executedToolResults: executedToolResults,
                tools: tools,
                interactionGeneration: interactionGeneration,
              );
          if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
          if (!ref.mounted) return;
          if (pythonAttachmentRepairResult != null) {
            if (pythonAttachmentRepairResult.hasToolCalls) {
              appLog('[Tool] Python attachment repair requested tool calls');
              currentToolCalls = pythonAttachmentRepairResult.toolCalls!;
              _recordHiddenEvidence(
                turnOwner,
                pythonAttachmentRepairResult.content,
              );
              currentAssistantContent =
                  pythonAttachmentRepairResult.content.isNotEmpty
                  ? pythonAttachmentRepairResult.content
                  : fallbackResponse;
              continue;
            }
            _recordHiddenEvidence(
              turnOwner,
              pythonAttachmentRepairResult.content,
            );
          }
        }
        final backgroundProcessRepairResult =
            await _requestBackgroundProcessMonitorRepairForCompletionClaim(
              candidateResponse: fallbackResponse,
              executedToolResults: executedToolResults,
              batchToolResults: batchToolResults,
              tools: tools,
              interactionGeneration: interactionGeneration,
            );
        if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
        if (!ref.mounted) return;
        if (backgroundProcessRepairResult != null) {
          if (backgroundProcessRepairResult.hasToolCalls) {
            appLog(
              '[BackgroundProcess] Monitor follow-up requested tool calls',
            );
            currentToolCalls = backgroundProcessRepairResult.toolCalls!;
            _recordHiddenEvidence(
              turnOwner,
              backgroundProcessRepairResult.content,
            );
            currentAssistantContent =
                backgroundProcessRepairResult.content.isNotEmpty
                ? backgroundProcessRepairResult.content
                : fallbackResponse;
            if (iteration >= maxIterations) {
              requestBudgetExtension(
                ExecutionBudgetExtensionReason.backgroundProcessMonitoring,
              );
            }
            continue;
          }

          final monitorResponse = backgroundProcessRepairResult.content.trim();
          _recordHiddenEvidence(turnOwner, monitorResponse);
          final monitorFollowUp =
              BackgroundProcessFollowUpPolicy.followUpToolCall(
                executedToolResults,
                waitMs: BackgroundProcessFollowUpPolicy.waitMsForIteration(
                  iteration,
                ),
              );
          if (monitorFollowUp != null &&
              forcedBackgroundProcessFollowUpCount < 2) {
            appLog(
              '[BackgroundProcess] Monitor prose response forced follow-up '
              'process check',
            );
            forcedBackgroundProcessFollowUpCount += 1;
            currentToolCalls = [monitorFollowUp];
            currentAssistantContent = monitorResponse;
            if (iteration >= maxIterations) {
              requestBudgetExtension(
                ExecutionBudgetExtensionReason.backgroundProcessMonitoring,
              );
            }
            continue;
          }

          currentToolCalls = [];
          if (monitorResponse.isNotEmpty) {
            _appendRecoveredAssistantResponse(
              monitorResponse,
              interactionGeneration: interactionGeneration,
            );
            currentAssistantContent = monitorResponse;
            hasTextResponse = true;
            break;
          }
          break;
        }
        final runningProcessFollowUp =
            BackgroundProcessFollowUpPolicy.followUpToolCall(
              executedToolResults,
              waitMs: BackgroundProcessFollowUpPolicy.waitMsForIteration(
                iteration,
              ),
            );
        if (runningProcessFollowUp != null &&
            forcedBackgroundProcessFollowUpCount < 2) {
          appLog(
            '[BackgroundProcess] Running process prose response forced '
            'follow-up process check',
          );
          forcedBackgroundProcessFollowUpCount += 1;
          currentToolCalls = [runningProcessFollowUp];
          currentAssistantContent = fallbackResponse;
          if (iteration >= maxIterations) {
            requestBudgetExtension(
              ExecutionBudgetExtensionReason.backgroundProcessMonitoring,
            );
          }
          continue;
        }
        final verificationRepairResult =
            await _requestCodingVerificationRepairForCompletionClaim(
              candidateResponse: fallbackResponse,
              executedToolResults: executedToolResults,
              batchToolResults: batchToolResults,
              attemptedMutationSignatures:
                  attemptedCompletionVerificationMutationSignatures,
              verificationFailureCounts: verificationFailureCounts,
              tools: tools,
              interactionGeneration: interactionGeneration,
            );
        if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
        if (!ref.mounted) return;
        if (verificationRepairResult != null) {
          if (verificationRepairResult.hasToolCalls) {
            appLog(
              '[CodingVerification] Repair follow-up requested tool calls',
            );
            currentToolCalls = verificationRepairResult.toolCalls!;
            _recordHiddenEvidence(turnOwner, verificationRepairResult.content);
            currentAssistantContent =
                verificationRepairResult.content.isNotEmpty
                ? verificationRepairResult.content
                : fallbackResponse;
            if (iteration >= maxIterations) {
              requestBudgetExtension(
                ExecutionBudgetExtensionReason.verificationRepair,
              );
            }
            continue;
          }

          final verificationResponse = verificationRepairResult.content.trim();
          currentToolCalls = [];
          _recordHiddenEvidence(turnOwner, verificationResponse);
          if (verificationResponse.isNotEmpty) {
            _appendRecoveredAssistantResponse(
              verificationResponse,
              interactionGeneration: interactionGeneration,
            );
            currentAssistantContent = verificationResponse;
            hasTextResponse = true;
            break;
          }
          break;
        }
        final shouldSkipCodingContinuationRecovery =
            _shouldSkipCompletedToolResultCodingContinuationRecovery(
              candidateResponse: fallbackResponse,
              toolResults: batchToolResults,
              interactionGeneration: interactionGeneration,
            );
        if (shouldSkipCodingContinuationRecovery) {
          appLog(
            '[Tool] Skipping coding continuation recovery after completed tool-result response',
          );
        }
        if (!attemptedCodingContinuationRecovery &&
            !shouldSkipCodingContinuationRecovery) {
          final codingContinuationRecoveryResult =
              await _requestCodingContinuationRecovery(
                candidateResponse: fallbackResponse,
                tools: tools,
                interactionGeneration: interactionGeneration,
                requireContinuationRequest: false,
                executedToolResults: executedToolResults,
              );
          if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
          if (!ref.mounted) return;
          if (codingContinuationRecoveryResult != null) {
            attemptedCodingContinuationRecovery = true;
            if (codingContinuationRecoveryResult.hasToolCalls) {
              appLog(
                '[Tool] Coding continuation recovery requested follow-up tool calls',
              );
              currentToolCalls = codingContinuationRecoveryResult.toolCalls!;
              activeToolNames.addAll(
                currentToolCalls.map((toolCall) => toolCall.name),
              );
              _recordHiddenEvidence(
                turnOwner,
                codingContinuationRecoveryResult.content,
              );
              currentAssistantContent =
                  codingContinuationRecoveryResult.content.isNotEmpty
                  ? codingContinuationRecoveryResult.content
                  : fallbackResponse;
              if (iteration >= maxIterations) {
                requestBudgetExtension(
                  ExecutionBudgetExtensionReason.codingContinuation,
                );
              }
              continue;
            }
            _recordHiddenEvidence(
              turnOwner,
              codingContinuationRecoveryResult.content,
            );
          }
        }
        if (savedValidationSucceededInLoop && fallbackResponse.isNotEmpty) {
          appLog(
            '[Tool] Accepting saved-validation final text without final answer fallback',
          );
          _appendRecoveredAssistantResponse(
            fallbackResponse,
            interactionGeneration: interactionGeneration,
          );
          currentAssistantContent = fallbackResponse;
          hasTextResponse = true;
          break;
        }
        if (_shouldAcceptTerminalToolRoleFinalTextResponse(
          fallbackResponse,
          batchToolResults,
        )) {
          appLog(
            '[Tool] Accepting terminal tool-role final text response without final answer fallback',
          );
          _appendRecoveredAssistantResponse(
            fallbackResponse,
            interactionGeneration: interactionGeneration,
          );
          currentAssistantContent = fallbackResponse;
          hasTextResponse = true;
          break;
        }
        if (_shouldAcceptTerminalBrowserSaveDataResponse(
          fallbackResponse,
          batchToolResults,
        )) {
          appLog(
            '[Tool] Accepting terminal browser save response without final answer fallback',
          );
          final normalizedBrowserSaveResponse = _terminalToolResponsePolicy
              .normalizeTerminalBrowserSaveDataResponse(fallbackResponse);
          _appendRecoveredAssistantResponse(
            normalizedBrowserSaveResponse,
            interactionGeneration: interactionGeneration,
          );
          currentAssistantContent = normalizedBrowserSaveResponse;
          hasTextResponse = true;
          break;
        }
        if (_shouldAcceptTerminalFileMutationFinalTextResponse(
          fallbackResponse,
          batchToolResults,
        )) {
          appLog(
            '[Tool] Accepting terminal file-mutation final text response without final answer fallback',
          );
          _appendRecoveredAssistantResponse(
            fallbackResponse,
            interactionGeneration: interactionGeneration,
          );
          currentAssistantContent = fallbackResponse;
          hasTextResponse = true;
          break;
        }
        final skillTerminalToolResults =
            _terminalToolResponsePolicy.hasSuccessfulLoadSkillResult(
              batchToolResults,
            )
            ? batchToolResults
            : executedToolResults;
        if (_shouldAcceptTerminalSkillToolRoleResponse(
          fallbackResponse,
          skillTerminalToolResults,
        )) {
          appLog(
            '[Tool] Accepting terminal skill tool-role response without final answer fallback',
          );
          final normalizedSkillResponse = _terminalToolResponsePolicy
              .normalizeTerminalSkillToolRoleResponse(
                fallbackResponse,
                skillTerminalToolResults,
              );
          _appendRecoveredAssistantResponse(
            normalizedSkillResponse,
            interactionGeneration: interactionGeneration,
          );
          currentAssistantContent = normalizedSkillResponse;
          hasTextResponse = true;
          break;
        }
        if (_shouldAcceptTerminalToolRoleBlockerResponse(fallbackResponse)) {
          appLog(
            '[Tool] Accepting terminal tool-role blocker response without final answer fallback',
          );
          _appendRecoveredAssistantResponse(
            fallbackResponse,
            interactionGeneration: interactionGeneration,
          );
          currentAssistantContent = fallbackResponse;
          hasTextResponse = true;
          break;
        }
      }
    }

    if (!hasTextResponse &&
        currentToolCalls.isNotEmpty &&
        iteration >= maxIterations) {
      appLog(
        '[Tool] Tool loop reached limit with a declared pending batch; '
        'executing it before finalization',
      );
      final finalBatchResult = await _executeToolLoopBatch(
        currentToolCalls: currentToolCalls,
        currentAssistantContent: currentAssistantContent,
        executedToolResults: executedToolResults,
        executedToolCallKeys: executedToolCallKeys,
        toolFailureCounts: toolFailureCounts,
        commandRetryGeneration: commandRetryGeneration,
        stateChangeGeneration: stateChangeGeneration,
        iteration: iteration + 1,
        interactionGeneration: interactionGeneration,
        verifierOnlyContinuation: verifierOnlyContinuation,
      );
      if (finalBatchResult.didCancel) return;
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      if (!ref.mounted) return;
      commandRetryGeneration = finalBatchResult.commandRetryGeneration;
      final completedToolCallIds = finalBatchResult.batchToolResults
          .map((result) => result.id)
          .toSet();
      currentToolCalls = finalBatchResult.pendingBatchCalls
          .where((toolCall) => !completedToolCallIds.contains(toolCall.id))
          .toList(growable: false);
      if (finalBatchResult.batchToolResults.isNotEmpty &&
          currentToolCalls.isEmpty) {
        _turnEnd.setHintIfAbsent(
          turnOwner,
          ToolLoopExitReason.pendingBatchExecuted,
        );
      }
    }

    final unexecutedPendingToolResults = _buildUnexecutedPendingToolResults(
      toolCalls: currentToolCalls,
      executedToolCallKeys: executedToolCallKeys,
      commandRetryGeneration: commandRetryGeneration,
      projectRoot: _projectRootForGeneration(interactionGeneration),
    );
    final unexecutedFileSideEffect = _claims
        .buildUnexecutedFileSideEffectToolResult(
          candidateResponse: currentAssistantContent ?? '',
          toolResults: [
            ...executedToolResults,
            ...unexecutedPendingToolResults,
          ],
          latestUserContent: turnSnapshot!.latestUserContent,
        );
    // Re-run analysis so final diagnostics reflect the post-edit state.
    final finalDiagnosticFeedback = hasTextResponse
        ? null
        : await _buildFinalCodingDiagnosticFeedbackToolResult(
            executedToolResults,
            interactionGeneration: interactionGeneration,
          );
    if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
    if (finalDiagnosticFeedback != null) {
      _logCodingDiagnosticFeedbackSummary(finalDiagnosticFeedback);
    }
    final finalToolResults = <ToolResultInfo>[
      ...executedToolResults,
      ...unexecutedPendingToolResults,
      ?unexecutedFileSideEffect,
      ?finalDiagnosticFeedback,
    ];
    var finalCompletionEvidence = ToolResultPromptBuilder.completionEvidence(
      finalToolResults,
    );
    finalCompletionEvidence = _goalCompletionEvidence
        .settleSuccessfulSavedValidation(
          finalCompletionEvidence,
          conversation: _conversationForGeneration(interactionGeneration),
          succeeded: savedValidationSucceededInLoop,
        );
    var finalCompletionEvidenceIsCurrent = true;
    if (!hasTextResponse && finalToolResults.isNotEmpty) {
      appLog('[Tool] Resending tool results as user message');
      if (!ref.mounted) return;
      final preFinalAnswerContent =
          _lastMessageContentForGeneration(interactionGeneration) ?? '';
      final toolResultCountBeforeFinalAnswer = finalToolResults.length;
      final mcpToolService = _mcpToolService;
      final recoveryTools = mcpToolService == null
          ? const <Map<String, dynamic>>[]
          : selectedDefinitionsFor(mcpToolService);
      final canPreparePendingActionRecovery = _pendingActions
          .canPrepareActionOnlyRecovery(
            isCodingWorkspace: _isCodingWorkspaceOrMode(interactionGeneration),
            hasAvailableActionTools: _hasCodingContinuationRecoveryTools(
              recoveryTools,
            ),
            retryAlreadyUsed: _pendingActionLengthRecoveryGenerations.contains(
              interactionGeneration,
            ),
            completionEvidence: finalCompletionEvidence,
          );
      var streamedFinalAnswer = await _streamToolResultAnswerWithContextRetry(
        toolResults: finalToolResults,
        interactionGeneration: interactionGeneration,
        completionEvidence: finalCompletionEvidence,
        deferIncompleteLengthRecovery: canPreparePendingActionRecovery,
      );
      if (finalToolResults.length != toolResultCountBeforeFinalAnswer) {
        finalCompletionEvidenceIsCurrent = false;
      }
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      if (!ref.mounted) return;

      final shouldRequestPendingActionRecovery = _pendingActions
          .shouldRequestActionOnlyRecovery(
            finishReason: _responseMetadata.finishReasonFor(turnOwner),
            isCodingWorkspace: _isCodingWorkspaceOrMode(interactionGeneration),
            hasAvailableActionTools: _hasCodingContinuationRecoveryTools(
              recoveryTools,
            ),
            retryAlreadyUsed: _pendingActionLengthRecoveryGenerations.contains(
              interactionGeneration,
            ),
            completionEvidence: finalCompletionEvidence,
          );
      if (shouldRequestPendingActionRecovery) {
        _pendingActionLengthRecoveryGenerations.add(interactionGeneration);
        _turnEnd.addTransform(turnOwner, 'pending_action_length_recovery');
        appLog(
          '[PendingActionLengthRecovery] Requesting one bounded tool-aware '
          'retry; evidence=${finalCompletionEvidence.summary}',
        );
        final recoveryResult = await _requestCodingContinuationRecovery(
          candidateResponse: streamedFinalAnswer,
          tools: recoveryTools,
          interactionGeneration: interactionGeneration,
          requireContinuationRequest: false,
          executedToolResults: finalToolResults,
          forcedRecoveryCode: 'length_truncated_pending_action',
          forcedRecoveryPrompt: _pendingActions.buildRetryPrompt(
            finalCompletionEvidence,
          ),
        );
        if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
        if (!ref.mounted) return;
        if (recoveryResult?.hasToolCalls == true) {
          appLog(
            '[PendingActionLengthRecovery] Tool-aware retry requested one or '
            'more tool calls',
          );
          _recordHiddenEvidence(turnOwner, streamedFinalAnswer);
          _removeStreamedAnswerSuffixForGeneration(
            interactionGeneration,
            preAnswerContent: preFinalAnswerContent,
          );
          final recoveredToolCalls = recoveryResult!.toolCalls!;
          await _executeToolCalls(
            recoveredToolCalls,
            assistantContent: recoveryResult.content.isNotEmpty
                ? recoveryResult.content
                : streamedFinalAnswer,
            toolSearchEnabled: toolSearchEnabled,
            selectedToolNames: {
              ...activeToolNames,
              ...recoveredToolCalls.map((toolCall) => toolCall.name),
            },
            stableToolDefinitions: stableToolDefinitions,
            completionVerificationFailureCounts: verificationFailureCounts,
            narratedTranscriptRepairSignatures: transcriptRepairSignatures,
            replayVerifierImmediatelyAfterMutation:
                replayVerifierImmediatelyAfterMutation,
            verifierOnlyContinuation: verifierOnlyContinuation,
            interactionGeneration: interactionGeneration,
          );
          return;
        }
        final recoveryContent = recoveryResult?.content.trim() ?? '';
        if (recoveryContent.isNotEmpty) {
          _recordHiddenEvidence(turnOwner, streamedFinalAnswer);
          _removeStreamedAnswerSuffixForGeneration(
            interactionGeneration,
            preAnswerContent: preFinalAnswerContent,
          );
          _appendRecoveredAssistantResponse(
            recoveryContent,
            interactionGeneration: interactionGeneration,
          );
          streamedFinalAnswer = recoveryContent;
        }
      }

      if (mcpToolService != null) {
        final streamVerificationBatchToolResults = <ToolResultInfo>[];
        final tools = recoveryTools;
        final backgroundProcessRepairResult =
            await _requestBackgroundProcessMonitorRepairForCompletionClaim(
              candidateResponse: streamedFinalAnswer,
              executedToolResults: executedToolResults,
              batchToolResults: streamVerificationBatchToolResults,
              tools: tools,
              interactionGeneration: interactionGeneration,
              onBlockingFeedbackPrepared: () =>
                  _removeStreamedAnswerSuffixForGeneration(
                    interactionGeneration,
                    preAnswerContent: preFinalAnswerContent,
                  ),
            );
        if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
        if (!ref.mounted) return;
        if (backgroundProcessRepairResult != null) {
          if (backgroundProcessRepairResult.hasToolCalls) {
            appLog(
              '[BackgroundProcess] Streamed final answer monitor follow-up '
              'requested tool calls',
            );
            await _executeToolCalls(
              backgroundProcessRepairResult.toolCalls!,
              assistantContent: backgroundProcessRepairResult.content.isNotEmpty
                  ? backgroundProcessRepairResult.content
                  : streamedFinalAnswer,
              toolSearchEnabled: toolSearchEnabled,
              selectedToolNames: activeToolNames,
              stableToolDefinitions: stableToolDefinitions,
              completionVerificationFailureCounts: verificationFailureCounts,
              narratedTranscriptRepairSignatures: transcriptRepairSignatures,
              verifierOnlyContinuation: verifierOnlyContinuation,
              interactionGeneration: interactionGeneration,
            );
            return;
          }

          final monitorResponse = backgroundProcessRepairResult.content.trim();
          _recordHiddenEvidence(turnOwner, monitorResponse);
          final monitorFollowUp =
              BackgroundProcessFollowUpPolicy.followUpToolCall(
                executedToolResults,
                waitMs: BackgroundProcessFollowUpPolicy.waitMsForIteration(
                  maxIterations,
                ),
              );
          if (monitorFollowUp != null) {
            appLog(
              '[BackgroundProcess] Streamed final answer monitor prose '
              'response forced follow-up process check',
            );
            await _executeToolCalls(
              [monitorFollowUp],
              assistantContent: monitorResponse.isNotEmpty
                  ? monitorResponse
                  : streamedFinalAnswer,
              toolSearchEnabled: toolSearchEnabled,
              selectedToolNames: activeToolNames,
              stableToolDefinitions: stableToolDefinitions,
              completionVerificationFailureCounts: verificationFailureCounts,
              narratedTranscriptRepairSignatures: transcriptRepairSignatures,
              verifierOnlyContinuation: verifierOnlyContinuation,
              interactionGeneration: interactionGeneration,
            );
            return;
          }

          if (monitorResponse.isNotEmpty) {
            _appendRecoveredAssistantResponse(
              monitorResponse,
              interactionGeneration: interactionGeneration,
            );
            currentAssistantContent = monitorResponse;
            hasTextResponse = true;
          }
        }
        final verificationRepairResult =
            await _requestCodingVerificationRepairForCompletionClaim(
              candidateResponse: streamedFinalAnswer,
              executedToolResults: executedToolResults,
              batchToolResults: streamVerificationBatchToolResults,
              retainedEvidenceToolResults: finalToolResults,
              attemptedMutationSignatures:
                  attemptedCompletionVerificationMutationSignatures,
              verificationFailureCounts: verificationFailureCounts,
              tools: tools,
              interactionGeneration: interactionGeneration,
              onBlockingFeedbackPrepared: () =>
                  _removeStreamedAnswerSuffixForGeneration(
                    interactionGeneration,
                    preAnswerContent: preFinalAnswerContent,
                  ),
            );
        if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
        if (!ref.mounted) return;
        if (verificationRepairResult != null) {
          if (verificationRepairResult.hasToolCalls) {
            appLog(
              '[CodingVerification] Streamed final answer repair requested '
              'tool calls',
            );
            await _executeToolCalls(
              verificationRepairResult.toolCalls!,
              assistantContent: verificationRepairResult.content.isNotEmpty
                  ? verificationRepairResult.content
                  : streamedFinalAnswer,
              toolSearchEnabled: toolSearchEnabled,
              selectedToolNames: activeToolNames,
              stableToolDefinitions: stableToolDefinitions,
              completionVerificationFailureCounts: verificationFailureCounts,
              narratedTranscriptRepairSignatures: transcriptRepairSignatures,
              verifierOnlyContinuation: verifierOnlyContinuation,
              interactionGeneration: interactionGeneration,
            );
            return;
          }

          final verificationResponse = verificationRepairResult.content.trim();
          if (verificationResponse.isNotEmpty) {
            _appendRecoveredAssistantResponse(
              verificationResponse,
              interactionGeneration: interactionGeneration,
            );
          }
        }
        final handledByReleaseRetry =
            await _applyBlockedProductionReleaseRetryToStreamedFinalAnswer(
              streamedFinalAnswer: streamedFinalAnswer,
              executedToolResults: executedToolResults,
              batchToolResults: streamVerificationBatchToolResults,
              tools: tools,
              toolSearchEnabled: toolSearchEnabled,
              activeToolNames: activeToolNames,
              stableToolDefinitions: stableToolDefinitions,
              verificationFailureCounts: verificationFailureCounts,
              transcriptRepairSignatures: transcriptRepairSignatures,
              interactionGeneration: interactionGeneration,
              onBlockingFeedbackPrepared: () =>
                  _removeStreamedAnswerSuffixForGeneration(
                    interactionGeneration,
                    preAnswerContent: preFinalAnswerContent,
                  ),
            );
        if (handledByReleaseRetry) return;
        final handledByTranscriptRepair =
            await _applyNarratedTranscriptRepairToStreamedFinalAnswer(
              streamedFinalAnswer: streamedFinalAnswer,
              executedToolResults: executedToolResults,
              batchToolResults: streamVerificationBatchToolResults,
              attemptedSignatures: transcriptRepairSignatures,
              tools: tools,
              toolSearchEnabled: toolSearchEnabled,
              activeToolNames: activeToolNames,
              stableToolDefinitions: stableToolDefinitions,
              verificationFailureCounts: verificationFailureCounts,
              interactionGeneration: interactionGeneration,
              onBlockingFeedbackPrepared: () =>
                  _removeStreamedAnswerSuffixForGeneration(
                    interactionGeneration,
                    preAnswerContent: preFinalAnswerContent,
                  ),
            );
        if (handledByTranscriptRepair) return;
        if (const FencedToolArgumentsDetector().detect(streamedFinalAnswer) !=
            null) {
          final handledByFencedRetry =
              await _applyUnexecutedCommandActionRetryToStreamedFinalAnswer(
                streamedFinalAnswer: streamedFinalAnswer,
                executedToolResults: finalToolResults,
                batchToolResults: streamVerificationBatchToolResults,
                allowedToolNames: turnSnapshot.allowedToolNames,
                tools: tools,
                toolSearchEnabled: toolSearchEnabled,
                activeToolNames: activeToolNames,
                stableToolDefinitions: stableToolDefinitions,
                verificationFailureCounts: verificationFailureCounts,
                transcriptRepairSignatures: transcriptRepairSignatures,
                interactionGeneration: interactionGeneration,
                onBlockingFeedbackPrepared: () =>
                    _removeStreamedAnswerSuffixForGeneration(
                      interactionGeneration,
                      preAnswerContent: preFinalAnswerContent,
                    ),
              );
          if (handledByFencedRetry) return;
        }
        final unexecutedCommandAction =
            _toolCallExecutionPolicy.offersCommandExecution(
              turnSnapshot.allowedToolNames,
            )
            ? _claims.buildUnexecutedCommandActionToolResult(
                candidateResponse: streamedFinalAnswer,
                toolResults: finalToolResults,
              )
            : null;
        if (unexecutedCommandAction != null) {
          finalToolResults.add(unexecutedCommandAction);
          finalCompletionEvidenceIsCurrent = false;
          final handledByCommandRetry =
              await _applyUnexecutedCommandActionRetryToStreamedFinalAnswer(
                streamedFinalAnswer: streamedFinalAnswer,
                executedToolResults: finalToolResults,
                batchToolResults: streamVerificationBatchToolResults,
                allowedToolNames: turnSnapshot.allowedToolNames,
                tools: tools,
                toolSearchEnabled: toolSearchEnabled,
                activeToolNames: activeToolNames,
                stableToolDefinitions: stableToolDefinitions,
                verificationFailureCounts: verificationFailureCounts,
                transcriptRepairSignatures: transcriptRepairSignatures,
                interactionGeneration: interactionGeneration,
                onBlockingFeedbackPrepared: () =>
                    _removeStreamedAnswerSuffixForGeneration(
                      interactionGeneration,
                      preAnswerContent: preFinalAnswerContent,
                    ),
              );
          if (handledByCommandRetry) return;
          _appendUnexecutedCommandActionNoticeIfNeeded(
            toolResults: finalToolResults,
            owner: turnOwner,
          );
        } else {
          final unverifiedInspectionClaim = _claims
              .buildUnverifiedReadOnlyInspectionClaimToolResult(
                candidateResponse: streamedFinalAnswer,
                toolResults: finalToolResults,
              );
          if (unverifiedInspectionClaim != null) {
            finalToolResults.add(unverifiedInspectionClaim);
            finalCompletionEvidenceIsCurrent = false;
            _appendUnverifiedReadOnlyInspectionClaimNoticeIfNeeded(
              toolResults: finalToolResults,
              owner: turnOwner,
            );
          }
        }
      }
    } else if (!hasTextResponse) {
      appLog('[Tool] Tool loop reached maximum iterations (no text response)');
      if (state.messages.isNotEmpty) {
        _appendToLastMessageForGeneration(
          interactionGeneration,
          '\nSorry, there was a problem executing the tools. Please try again later.',
        );
      }
    }

    if (!finalCompletionEvidenceIsCurrent) {
      finalCompletionEvidence = ToolResultPromptBuilder.completionEvidence(
        finalToolResults,
      );
      finalCompletionEvidence = _goalCompletionEvidence
          .settleSuccessfulSavedValidation(
            finalCompletionEvidence,
            conversation: _conversationForGeneration(interactionGeneration),
            succeeded: savedValidationSucceededInLoop,
          );
    }
    finalCompletionEvidence = _goalCompletionEvidence
        .replaceWithCombinedEvidence(turnOwner, finalCompletionEvidence);
    final postMutationVerifierReplay = _takePostMutationVerifierReplay(
      evidence: finalCompletionEvidence,
      interactionGeneration: interactionGeneration,
    );
    if (postMutationVerifierReplay != null) {
      appLog(
        '[CodingVerification] Replaying the last executed verifier after '
        'a later mutation',
      );
      await _executeToolCalls(
        [postMutationVerifierReplay],
        assistantContent:
            'The implementation changed after its last verification. '
            'Re-running the same verifier now.',
        toolSearchEnabled: toolSearchEnabled,
        selectedToolNames: activeToolNames,
        stableToolDefinitions: stableToolDefinitions,
        completionVerificationFailureCounts: verificationFailureCounts,
        narratedTranscriptRepairSignatures: transcriptRepairSignatures,
        verifierOnlyContinuation: verifierOnlyContinuation,
        interactionGeneration: interactionGeneration,
      );
      return;
    }
    await _recordSuccessfulVerificationGenerationIfNeeded(
      finalCompletionEvidence,
      owner: turnOwner,
    );
    if (!_activeResponseRegistry.containsOwner(turnOwner)) return;
    _turnToolResults.setCompleted(turnOwner, finalToolResults);
    await _finishStreaming(interactionGeneration: interactionGeneration);
  }

  static const _stickyToolResultPolicy = StickyToolResultPolicy();

  void _appendToLastMessageForGeneration(
    int generation,
    String chunk, {
    bool scanForTools = true,
  }) {
    if (_isActiveResponseDetachedForGeneration(generation)) {
      final activeMessages = _activeResponseMessagesForGeneration(generation);
      if (activeMessages == null || activeMessages.isEmpty) return;

      final updatedMessages = [...activeMessages];
      final lastIndex = updatedMessages.length - 1;
      final lastMessage = updatedMessages[lastIndex];
      final newContent = lastMessage.content + chunk;
      _runtimeEvents.emitRuntimeAssistantContent(generation, newContent);
      updatedMessages[lastIndex] = lastMessage.copyWith(content: newContent);
      _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
      if (scanForTools) {
        _checkForContentToolCalls(
          newContent,
          interactionGeneration: generation,
        );
      }
      return;
    }

    if (!ref.mounted || state.messages.isEmpty) return;

    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];

    final newContent = lastMessage.content + chunk;
    _runtimeEvents.emitRuntimeAssistantContent(generation, newContent);
    updatedMessages[lastIndex] = lastMessage.copyWith(content: newContent);

    state = state.copyWith(messages: updatedMessages);
    _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);

    // Check whether the content contains completed tool-call tags.
    if (scanForTools) {
      _checkForContentToolCalls(newContent, interactionGeneration: generation);
    }
  }

  /// Returns the turn's own last message so recovery cannot cross threads.
  Message? _lastMessageForGeneration(int? generation) {
    if (generation != null &&
        _isActiveResponseDetachedForGeneration(generation)) {
      final activeMessages = _activeResponseMessagesForGeneration(generation);
      return activeMessages == null || activeMessages.isEmpty
          ? null
          : activeMessages.last;
    }
    if (!ref.mounted || state.messages.isEmpty) return null;
    return state.messages.last;
  }

  String? _lastMessageContentForGeneration(int generation) =>
      _lastMessageForGeneration(generation)?.content;

  void _replaceLastMessageContentForGeneration(
    int generation,
    String newContent,
  ) {
    if (_isActiveResponseDetachedForGeneration(generation)) {
      final activeMessages = _activeResponseMessagesForGeneration(generation);
      if (activeMessages == null || activeMessages.isEmpty) return;

      final updatedMessages = [...activeMessages];
      final lastIndex = updatedMessages.length - 1;
      final lastMessage = updatedMessages[lastIndex];
      updatedMessages[lastIndex] = lastMessage.copyWith(content: newContent);
      _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
      return;
    }

    if (!ref.mounted || state.messages.isEmpty) return;

    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];

    updatedMessages[lastIndex] = lastMessage.copyWith(content: newContent);
    state = state.copyWith(messages: updatedMessages);
    _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
  }

  void _removeTrailingThinkTagForGeneration(int generation) {
    if (_isActiveResponseDetachedForGeneration(generation)) {
      final activeMessages = _activeResponseMessagesForGeneration(generation);
      if (activeMessages == null || activeMessages.isEmpty) return;
      final lastMessage = activeMessages.last;
      final content = lastMessage.content;
      if (content.endsWith('<think>')) {
        _replaceLastMessageContentForGeneration(
          generation,
          content.substring(0, content.length - '<think>'.length),
        );
      }
      return;
    }

    if (!ref.mounted || state.messages.isEmpty) return;

    final lastMessage = state.messages.last;
    final content = lastMessage.content;
    if (content.endsWith('<think>')) {
      _replaceLastMessageContentForGeneration(
        generation,
        content.substring(0, content.length - '<think>'.length),
      );
    }
  }

  void _appendToolUseToLastMessage(
    ToolCallInfo toolCall, {
    int? interactionGeneration,
  }) {
    final generation = interactionGeneration ?? _interactionGeneration;
    _markToolCallSeenForContentDedup(
      toolCall.name,
      toolCall.arguments,
      interactionGeneration: generation,
    );
    final payload = <String, dynamic>{
      'name': toolCall.name,
      'arguments': toolCall.arguments,
    };
    _appendToLastMessageForGeneration(
      generation,
      '<tool_use>${jsonEncode(payload)}</tool_use>\n',
      scanForTools: false,
    );
  }

  void _appendAssistantToolPreambleIfPresent(
    String content, {
    required int interactionGeneration,
  }) {
    final visibleContent = ContentParser.stripToolArtifactsPreservingThinking(
      content,
    ).trim();
    if (visibleContent.isEmpty) {
      return;
    }
    final currentContent =
        _lastMessageContentForGeneration(interactionGeneration) ?? '';
    final needsLeadingBreak =
        currentContent.isNotEmpty && !currentContent.endsWith('\n');
    _appendToLastMessageForGeneration(
      interactionGeneration,
      '${needsLeadingBreak ? '\n\n' : ''}$visibleContent\n',
      scanForTools: false,
    );
  }

  /// Detects and runs `tool_call` tags embedded in the content.
  void _checkForContentToolCalls(String content, {int? interactionGeneration}) {
    final generation = interactionGeneration ?? _interactionGeneration;
    final owner = _turnOwnerForGeneration(generation);
    if (owner == null) return;
    final toolCalls = const PrintedToolCallRecovery().extract(
      content: content,
      advertisedToolNames: _activeResponseRegistry
          .snapshotForOwner(owner)
          ?.allowedToolNames,
    );
    final freshToolCalls = <ToolCallData>[];
    final repeatedToolCalls = <ToolCallData>[];
    for (final toolCall in toolCalls) {
      if (_contentToolTurns.markSeenCall(
        owner,
        _contentToolCallHash(toolCall, owner),
      )) {
        freshToolCalls.add(toolCall);
      } else {
        repeatedToolCalls.add(toolCall);
      }
    }

    _handleRepeatedContentToolCalls(
      repeatedToolCalls,
      interactionGeneration: generation,
    );

    _queueContentToolCalls(freshToolCalls, interactionGeneration: generation);
  }

  void _handleRepeatedContentToolCalls(
    List<ToolCallData> repeatedToolCalls, {
    required int interactionGeneration,
  }) {
    if (repeatedToolCalls.isEmpty ||
        !_isCurrentInteractionGeneration(interactionGeneration) ||
        _settings.llmCapabilities.supportsAdvancedLiveToolDiagnostics) {
      return;
    }

    for (final toolCall in repeatedToolCalls) {
      final previousResult = _lastSuccessfulContentResult(
        toolCall,
        interactionGeneration,
      );
      if (previousResult == null) {
        continue;
      }

      appLog(
        '[ContentTool] Repeated successful tool call suppressed for '
        '${toolCall.name}: ${toolCall.arguments}',
      );
      _replaceLastMessageContentForGeneration(
        interactionGeneration,
        _buildRepeatedContentToolCallFallback(previousResult),
      );
      return;
    }
  }

  ToolResultInfo? _lastSuccessfulContentResult(
    ToolCallData toolCall,
    int interactionGeneration,
  ) {
    final owner = _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) return null;
    final toolCallKey = _contentToolCallHash(toolCall, owner);
    return _turnToolResults.lastSuccessfulContentWhere(
      owner,
      (result) => _toolResultDedupKey(result, owner: owner) == toolCallKey,
    );
  }

  String _buildRepeatedContentToolCallFallback(ToolResultInfo previousResult) =>
      'The ${previousResult.name} tool already ran with the same arguments. '
      'I will use the previous tool result instead of repeating the call.';

  void _queueContentToolCalls(
    List<ToolCallData> freshToolCalls, {
    required int interactionGeneration,
  }) {
    if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
    final owner = _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) return;
    if (freshToolCalls.isNotEmpty) {
      appLog('[ContentTool] Detected tool_call(s): ${freshToolCalls.length}');
      for (final tc in freshToolCalls) {
        appLog('[ContentTool]   - ${tc.name}: ${tc.arguments}');
      }
      appLog(
        '[ContentTool] MCP tool service: ${_mcpToolService != null ? "enabled" : "disabled (enable MCP in settings)"}',
      );
    }

    if (_mcpToolService == null) return;

    for (final tc in freshToolCalls) {
      if (tc.name == 'memory_update' || tc.name == 'print') {
        appLog('[ContentTool] Ignoring display-only tool: ${tc.name}');
        continue;
      }
      final hash = ToolDedupeKeys.contentExecution(tc.name, tc.arguments);
      if (_contentToolTurns.markExecutedCall(owner, hash)) {
        appLog('[ContentTool] Starting execution: $hash');
        _enqueueContentToolCall(tc, owner);
      } else {
        appLog('[ContentTool] Already executed: $hash');
      }
    }
  }

  Future<void>? _enqueueContentToolCall(ToolCallData tc, ChatTurnOwner owner) {
    return _contentToolTurns.enqueueExecution(owner, () {
      if (!_activeResponseRegistry.containsOwner(owner)) {
        return Future<void>.value();
      }
      return _executeContentToolCall(tc, owner.interactionGeneration);
    });
  }

  String _contentToolCallHash(ToolCallData toolCall, ChatTurnOwner owner) {
    return _toolCallDedupKey(toolCall.name, toolCall.arguments, owner: owner);
  }

  String _toolExecutionKey(
    ToolCallInfo toolCall, {
    required String? projectRoot,
    int commandRetryGeneration = 0,
    int stateChangeGeneration = 0,
  }) => ToolDedupeKeys.toolExecution(
    toolCall,
    projectRoot: projectRoot,
    commandRetryGeneration: commandRetryGeneration,
    stateChangeGeneration: stateChangeGeneration,
  );

  bool _containsOnlyReadOnlyInspectionToolCalls(List<ToolCallInfo> toolCalls) =>
      _toolLoopRecoveryPolicy.containsOnlyReadOnlyInspectionToolCalls(
        toolCalls,
        isReadOnlyInspectionToolCall:
            _toolCallExecutionPolicy.isReadOnlyInspectionToolCall,
      );

  bool _looksLikePendingToolActionResponse(String response) => RegExp(
    r"\b(?:now\s+)?let me\b|\bi (?:will|need to|should|am going to)\b|\bi(?:'ll| will)\b",
  ).hasMatch(response.toLowerCase());

  bool _containsOnlyPreviouslySuccessfulCurrentSavedValidationToolCalls(
    List<ToolCallInfo> toolCalls,
    List<ToolResultInfo> previousToolResults,
    int interactionGeneration,
  ) {
    if (toolCalls.isEmpty || previousToolResults.isEmpty) {
      return false;
    }
    final validationCommand = _savedValidationCommandForGeneration(
      interactionGeneration,
    );
    if (validationCommand == null) return false;
    final normalizedValidationCommand = _normalizeToolCommandForComparison(
      validationCommand,
    );

    return toolCalls.every((toolCall) {
      if (toolCall.name == 'run_tests') {
        final testPath = _runTestsPathArgument(toolCall.arguments);
        return previousToolResults.any((result) {
          if (result.name != toolCall.name ||
              _runTestsPathArgument(result.arguments) != testPath ||
              !_toolCallExecutionPolicy.toolResultHasSuccessfulExit(result)) {
            return false;
          }
          return _runTestsMatchesSavedValidation(
            arguments: result.arguments,
            normalizedValidationCommand: normalizedValidationCommand,
          );
        });
      }
      if (!_toolCallExecutionPolicy.isCommandExecutionTool(toolCall.name)) {
        return false;
      }
      final command = _toolCallExecutionPolicy.toolCommandArgument(
        toolCall.arguments,
      );
      if (command == null) return false;
      final normalizedCommand = _normalizeToolCommandForComparison(command);
      return previousToolResults.any((result) {
        if (result.name != toolCall.name ||
            !_toolCallExecutionPolicy.toolResultHasSuccessfulExit(result)) {
          return false;
        }
        final resultCommand = _toolCallExecutionPolicy.toolCommandArgument(
          result.arguments,
        );
        if (resultCommand == null ||
            _normalizeToolCommandForComparison(resultCommand) !=
                normalizedCommand) {
          return false;
        }
        return _toolCommandMatchesSavedValidation(
          result: result,
          command: command,
          normalizedValidationCommand: normalizedValidationCommand,
        );
      });
    });
  }

  bool _toolResultsContainSuccessfulCurrentSavedValidation(
    List<ToolResultInfo> toolResults,
    int interactionGeneration,
  ) {
    final validationCommand = _savedValidationCommandForGeneration(
      interactionGeneration,
    );
    if (validationCommand == null) {
      return false;
    }
    final normalizedValidationCommand = _normalizeToolCommandForComparison(
      validationCommand,
    );
    final ownerProjectRoot = _projectRootForGeneration(interactionGeneration);
    return toolResults.any((result) {
      if (_readFileMatchesSavedCatValidation(
        result: result,
        validationCommand: validationCommand,
        ownerProjectRoot: ownerProjectRoot,
      )) {
        return true;
      }
      if (!_toolCallExecutionPolicy.toolResultHasSuccessfulExit(result)) {
        return false;
      }
      if (result.name == 'run_tests') {
        return _runTestsMatchesSavedValidation(
          arguments: result.arguments,
          normalizedValidationCommand: normalizedValidationCommand,
        );
      }
      final command = _toolCallExecutionPolicy.toolCommandArgument(
        result.arguments,
      );
      if (command == null) return false;
      return _toolCommandMatchesSavedValidation(
        result: result,
        command: command,
        normalizedValidationCommand: normalizedValidationCommand,
      );
    });
  }

  bool _readFileMatchesSavedCatValidation({
    required ToolResultInfo result,
    required String validationCommand,
    required String? ownerProjectRoot,
  }) {
    if (result.name != 'read_file') return false;
    final validationArgs = GitTools.splitArgs(validationCommand.trim());
    if (validationArgs.length != 2 ||
        validationArgs.first.split('/').last.toLowerCase() != 'cat') {
      return false;
    }
    final decoded = decodeJsonObject(result.result);
    if (decoded == null || decoded['error'] != null) return false;
    if (decoded['content'] is! String) return false;
    final actualPath = _fileMutationEvidencePolicy.pathForResult(result);
    if (actualPath == null) return false;
    final normalizedActualPath = const SavedTaskTargetScopeGuard()
        .normalizePath(actualPath, projectRoot: ownerProjectRoot);
    final normalizedValidationPath = const SavedTaskTargetScopeGuard()
        .normalizePath(validationArgs[1], projectRoot: ownerProjectRoot);
    return normalizedActualPath != null &&
        normalizedActualPath == normalizedValidationPath;
  }

  bool _toolCommandMatchesSavedValidation({
    required ToolResultInfo result,
    required String command,
    required String normalizedValidationCommand,
  }) => _toolCallExecutionPolicy.toolCommandMatchesSavedValidation(
    result: result,
    command: command,
    normalizedValidationCommand: normalizedValidationCommand,
  );

  bool _hasSavedTaskForGeneration(int interactionGeneration) =>
      _turnOwnerSnapshotForGeneration(interactionGeneration)?.savedTask != null;

  String? _savedValidationCommandForGeneration(int interactionGeneration) {
    final command = _turnOwnerSnapshotForGeneration(
      interactionGeneration,
    )?.savedTask?.validationCommand.trim();
    return command == null || command.isEmpty ? null : command;
  }

  String _normalizeToolCommandForComparison(String command) =>
      _toolCallExecutionPolicy.normalizeToolCommandForComparison(command);

  String? _runTestsPathArgument(Map<String, dynamic> arguments) =>
      _toolCallExecutionPolicy.runTestsPathArgument(arguments);

  bool _runTestsMatchesSavedValidation({
    required Map<String, dynamic> arguments,
    required String normalizedValidationCommand,
  }) {
    return _toolCallExecutionPolicy.runTestsMatchesSavedValidation(
      arguments: arguments,
      normalizedValidationCommand: normalizedValidationCommand,
    );
  }

  List<ToolResultInfo> _buildUnexecutedPendingToolResults({
    required List<ToolCallInfo> toolCalls,
    required Set<String> executedToolCallKeys,
    required int commandRetryGeneration,
    required String? projectRoot,
  }) {
    return _toolLoopRecoveryPolicy.buildUnexecutedPendingToolResults(
      toolCalls: toolCalls,
      executedToolCallKeys: executedToolCallKeys,
      commandRetryGeneration: commandRetryGeneration,
      toolCallKey: (toolCall, generation) => _toolExecutionKey(
        toolCall,
        projectRoot: projectRoot,
        commandRetryGeneration: generation,
      ),
    );
  }

  /// Redirects a model that keeps re-inspecting instead of acting.
  String _buildDuplicateInspectionRecoveryPrompt(
    List<ToolCallInfo> toolCalls, {
    List<ToolResultInfo> previousToolResults = const [],
    bool hasSavedTask = true,
  }) => const DuplicateRecoveryPromptBuilder().buildInspectionPrompt(
    toolCalls: toolCalls,
    hasSavedTask: hasSavedTask,
    previousCommandValidationFailed: _toolResultsContainFailedCommandValidation(
      previousToolResults,
    ),
    previousExactExitCodeExpectationFailed:
        _toolResultsMentionExactNonZeroExitCodeExpectation(previousToolResults),
    budgetReducedToolNames: ToolResultPromptBuilder.budgetReducedToolNames(
      previousToolResults,
    ),
  );

  /// Redirects a model that re-issues the same follow-up call.
  String _buildDuplicateFollowUpRecoveryPrompt(
    List<ToolCallInfo> toolCalls, {
    List<ToolResultInfo> previousToolResults = const [],
    bool hasSavedTask = true,
  }) => const DuplicateRecoveryPromptBuilder().buildFollowUpPrompt(
    toolCalls: toolCalls,
    hasSavedTask: hasSavedTask,
    repeatedValidationTool: toolCalls.any(_isRepeatableCommandTool),
    inspectedFailingFile: previousToolResults.any(
      (toolResult) => toolResult.name == 'read_file',
    ),
    budgetReducedToolNames: ToolResultPromptBuilder.budgetReducedToolNames(
      previousToolResults,
    ),
  );

  String _buildToolLoopExhaustionRecoveryPrompt(
    List<ToolCallInfo> toolCalls, {
    List<ToolResultInfo> previousToolResults = const [],
  }) {
    return _toolLoopRecoveryPolicy.buildExhaustionRecoveryPrompt(
      toolCalls,
      previousToolResults: previousToolResults,
    );
  }

  List<ToolResultInfo> _buildToolLoopRecoveryToolResults({
    required List<ToolResultInfo> currentToolResults,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolCallInfo> pendingToolCalls,
    required String? projectRoot,
  }) {
    return _toolLoopRecoveryPolicy.buildRecoveryToolResults(
      currentToolResults: currentToolResults,
      executedToolResults: executedToolResults,
      pendingToolCalls: pendingToolCalls,
      pathFromArguments: _fileMutationEvidencePolicy.argumentPath,
      toolResultKey: (toolResult) =>
          ToolDedupeKeys.toolResult(toolResult, projectRoot: projectRoot),
    );
  }

  String _extractAssistantStreamDelta({
    required int messageIndex,
    required int startingLength,
  }) {
    if (messageIndex < 0 || messageIndex >= state.messages.length) return '';
    return const AssistantStreamDelta().since(
      content: state.messages[messageIndex].content,
      startingLength: startingLength,
    );
  }

  void _removeAssistantStreamDeltaForGeneration({
    required int generation,
    required int messageIndex,
    required int startingLength,
  }) {
    final activeMessages =
        _activeResponseMessagesForGeneration(generation) ?? state.messages;
    if (messageIndex < 0 || messageIndex >= activeMessages.length) {
      return;
    }
    if (messageIndex != activeMessages.length - 1) {
      return;
    }

    final content = activeMessages[messageIndex].content;
    final clampedStart = startingLength.clamp(0, content.length).toInt();
    if (clampedStart >= content.length) {
      return;
    }
    _replaceLastMessageContentForGeneration(
      generation,
      content.substring(0, clampedStart).trimRight(),
    );
  }

  bool _isRepeatableCommandTool(ToolCallInfo toolCall) =>
      _toolCallExecutionPolicy.isRepeatableCommandTool(toolCall);

  String _toolCallDedupKey(
    String name,
    Object? arguments, {
    required ChatTurnOwner owner,
  }) => ToolDedupeKeys.toolCall(
    name,
    arguments,
    projectRoot: _toolDedupeProjectRoot(owner),
  );

  String _toolResultDedupKey(
    ToolResultInfo toolResult, {
    required ChatTurnOwner owner,
  }) => ToolDedupeKeys.toolResult(
    toolResult,
    projectRoot: _toolDedupeProjectRoot(owner),
  );

  String? _toolDedupeProjectRoot(ChatTurnOwner owner) {
    final snapshot = _turnOwnerSnapshotForGeneration(
      owner.interactionGeneration,
    );
    return snapshot?.owner == owner ? snapshot?.projectRoot : null;
  }

  void _markToolCallSeenForContentDedup(
    String name,
    Object? arguments, {
    required int interactionGeneration,
  }) {
    final owner = _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) return;
    _contentToolTurns.markSeenCall(
      owner,
      _toolCallDedupKey(name, arguments, owner: owner),
    );
  }

  /// Executes a `tool_call` detected from message content.
  Future<void> _executeContentToolCall(
    ToolCallData tc,
    int interactionGeneration,
  ) async {
    if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
    final turnOwner = _turnOwnerForGeneration(interactionGeneration);
    if (turnOwner == null) return;

    appLog('[ContentTool] Executing tool: ${tc.name}');
    appLog('[ContentTool] Arguments: ${tc.arguments}');

    final toolCall = ToolCallInfo(
      id: 'content_${DateTime.now().microsecondsSinceEpoch}',
      name: tc.name,
      arguments: Map<String, dynamic>.unmodifiable(tc.arguments),
    );

    try {
      final result = await _dispatchToolCall(
        toolCall,
        interactionGeneration: interactionGeneration,
      );
      if (!_activeResponseRegistry.containsOwner(turnOwner)) return;

      if (!result.isSuccess) {
        appLog('[ContentTool] Execution failed: ${result.errorMessage}');
        final failureResult = _contentToolFailureFormatter.format(
          tc.name,
          result.errorMessage,
        );
        _turnToolResults.recordContent(turnOwner, toolCall, failureResult);
        if (ref.mounted) {
          _appendToLastMessageForGeneration(
            interactionGeneration,
            '\n\n${ContentToolResultFormatter.format(tc.name, failureResult)}',
            scanForTools: false,
          );
          appLog('[ContentTool] Appended failure result to message');
        }
        _contentToolTurns.addPendingResult(
          turnOwner,
          '[Result of ${tc.name}]\n$failureResult',
        );
        return;
      }

      appLog('[ContentTool] Result retrieved: ${result.result.length} chars');
      final contentToolResult = await _toolResultArtifactStore.persistIfLarge(
        ToolResultInfo(
          id: toolCall.id,
          name: toolCall.name,
          arguments: Map<String, dynamic>.unmodifiable(toolCall.arguments),
          result: result.result,
        ),
        conversationId: turnOwner.conversationId,
      );
      if (!_activeResponseRegistry.containsOwner(turnOwner)) return;
      _turnToolResults.addContent(turnOwner, contentToolResult);
      await _recordModelEditApplyTelemetry(
        turnOwner,
        contentToolResult,
        baselineProfile: _modelEditApplyTelemetryBaseline(),
      );
      final promptResult = contentToolResult.result;

      // Append results without triggering recursive tool-call checks.
      if (ref.mounted) {
        _appendToLastMessageForGeneration(
          interactionGeneration,
          '\n\n${ContentToolResultFormatter.format(tc.name, promptResult)}',
          scanForTools: false,
        );
        appLog('[ContentTool] Appended result to message');
      }

      _contentToolTurns.addPendingResult(
        turnOwner,
        '[Result of ${tc.name}]\n$promptResult',
      );
    } catch (e) {
      if (!_activeResponseRegistry.containsOwner(turnOwner)) return;
      appLog('[ContentTool] Error: $e');
      final failureResult = _contentToolFailureFormatter.format(tc.name, '$e');
      _turnToolResults.recordContent(turnOwner, toolCall, failureResult);
      if (ref.mounted) {
        _appendToLastMessageForGeneration(
          interactionGeneration,
          '\n\n${ContentToolResultFormatter.format(tc.name, failureResult)}',
          scanForTools: false,
        );
        appLog('[ContentTool] Appended failure result to message');
      }
      _contentToolTurns.addPendingResult(
        turnOwner,
        '[Result of ${tc.name}]\n$failureResult',
      );
    }
  }

  bool _toolResultsContainEditMismatch(List<ToolResultInfo> toolResults) =>
      _toolLoopRecoveryPolicy.toolResultsContainEditMismatch(toolResults);

  bool _toolResultsContainFailedCommandValidation(
    List<ToolResultInfo> toolResults,
  ) {
    return toolResults.any((toolResult) {
      final normalizedName = toolResult.name.trim().toLowerCase();
      if (normalizedName != 'local_execute_command' &&
          normalizedName != 'process_start' &&
          normalizedName != 'process_status' &&
          normalizedName != 'process_wait' &&
          normalizedName != 'run_tests' &&
          normalizedName != 'git_execute_command' &&
          normalizedName != 'ssh_execute_command') {
        return false;
      }
      final normalizedResult = toolResult.result.toLowerCase();
      return RegExp(
            r'"exit_code"\s*:\s*(?!0\b)-?\d+',
          ).hasMatch(normalizedResult) ||
          RegExp(r'exit_code:\s*(?!0\b)-?\d+').hasMatch(normalizedResult);
    });
  }

  bool _toolResultsMentionExactNonZeroExitCodeExpectation(
    List<ToolResultInfo> toolResults,
  ) {
    return toolResults.any((toolResult) {
      final normalized = toolResult.result.toLowerCase();
      return normalized.contains('expected exit code') ||
          RegExp(r'returned\s+-?\d+,\s*expected\s+-?\d+').hasMatch(normalized);
    });
  }

  /// Dispatches tools while intercepting SSH calls that require confirmation.
  Future<McpToolResult> _dispatchToolCall(
    ToolCallInfo toolCall, {
    int? interactionGeneration,
    String? projectRoot,
  }) async {
    final approvalCache = _approvalCacheForGeneration(interactionGeneration);
    if (interactionGeneration != null && approvalCache == null) {
      return _turnOwnerSnapshotUnavailableResult(toolCall.name);
    }
    return TurnProjectRoot.runScoped(
      projectRoot == null
          ? _turnProjectRootFor(interactionGeneration)
          : TurnProjectRoot(projectRoot),
      () => TurnGeneration.runScoped(
        interactionGeneration,
        () => TurnThread.runScoped(
          interactionGeneration == null
              ? null
              : _activeResponseConversationIdForGeneration(
                  interactionGeneration,
                ),
          () => ChatToolDispatcher(
            enforcePlanningPolicy: (toolCall) =>
                _enforcePlanningToolPolicy(toolCall, interactionGeneration),
            enforceNetworkReadTaint: (toolCall) =>
                _enforceNetworkReadTaint(toolCall, approvalCache),
            handleComputerUseAction: _ownerComputerUseHandler(approvalCache),
            handleComputerUseObservation:
                _handleComputerUseActionWithoutApproval,
            handleBrowserAction: _ownerBrowserActionHandler(approvalCache),
            handleBrowserObservation: _handleBrowserActionWithoutApproval,
            handleNetworkMutation: _ownerNetworkMutationHandler(approvalCache),
            handlerRegistry: _buildToolHandlerRegistry(
              interactionGeneration: interactionGeneration,
              approvalCache: approvalCache,
              projectRoot: projectRoot,
            ),
            executeFallbackTool: (toolCall) => _mcpToolService!.executeTool(
              name: toolCall.name,
              arguments: toolCall.arguments,
            ),
          ).dispatch(toolCall),
        ),
      ),
    );
  }

  /// [owner] selects the owner-bound execution facade, which dispatches by
  /// identity rather than tool name; [approvalOwner] only says who to ask when
  /// a read needs releasing. They are not interchangeable.
  Future<McpToolResult> _handleProjectScopedTool(
    ToolCallInfo toolCall, {
    ChatTurnOwner? owner,
    String? projectRoot,
    ChatTurnOwner? approvalOwner,
  }) async {
    final accessFailure = await _ensureActiveProjectAccess(toolCall.name);
    if (accessFailure != null) return accessFailure;

    final arguments = _resolveProjectScopedArguments(
      toolCall.name,
      toolCall.arguments,
    );
    var authorizedArguments = arguments;
    if (_mcpToolService!.ownsBuiltInFilesystemEffects) {
      final authorization = await _outsideRootReadGrants.authorizeRead(
        toolName: toolCall.name,
        arguments: arguments,
        projectRoot: projectRoot,
        owner: approvalOwner,
        requestApproval: requestFileOperation,
        onDecision: ({required path, required approved}) =>
            _recordOutsideRootReadAudit(
              owner: approvalOwner!,
              toolName: toolCall.name,
              path: path,
              approved: approved,
            ),
      );
      if (!authorization.isAllowed) return authorization.deniedResult!;
      authorizedArguments = authorization.arguments!;
    }
    if (owner != null) {
      return _mcpToolService!.executeFileTool(
        owner: owner,
        name: toolCall.name,
        arguments: authorizedArguments,
      );
    }
    return _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: authorizedArguments,
    );
  }

  McpToolResult? _enforcePlanningToolPolicy(
    ToolCallInfo toolCall,
    int? interactionGeneration,
  ) {
    final turnThreadId = TurnThread.currentId;
    return _planningToolPolicy.enforce(
      toolCall,
      isPlanningSession: interactionGeneration == null
          ? (turnThreadId == null
                    ? null
                    : _conversationForId(turnThreadId)?.isPlanningSession) ??
                false
          : _turnOwnerSnapshotForGeneration(
                  interactionGeneration,
                )?.isPlanning ??
                false,
      isExternalMcpTool:
          _mcpToolService?.isExternalMcpToolName(toolCall.name) ?? false,
      resolveArguments: _resolveProjectScopedArguments,
    );
  }

  void _recoverIncompleteContentToolCallsFromLastMessage({
    required int interactionGeneration,
  }) {
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return;
    }
    final owner = _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) return;

    final lastMessage = _lastMessageForGeneration(interactionGeneration);
    if (lastMessage == null) {
      return;
    }
    if (lastMessage.role != MessageRole.assistant ||
        !ContentParser.hasIncompleteToolCall(lastMessage.content)) {
      return;
    }

    final recoveredToolCalls =
        ContentParser.extractRecoverableIncompleteToolCalls(
          lastMessage.content,
        ).where((tc) {
          return _contentToolTurns.markSeenCall(
            owner,
            _contentToolCallHash(tc, owner),
          );
        }).toList();

    if (recoveredToolCalls.isEmpty) {
      appLog(
        '[ContentTool] Incomplete tool call could not be parsed; requesting continuation recovery',
      );
      _stripToolArtifactsFromLastAssistantMessage(
        interactionGeneration: interactionGeneration,
      );
      _contentToolTurns.addPendingResult(
        owner,
        '[Incomplete assistant tool call]\n'
        'The assistant emitted an unfinished tool call tag. Reissue the needed '
        'tool call as one complete <tool_use>...</tool_use> tag, or finish with '
        'a concise text answer if no more tools are needed. Do not write '
        '<tool_result> tags yourself.',
      );
      return;
    }

    appLog(
      '[ContentTool] Recovering incomplete tool_call(s): ${recoveredToolCalls.length}',
    );
    _stripToolArtifactsFromLastAssistantMessage(
      interactionGeneration: interactionGeneration,
    );
    _queueContentToolCalls(
      recoveredToolCalls,
      interactionGeneration: interactionGeneration,
    );
  }

  bool _recoverUntrustedAssistantToolResultsFromLastMessage({
    int? interactionGeneration,
  }) {
    final generation = interactionGeneration ?? _interactionGeneration;
    final owner = _turnOwnerForGeneration(generation);
    if (owner == null) return false;
    final lastMessage = _lastMessageForGeneration(generation);
    if (lastMessage == null || lastMessage.role != MessageRole.assistant) {
      return false;
    }

    final toolResults = ContentParser.extractToolResultMarkers(
      lastMessage.content,
    );
    if (toolResults.isEmpty) {
      return false;
    }

    appLog(
      '[ContentTool] Ignoring assistant-authored tool_result tag(s): '
      '${toolResults.map((tc) => tc.name).join(", ")}',
    );
    _stripToolArtifactsFromLastAssistantMessage(
      interactionGeneration: generation,
    );
    _contentToolTurns.addPendingResult(
      owner,
      '[Assistant-authored tool_result ignored]\n'
      'The assistant emitted <tool_result> tags without a corresponding tool '
      'execution. Tool results must come from executed tools only. If the data '
      'is still needed, call the tool with one complete <tool_use>...</tool_use> '
      'tag. If the current user request can be completed without the ignored '
      'tag or any additional tool, answer that user request directly now. For '
      'exact no-tool recovery or echo requests, return the literal text the '
      'user requested exactly. Do not use values that appear only inside the '
      'ignored <tool_result> content.',
    );
    return true;
  }

  bool _recoverContentToolArtifactsBeforeNoToolFinalization({
    required int interactionGeneration,
  }) {
    final owner = _turnOwnerForGeneration(interactionGeneration);
    if (owner == null) return false;
    final pendingToolExecutionCount = _contentToolTurns.pendingExecutionCount(
      owner,
    );
    final pendingContentToolResultCount = _contentToolTurns.pendingResultCount(
      owner,
    );

    _recoverIncompleteContentToolCallsFromLastMessage(
      interactionGeneration: interactionGeneration,
    );
    if (_contentToolTurns.pendingExecutionCount(owner) >
            pendingToolExecutionCount ||
        _contentToolTurns.pendingResultCount(owner) >
            pendingContentToolResultCount) {
      return true;
    }

    if (_recoverUntrustedAssistantToolResultsFromLastMessage(
      interactionGeneration: interactionGeneration,
    )) {
      return true;
    }

    return _recoverAssistantToolNameBlocksFromLastMessage(
      interactionGeneration: interactionGeneration,
    );
  }

  bool _recoverAssistantToolNameBlocksFromLastMessage({
    int? interactionGeneration,
  }) {
    final generation = interactionGeneration ?? _interactionGeneration;
    final owner = _turnOwnerForGeneration(generation);
    if (owner == null) return false;
    final lastMessage = _lastMessageForGeneration(generation);
    if (lastMessage == null || lastMessage.role != MessageRole.assistant) {
      return false;
    }

    final toolNames = FencedToolNameBlocks.extract(lastMessage.content);
    if (toolNames.isEmpty) {
      return false;
    }

    appLog(
      '[ContentTool] Ignoring assistant-authored fenced tool_name block(s): '
      '${toolNames.join(", ")}',
    );
    _replaceLastMessageContentForGeneration(
      generation,
      FencedToolNameBlocks.strip(lastMessage.content),
    );
    _contentToolTurns.addPendingResult(
      owner,
      '[Assistant tool-name block ignored]\n'
      'The assistant emitted fenced tool_name block(s) instead of a complete '
      '<tool_use>...</tool_use> call: ${toolNames.join(", ")}. '
      'No tool was executed from the fenced tool_name block. If tool use is '
      'still needed, call one available tool with exactly one complete '
      '<tool_use>...</tool_use> JSON tag; otherwise answer from verified prior '
      'tool results only.',
    );
    return true;
  }

  void _stripToolArtifactsFromLastAssistantMessage({
    int? interactionGeneration,
  }) {
    final generation = interactionGeneration ?? _interactionGeneration;
    if (_isActiveResponseDetachedForGeneration(generation)) {
      final activeMessages = _activeResponseMessagesForGeneration(generation);
      if (activeMessages == null || activeMessages.isEmpty) return;

      final updatedMessages = [...activeMessages];
      final lastIndex = updatedMessages.length - 1;
      final lastMessage = updatedMessages[lastIndex];
      if (lastMessage.role != MessageRole.assistant) {
        return;
      }

      final strippedContent =
          ContentParser.stripToolArtifactsPreservingThinking(
            lastMessage.content,
          );
      if (strippedContent.trim().isEmpty) {
        updatedMessages.removeAt(lastIndex);
      } else {
        updatedMessages[lastIndex] = lastMessage.copyWith(
          content: strippedContent,
        );
      }
      _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
      return;
    }

    if (!ref.mounted || state.messages.isEmpty) return;

    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];
    if (lastMessage.role != MessageRole.assistant) {
      return;
    }

    final strippedContent = ContentParser.stripToolArtifactsPreservingThinking(
      lastMessage.content,
    );
    if (strippedContent.trim().isEmpty) {
      updatedMessages.removeAt(lastIndex);
    } else {
      updatedMessages[lastIndex] = lastMessage.copyWith(
        content: strippedContent,
      );
    }
    state = state.copyWith(messages: updatedMessages);
    _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
  }

  void _stripToolArtifactsFromStreamedAnswerSuffix(
    int generation, {
    required String preAnswerContent,
  }) {
    final currentContent = _lastMessageContentForGeneration(generation);
    if (currentContent == null ||
        !currentContent.startsWith(preAnswerContent)) {
      _stripToolArtifactsFromLastAssistantMessage(
        interactionGeneration: generation,
      );
      return;
    }

    final streamedSuffix = currentContent.substring(preAnswerContent.length);
    final strippedSuffix = ContentParser.stripToolArtifactsPreservingThinking(
      streamedSuffix,
    ).trim();
    if (strippedSuffix.isEmpty) {
      _replaceLastMessageContentForGeneration(generation, preAnswerContent);
      return;
    }

    final separator =
        preAnswerContent.isEmpty || preAnswerContent.endsWith('\n')
        ? ''
        : '\n\n';
    _replaceLastMessageContentForGeneration(
      generation,
      '$preAnswerContent$separator$strippedSuffix',
    );
  }

  void _removeStreamedAnswerSuffixForGeneration(
    int generation, {
    required String preAnswerContent,
  }) {
    final currentContent = _lastMessageContentForGeneration(generation);
    if (currentContent == null) {
      return;
    }
    if (!currentContent.startsWith(preAnswerContent)) {
      return;
    }
    _replaceLastMessageContentForGeneration(generation, preAnswerContent);
  }

  void _appendUnexecutedToolRequestNoticeIfNeeded({
    int? interactionGeneration,
  }) {
    final generation = interactionGeneration ?? _interactionGeneration;
    _applyFinalAnswerMessageMutation(
      generation,
      _messageNotices.appendUnexecutedToolRequest(
        _finalAnswerMessagesForGeneration(generation),
      ),
    );
  }

  void _appendUnexecutedFileSideEffectNoticeIfNeeded({
    required List<ToolResultInfo> toolResults,
    int? interactionGeneration,
  }) {
    final generation = interactionGeneration ?? _interactionGeneration;
    _applyFinalAnswerMessageMutation(
      generation,
      _messageNotices.appendUnexecutedFileSideEffect(
        _finalAnswerMessagesForGeneration(generation),
        toolResults,
      ),
    );
  }

  void _appendUnexecutedCommandActionNoticeIfNeeded({
    required List<ToolResultInfo> toolResults,
    required ChatTurnOwner owner,
  }) {
    final generation = owner.interactionGeneration;
    _applyFinalAnswerMessageMutation(
      generation,
      _messageNotices.appendUnexecutedCommandAction(
        _finalAnswerMessagesForGeneration(generation),
        toolResults,
      ),
      owner: owner,
    );
  }

  void _appendUnverifiedReadOnlyInspectionClaimNoticeIfNeeded({
    required List<ToolResultInfo> toolResults,
    required ChatTurnOwner owner,
  }) {
    final generation = owner.interactionGeneration;
    _applyFinalAnswerMessageMutation(
      generation,
      _messageNotices.appendUnverifiedReadOnlyInspection(
        _finalAnswerMessagesForGeneration(generation),
        toolResults,
      ),
      owner: owner,
    );
  }

  void _replaceTimedOutCommandSuccessClaimIfNeeded({
    required List<ToolResultInfo> toolResults,
    int? interactionGeneration,
  }) {
    final generation = interactionGeneration ?? _interactionGeneration;
    _applyFinalAnswerMessageMutation(
      generation,
      _messageNotices.replaceTimedOutCommandClaim(
        _finalAnswerMessagesForGeneration(generation),
        toolResults,
      ),
    );
  }

  void _replaceFailedCommandSuccessClaimIfNeeded({
    required List<ToolResultInfo> toolResults,
    int? interactionGeneration,
  }) {
    final generation = interactionGeneration ?? _interactionGeneration;
    _applyFinalAnswerMessageMutation(
      generation,
      _messageNotices.replaceFailedCommandClaim(
        _finalAnswerMessagesForGeneration(generation),
        toolResults,
      ),
    );
  }

  bool _hasTimedOutCommandResult(List<ToolResultInfo> toolResults) =>
      _messageNotices.hasTimedOutCommandResult(toolResults);

  List<Message> _finalAnswerMessagesForGeneration(int generation) {
    final active = _activeResponseMessagesForGeneration(generation);
    if (active != null) return active;
    if (_isActiveResponseDetachedForGeneration(generation)) {
      return const <Message>[];
    }
    return ref.mounted ? state.messages : const <Message>[];
  }

  void _applyFinalAnswerMessageMutation(
    int generation,
    FinalAnswerMessageMutation? mutation, {
    ChatTurnOwner? owner,
  }) {
    if (mutation == null) return;
    final transformId = mutation.transformId;
    final transformOwner = owner ?? _turnOwnerForGeneration(generation);
    if (transformOwner != null && transformId != null) {
      _turnEnd.addTransform(transformOwner, transformId);
    }
    final messages = mutation.messages;
    if (messages.isEmpty) return;
    _cacheActiveResponseMessagesForGeneration(generation, messages);
    if (_isActiveResponseDetachedForGeneration(generation) || !ref.mounted) {
      return;
    }
    if (owner == null) {
      state = state.copyWith(messages: messages);
    } else {
      _routeThreadState(
        owner.conversationId,
        (current) => current.copyWith(messages: messages),
      );
    }
  }

  bool _containsAny(String value, List<String> markers) =>
      markers.any(value.contains);

  void _appendToolContinuationLimitNotice(ChatTurnOwner owner) {
    final ownerMessages = _activeResponseRegistry.messagesForOwner(owner);
    if (ownerMessages == null || ownerMessages.isEmpty) return;
    final updatedMessages = [...ownerMessages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];
    updatedMessages[lastIndex] = lastMessage.copyWith(
      content:
          '${lastMessage.content}\n\n[Tool continuation limit reached. Please ask again with a more specific request.]',
    );
    _activeResponseRegistry.cacheMessagesForOwner(owner, updatedMessages);
    if (ref.mounted && conversationId == owner.conversationId) {
      state = state.copyWith(messages: updatedMessages);
    }
  }

  Future<bool> _continueWithPendingContentToolResults(
    ChatTurnOwner owner,
  ) async {
    final toolResults = _contentToolTurns.takePendingResults(owner);
    if (toolResults.isEmpty) return false;
    if (_contentToolTurns.continuationCount(owner) >=
        _maxContentToolContinuations) {
      _appendToolContinuationLimitNotice(owner);
      return false;
    }
    _contentToolTurns.incrementContinuationCount(owner);
    await _continueAfterContentToolResults(
      toolResults,
      interactionGeneration: owner.interactionGeneration,
    );
    return true;
  }

  Future<void> _finishStreaming({int? interactionGeneration}) async {
    final generation = interactionGeneration ?? _interactionGeneration;
    if (!_isCurrentInteractionGeneration(generation)) return;
    final turnSnapshot = _turnOwnerSnapshotForGeneration(generation);
    final turnOwner = turnSnapshot?.owner;
    if (turnOwner == null) {
      return _handleTurnOwnerSnapshotUnavailable(generation);
    }
    // Capture the owner before finalization clears its active registration.
    final turnThreadId = _activeResponseConversationIdForGeneration(generation);
    _recoverIncompleteContentToolCallsFromLastMessage(
      interactionGeneration: generation,
    );
    final pendingExecutionCount = _contentToolTurns.pendingExecutionCount(
      turnOwner,
    );
    if (pendingExecutionCount > 0) {
      appLog(
        '[ChatNotifier] Waiting for pending tool executions: '
        '$pendingExecutionCount',
      );
      await _contentToolTurns.drainPendingExecutions(turnOwner);
      if (!_activeResponseRegistry.containsOwner(turnOwner)) return;
      appLog('[ChatNotifier] Tool executions completed');
    }
    if (_contentToolTurns.pendingResultCount(turnOwner) > 0) {
      if (await _continueWithPendingContentToolResults(turnOwner)) return;
    }
    if (_contentToolTurns.pendingResultCount(turnOwner) == 0) {
      final recoveredUntrustedToolResult =
          _recoverUntrustedAssistantToolResultsFromLastMessage(
            interactionGeneration: generation,
          );
      if (recoveredUntrustedToolResult &&
          await _continueWithPendingContentToolResults(turnOwner)) {
        return;
      }
    }
    if (_contentToolTurns.pendingResultCount(turnOwner) == 0) {
      final recoveredToolNameBlock =
          _recoverAssistantToolNameBlocksFromLastMessage(
            interactionGeneration: generation,
          );
      if (recoveredToolNameBlock &&
          await _continueWithPendingContentToolResults(turnOwner)) {
        return;
      }
    }
    if (!_activeResponseRegistry.containsOwner(turnOwner)) {
      return;
    }
    if (_isActiveResponseDetachedForGeneration(generation)) {
      await _finishDetachedActiveResponse(generation);
      return;
    }
    final responseMessages = _activeResponseRegistry.messagesForOwner(
      turnOwner,
    );
    if (responseMessages == null || responseMessages.isEmpty) {
      return _failResponseMessagesMissing(generation);
    }

    final finalMessage = _resolveTurnFinalMessage(
      responseMessages.last,
      turnOwner,
    );
    final shouldDropLastAssistant = finalMessage.dropLastAssistant;
    final provisionalFinishReason =
        _responseMetadata.finishReasonFor(turnOwner) ?? '';
    var updatedMessages = finalMessage.apply(
      responseMessages,
      metrics: null,
      truncated: ProposalParsingTextUtils.isCompletionTruncated(
        provisionalFinishReason,
      ),
    );
    _contentToolTurns.setContinuationFallback(turnOwner, null);
    if (!_activeResponseRegistry.containsOwner(turnOwner)) return;
    final snapshot = turnSnapshot!;
    if (snapshot.hiddenPrompt != null &&
        !snapshot.persistHiddenPromptAssistantResponse) {
      _updateTokenUsage(turnOwner);
      final hiddenFinishReason =
          _responseMetadata.finishReasonFor(turnOwner) ?? '';
      updatedMessages = finalMessage.apply(
        responseMessages,
        metrics: _turnResponseMetrics(turnOwner, finalMessage),
        truncated: ProposalParsingTextUtils.isCompletionTruncated(
          hiddenFinishReason,
        ),
      );
      if (await _finishEphemeralHiddenResponse(
        snapshot: snapshot,
        updatedMessages: updatedMessages,
        shouldDropLastAssistant: shouldDropLastAssistant,
        turnThreadId: turnThreadId,
        finishReason: hiddenFinishReason,
      )) {
        return;
      }
    }
    _clearHiddenPromptMirrorForSnapshot(snapshot);
    final recoveredBeforeFinalization =
        await _recoverBeforeTurnFinalizationIfNeeded(
          generation: generation,
          finalizedMessages: updatedMessages,
          shouldDropLastAssistant: shouldDropLastAssistant,
        );
    if (recoveredBeforeFinalization) return;
    if (!_activeResponseRegistry.containsOwner(turnOwner)) return;
    final goalTokenUsageDelta = _updateTokenUsage(turnOwner);
    final finishReason = _responseMetadata.finishReasonFor(turnOwner) ?? '';
    updatedMessages = finalMessage.apply(
      responseMessages,
      metrics: _turnResponseMetrics(turnOwner, finalMessage),
      truncated: ProposalParsingTextUtils.isCompletionTruncated(finishReason),
    );
    if (!shouldDropLastAssistant && updatedMessages.isNotEmpty) {
      final finalMessageIndex = updatedMessages.length - 1;
      final finalMessage = updatedMessages[finalMessageIndex];
      final noticeResult = _claimNotices.apply(
        FinalAnswerClaimNoticeInput(
          isCodingWorkspaceOrMode: snapshot.isCodingWorkspaceOrMode,
          candidateContent: finalMessage.content,
          toolResults: _turnToolResults.all(snapshot.owner),
          executedCommands: _turnToolResults.commands(snapshot.owner),
          projectRoot: snapshot.projectRoot,
          offersCommandExecution: _toolCallExecutionPolicy
              .offersCommandExecution(snapshot.allowedToolNames),
        ),
      );
      for (final transformId in noticeResult.transformIds) {
        _turnEnd.addTransform(snapshot.owner, transformId);
      }
      if (noticeResult.content != finalMessage.content) {
        updatedMessages[finalMessageIndex] = finalMessage.copyWith(
          content: noticeResult.content,
        );
      }
    }
    await _logTurnExitReason(
      owner: turnOwner,
      finalizedMessages: updatedMessages,
      shouldDropLastAssistant: shouldDropLastAssistant,
      finishReason: finishReason,
    );
    if (!_activeResponseRegistry.containsOwner(turnOwner)) return;
    _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
    if (!_isActiveResponseDetachedForGeneration(generation)) {
      state = state.copyWith(messages: updatedMessages, isLoading: false);
    }
    final explicitTerminalSuccessSummary =
        _explicitTerminalSuccessSummariesByGeneration.remove(generation);
    _contentToolTurns.resetContinuationCount(turnOwner);
    updatedMessages = await _saveMessages(
      messages: updatedMessages,
      conversationId: turnOwner.conversationId,
      memoryToolResults: _turnToolResults.completed(turnOwner),
    );
    if (!_activeResponseRegistry.containsOwner(turnOwner)) return;
    _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
    if (conversationId == turnOwner.conversationId) {
      state = state.copyWith(messages: updatedMessages, isLoading: false);
    }
    if (shouldDropLastAssistant || updatedMessages.isEmpty) {
      _clearTurnDiffCapture();
      _onResponseCompleted('');
      _completeRuntimeTurn(generation, content: '');
      if (!_isCurrentInteractionGeneration(generation)) return;
      await _drainQueuedChatMessagesForThreadIfIdle(turnThreadId ?? '');
      _clearGoalAutoContinueIndicator();
      return;
    }
    final finalizedLastMessage = updatedMessages.last;
    if (finalizedLastMessage.role == MessageRole.assistant) {
      await _persistPendingTurnDiffForAssistant(finalizedLastMessage.id);
    } else {
      _clearTurnDiffCapture();
    }
    if (!_activeResponseRegistry.containsOwner(turnOwner)) return;
    final finalCompletionEvidence = await _finalizeGoalTurn(
      owner: turnOwner,
      assistantResponse:
          explicitTerminalSuccessSummary?.trim().isNotEmpty == true
          ? explicitTerminalSuccessSummary!
          : finalizedLastMessage.content,
      tokenUsageDelta: goalTokenUsageDelta,
    );
    if (finalCompletionEvidence == null) return;
    if (!_activeResponseRegistry.containsOwner(turnOwner)) return;
    if (_settings.autoReadEnabled && _settings.ttsEnabled) {
      final lastMsg = finalizedLastMessage;
      if (lastMsg.role == MessageRole.assistant && lastMsg.content.isNotEmpty) {
        _onAutoRead(lastMsg.content);
      }
    }
    final lastMsg = finalizedLastMessage;
    if (lastMsg.role == MessageRole.assistant && lastMsg.content.isNotEmpty) {
      _onResponseCompleted(lastMsg.content);
      _dispatchExternalToolHook('Stop', assistantMessage: lastMsg.content);
    } else {
      _onResponseCompleted('');
      _dispatchExternalToolHook('Stop');
    }
    _completeRuntimeTurn(
      generation,
      content: lastMsg.role == MessageRole.assistant ? lastMsg.content : '',
    );
    if (!_isCurrentInteractionGeneration(generation)) return;
    await _drainQueuedChatMessagesForThreadIfIdle(turnThreadId ?? '');
    if (!_isCurrentInteractionGeneration(generation)) return;
    if (!_isGoalAutoContinueOwnerCurrent(turnOwner)) return;
    await _maybeAutoContinueCurrentGoal(
      owner: turnOwner,
      finalizedAssistantResponse: finalizedLastMessage.content,
      languageCode: _languageCode,
      evidence: finalCompletionEvidence,
    );
  }

  TurnFinalMessage _resolveTurnFinalMessage(
    Message lastMessage,
    ChatTurnOwner owner,
  ) => TurnFinalMessage.resolve(
    lastMessage: lastMessage,
    contentToolFallback: _contentToolTurns.continuationFallback(owner),
  );

  Future<McpToolResult?> _ensureActiveProjectAccess(String toolName) async {
    final scopedRoot = TurnProjectRoot.current?.rootPath.trim();
    final project = scopedRoot == null
        ? _codingProjects.active
        : scopedRoot.isEmpty
        ? null
        : ref.read(codingProjectsNotifierProvider).findByRootPath(scopedRoot);
    if (project == null) return null;

    final bookmark = project.securityScopedBookmark?.trim();
    if (bookmark == null || bookmark.isEmpty) return null;

    final projectsNotifier = ref.read(codingProjectsNotifierProvider.notifier);
    final accessGranted = await projectsNotifier.ensureProjectAccess(
      project.id,
    );
    if (accessGranted) return null;

    final payload = jsonEncode({
      'error':
          'Failed to restore access to the selected coding project. Re-select the project folder and allow access in macOS.',
      'code': 'bookmark_restore_failed',
      'path': project.rootPath,
    });

    return McpToolResult(
      toolName: toolName,
      result: payload,
      isSuccess: false,
      errorMessage: 'Failed to restore security-scoped bookmark access',
    );
  }

  Future<void> _continueAfterContentToolResults(
    List<String> toolResults, {
    required int interactionGeneration,
  }) async {
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return;
    }
    final turnOwner = _turnOwnerForGeneration(interactionGeneration);
    if (turnOwner == null) {
      await _handleTurnOwnerSnapshotUnavailable(interactionGeneration);
      return;
    }
    final ownerMessages = _activeResponseRegistry.messagesForOwner(turnOwner);
    if (ownerMessages == null || ownerMessages.isEmpty) return;

    final finalizedMessages = [...ownerMessages];
    final lastIndex = finalizedMessages.length - 1;
    finalizedMessages[lastIndex] = finalizedMessages[lastIndex].copyWith(
      isStreaming: false,
    );

    final continuationMessage = Message(
      id: _uuid.v4(),
      content: '',
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
      isStreaming: true,
    );

    final continuationMessages = [...finalizedMessages, continuationMessage];
    _activeResponseRegistry.cacheMessagesForOwner(
      turnOwner,
      continuationMessages,
    );
    if (!_isActiveResponseDetachedForGeneration(interactionGeneration)) {
      state = state.copyWith(
        messages: continuationMessages,
        isLoading: true,
        error: null,
      );
    }

    final continuationToolDefinitions =
        _foundationModelsTextToolDefinitionsForContinuation();
    final messagesForLLM = _prepareMessagesForLLM(
      toolDefinitionsOverride: continuationToolDefinitions,
      interactionGeneration: interactionGeneration,
    );
    _contentToolTurns.setContinuationFallback(
      turnOwner,
      ContentToolContinuationPromptBuilder.fallback(toolResults),
    );
    messagesForLLM.add(
      Message(
        id: 'content_tool_result_${DateTime.now().millisecondsSinceEpoch}',
        content: ContentToolContinuationPromptBuilder.build(toolResults),
        role: MessageRole.user,
        timestamp: DateTime.now(),
      ),
    );

    _runWithLlmSessionLogContextForGeneration(
      interactionGeneration,
      requestLabel: 'content tool-result continuation',
      () {
        late final Stream<String> stream;
        late final Future<ChatCompletionTerminalMetadata> terminal;
        if (continuationToolDefinitions == null) {
          final completion =
              _primaryDataSourceForGeneration(
                interactionGeneration,
              ).streamChatCompletion(
                messages: messagesForLLM,
                model: _primaryModelForGeneration(interactionGeneration),
                temperature: _primaryAssistantTemperatureForGeneration(
                  interactionGeneration,
                ),
                maxTokens: _settings.maxTokens,
              );
          stream = completion;
          terminal = completion.terminal;
        } else {
          final completion =
              _primaryDataSourceForGeneration(
                interactionGeneration,
              ).streamChatCompletionWithTools(
                messages: messagesForLLM,
                tools: continuationToolDefinitions,
                model: _primaryModelForGeneration(interactionGeneration),
                temperature: _primaryAgenticTemperatureForGeneration(
                  interactionGeneration,
                ),
                maxTokens: _settings.maxTokens,
              );
          stream = completion.stream;
          terminal = _responseMetadata.terminalFor(completion.completion);
        }

        _turnStream.listen(
          turnOwner,
          stream,
          onChunk: (chunk) {
            if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
            _appendToLastMessageForGeneration(interactionGeneration, chunk);
          },
          onError: (error, stackTrace) {
            if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
            appLog(
              '[ChatNotifier] _continueAfterContentToolResults onError: ${error.runtimeType}: $error',
            );
            appLog('[ChatNotifier] stackTrace: $stackTrace');
            unawaited(
              _recoverAfterContentToolResultsStreamError(
                messagesForLLM,
                error,
                stackTrace,
                interactionGeneration: interactionGeneration,
              ),
            );
          },
          onDone: () =>
              _finishStreamedCompletionInBackground(turnOwner, terminal),
        );
      },
    );
  }

  List<Map<String, dynamic>>?
  _foundationModelsTextToolDefinitionsForContinuation() {
    if (_settings.llmProvider != LlmProvider.appleFoundationModels) {
      return null;
    }
    final mcpToolService = _mcpToolService;
    if (mcpToolService == null || !_settings.mcpEnabled) {
      return null;
    }
    final allTools = mcpToolService.getOpenAiToolDefinitions();
    if (allTools.isEmpty) {
      return null;
    }
    return ToolDefinitionSearchService.buildInitialSelection(
      allTools,
    ).toolDefinitions;
  }

  Future<void> _recoverAfterContentToolResultsStreamError(
    List<Message> messagesForLLM,
    Object error,
    StackTrace stackTrace, {
    required int interactionGeneration,
  }) async {
    final turnOwner = _turnOwnerForGeneration(interactionGeneration);
    if (turnOwner == null) {
      await _handleTurnOwnerSnapshotUnavailable(interactionGeneration);
      return;
    }
    try {
      final result = await _runWithLlmSessionLogContextForGeneration(
        interactionGeneration,
        () => _primaryDataSourceForGeneration(interactionGeneration)
            .createChatCompletion(
              messages: messagesForLLM,
              model: _primaryModelForGeneration(interactionGeneration),
              temperature: _primaryAssistantTemperatureForGeneration(
                interactionGeneration,
              ),
              maxTokens: _settings.maxTokens,
            ),
      );

      final ownerMessages = _activeResponseRegistry.messagesForOwner(turnOwner);
      if (ownerMessages == null || ownerMessages.isEmpty) {
        return;
      }

      if (result.content.trim().isEmpty) {
        appLog(
          '[ChatNotifier] Content-tool continuation fallback returned empty content',
        );
        await _handleError(error, owner: turnOwner);
        return;
      }

      appLog(
        '[ChatNotifier] Recovered content-tool continuation with non-streaming completion',
      );
      if (!_responseMetadata.captureResult(turnOwner, result)) return;
      _replaceLastMessageContentForGeneration(
        interactionGeneration,
        result.content,
      );
      _checkForContentToolCalls(
        result.content,
        interactionGeneration: interactionGeneration,
      );
      await _finishStreaming(interactionGeneration: interactionGeneration);
    } catch (fallbackError, fallbackStackTrace) {
      if (!_activeResponseRegistry.containsOwner(turnOwner)) return;
      appLog(
        '[ChatNotifier] Content-tool continuation fallback failed: ${fallbackError.runtimeType}: $fallbackError',
      );
      appLog('[ChatNotifier] fallbackStackTrace: $fallbackStackTrace');
      appLog('[ChatNotifier] originalStackTrace: $stackTrace');
      await _handleError(error, owner: turnOwner);
    }
  }

  Future<void> _updateSessionMemory(
    String currentConversationId,
    List<Message> messagesToSave,
    String targetAssistantMessageId,
    List<ToolResultInfo> toolResults,
  ) async {
    final draft = await _extractMemoryDraftWithLlm(messagesToSave, toolResults);
    final result = await _memoryService.updateFromConversation(
      conversationId: currentConversationId,
      messages: messagesToSave,
      draft: draft,
    );
    if (!ref.mounted || !result.hasAnyUpdate) return;

    final updatedMessages = [...state.messages];
    final targetIndex = updatedMessages.indexWhere(
      (message) => message.id == targetAssistantMessageId,
    );
    if (targetIndex < 0) return;
    final targetMessage = updatedMessages[targetIndex];
    if (targetMessage.role != MessageRole.assistant ||
        targetMessage.isStreaming) {
      return;
    }

    final memoryTag = _buildMemoryUpdateToolUse(result);
    if (targetMessage.content.contains(memoryTag)) return;

    updatedMessages[targetIndex] = targetMessage.copyWith(
      content: '${targetMessage.content}\n$memoryTag',
    );
    state = state.copyWith(messages: updatedMessages);

    final normalized = updatedMessages.where((m) => !m.isStreaming).toList();
    unawaited(_messagePersistence.persistCurrentMessages(normalized));
  }

  Future<MemoryExtractionDraft?> _extractMemoryDraftWithLlm(
    List<Message> messages,
    List<ToolResultInfo> toolResults,
  ) => _memoryExtraction.extract(
    enabled: _settings.llmCapabilities.supportsLlmMemoryExtraction,
    messages: messages,
    toolResults: toolResults,
    loadProfile: _memoryService.loadProfile,
    router: _secondaryCompletionRouter,
    primaryDataSource: _dataSource,
    route: _settings._memoryExtractionCompletionRoute,
    maxTokens: _settings.maxTokens,
  );

  String _buildMemoryUpdateToolUse(MemoryUpdateResult result) {
    final payload = <String, dynamic>{
      'name': 'memory_update',
      'arguments': <String, dynamic>{
        'summaryUpdated': result.summaryUpdated,
        'added': result.addedMemoryCount,
        'updated': result.updatedMemoryCount,
        'queuedReview': result.queuedReviewCount,
        'suppressed': result.suppressedCandidateCount,
        'profileUpdated': result.profileUpdated,
        'method': result.generationMethod.name,
      },
    };
    return '<tool_use>${jsonEncode(payload)}</tool_use>';
  }

  bool get _isCancellationMounted => ref.mounted;

  ChatState get _cancellationState => state;

  void _setCancellationState(ChatState nextState) {
    state = nextState;
  }

  void cancelStreaming() => _cancelStreaming();

  /// Waits for message writes that must finish before a headless frontend
  /// disposes its provider container.
  Future<void> flushPendingPersistence() => _messagePersistence.flush();

  void clearMessages() {
    if (!ref.mounted) return;
    _beginInteractionGeneration();
    _turnStream.cancelAll();
    _failAllRuntimeTurns(
      code: 'messages_cleared',
      message: 'The conversation was cleared before the turn completed.',
      exitCode: 130,
    );
    _cancelAllPendingToolApprovals();
    _contentToolTurns.clear();
    _hiddenAssistantEvidence.clear();
    _turnEnd.clear();
    _goalCompletionEvidence.clear();
    _toolApprovalCache.clearAll();
    _queuedChatMessages.clear();
    _turnToolResults.clear();
    _goalAutoContinueTrackerRegistry.resetConversation(null);
    _goalContinuationLifecycle.clear();
    _dismissAllPendingAskUserQuestions();
    _clearAllActiveResponses();
    _sessionMemoryContext = null;
    _temporalReferenceContext = null;
    _clearTurnDiffCapture();
    state = ChatState.initial();
  }
}
