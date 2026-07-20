import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno_content_protocol/caverno_content_protocol.dart';
import 'package:caverno_execution_runtime/caverno_execution_runtime.dart';
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
import '../../../../core/services/ssh_credentials_manager.dart';
import '../../../../core/services/ssh_service.dart';
import '../../../../core/services/tool_approval_audit_log.dart';
import '../../../../core/services/voice_providers.dart';
import '../../../../core/types/assistant_mode.dart';
import '../../../../core/types/workspace_mode.dart';
import '../../../../core/utils/logger.dart';
import '../../data/repositories/chat_memory_repository.dart';
import '../../data/repositories/tool_result_artifact_store.dart';
import '../../domain/services/conversation_goal_suggestion_service.dart';
import '../../domain/services/conversation_plan_document_builder.dart';
import '../../domain/services/conversation_planning_prompt_service.dart';
import '../../domain/services/system_prompt_builder.dart';
import '../../domain/services/session_memory_service.dart';
import '../../domain/services/skill_markdown_parser.dart';
import '../../domain/services/skill_prompt_index_builder.dart';
import '../../domain/services/skill_similarity_service.dart';
import '../../../routines/domain/entities/routine.dart';
import '../../../routines/domain/services/routine_schedule_service.dart';
import '../../../routines/presentation/providers/routines_notifier.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/domain/services/llm_provider_capabilities.dart';
import '../../../settings/domain/services/llm_request_temperature_policy.dart';
import '../../../settings/domain/services/llm_sampler_preset_profile.dart';
import '../../../settings/domain/services/llm_sampler_runtime_feedback_service.dart';
import '../../../settings/domain/services/external_tool_hook_service.dart';
import '../../../settings/domain/services/primary_model_preparation_service.dart';
import '../../../settings/presentation/providers/local_model_lifecycle_provider.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/apple_foundation_models_datasource.dart';
import '../../../settings/presentation/providers/mesh_endpoint_provider.dart';
import '../../data/datasources/chat_datasource.dart';
import '../../data/datasources/chat_remote_datasource.dart';
import '../../data/datasources/mesh_secondary_completion_runner.dart';
import '../../data/datasources/participant_completion_runner.dart';
import '../../data/datasources/demo_datasource.dart';
import '../../data/datasources/background_process_monitor_service.dart';
import '../../data/datasources/file_rollback_checkpoint_store.dart';
import '../../data/datasources/filesystem_tools.dart';
import '../../data/datasources/git_tools.dart';
import '../../data/datasources/local_shell_tools.dart';
import '../../data/datasources/lsp_json_rpc_session_registry.dart';
import '../../data/datasources/mcp_tool_service.dart';
import '../../data/datasources/python_input_staging.dart';
import '../../data/datasources/llm_session_log_store.dart';
import '../../data/datasources/session_logging_chat_datasource.dart';
import '../../domain/entities/coding_project.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_compaction_artifact.dart';
import '../../domain/entities/conversation_goal.dart';
import '../../domain/entities/conversation_participant.dart';
import '../../domain/entities/conversation_plan_artifact.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/skill.dart';
import '../../domain/entities/turn_diff.dart';
import '../../domain/entities/subagent_task.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../../domain/services/conversation_compaction_service.dart';
import '../../domain/services/conversation_goal_auto_continue_policy.dart';
import '../../domain/services/context_surgery_observation_service.dart';
import '../../domain/services/tool_approval_auto_review_service.dart';
import '../../domain/services/tool_approval_gate.dart';
import '../../../../core/security/conversation_taint_state.dart';
import '../../../../core/security/tool_capability_classifier.dart';
import '../../domain/services/tool_call_execution_policy.dart';
import '../../domain/services/tool_loop_context_digest.dart';
import '../../domain/services/tool_loop_exit_reason.dart';
import '../../domain/services/truncation_notice.dart';
import '../../domain/services/analysis_options_lint_edit_guard.dart';
import '../../domain/services/coding_command_output_guardrail_service.dart';
import '../../domain/services/coding_diagnostic_feedback_service.dart';
import '../../domain/services/coding_verification_claim_guard.dart';
import '../../domain/services/coding_verification_feedback_service.dart';
import '../../domain/services/command_diagnostic_verifier_replay_policy.dart';
import '../../domain/services/chat_tool_dispatcher.dart';
import '../../domain/services/conversation_plan_execution_coordinator.dart';
import '../../domain/services/conversation_plan_execution_guardrails.dart';
import '../../domain/services/execution_snapshot_projector.dart';
import '../../domain/services/execution_budget_policy.dart';
import '../../domain/services/short_prompt_contract_builder.dart';
import '../../domain/services/dart_project_tooling.dart';
import '../../domain/services/lsp_diagnostic_feedback_provider.dart';
import '../../domain/services/final_answer_claim_detector.dart';
import '../../domain/services/final_answer_recovery_policy.dart';
import '../../domain/services/pending_action_length_recovery_policy.dart';
import '../../domain/services/successful_read_result_replay_cache.dart';
import '../../domain/services/structured_coding_execution_deferral_detector.dart';
import '../../domain/services/memory_extraction_draft_service.dart';
import '../../domain/services/model_edit_apply_telemetry_service.dart';
import '../../domain/services/narrated_transcript_claim_guard.dart';
import '../../domain/services/model_switch_handoff_brief_service.dart';
import '../../domain/services/participant_tool_policy.dart';
import '../../domain/services/participant_turn_coordinator.dart';
import '../../domain/services/secondary_call_budget.dart';
import '../../domain/services/planning_research_collector.dart';
import '../../domain/services/proposal_option_extraction.dart';
import '../../domain/services/proposal_parsing_text_utils.dart';
import '../../domain/services/task_proposal_parser.dart';
import '../../domain/services/workflow_proposal_parser.dart';
import '../../domain/services/planning_tool_policy.dart';
import '../../domain/services/temporal_context_builder.dart';
import '../../domain/services/tool_definition_search_service.dart';
import '../../domain/services/tool_execution_scheduler.dart';
import '../../domain/services/tool_failure_classifier.dart';
import '../../domain/services/tool_loop_recovery_policy.dart';
import '../../domain/services/tool_result_prompt_builder.dart';
import '../../domain/services/tool_result_taint_recorder.dart';
import '../../domain/services/tool_terminal_response_policy.dart';
import '../../domain/services/tool_terminal_success_policy.dart';
import '../../domain/services/turn_diff_service.dart';
import '../../domain/services/unwritten_file_claim_guard.dart';
import '../../domain/services/subagent_execution_service.dart';
import '../../domain/services/subagent_tool_policy.dart';
import '../../domain/services/stalled_diagnostic_repair_contract.dart';
import '../../domain/services/workflow_task_proposal_quality_service.dart';
import '../../../settings/domain/services/local_command_permission_service.dart';
import 'active_response_registry.dart';
import 'chat_state.dart';
import 'chat_tool_execution_log_formatter.dart';
import 'coding_projects_notifier.dart';
import 'caverno_execution_runtime_provider.dart';
import 'conversations_notifier.dart';
import 'macos_computer_use_approval_copy.dart';
import 'mcp_tool_provider.dart';
import 'repo_map_precompute_cache_provider.dart';
import 'skills_notifier.dart';
import 'tool_approval_cache.dart';
import 'subagent_task_notifier.dart';

part 'chat_notifier_approval_handlers.dart';
part 'chat_notifier_ask_user_question.dart';
part 'chat_notifier_ble_handlers.dart';
part 'chat_notifier_browser_handlers.dart';
part 'chat_notifier_cancellation.dart';
part 'chat_notifier_coding_continuation_recovery.dart';
part 'chat_notifier_command_guardrails.dart';
part 'chat_notifier_computer_use_handlers.dart';
part 'chat_notifier_context_surgery.dart';
part 'chat_notifier_duplicate_recovery.dart';
part 'chat_notifier_error_handling.dart';
part 'chat_notifier_execution_runtime.dart';
part 'chat_notifier_final_answer_recovery.dart';
part 'chat_notifier_git_handlers.dart';
part 'chat_notifier_local_file_handlers.dart';
part 'chat_notifier_mesh_routing.dart';
part 'chat_notifier_participant_turns.dart';
part 'chat_notifier_serial_handlers.dart';
part 'chat_notifier_skill_handlers.dart';
part 'chat_notifier_routine_handlers.dart';
part 'chat_notifier_ssh_handlers.dart';
part 'chat_notifier_subagent_handlers.dart';
part 'chat_notifier_python_attachment_repair.dart';
part 'chat_notifier_unexecuted_action_recovery.dart';
part 'chat_notifier_content_tool_result_format.dart';
part 'chat_notifier_coding_verification_feedback.dart';
part 'chat_notifier_python_handlers.dart';
part 'chat_notifier_planning_research.dart';
part 'chat_notifier_proposal_option_extraction.dart';
part 'chat_notifier_proposal_parsing.dart';
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

final chatRemoteDataSourceProvider = Provider<ChatDataSource>((ref) {
  final settings = ref.watch(settingsNotifierProvider);
  if (settings.demoMode) {
    return DemoDataSource();
  }
  if (settings.llmProvider == LlmProvider.appleFoundationModels) {
    return AppleFoundationModelsDataSource(enableSafePromptRetry: true);
  }
  return ChatRemoteDataSource(
    baseUrl: settings.baseUrl,
    apiKey: settings.apiKey,
    reasoningEffort: settings.reasoningEffort.apiValue,
  );
});

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

final class _PendingPrimaryModelPreparation {
  const _PendingPrimaryModelPreparation({
    required this.key,
    this.previousModelId,
  });

  final String key;
  final String? previousModelId;
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
  _PendingPrimaryModelPreparation? _pendingPrimaryModelPreparation;
  late CodingDiagnosticFeedbackService _codingDiagnosticFeedbackService;
  late CodingVerificationFeedbackService _codingVerificationFeedbackService;
  late BackgroundProcessMonitorService _backgroundProcessMonitorService;
  final ToolLoopRecoveryPolicy _toolLoopRecoveryPolicy =
      const ToolLoopRecoveryPolicy();
  final ToolCallExecutionPolicy _toolCallExecutionPolicy =
      const ToolCallExecutionPolicy();
  final FinalAnswerClaimDetector _finalAnswerClaimDetector =
      const FinalAnswerClaimDetector();
  final FinalAnswerRecoveryPolicy _finalAnswerRecoveryPolicy =
      const FinalAnswerRecoveryPolicy();
  final PendingActionLengthRecoveryPolicy _pendingActionLengthRecoveryPolicy =
      const PendingActionLengthRecoveryPolicy();
  final UnwrittenFileClaimGuard _unwrittenFileClaimGuard =
      const UnwrittenFileClaimGuard();
  final CodingVerificationClaimGuard _codingVerificationClaimGuard =
      const CodingVerificationClaimGuard();
  final NarratedTranscriptClaimGuard _narratedTranscriptClaimGuard =
      const NarratedTranscriptClaimGuard();
  final PlanningToolPolicy _planningToolPolicy = const PlanningToolPolicy();
  final ToolLoopContextDigest _toolLoopContextDigest =
      const ToolLoopContextDigest();
  final Map<int, CavernoRuntimeTurnHandle> _runtimeTurnsByGeneration =
      <int, CavernoRuntimeTurnHandle>{};
  final CavernoRuntimeFailureClassifier _runtimeFailureClassifier =
      const CavernoRuntimeFailureClassifier();

  final ConversationTaintState _conversationTaintState =
      ConversationTaintState();
  String? conversationId;
  String _languageCode = 'en';
  String? _sessionMemoryContext;
  String? _temporalReferenceContext;
  Message? _hiddenPrompt;
  bool _persistHiddenPromptAssistantResponse = false;
  bool _isVoiceMode = false;
  TokenUsage _accumulatedTokenUsage = TokenUsage.zero;
  String? _finalAnswerFinishReasonOverride;
  AssistantMode? _assistantModeOverride;
  List<ToolResultInfo> _latestCompletedToolResults = const [];
  String? _latestObservedSystemPrompt;
  String? _latestExecutionSnapshotObservationKey;
  List<ToolResultInfo> _latestObservedToolResults = const [];
  List<Map<String, dynamic>> _latestObservedToolDefinitions = const [];
  Set<String> _latestObservedMcpToolNames = const {};
  String? _modelSwitchHandoffBrief, _modelSwitchHandoffConversationId;
  final List<ToolResultInfo> _latestContentToolResults = [];
  final List<TurnDiffFile> _pendingTurnDiffFiles = [];
  late ToolResultArtifactStore _toolResultArtifactStore;
  String? _latestHiddenAssistantResponse;
  String? _activeTurnUserPrompt;
  DateTime? _activeTurnStartedAt;
  double get _agenticRequestTemperature =>
      LlmRequestTemperaturePolicy.forSettings(_settings).agenticTemperature;
  double get _assistantRequestTemperature =>
      LlmRequestTemperaturePolicy.forSettings(
        _settings,
      ).temperatureForAssistantMode(
        _resolveAssistantMode(
          currentConversation: ref
              .read(conversationsNotifierProvider)
              .currentConversation,
        ),
      );
  static const int _maxRepeatedCodingVerificationRepairAttempts = 2;
  static const int _maxNarratedTranscriptRepairAttempts = 2;

  @override
  ChatState build() {
    _executionRuntime = ref.read(cavernoExecutionRuntimeProvider);
    _settings = ref.read(settingsNotifierProvider);
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

    // Connect MCP tool service.
    _mcpToolService?.connect();

    // Load initial messages from the currently selected conversation.
    final conversationsState = ref.read(conversationsNotifierProvider);
    final initialMessages =
        conversationsState.currentConversation?.messages ?? const <Message>[];
    conversationId = conversationsState.currentConversation?.id;

    // React to settings changes.
    ref.listen<AppSettings>(settingsNotifierProvider, (previous, next) {
      _updateConnectionSettings(next);
    });

    // React to MCP tool service changes.
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

    // React to conversation switches.
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

    // Cancel any in-flight streaming when the provider is disposed.
    ref.onDispose(() {
      _streamSubscription?.cancel();
      _streamSubscription = null;
    });

    return initialMessages.isEmpty
        ? ChatState.initial()
        : ChatState.initial().copyWith(messages: initialMessages);
  }

  /// Persists messages to the conversation store. Replaces the previous
  /// `onMessagesChanged` callback wired in via the provider builder.
  Future<void> _onMessagesChanged(List<Message> messages) {
    final targetConversationId = ref
        .read(conversationsNotifierProvider)
        .currentConversationId;
    if (targetConversationId == null) {
      return Future<void>.value();
    }
    return _onConversationMessagesChanged(targetConversationId, messages);
  }

  Future<void> _onConversationMessagesChanged(
    String conversationId,
    List<Message> messages,
  ) {
    final messagesSnapshot = List<Message>.unmodifiable(messages);
    final write = _conversationMessagePersistenceTail.then((_) async {
      if (!ref.mounted) return;
      await ref
          .read(conversationsNotifierProvider.notifier)
          .updateConversationMessages(conversationId, messagesSnapshot);
    });
    _conversationMessagePersistenceTail = write.catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      appLog(
        '[ChatNotifier] Conversation message persistence failed: '
        '${error.runtimeType}: $error',
      );
      appLog('[ChatNotifier] stackTrace: $stackTrace');
    });
    return write;
  }

  void _persistCurrentNonStreamingMessages() {
    final messagesToSave = state.messages
        .where((message) => !message.isStreaming)
        .where(_shouldKeepVisibleMessage)
        .toList(growable: false);
    unawaited(_onMessagesChanged(messagesToSave));
  }

  /// Speaks the assistant response via TTS when auto-read is enabled.
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

  /// Begins extended background execution on iOS when a request starts.
  void _onSendStarted() {
    _finalAnswerFinishReasonOverride = null;
    ref.read(backgroundTaskServiceProvider).beginBackgroundTask();
  }

  String _primaryModelPreparationKey(AppSettings settings) {
    return [
      settings.llmProvider.name,
      settings.baseUrl.trim(),
      settings.model.trim(),
    ].join('|');
  }

  Future<void> _preparePrimaryModelForPendingRouteIfNeeded() async {
    final pending = _pendingPrimaryModelPreparation;
    if (pending == null) {
      return;
    }
    final settings = _settings;
    if (pending.key != _primaryModelPreparationKey(settings)) {
      _pendingPrimaryModelPreparation = null;
      return;
    }
    if (settings.demoMode ||
        settings.llmProvider != LlmProvider.openAiCompatible ||
        settings.model.trim().isEmpty) {
      _pendingPrimaryModelPreparation = null;
      return;
    }

    try {
      final outcome = await ref
          .read(primaryModelPreparationServiceProvider)
          .preparePrimaryModel(
            settings: settings,
            previousPrimaryModelId: pending.previousModelId,
            refreshCatalog: true,
          );
      _logPrimaryModelPreparationOutcome(outcome);
    } on Object catch (error, stackTrace) {
      appLog(
        '[LL9] Primary model auto-prepare failed: '
        '${error.runtimeType}: $error',
      );
      appLog('[LL9] stackTrace: $stackTrace');
    } finally {
      if (_pendingPrimaryModelPreparation == pending) {
        _pendingPrimaryModelPreparation = null;
      }
    }
  }

  void _logPrimaryModelPreparationOutcome(
    PrimaryModelPreparationOutcome outcome,
  ) {
    final previousModelId = outcome.previousModelId;
    final unloadResult = outcome.unloadActionResult;
    if (previousModelId != null && unloadResult != null) {
      appLog(
        '[LL9] Previous primary model "$previousModelId" unload result: '
        'supported=${unloadResult.supported}, '
        'succeeded=${unloadResult.succeeded}, message=${unloadResult.message}',
      );
      if (outcome.previousModelUnloadConfirmed) {
        appLog(
          '[LL9] Previous primary model "$previousModelId" confirmed '
          'unloaded before preparing "${outcome.modelId}".',
        );
      }
    }

    switch (outcome.status) {
      case PrimaryModelPreparationStatus.loadStarted:
        appLog(
          '[LL9] Primary model "${outcome.modelId}" load requested: '
          '${outcome.message}',
        );
      case PrimaryModelPreparationStatus.inProgress:
        appLog('[LL9] Primary model "${outcome.modelId}" is already loading.');
      case PrimaryModelPreparationStatus.missing:
        appLog(
          '[LL9] Primary model "${outcome.modelId}" is not in the managed '
          'model catalog; continuing without a lifecycle load.',
        );
      case PrimaryModelPreparationStatus.unsupported:
        appLog('[LL9] Primary model auto-prepare skipped: ${outcome.message}');
      case PrimaryModelPreparationStatus.failed:
        appLog(
          '[LL9] Primary model "${outcome.modelId}" preparation failed: '
          '${outcome.message}',
        );
      case PrimaryModelPreparationStatus.ready:
      case PrimaryModelPreparationStatus.skipped:
      case PrimaryModelPreparationStatus.loadRequired:
        break;
    }
  }

  /// Ends extended background execution and posts a notification when the
  /// app is in the background. Replaces the previous `onResponseCompleted`
  /// callback.
  void _onResponseCompleted(String content) {
    ref.read(backgroundTaskServiceProvider).endBackgroundTask();

    if (content.isEmpty) return;
    final lifecycleService = ref.read(appLifecycleServiceProvider);
    if (!lifecycleService.isInBackground) return;

    // Strip <think> blocks and extract readable text for the notification.
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
    final conversationsState = ref.read(conversationsNotifierProvider);
    final currentConversation = targetConversationId == null
        ? conversationsState.currentConversation
        : _conversationForId(targetConversationId);
    final workspaceMode =
        currentConversation?.workspaceMode ??
        (_settings.assistantMode == AssistantMode.coding ||
                _settings.assistantMode == AssistantMode.plan
            ? WorkspaceMode.coding
            : WorkspaceMode.chat);
    final resolvedConversationId =
        targetConversationId ??
        currentConversation?.id ??
        conversationId ??
        'unassigned';

    return LlmSessionLogContext(
      workspaceMode: workspaceMode,
      sessionId: resolvedConversationId,
      sessionTitle: currentConversation?.title,
      conversationId: resolvedConversationId,
      phase: _hiddenPrompt != null
          ? 'hidden_prompt'
          : (_isRemoteInteraction ? 'remote_interaction' : 'chat_turn'),
    );
  }

  Conversation? _conversationForId(String conversationId) {
    for (final conversation
        in ref.read(conversationsNotifierProvider).conversations) {
      if (conversation.id == conversationId) {
        return conversation;
      }
    }
    return null;
  }

  LlmSessionLogContext? _currentLlmSessionLogContext() {
    return _buildLlmSessionLogContext();
  }

  LlmSessionLogContext _llmSessionLogContextForGeneration(int generation) {
    final existing = _llmSessionLogContextsByGeneration[generation];
    if (existing != null) return existing;
    return _buildLlmSessionLogContext(
      targetConversationId: _activeResponseConversationIdForGeneration(
        generation,
      ),
    );
  }

  T _runWithLlmSessionLogContextForGeneration<T>(
    int generation,
    T Function() body,
  ) {
    return LlmSessionLogContext.run(
      _llmSessionLogContextForGeneration(generation),
      body,
    );
  }

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
    final sameConversation = this.conversationId == conversationId;
    final sameMessages = listEquals(state.messages, messages);

    if (sameConversation && sameMessages) {
      return;
    }

    // While a response is in flight, the local chat state is authoritative for
    // the active conversation. Persisted conversation updates can lag behind
    // and would otherwise cancel streaming or discard pending content-tool
    // continuations mid-task.
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
      _clearAllActiveResponses();
      _dismissAllPendingAskUserQuestions();
    }

    if (!preservingActiveResponse) {
      _streamSubscription?.cancel();
      _streamSubscription = null;
      _executedContentToolCalls.clear();
      _seenContentToolCallHashes.clear();
      _toolApprovalCache.clear();
      _conversationTaintState.reset();
      _pendingContentToolResults.clear();
      _pendingContentToolContinuationFallback = null;
      _pendingToolExecutions.clear();
      if (!sameConversation) {
        _queuedChatMessages.clear();
        _latestContentToolResults.clear();
        _latestCompletedToolResults = const [];
        _latestObservedSystemPrompt = null;
        _latestObservedToolResults = const [];
        _latestObservedToolDefinitions = const [];
        _latestObservedMcpToolNames = const {};
        _clearPendingModelSwitchHandoff();
      }
      _clearTurnDiffCapture();
      _contentToolContinuationCount = 0;
      _contentToolExecutionTail = Future<void>.value();
      _sessionMemoryContext = null;
      _temporalReferenceContext = null;
    }

    final restoredActiveGeneration = _activeResponseGenerationForConversation(
      conversationId,
    );
    final restoredActiveMessages = restoredActiveGeneration == null
        ? null
        : _activeResponseMessagesForGeneration(restoredActiveGeneration);
    final restoredPendingQuestion = conversationId == null
        ? null
        : _pendingAskUserQuestionsByThread[conversationId];
    final restoredMessages = restoredActiveMessages ?? messages;
    final restoredLoading = restoredActiveMessages != null;

    this.conversationId = conversationId;
    state = ChatState(
      messages: restoredMessages,
      queuedMessages: restoredLoading
          ? List<QueuedChatMessage>.unmodifiable(_queuedChatMessages)
          : const <QueuedChatMessage>[],
      isLoading: restoredLoading,
      error: null,
      pendingAskUserQuestion: restoredPendingQuestion,
    );
    _refreshContextTokenPressureFromState();
    if (!preservingActiveResponse) {
      _accumulatedTokenUsage = TokenUsage.zero;
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

  Future<void> _recordFileMutationDiff({
    required TextFileSnapshot before,
    required String path,
  }) async {
    if (_activeTurnUserPrompt == null) {
      return;
    }

    final after = await FilesystemTools.captureTextSnapshot(path);
    final filePath = after.path.trim().isNotEmpty ? after.path : before.path;
    final beforeError = before.error?.trim();
    final afterError = after.error?.trim();
    final unavailable =
        beforeError?.isNotEmpty == true || afterError?.isNotEmpty == true;

    final TurnDiffFile? file;
    if (unavailable) {
      file = TurnDiffFile(
        filePath: filePath,
        isNewFile: !before.exists && after.exists,
        isDeletedFile: before.exists && !after.exists,
        isBinary:
            _snapshotErrorSuggestsBinary(beforeError) ||
            _snapshotErrorSuggestsBinary(afterError),
        isLargeFile: false,
        note: [
          if (beforeError?.isNotEmpty == true) beforeError!,
          if (afterError?.isNotEmpty == true) afterError!,
        ].join('\n'),
      );
    } else {
      file = TurnDiffService.buildFileDiff(
        filePath: filePath,
        oldContent: before.exists ? before.content : null,
        newContent: after.exists ? after.content : null,
        oldExists: before.exists,
        newExists: after.exists,
      )?.file;
    }

    if (file == null || !file.hasChanges) {
      return;
    }
    _pendingTurnDiffFiles.add(file);
  }

  bool _snapshotErrorSuggestsBinary(String? error) {
    final lower = error?.toLowerCase() ?? '';
    return lower.contains('binary') || lower.contains('utf-8');
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
    if (!_containsSkillKeyword(latestUserContent)) {
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
        !_looksLikeSkippedSkillLoadResponse(responseContent)) {
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
    if (!_looksLikeBrowserActionRequest(latestUserContent)) {
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
    if (!_hasRecoveredBrowserSnapshot(batchToolResults)) {
      return false;
    }
    final latestUserContent = _latestUserContentForGeneration(
      interactionGeneration,
    );
    return _looksLikeBrowserActionRequest(latestUserContent);
  }

  bool _hasRecoveredBrowserSnapshot(List<ToolResultInfo> toolResults) {
    return toolResults.any(
      (toolResult) =>
          toolResult.name == 'browser_snapshot' &&
          toolResult.id.startsWith('recovered_browser_snapshot_'),
    );
  }

  String _buildSkippedBrowserActionRepairPrompt(int interactionGeneration) {
    final latestUserContent = _latestUserContentForGeneration(
      interactionGeneration,
    );
    final missingToolName = _browserActionToolNameForText(latestUserContent);
    return [
      'The latest user request still requires a browser action.',
      'The application only executed a recovered browser_snapshot so far.',
      'Do not claim the browser action is complete in prose.',
      'If the snapshot contains a safe target, call $missingToolName now using the latest snapshot ref or selector.',
      'If no safe target exists, answer briefly that $missingToolName remains unexecuted.',
    ].join('\n');
  }

  bool _containsAnyCodeUnitSequence(String text, List<List<int>> sequences) {
    return sequences.any(
      (sequence) => _containsCodeUnitSequence(text, sequence),
    );
  }

  String _latestUserContentForGeneration(int generation) {
    final messages =
        _activeResponseMessagesForGeneration(generation) ?? state.messages;
    for (final message in messages.reversed) {
      if (message.role != MessageRole.user) {
        continue;
      }
      final content = message.content.trim();
      if (content.isNotEmpty) {
        return content;
      }
    }
    return '';
  }

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

  bool _containsSkillKeyword(String text) {
    final normalized = text.toLowerCase();
    return normalized.contains('skill') ||
        _containsCodeUnitSequence(text, const [0x30b9, 0x30ad, 0x30eb]);
  }

  bool _looksLikeSkippedSkillLoadResponse(String text) {
    final normalized = text.toLowerCase();
    if (!_containsSkillKeyword(text)) {
      return false;
    }
    return normalized.contains('load') ||
        normalized.contains('read') ||
        normalized.contains('use') ||
        normalized.contains('follow') ||
        _containsCodeUnitSequence(text, const [0x8aad, 0x307f, 0x8fbc]) ||
        _containsCodeUnitSequence(text, const [0x30ed, 0x30fc, 0x30c9]) ||
        text.contains(String.fromCharCode(0x4f7f));
  }

  bool _containsCodeUnitSequence(String text, List<int> sequence) {
    if (sequence.isEmpty || text.length < sequence.length) {
      return false;
    }
    final units = text.codeUnits;
    for (var index = 0; index <= units.length - sequence.length; index++) {
      var matched = true;
      for (var offset = 0; offset < sequence.length; offset++) {
        if (units[index + offset] != sequence[offset]) {
          matched = false;
          break;
        }
      }
      if (matched) {
        return true;
      }
    }
    return false;
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

  CodingProject? _getActiveCodingProject() {
    final conversationsState = ref.read(conversationsNotifierProvider);
    if (conversationsState.activeProjectId == null) {
      return null;
    }
    final projectsState = ref.read(codingProjectsNotifierProvider);
    return projectsState.findById(conversationsState.activeProjectId);
  }

  String? _getActiveProjectRootPath() {
    return _getEffectiveCodingProject()?.rootPath.trim();
  }

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
      _createSystemMessage().copyWith(
        id: 'workflow_proposal_system',
        timestamp: now,
      ),
      Message(
        id: 'workflow_proposal_user',
        role: MessageRole.user,
        timestamp: now,
        content: _buildWorkflowProposalRequest(
          currentConversation: currentConversation,
          languageCode: languageCode,
          researchContext: researchContext,
          decisionAnswers: decisionAnswers,
          additionalPlanningContext: additionalPlanningContext,
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
      _createSystemMessage().copyWith(
        id: 'task_proposal_system',
        timestamp: now,
      ),
      Message(
        id: 'task_proposal_user',
        role: MessageRole.user,
        timestamp: now,
        content: _buildTaskProposalRequest(
          currentConversation: currentConversation,
          languageCode: languageCode,
          researchContext: researchContext,
          workflowStageOverride: workflowStageOverride,
          workflowSpecOverride: workflowSpecOverride,
          additionalPlanningContext: additionalPlanningContext,
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
        state = state.copyWith(
          isLoading: true,
          isGeneratingWorkflowProposal: true,
          workflowProposalError: null,
          pendingWorkflowDecision: null,
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
        final sanitizedProposal = _removeAnsweredOpenQuestions(
          proposal,
          decisionAnswers,
        );
        latestProposal = sanitizedProposal;
        final promotedDecisions = _promoteOpenQuestionsToPlanningPrompts(
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
        _mergeWorkflowDecisionAnswers(decisionAnswers, resolvedAnswers);
        continue;
      }

      if (result case WorkflowProposalParsedDecisions(:final decisions)) {
        final unresolvedDecisions = _filterUnansweredWorkflowDecisions(
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
        _mergeWorkflowDecisionAnswers(decisionAnswers, resolvedAnswers);
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
    final projectLooksEmpty = _projectLooksEmptyForTaskPlanning(
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
      final result = await _dataSource.createChatCompletion(
        messages: _buildWorkflowProposalMessages(
          currentConversation: currentConversation,
          languageCode: languageCode,
          researchContext: researchContext,
          decisionAnswers: decisionAnswers,
          additionalPlanningContext: _buildWorkflowProposalRetryContext(
            additionalPlanningContext,
            minimalRetry: attempt.minimalRetry,
            projectLooksEmpty: projectLooksEmpty,
          ),
          compact: attempt.compact,
        ),
        model: _settings.model,
        temperature: 0.1,
        maxTokens: attempt.maxTokens,
      );

      final response = _parseWorkflowProposalResponseWithFallback(
        result.content,
      );
      if (response != null) {
        if (index > 0) {
          appLog('[Workflow] Workflow proposal recovered on retry');
        }
        return response;
      }

      final truncated = _isCompletionTruncated(result.finishReason);
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

      final preview = _proposalPreview(result.content);
      appLog(
        '[Workflow] Workflow proposal parse failed (attempt ${index + 1}/${attempts.length}, truncated: $truncated): $preview',
      );
      lastError = truncated
          ? 'workflow proposal was truncated: $preview'
          : 'workflow proposal parse failed: $preview';
    }

    throw FormatException(lastError ?? 'workflow proposal parse failed');
  }

  String? _buildWorkflowProposalRetryContext(
    String? additionalPlanningContext, {
    required bool minimalRetry,
    required bool projectLooksEmpty,
  }) {
    final normalizedContext = additionalPlanningContext?.trim();
    if (!minimalRetry && !projectLooksEmpty) {
      return normalizedContext;
    }

    final retryLines = <String>[
      if (projectLooksEmpty)
        'Retry hint: The workspace is empty, so prefer the shortest viable workflow proposal.',
      'Retry hint:',
      '- Return the smallest valid JSON proposal possible.',
      '- Do not restate the user request, project summary, or research context.',
      '- Prefer a short goal plus one or two short list items over verbose explanations.',
      '- If you are space-constrained, return workflowStage, goal, and a minimal acceptanceCriteria list only.',
    ];
    if (projectLooksEmpty) {
      retryLines.add(
        '- For an empty project, avoid setup narration and focus on the requested outcome.',
      );
    }
    final retryHint = retryLines.join('\n');
    if (normalizedContext == null || normalizedContext.isEmpty) {
      return retryHint;
    }
    return '$normalizedContext\n$retryHint'.trim();
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
    final projectLooksEmpty = _projectLooksEmptyForTaskPlanning(
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
      final result = await _dataSource.createChatCompletion(
        messages: _buildTaskProposalMessages(
          currentConversation: currentConversation,
          languageCode: languageCode,
          researchContext: researchContext,
          workflowStageOverride: workflowStageOverride,
          workflowSpecOverride: workflowSpecOverride,
          additionalPlanningContext: _buildTaskProposalRetryContext(
            additionalPlanningContext,
            minimalRetry: attempt.minimalRetry,
            projectLooksEmpty: projectLooksEmpty,
            workflowSpec: workflowSpec,
          ),
          compact: attempt.compact,
        ),
        model: _settings.model,
        temperature: 0.1,
        maxTokens: attempt.maxTokens,
      );

      final proposal = _parseTaskProposalWithFallback(result.content);
      if (proposal != null) {
        final finalizedProposal = _finalizeTaskProposalDraft(
          proposal,
          researchContext: researchContext,
        );
        if (_taskProposalNeedsRetryForWorkflow(
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

      final preview = _proposalPreview(result.content);
      final truncated = _isCompletionTruncated(result.finishReason);
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
          if (!_taskProposalNeedsRetryForWorkflow(
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
        !_taskProposalNeedsRetryForWorkflow(
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

    throw FormatException(lastError ?? 'task proposal parse failed');
  }

  String? _buildTaskProposalRetryContext(
    String? additionalPlanningContext, {
    required bool minimalRetry,
    required bool projectLooksEmpty,
    ConversationWorkflowSpec? workflowSpec,
  }) {
    final normalizedContext = additionalPlanningContext?.trim();
    if (!minimalRetry) {
      return normalizedContext;
    }

    final prefersSingleTask =
        workflowSpec != null &&
        _workflowPrefersExplicitSingleTask(workflowSpec);

    final retryHint = StringBuffer()
      ..writeln('Retry hint:')
      ..writeln('- Return the smallest valid JSON task list possible.')
      ..writeln(
        '- Every task must describe an action the agent can perform immediately.',
      )
      ..writeln('- Keep each title short and imperative.')
      ..writeln(
        '- Use at most one primary implementation file per non-scaffold task.',
      )
      ..writeln(
        '- For implementation tasks, use a validationCommand that directly references, executes, or tests the target file or module.',
      )
      ..writeln(
        '- Do not use generic validation such as "module importable" or commands that only append src to sys.path.',
      )
      ..writeln(
        '- Do not restate the user request, repo summary, or research context.',
      );
    if (prefersSingleTask) {
      retryHint
        ..writeln('- Return exactly one concrete implementation task.')
        ..writeln(
          '- The single task must include implementation and validation in that task.',
        )
        ..writeln(
          '- Do not add a separate verification-only task or follow-up task.',
        );
    } else {
      final requiredFirstSliceTargets = workflowSpec == null
          ? const <String>{}
          : _explicitFirstSliceTargetFiles(workflowSpec);
      retryHint
        ..writeln('- Return two to four concrete tasks.')
        ..writeln('- Do not stop at a single generic setup or scaffold task.');
      if (requiredFirstSliceTargets.isNotEmpty) {
        final targetList = requiredFirstSliceTargets.toList()..sort();
        retryHint
          ..writeln(
            '- The first task targetFiles must include ${targetList.join(', ')}.',
          )
          ..writeln(
            '- Do not split those first-slice scaffold files into separate tasks.',
          );
      }
    }
    if (projectLooksEmpty) {
      if (prefersSingleTask) {
        retryHint
          ..writeln(
            '- In an empty workspace, create the requested single implementation file directly.',
          )
          ..writeln(
            '- Do not scaffold README.md, requirements.txt, tests, or package files unless the workflow explicitly names them.',
          );
      } else {
        retryHint
          ..writeln(
            '- The first task may scaffold the workspace, but a later task must implement or validate the requested feature.',
          )
          ..writeln('- Include a concrete code task after any scaffold task.')
          ..writeln(
            '- Prefer a simple Python entrypoint such as main.py when the workspace is empty.',
          )
          ..writeln(
            '- Avoid pytest-based verification in an empty Python workspace. Prefer standard-library validation such as python3 target.py, python3 tests/test_ping.py, or python3 -m unittest.',
          );
      }
      retryHint.writeln(
        '- Prefer Python standard-library or subprocess-based implementations over third-party runtime dependencies unless the user explicitly asked for a package.',
      );
    }

    final retryContext = retryHint.toString().trim();
    if (normalizedContext == null || normalizedContext.isEmpty) {
      return retryContext;
    }
    return '$normalizedContext\n$retryContext'.trim();
  }

  String _buildWorkflowProposalRequest({
    required Conversation currentConversation,
    required String languageCode,
    PlanningResearchContext researchContext = const PlanningResearchContext(),
    List<WorkflowPlanningDecisionAnswer> decisionAnswers = const [],
    String? additionalPlanningContext,
    bool compact = false,
  }) {
    return ConversationPlanningPromptService.buildWorkflowProposalRequest(
      currentConversation: currentConversation,
      messages: state.messages,
      languageCode: languageCode,
      project: _getEffectiveCodingProject(),
      researchContextBlock: researchContext.hasContent
          ? researchContext.toPromptBlock()
          : null,
      selectedDecisionLines: decisionAnswers
          .map((answer) => '${answer.question}: ${answer.optionLabel}')
          .toList(growable: false),
      additionalPlanningContext: additionalPlanningContext,
      compact: compact,
    );
  }

  String _buildTaskProposalRequest({
    required Conversation currentConversation,
    required String languageCode,
    PlanningResearchContext researchContext = const PlanningResearchContext(),
    ConversationWorkflowStage? workflowStageOverride,
    ConversationWorkflowSpec? workflowSpecOverride,
    String? additionalPlanningContext,
    bool compact = false,
  }) {
    return ConversationPlanningPromptService.buildTaskProposalRequest(
      currentConversation: currentConversation,
      messages: state.messages,
      languageCode: languageCode,
      project: _getEffectiveCodingProject(),
      researchContextBlock: researchContext.hasContent
          ? researchContext.toPromptBlock()
          : null,
      workflowStageOverride: workflowStageOverride,
      workflowSpecOverride: workflowSpecOverride,
      additionalPlanningContext: additionalPlanningContext,
      compact: compact,
    );
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
        : _deriveWorkflowFallbackGoalFromConversation(currentConversation);
    if (rawGoal == null || rawGoal.isEmpty) {
      return null;
    }

    if (bestRetryCandidate != null &&
        !_taskProposalNeedsRetryForWorkflow(
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
    if (_taskProposalNeedsRetryForWorkflow(
      fallbackProposal,
      finalizedFallback,
      projectLooksEmpty,
      workflowSpec,
    )) {
      return null;
    }
    return finalizedFallback;
  }

  bool _projectLooksEmptyForTaskPlanning(PlanningResearchContext context) {
    final rootEntries = context.rootEntries
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (rootEntries.isEmpty) {
      return true;
    }
    return rootEntries.every(
      (entry) =>
          entry.contains('.png') ||
          entry.contains('.jpg') ||
          entry.contains('.jpeg'),
    );
  }

  @visibleForTesting
  WorkflowProposalDraft? parseWorkflowProposalForTest(String rawContent) {
    final response = _parseWorkflowProposalResponseWithFallback(rawContent);
    return switch (response) {
      WorkflowProposalParsedDraft(:final proposal) => proposal,
      _ => null,
    };
  }

  @visibleForTesting
  List<WorkflowPlanningDecision>? parseWorkflowDecisionsForTest(
    String rawContent,
  ) {
    final response = _parseWorkflowProposalResponseWithFallback(rawContent);
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
    return _promoteOpenQuestionsToPlanningPrompts(
      openQuestions,
      decisionAnswers: decisionAnswers,
    );
  }

  @visibleForTesting
  WorkflowTaskProposalDraft? parseTaskProposalForTest(String rawContent) {
    return _parseTaskProposalWithFallback(rawContent);
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
        _sanitizeTaskProposalTasks(proposal.tasks),
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
    return _taskProposalNeedsRetry(original, finalized, projectLooksEmpty);
  }

  @visibleForTesting
  bool taskProposalNeedsRetryForWorkflowForTest(
    WorkflowTaskProposalDraft original,
    WorkflowTaskProposalDraft finalized,
    bool projectLooksEmpty,
    ConversationWorkflowSpec workflowSpec,
  ) {
    return _taskProposalNeedsRetryForWorkflow(
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
    return _buildTaskProposalRetryContext(
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
  }) {
    return _buildDuplicateFollowUpRecoveryPrompt(
      toolCalls,
      previousToolResults: previousToolResults,
    );
  }

  @visibleForTesting
  String buildDuplicateInspectionRecoveryPromptForTest(
    List<ToolCallInfo> toolCalls, {
    List<ToolResultInfo> previousToolResults = const [],
  }) {
    return _buildDuplicateInspectionRecoveryPrompt(
      toolCalls,
      previousToolResults: previousToolResults,
    );
  }

  @visibleForTesting
  String messageContentWithPrependedClaimCorrectionNoticeForTest(
    String content,
    String notice,
  ) {
    return _messageContentWithPrependedClaimCorrectionNotice(content, notice);
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
  String buildSkippedPythonAttachmentAnalysisRepairPromptForTest() {
    return _buildSkippedPythonAttachmentAnalysisRepairPrompt();
  }

  @visibleForTesting
  String buildPythonAttachmentPathFailureRepairPromptForTest() {
    return _buildPythonAttachmentPathFailureRepairPrompt();
  }

  @visibleForTesting
  List<ToolResultInfo> buildToolLoopRecoveryToolResultsForTest({
    required List<ToolResultInfo> currentToolResults,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolCallInfo> pendingToolCalls,
  }) {
    return _buildToolLoopRecoveryToolResults(
      currentToolResults: currentToolResults,
      executedToolResults: executedToolResults,
      pendingToolCalls: pendingToolCalls,
    );
  }

  @visibleForTesting
  List<ToolResultInfo> buildDuplicateRecoveryToolResultsForTest({
    required List<ToolCallInfo> currentToolCalls,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolResultInfo> fallbackToolResults,
  }) {
    return _buildDuplicateRecoveryToolResults(
      currentToolCalls: currentToolCalls,
      executedToolResults: executedToolResults,
      fallbackToolResults: fallbackToolResults,
    );
  }

  @visibleForTesting
  bool assistantMessageHasVisibleContentForTest(String content) {
    return _assistantMessageHasVisibleContent(content);
  }

  @visibleForTesting
  WorkflowProposalDraft? buildWorkflowProposalFallbackForTest({
    WorkflowProposalDraft? latestProposal,
    required List<WorkflowPlanningDecision> decisions,
    List<WorkflowPlanningDecisionAnswer> decisionAnswers = const [],
  }) {
    final unresolvedDecisions = _filterUnansweredWorkflowDecisions(
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
    return _normalizeWriteFileArgumentAliases(arguments);
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
    String? projectRoot;
    var projectRootLoaded = false;

    String? loadProjectRoot() {
      if (!projectRootLoaded) {
        projectRoot = _getActiveProjectRootPath();
        projectRootLoaded = true;
      }
      return projectRoot;
    }

    String? resolvePathArg(
      String key, {
      bool allowEmpty = false,
      List<String> aliases = const [],
      String? fallbackWhenMissing,
    }) {
      String? rawValue = (arguments[key] as String?)?.trim();
      for (final alias in aliases) {
        if (rawValue != null && rawValue.isNotEmpty) {
          break;
        }
        rawValue = (arguments[alias] as String?)?.trim();
      }
      final hasExplicitValue = rawValue != null && rawValue.isNotEmpty;
      if (!hasExplicitValue && fallbackWhenMissing != null) {
        rawValue = fallbackWhenMissing;
      }
      if ((rawValue == null || rawValue.isEmpty) && !allowEmpty) {
        return null;
      }
      final resolved = FilesystemTools.resolvePath(
        rawValue,
        defaultRoot: loadProjectRoot(),
      );
      if (resolved == null &&
          !hasExplicitValue &&
          fallbackWhenMissing != null) {
        return fallbackWhenMissing;
      }
      return resolved;
    }

    return switch (toolName) {
      'list_directory' || 'find_files' || 'search_files' => () {
        final resolvedPath = resolvePathArg(
          'path',
          allowEmpty: true,
          fallbackWhenMissing: '.',
        );
        final resolvedArguments = <String, dynamic>{...arguments};
        if (resolvedPath != null) {
          resolvedArguments['path'] = resolvedPath;
        }
        return resolvedArguments;
      }(),
      'resolve_installed_dependency' => () {
        final resolvedProjectPath = resolvePathArg(
          'project_path',
          allowEmpty: true,
          aliases: const ['path', 'working_directory', 'cwd'],
          fallbackWhenMissing: '.',
        );
        final resolvedArguments = <String, dynamic>{...arguments};
        if (resolvedProjectPath != null) {
          resolvedArguments['project_path'] = resolvedProjectPath;
        }
        return resolvedArguments;
      }(),
      'read_file' ||
      'inspect_file' ||
      'write_file' ||
      'edit_file' ||
      'delete_file' ||
      'lsp_go_to_definition' => () {
        final resolvedPath = resolvePathArg('path');
        final resolvedArguments = toolName == 'write_file'
            ? _normalizeWriteFileArgumentAliases(arguments)
            : <String, dynamic>{...arguments};
        if (resolvedPath != null) {
          resolvedArguments['path'] = resolvedPath;
        }
        return resolvedArguments;
      }(),
      'local_execute_command' || 'process_start' => () {
        final resolvedWorkingDirectory = resolvePathArg(
          'working_directory',
          allowEmpty: true,
          aliases: const ['cwd'],
        );
        final resolvedArguments = <String, dynamic>{...arguments};
        final command = (resolvedArguments['command'] as String?)?.trim();
        if (command != null && command.isNotEmpty) {
          resolvedArguments['command'] = LocalShellTools.normalizeCommand(
            command,
          );
        }
        if (resolvedWorkingDirectory != null) {
          resolvedArguments['working_directory'] = resolvedWorkingDirectory;
        }
        return resolvedArguments;
      }(),
      'git_execute_command' || 'git_finish_worktree_session' => () {
        final resolvedWorkingDirectory = resolvePathArg(
          'working_directory',
          allowEmpty: true,
          aliases: const ['cwd'],
        );
        final resolvedWorktreePath = resolvePathArg(
          'worktree_path',
          allowEmpty: true,
        );
        final resolvedArguments = <String, dynamic>{...arguments};
        if (resolvedWorkingDirectory != null) {
          resolvedArguments['working_directory'] = resolvedWorkingDirectory;
        }
        if (resolvedWorktreePath != null) {
          resolvedArguments['worktree_path'] = resolvedWorktreePath;
        }
        return resolvedArguments;
      }(),
      _ => arguments,
    };
  }

  Map<String, dynamic> _normalizeWriteFileArgumentAliases(
    Map<String, dynamic> arguments,
  ) {
    final normalizedArguments = <String, dynamic>{...arguments};
    final content = (normalizedArguments['content'] as String?)?.trim();
    final contents = (normalizedArguments['contents'] as String?)?.trim();
    if ((content == null || content.isEmpty) &&
        contents != null &&
        contents.isNotEmpty) {
      normalizedArguments['content'] = contents;
    }
    return normalizedArguments;
  }

  /// Prepares the message list sent to the LLM, including system messages.
  List<Message> _prepareMessagesForLLM({
    bool forceCompaction = false,
    List<Map<String, dynamic>>? toolDefinitionsOverride,
    int? interactionGeneration,
    String? participantRolePrompt,
  }) {
    final conversationsState = ref.read(conversationsNotifierProvider);
    final activeConversationId = interactionGeneration == null
        ? _activeResponseConversationId
        : _activeResponseConversationIdForGeneration(interactionGeneration);
    final currentConversation = activeConversationId == null
        ? conversationsState.currentConversation
        : conversationsState.conversations
              .where((conversation) => conversation.id == activeConversationId)
              .firstOrNull;
    final sourceMessages = interactionGeneration == null
        ? (_isActiveResponseDetached && _activeResponseMessages != null
              ? _activeResponseMessages!
              : state.messages)
        : (_activeResponseMessagesForGeneration(interactionGeneration) ??
              state.messages);
    final messages =
        ConversationPlanExecutionCoordinator.filterSupersededTaskExecutionTurns(
              messages: sourceMessages.where((message) => !message.isStreaming),
              currentExecutionPrompt: _hiddenPrompt?.content,
            )
            .map(_sanitizeMessageForModelHistory)
            .where(_shouldKeepMessageForModelHistory)
            .toList();
    final modelSwitchHandoffBrief = _takePendingModelSwitchHandoffBrief(
      currentConversation?.id,
    );
    final shouldForceCompaction = _consumeForcePromptCompactionFlag(
      forceCompaction: forceCompaction,
      hasModelSwitchHandoff: modelSwitchHandoffBrief != null,
    );
    final promptMessages = <Message>[
      _createSystemMessage(
        participantRolePrompt: participantRolePrompt,
        toolNamesOverride: toolDefinitionsOverride == null
            ? null
            : ToolDefinitionSearchService.toolNamesFromDefinitions(
                toolDefinitionsOverride,
              ).toList(),
      ),
    ];
    if (_temporalReferenceContext != null) {
      promptMessages.add(
        Message(
          id: 'system_temporal',
          content: _temporalReferenceContext!,
          role: MessageRole.system,
          timestamp: DateTime.now(),
        ),
      );
    }
    _addModelSwitchHandoffPromptMessage(
      promptMessages,
      modelSwitchHandoffBrief,
    );
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
    if (_hiddenPrompt != null) {
      result.add(_hiddenPrompt!);
    }
    _updateContextTokenPressureState(
      pressure: ConversationCompactionService.assessTokenPressure(
        messages: result,
      ),
      compactionActive: compactionArtifact?.hasContent ?? false,
    );
    return result;
  }

  Message _sanitizeMessageForModelHistory(Message message) {
    if (message.role != MessageRole.assistant) {
      return message;
    }

    final strippedContent = ContentParser.stripModelHistoryArtifacts(
      message.content,
    );
    if (strippedContent == message.content) {
      return message;
    }
    return message.copyWith(content: strippedContent);
  }

  bool _shouldKeepMessageForModelHistory(Message message) {
    if (message.role != MessageRole.assistant) {
      return true;
    }
    return message.content.trim().isNotEmpty;
  }

  bool _shouldKeepVisibleMessage(Message message) {
    if (message.role != MessageRole.assistant) {
      return true;
    }
    return message.content.trim().isNotEmpty ||
        ContentParser.parse(message.content).segments.any(
          (segment) =>
              segment.type == ContentType.toolCall ||
              segment.type == ContentType.toolResult,
        );
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
  StreamSubscription<String>? _streamSubscription;

  /// Tracks executed `tool_call`s to avoid duplicate execution.
  final Set<String> _executedContentToolCalls = {};
  final Set<String> _seenContentToolCallHashes = {};
  final List<String> _pendingContentToolResults = [];
  String? _pendingContentToolContinuationFallback;
  final List<QueuedChatMessage> _queuedChatMessages = [];
  final ToolApprovalCache _toolApprovalCache = ToolApprovalCache();
  final SuccessfulReadResultReplayCache _successfulReadResultReplayCache =
      SuccessfulReadResultReplayCache();
  static const int _maxContentToolContinuations = 5;
  int _contentToolContinuationCount = 0;
  final Set<int> _turnFinalizationRecoveryGenerations = {};
  // LL31: reason the current tool-calling turn ended, set by the loop at the
  // break sites where it cannot be derived from terminal state and consumed by
  // `_logTurnExitReason` during finalization.
  ToolLoopExitReason? _turnExitReasonHint;
  // Turn provenance: transforms (guard notices, ...) applied to the turn's
  // final message, recorded on the turn_exit record so the log explains why the
  // on-screen content differs from the raw LLM output.
  final Set<String> _appliedTurnTransforms = <String>{};
  // Commands issued through command-execution tools during the current
  // interaction generation. Repair revivals re-enter _executeToolCalls with a
  // fresh executedToolResults list, so the transcript claim guard needs a
  // generation-scoped ledger to avoid flagging commands that ran before the
  // revival.
  int? _turnCommandLedgerGeneration;
  final List<String> _turnCommandLedger = <String>[];
  // Tool call ids whose arguments were lost to an output-token-limit
  // truncation (finish_reason=length with empty parsed arguments). The batch
  // executor answers these with a truncation-specific diagnostic instead of a
  // generic missing-argument error, so the model re-issues the intended call
  // instead of misattributing the failure.
  Set<String> _lengthTruncatedToolCallIds = const <String>{};
  Future<void> _contentToolExecutionTail = Future<void>.value();
  Future<void> _conversationMessagePersistenceTail = Future<void>.value();
  Future<void> _cancelledMessagePersistenceTail = Future<void>.value();
  final Map<int, String> _runtimeVisibleAssistantContentByGeneration =
      <int, String>{};
  bool _forcePromptCompactionForNextRequest = false;
  bool _isDrainingQueuedMessages = false;
  bool _isSchedulingGoalAutoContinue = false;
  final Map<String, _GoalAutoContinueTracker> _goalAutoContinueTrackers =
      <String, _GoalAutoContinueTracker>{};
  final Set<String> _goalAutoContinueBudgetNotifiedConversations = <String>{};
  ToolResultCompletionEvidence _latestGoalAutoContinueEvidence =
      const ToolResultCompletionEvidence();
  // Interaction generation in which a save_skill tool call last succeeded. Used
  // to suppress coding continuation-recovery: once a skill has been authored
  // this turn, the model's "skill created" summary is a legitimate completion,
  // not an unexecuted coding continuation that needs a forced retry.
  int? _lastSaveSkillGeneration;
  final ActiveResponseRegistry _activeResponseRegistry =
      ActiveResponseRegistry();
  final Map<int, String> _lastStreamedToolResultFinalAnswersByGeneration =
      <int, String>{};
  final Set<int> _pendingActionLengthRecoveryGenerations = <int>{};
  final Map<int, String> _explicitTerminalSuccessSummariesByGeneration =
      <int, String>{};
  final Map<int, LlmSessionLogContext> _llmSessionLogContextsByGeneration =
      <int, LlmSessionLogContext>{};
  final _AskUserQuestionTurnCache _askUserQuestionTurnCache =
      _AskUserQuestionTurnCache();
  final Map<int, Stopwatch> _responseMetricTimersByGeneration =
      <int, Stopwatch>{};
  final Map<String, PendingAskUserQuestion> _pendingAskUserQuestionsByThread =
      <String, PendingAskUserQuestion>{};
  bool _participantTurnStopRequested = false;
  ParticipantTurnCursor? _pausedParticipantTurnCursor;
  List<ConversationParticipant> _pausedParticipantTurnParticipants = const [];
  ParticipantTurnConfig? _pausedParticipantTurnConfig;
  String? _pausedParticipantTurnConversationId;
  String? _pausedParticipantTurnPreferredId;
  String? _pausedParticipantTurnLastSpeakerId;
  ChatInteractionOrigin _activeInteractionOrigin = ChatInteractionOrigin.local;

  bool get _isRemoteInteraction =>
      _activeInteractionOrigin == ChatInteractionOrigin.remote;

  int get _interactionGeneration => _activeResponseRegistry.currentGeneration;

  String? get _activeResponseConversationId =>
      _activeResponseRegistry.currentConversationId;

  List<Message>? get _activeResponseMessages =>
      _activeResponseRegistry.currentMessages;

  int _beginInteractionGeneration() {
    return _activeResponseRegistry.beginGeneration();
  }

  void _startResponseMetricsTimer(int generation) {
    _responseMetricTimersByGeneration[generation]?.stop();
    _responseMetricTimersByGeneration[generation] = Stopwatch()..start();
  }

  bool _isCurrentInteractionGeneration(int generation) {
    return ref.mounted &&
        _activeResponseRegistry.isCurrentOrRegistered(generation);
  }

  bool isConversationBusy(String targetConversationId) {
    final normalizedConversationId = targetConversationId.trim();
    if (normalizedConversationId.isEmpty) {
      return false;
    }
    if (_activeResponseGenerationForConversation(normalizedConversationId) !=
        null) {
      return true;
    }
    if (conversationId != normalizedConversationId) {
      return false;
    }
    return state.isLoading ||
        state.isGeneratingWorkflowProposal ||
        state.isGeneratingTaskProposal;
  }

  bool get _hasActiveResponse => _activeResponseRegistry.hasActiveResponse;

  bool get _isActiveResponseDetached =>
      _activeResponseRegistry.isDetached(visibleConversationId: conversationId);

  int? _activeResponseGenerationForConversation(String? targetConversationId) {
    return _activeResponseRegistry.generationForConversation(
      targetConversationId,
    );
  }

  String? _activeResponseConversationIdForGeneration(int generation) {
    return _activeResponseRegistry.conversationIdForGeneration(generation);
  }

  List<Message>? _activeResponseMessagesForGeneration(int generation) {
    return _activeResponseRegistry.messagesForGeneration(generation);
  }

  bool _isActiveResponseDetachedForGeneration(int generation) {
    return _activeResponseRegistry.isDetachedForGeneration(
      generation: generation,
      visibleConversationId: conversationId,
    );
  }

  void _registerActiveResponse({
    required int generation,
    required String? targetConversationId,
    required List<Message> messages,
  }) {
    _activeResponseRegistry.register(
      generation: generation,
      targetConversationId: targetConversationId,
      messages: messages,
    );
  }

  void _cacheActiveResponseMessagesForGeneration(
    int generation,
    List<Message> messages,
  ) {
    _activeResponseRegistry.cacheMessages(generation, messages);
  }

  void _clearActiveResponseForGeneration(int generation) {
    _activeResponseRegistry.clearGeneration(generation);
    _lastStreamedToolResultFinalAnswersByGeneration.remove(generation);
    _pendingActionLengthRecoveryGenerations.remove(generation);
    _explicitTerminalSuccessSummariesByGeneration.remove(generation);
    _llmSessionLogContextsByGeneration.remove(generation);
    _askUserQuestionTurnCache.removeGeneration(generation);
    _responseMetricTimersByGeneration.remove(generation)?.stop();
    _turnFinalizationRecoveryGenerations.remove(generation);
  }

  void _clearAllActiveResponses() {
    _activeResponseRegistry.clearAll();
    _lastStreamedToolResultFinalAnswersByGeneration.clear();
    _pendingActionLengthRecoveryGenerations.clear();
    _explicitTerminalSuccessSummariesByGeneration.clear();
    _llmSessionLogContextsByGeneration.clear();
    _askUserQuestionTurnCache.clear();
    for (final timer in _responseMetricTimersByGeneration.values) {
      timer.stop();
    }
    _responseMetricTimersByGeneration.clear();
    _turnFinalizationRecoveryGenerations.clear();
    _participantTurnStopRequested = false;
    _pausedParticipantTurnCursor = null;
    _pausedParticipantTurnParticipants = const [];
    _pausedParticipantTurnConfig = null;
    _pausedParticipantTurnConversationId = null;
    _pausedParticipantTurnPreferredId = null;
    _pausedParticipantTurnLastSpeakerId = null;
  }

  Future<void> sendMessage(
    String content, {
    String? imageBase64,
    String? imageMimeType,
    String? originalImagePath,
    String? originalImageMimeType,
    String languageCode = 'en',
    bool isVoiceMode = false,
    bool bypassPlanMode = false,
    ChatInteractionOrigin origin = ChatInteractionOrigin.local,
  }) async {
    // Do not send empty input with no attached image.
    if (content.trim().isEmpty && imageBase64 == null) return;
    if (!ref.mounted) return;

    // A fresh user message means any unanswered ask_user_question is being
    // bypassed (the user typed the answer instead of using the dialog — common
    // on remote/mobile where the dialog may not surface). Dismiss it now so its
    // awaiting tool loop unblocks and the pending dialog clears, instead of the
    // question being orphaned (still open on the desktop) and the turn stalling.
    _dismissAllPendingAskUserQuestions();

    final queuedMessage = QueuedChatMessage(
      id: _uuid.v4(),
      content: content,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      originalImagePath: originalImagePath,
      originalImageMimeType: originalImageMimeType,
      languageCode: languageCode,
      isVoiceMode: isVoiceMode,
      bypassPlanMode: bypassPlanMode,
      origin: origin,
    );
    if (state.isLoading) {
      final participantRuntime = state.participantTurnRuntime;
      if (participantRuntime != null && !participantRuntime.paused) {
        _participantTurnStopRequested = true;
        state = state.copyWith(
          participantTurnRuntime: participantRuntime.copyWith(
            stopRequested: true,
          ),
        );
      }
      _queuedChatMessages.add(queuedMessage);
      _syncQueuedChatMessagesState();
      appLog(
        '[ChatNotifier] Queued user message while a response is in flight '
        '(${_queuedChatMessages.length} pending)',
      );
      return;
    }

    await _sendMessageNow(queuedMessage);
  }

  Future<void> _sendMessageNow(QueuedChatMessage queuedMessage) async {
    if (!ref.mounted) return;

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
    if (currentConversation == null) {
      final draftMessages = state.messages
          .where((message) => !message.isStreaming)
          .toList(growable: false);
      currentConversation = conversationsNotifier.ensureCurrentConversation();
      if (currentConversation != null && draftMessages.isNotEmpty) {
        await conversationsNotifier.updateConversationMessages(
          currentConversation.id,
          draftMessages,
        );
      }
      conversationsState = ref.read(conversationsNotifierProvider);
    }

    _activeInteractionOrigin = queuedMessage.origin;
    final interactionGeneration = _beginInteractionGeneration();

    _hiddenPrompt = null;
    _persistHiddenPromptAssistantResponse = false;
    _languageCode = languageCode;
    _isVoiceMode = isVoiceMode;
    _toolApprovalCache.clear();
    _pendingContentToolResults.clear();
    _pendingContentToolContinuationFallback = null;
    _pendingToolExecutions.clear();
    _latestContentToolResults.clear();
    _latestCompletedToolResults = const [];
    _latestObservedSystemPrompt = null;
    _latestObservedToolResults = const [];
    _latestObservedToolDefinitions = const [];
    _latestObservedMcpToolNames = const {};
    _latestGoalAutoContinueEvidence = const ToolResultCompletionEvidence();
    _contentToolContinuationCount = 0;
    _contentToolExecutionTail = Future<void>.value();
    _latestHiddenAssistantResponse = null;
    _beginTurnDiffCapture(content);

    _temporalReferenceContext = TemporalContextBuilder.build(
      now: DateTime.now(),
      userInput: content,
    );
    final shouldUseTemporalTool = _temporalReferenceContext != null;
    currentConversation = conversationsState.currentConversation;
    conversationId = currentConversation?.id;
    if (!await _startRuntimeTurn(
      generation: interactionGeneration,
      hidden: false,
    )) {
      return;
    }
    conversationsState = ref.read(conversationsNotifierProvider);
    currentConversation = conversationsState.currentConversation;
    conversationId = currentConversation?.id;
    _resetGoalAutoContinueTrackerForConversation(conversationId);
    final shouldAutoEnterPlanning =
        !bypassPlanMode && _shouldAutoEnterPlanningSession(currentConversation);
    if (shouldAutoEnterPlanning) {
      await conversationsNotifier.enterPlanningSession();
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      currentConversation = ref
          .read(conversationsNotifierProvider)
          .currentConversation;
      conversationId = currentConversation?.id;
    }

    // Inject memory context only on the first turn of a new session.
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

    // Append the user message.
    final userMessage = Message(
      id: _uuid.v4(),
      content: content.trim(),
      role: MessageRole.user,
      timestamp: DateTime.now(),
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      originalImagePath: originalImagePath,
      originalImageMimeType: originalImageMimeType,
    );

    if (!ref.mounted) return;
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isLoading: true,
      error: null,
      goalAutoContinueCount: 0,
      goalAutoContinueBudget: 0,
      goalAutoContinueNotice: null,
    );
    _refreshContextTokenPressureFromState();
    _llmSessionLogContextsByGeneration[interactionGeneration] =
        _buildLlmSessionLogContext(targetConversationId: conversationId);
    _registerActiveResponse(
      generation: interactionGeneration,
      targetConversationId: conversationId,
      messages: state.messages,
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

    await conversationsNotifier.ensureCurrentPlanArtifactBackfilled();
    if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
    currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    conversationId = currentConversation?.id;
    await _ensureShortPromptExecutionContract(
      currentConversation: currentConversation,
      userMessage: userMessage,
      conversationsNotifier: conversationsNotifier,
    );
    if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
    await _markPendingExecutionTaskStarted(
      conversationsNotifier: conversationsNotifier,
      bypassPlanMode: bypassPlanMode,
    );
    if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
    currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    conversationId = currentConversation?.id;
    await _preparePrimaryModelForPendingRouteIfNeeded();
    if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
    final shouldInterceptForPlanMode =
        !bypassPlanMode &&
        (currentConversation?.isPlanningSession ?? false) &&
        currentConversation?.workspaceMode == WorkspaceMode.coding;

    if (shouldInterceptForPlanMode) {
      await _onMessagesChanged(
        state.messages.where((message) => !message.isStreaming).toList(),
      );
      if (currentConversation == null) {
        state = state.copyWith(isLoading: false);
        _failRuntimeTurn(
          interactionGeneration,
          code: 'conversation_unavailable',
          message: 'No conversation is available for Plan Mode execution.',
        );
        return;
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
        return;
      }
      await _runPlanProposalFlow(
        currentConversation: currentConversation,
        languageCode: languageCode,
        interactionGeneration: interactionGeneration,
      );
      return;
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
      }
      return;
    }

    // Append a placeholder assistant message for streaming.
    final assistantMessage = Message(
      id: _uuid.v4(),
      content: '',
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
      isStreaming: true,
    );

    if (!ref.mounted) return;
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

    _startResponseMetricsTimer(interactionGeneration);

    // Request extended background execution time on iOS.
    _onSendStarted();

    _assistantModeOverride = bypassPlanMode ? AssistantMode.coding : null;

    try {
      // Use tool-aware flow when the MCP tool service is available.
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
        await _sendWithoutTools(interactionGeneration: interactionGeneration);
      }
    } finally {
      _assistantModeOverride = null;
      _activeInteractionOrigin = ChatInteractionOrigin.local;
    }
  }

  void removeQueuedMessage(String id) {
    final beforeLength = _queuedChatMessages.length;
    _queuedChatMessages.removeWhere((message) => message.id == id);
    if (_queuedChatMessages.length == beforeLength) {
      return;
    }
    _syncQueuedChatMessagesState();
    appLog(
      '[ChatNotifier] Removed queued user message '
      '(${_queuedChatMessages.length} remaining)',
    );
  }

  void _syncQueuedChatMessagesState() {
    if (!ref.mounted) {
      return;
    }
    state = state.copyWith(
      queuedMessages: List<QueuedChatMessage>.unmodifiable(_queuedChatMessages),
    );
  }

  Future<void> _drainQueuedChatMessagesIfIdle() async {
    if (_isDrainingQueuedMessages || state.isLoading) {
      return;
    }
    if (_queuedChatMessages.isEmpty) {
      return;
    }

    _isDrainingQueuedMessages = true;
    try {
      while (ref.mounted &&
          !state.isLoading &&
          _queuedChatMessages.isNotEmpty) {
        final queuedMessage = _queuedChatMessages.removeAt(0);
        _syncQueuedChatMessagesState();
        appLog(
          '[ChatNotifier] Sending queued user message '
          '(${_queuedChatMessages.length} remaining)',
        );
        await _sendMessageNow(queuedMessage);
      }
    } finally {
      _isDrainingQueuedMessages = false;
    }
  }

  /// Sends a hidden prompt without appending it to the visible conversation state.
  /// Typically used for proactive AI responses, like handling user silence in Voice Mode.
  Future<void> sendHiddenPrompt(
    String instruction, {
    bool isVoiceMode = false,
    String languageCode = 'en',
    bool persistAssistantResponse = false,
    bool preserveGoalAutoContinueEvidence = false,
    bool replayVerifierImmediatelyAfterMutation = false,
    bool verifierOnlyContinuation = false,
    Set<String>? allowedToolNames,
  }) async {
    if (!ref.mounted) return;

    _temporalReferenceContext = null;
    _isVoiceMode = isVoiceMode;
    _languageCode = languageCode;
    _toolApprovalCache.clear();
    // Hidden continuations are new turns for approval/result buffers, token
    // accounting, and completion evidence. Keep content-tool dedupe guards:
    // those are conversation-scoped so echoed earlier tool-call text cannot
    // re-execute a side-effectful embedded call.
    _pendingContentToolResults.clear();
    _pendingContentToolContinuationFallback = null;
    _pendingToolExecutions.clear();
    _latestContentToolResults.clear();
    _latestCompletedToolResults = const [];
    _contentToolContinuationCount = 0;
    _contentToolExecutionTail = Future<void>.value();
    _accumulatedTokenUsage = TokenUsage.zero;
    _latestHiddenAssistantResponse = null;
    if (!preserveGoalAutoContinueEvidence) {
      _latestGoalAutoContinueEvidence = const ToolResultCompletionEvidence();
    }
    _persistHiddenPromptAssistantResponse = persistAssistantResponse;
    final interactionGeneration = _beginInteractionGeneration();
    if (!await _startRuntimeTurn(
      generation: interactionGeneration,
      hidden: true,
    )) {
      return;
    }
    _clearTurnDiffCapture();
    _hiddenPrompt = Message(
      id: _uuid.v4(),
      content: instruction,
      role: MessageRole.user,
      timestamp: DateTime.now(),
    );

    // Append a placeholder assistant message for streaming.
    final assistantMessage = Message(
      id: _uuid.v4(),
      content: '',
      role: MessageRole.assistant,
      timestamp: DateTime.now(),
      isStreaming: true,
    );

    state = state.copyWith(
      messages: [...state.messages, assistantMessage],
      isLoading: true,
      error: null,
    );

    _startResponseMetricsTimer(interactionGeneration);

    _onSendStarted();

    await _preparePrimaryModelForPendingRouteIfNeeded();
    if (!_isCurrentInteractionGeneration(interactionGeneration)) return;

    // Use tool-aware flow when the MCP tool service is available.
    if (_mcpToolService != null &&
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
      await _sendWithoutTools(interactionGeneration: interactionGeneration);
    }
  }

  Future<void> generateWorkflowProposal({String languageCode = 'en'}) async {
    if (!ref.mounted || state.isGeneratingWorkflowProposal) return;

    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) return;

    state = state.copyWith(
      isGeneratingWorkflowProposal: true,
      workflowProposalDraft: null,
      workflowProposalError: null,
      pendingWorkflowDecision: null,
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

      state = state.copyWith(
        isGeneratingWorkflowProposal: false,
        workflowProposalDraft: proposal,
        workflowProposalError: null,
      );
    } on _WorkflowProposalCancelled {
      if (!ref.mounted) return;
      state = state.copyWith(
        isGeneratingWorkflowProposal: false,
        workflowProposalDraft: null,
        workflowProposalError: null,
        pendingWorkflowDecision: null,
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        isGeneratingWorkflowProposal: false,
        workflowProposalDraft: null,
        workflowProposalError: error.toString(),
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
      final result = await _runSecondaryCompletion(
        endpointId: _settings.goalSuggestionEndpointId,
        model: _settings.effectiveGoalSuggestionModel,
        call: (dataSource, model) => dataSource.createChatCompletion(
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

  List<ToolResultInfo> takeLatestToolResults() {
    final snapshot = List<ToolResultInfo>.unmodifiable([
      ..._latestCompletedToolResults,
      ..._latestContentToolResults,
    ]);
    _latestCompletedToolResults = const [];
    _latestContentToolResults.clear();
    return snapshot;
  }

  String? takeLatestHiddenAssistantResponse() {
    final snapshot = _latestHiddenAssistantResponse;
    _latestHiddenAssistantResponse = null;
    return snapshot;
  }

  void _recordHiddenAssistantResponse(String? response) {
    final candidate = response?.trim() ?? '';
    if (candidate.isEmpty) {
      return;
    }

    final existing = _latestHiddenAssistantResponse?.trim() ?? '';
    if (existing.isEmpty) {
      _latestHiddenAssistantResponse = candidate;
      return;
    }

    final existingScore = _hiddenAssistantEvidenceScore(existing);
    final candidateScore = _hiddenAssistantEvidenceScore(candidate);
    if (candidateScore > existingScore ||
        (candidateScore == existingScore &&
            candidate.length >= existing.length)) {
      _latestHiddenAssistantResponse = candidate;
    }
  }

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
    conversationId = currentConversation.id;
    final interactionGeneration = _beginInteractionGeneration();
    if (!await _startRuntimeTurn(
      generation: interactionGeneration,
      hidden: false,
    )) {
      return;
    }
    currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) {
      _failRuntimeTurn(
        interactionGeneration,
        code: 'conversation_unavailable',
        message: 'The selected conversation is no longer available.',
        exitCode: 65,
      );
      return;
    }
    conversationId = currentConversation.id;

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

    state = state.copyWith(
      isGeneratingTaskProposal: true,
      taskProposalDraft: null,
      taskProposalError: null,
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

      state = state.copyWith(
        isGeneratingTaskProposal: false,
        taskProposalDraft: proposal,
        taskProposalError: null,
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        isGeneratingTaskProposal: false,
        taskProposalDraft: null,
        taskProposalError: error.toString(),
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
    state = state.copyWith(
      isLoading: false,
      isGeneratingWorkflowProposal: false,
      isGeneratingTaskProposal: false,
      pendingWorkflowDecision: pending,
    );
    _emitRuntimeQuestionRequired(
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

  Map<String, dynamic>? _decodeJsonObject(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _trimStringArgument(Map<String, dynamic> arguments, String key) {
    return (arguments[key] as String?)?.trim() ?? '';
  }

  Future<void> _runPlanProposalFlow({
    required Conversation currentConversation,
    required String languageCode,
    required int interactionGeneration,
    String? additionalPlanningContext,
  }) async {
    if (!ref.mounted) return;

    state = state.copyWith(
      isLoading: true,
      error: null,
      isGeneratingWorkflowProposal: true,
      isGeneratingTaskProposal: true,
      workflowProposalDraft: null,
      taskProposalDraft: null,
      workflowProposalError: null,
      taskProposalError: null,
      pendingWorkflowDecision: null,
    );

    final researchContext = await _buildPlanningResearchContext(
      currentConversation: currentConversation,
    );

    WorkflowProposalDraft? workflowDraft;
    try {
      workflowDraft = await _requestWorkflowProposal(
        currentConversation: currentConversation,
        languageCode: languageCode,
        researchContext: researchContext,
        additionalPlanningContext: additionalPlanningContext,
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        isGeneratingWorkflowProposal: false,
        workflowProposalDraft: workflowDraft,
        workflowProposalError: null,
      );
      appLog('[Workflow] Workflow proposal ready');
      await _persistPlanArtifactDraft(
        workflowStage: workflowDraft.workflowStage,
        workflowSpec: workflowDraft.workflowSpec,
      );
      appLog('[Workflow] Workflow plan artifact draft persisted');
    } on _WorkflowProposalCancelled {
      if (!ref.mounted) return;
      state = state.copyWith(
        isLoading: false,
        isGeneratingWorkflowProposal: false,
        isGeneratingTaskProposal: false,
        workflowProposalDraft: null,
        taskProposalDraft: null,
        workflowProposalError: null,
        taskProposalError: null,
        pendingWorkflowDecision: null,
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
      state = state.copyWith(
        isLoading: false,
        isGeneratingWorkflowProposal: false,
        isGeneratingTaskProposal: false,
        workflowProposalDraft: null,
        taskProposalDraft: null,
        workflowProposalError: error.toString(),
        pendingWorkflowDecision: null,
      );
      _failRuntimeTurn(
        interactionGeneration,
        code: 'workflow_proposal_failed',
        message: error.toString(),
      );
      return;
    }

    try {
      final taskDraft = await _requestTaskProposal(
        currentConversation: currentConversation,
        languageCode: languageCode,
        researchContext: researchContext,
        workflowStageOverride: workflowDraft.workflowStage,
        workflowSpecOverride: workflowDraft.workflowSpec,
        additionalPlanningContext: additionalPlanningContext,
      );
      if (!ref.mounted) return;
      appLog('[Workflow] Task proposal ready');
      await _persistPlanArtifactDraft(
        workflowStage: workflowDraft.workflowStage,
        workflowSpec: workflowDraft.workflowSpec,
        tasks: taskDraft.tasks,
      );
      appLog('[Workflow] Task plan artifact draft persisted');
      if (!ref.mounted) return;
      state = state.copyWith(
        isLoading: false,
        isGeneratingTaskProposal: false,
        taskProposalDraft: taskDraft,
        taskProposalError: null,
      );
      _emitRuntimeWorkflowTransition(
        stage: taskDraft.tasks.isEmpty ? 'tasks' : 'implement',
        taskStatus: 'proposal_ready',
      );
      final planMarkdown = ConversationPlanDocumentBuilder.build(
        workflowStage: workflowDraft.workflowStage,
        workflowSpec: workflowDraft.workflowSpec,
        tasks: taskDraft.tasks,
      );
      _completeRuntimeTurn(interactionGeneration, content: planMarkdown);
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        isLoading: false,
        isGeneratingTaskProposal: false,
        taskProposalDraft: null,
        taskProposalError: error.toString(),
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
    List<ConversationWorkflowTask> tasks = const [],
  }) async {
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) {
      return;
    }

    final existingArtifact =
        currentConversation.planArtifact ?? const ConversationPlanArtifact();
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
        );
  }

  /// Sends a streaming request without tools.
  Future<void> _sendWithoutTools({
    bool allowContextRetry = true,
    int? interactionGeneration,
  }) async {
    if (!ref.mounted) return;
    final generation = interactionGeneration ?? _interactionGeneration;
    try {
      _runWithLlmSessionLogContextForGeneration(generation, () {
        final stream = _dataSource.streamChatCompletion(
          messages: _prepareMessagesForLLM(interactionGeneration: generation),
          model: _settings.model,
          temperature: _assistantRequestTemperature,
          maxTokens: _settings.maxTokens,
        );

        _streamSubscription = stream.listen(
          (chunk) {
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
                  ),
                ).then((retried) {
                  if (!_isCurrentInteractionGeneration(generation)) return;
                  if (!retried) {
                    _handleError(error.toString());
                  }
                }),
              );
              return;
            }
            _handleError(error.toString());
          },
          onDone: () {
            unawaited(_finishStreaming(interactionGeneration: generation));
          },
        );
      });
    } catch (e, stackTrace) {
      appLog('[ChatNotifier] _sendWithoutTools catch: ${e.runtimeType}: $e');
      appLog('[ChatNotifier] stackTrace: $stackTrace');
      if (allowContextRetry &&
          await _retryAfterContextLengthError(
            e,
            () => _sendWithoutTools(
              allowContextRetry: false,
              interactionGeneration: generation,
            ),
          )) {
        return;
      }
      if (!_isCurrentInteractionGeneration(generation)) return;
      _handleError(e.toString());
    }
  }

  Future<void> _sendWithEmbeddedToolTagFallback({
    required List<Map<String, dynamic>> toolDefinitions,
    bool allowContextRetry = true,
    required int interactionGeneration,
  }) async {
    if (!ref.mounted) return;
    _resetStreamingAssistantForRetry();
    try {
      _runWithLlmSessionLogContextForGeneration(interactionGeneration, () {
        final messages = _prepareMessagesForLLM(
          toolDefinitionsOverride: toolDefinitions,
          interactionGeneration: interactionGeneration,
        );
        messages.add(_embeddedToolTagFallbackInstructionMessage());

        final stream = _dataSource.streamChatCompletion(
          messages: messages,
          model: _settings.model,
          temperature: _agenticRequestTemperature,
          maxTokens: _settings.maxTokens,
        );

        _streamSubscription = stream.listen(
          (chunk) {
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
                ).then((retried) {
                  if (!_isCurrentInteractionGeneration(interactionGeneration)) {
                    return;
                  }
                  if (!retried) {
                    _handleError(error.toString());
                  }
                }),
              );
              return;
            }
            _handleError(error.toString());
          },
          onDone: () {
            unawaited(
              _finishStreaming(interactionGeneration: interactionGeneration),
            );
          },
          cancelOnError: true,
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
          )) {
        return;
      }
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      _handleError(error.toString());
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
    Future<void> Function() retry,
  ) async {
    if (!ConversationCompactionService.isContextLengthError(error.toString())) {
      return false;
    }

    final messages = state.messages
        .where((message) => !message.isStreaming)
        .toList(growable: false);
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    final artifact = ConversationCompactionService.buildArtifact(
      messages: messages,
      planDocument: currentConversation?.displayPlanDocument(
        isPlanning: currentConversation.isPlanningSession,
      ),
      now: DateTime.now(),
      force: true,
    );
    if (artifact == null || !artifact.hasContent) {
      appLog(
        '[Compaction] Context-length retry skipped because no compactable history is available',
      );
      return false;
    }

    appLog(
      '[Compaction] Retrying after context-length error with ${artifact.compactedMessageCount} compacted message(s)',
    );
    _forcePromptCompactionForNextRequest = true;
    _resetStreamingAssistantForRetry();
    await retry();
    return true;
  }

  void _resetStreamingAssistantForRetry() {
    if (!ref.mounted || state.messages.isEmpty) return;
    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];
    if (lastMessage.role != MessageRole.assistant || !lastMessage.isStreaming) {
      return;
    }
    updatedMessages[lastIndex] = lastMessage.copyWith(content: '', error: null);
    state = state.copyWith(messages: updatedMessages, error: null);
  }

  bool _hasCompactablePromptHistory() {
    final messages = state.messages
        .where((message) => !message.isStreaming)
        .toList(growable: false);
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    final artifact = ConversationCompactionService.buildArtifact(
      messages: messages,
      planDocument: currentConversation?.displayPlanDocument(
        isPlanning: currentConversation.isPlanningSession,
      ),
      now: DateTime.now(),
      force: true,
    );
    return artifact?.hasContent ?? false;
  }

  Future<ChatCompletionResult> _createToolResultCompletionWithContextRetry({
    required String logLabel,
    required int interactionGeneration,
    required List<Message> Function(bool forceCompaction) buildMessages,
    required List<ToolResultInfo> toolResults,
    required String? assistantContent,
    required List<Map<String, dynamic>> tools,
  }) async {
    Future<ChatCompletionResult> send({
      required bool forceCompaction,
      required ToolResultPromptBudgetMode budgetMode,
    }) {
      return _runWithLlmSessionLogContextForGeneration(
        interactionGeneration,
        () => _dataSource.createChatCompletionWithToolResults(
          messages: buildMessages(forceCompaction),
          toolResults: _budgetToolResultsForPrompt(
            toolResults,
            mode: budgetMode,
          ),
          assistantContent: assistantContent,
          tools: tools,
          model: _settings.model,
          temperature: _agenticRequestTemperature,
          maxTokens: _settings.maxTokens,
        ),
      );
    }

    try {
      return await send(
        forceCompaction: false,
        budgetMode: ToolResultPromptBudgetMode.normal,
      );
    } catch (error) {
      final hasCompactableHistory = _hasCompactablePromptHistory();
      final hasToolResultBudget = _hasAdditionalCompactToolResultBudget(
        toolResults,
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
    var nativeToolFallbackDefinitions = const <Map<String, dynamic>>[];
    if (!_supportsToolAwareRequests) {
      appLog(
        '[Tool] Tool-aware requests are unavailable for the selected provider; '
        'falling back to normal mode',
      );
      await _sendWithoutTools(
        allowContextRetry: allowContextRetry,
        interactionGeneration: generation,
      );
      return;
    }
    _mcpToolService?.beginFileTurnCheckpoint('chat_generation_$generation');
    try {
      final allTools = _toolDefinitionsAllowedBy(allowedToolNames);
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
      final streamedMessageIndex = state.messages.isEmpty
          ? -1
          : state.messages.length - 1;
      final streamedContentStart = streamedMessageIndex >= 0
          ? state.messages[streamedMessageIndex].content.length
          : 0;

      // Stream the initial request to show thinking/content in real-time
      // while also detecting tool calls.
      final streamResult = _runWithLlmSessionLogContextForGeneration(
        generation,
        () => _dataSource.streamChatCompletionWithTools(
          messages: _prepareMessagesForLLM(
            toolDefinitionsOverride: initialToolSelection.toolDefinitions,
            interactionGeneration: generation,
          ),
          tools: initialToolSelection.toolDefinitions,
          model: _settings.model,
          temperature: _agenticRequestTemperature,
          maxTokens: _settings.maxTokens,
        ),
      );

      // Display streamed content (thinking, preamble) in real-time.
      await for (final chunk in streamResult.stream) {
        if (!_isCurrentInteractionGeneration(generation)) return;
        if (!ref.mounted) return;
        _appendToLastMessageForGeneration(generation, chunk);
      }

      // Retrieve the accumulated tool calls after the stream ends.
      final result = await streamResult.completion;

      if (!_isCurrentInteractionGeneration(generation)) return;
      if (!ref.mounted) return;
      appLog(
        '[Tool] LLM response - finishReason: ${result.finishReason}, hasToolCalls: ${result.hasToolCalls}',
      );
      appLog(
        '[Tool] toolCalls: ${result.toolCalls?.map((t) => t.name).toList()}',
      );

      // Execute tool calls when the model requests them.
      if (result.hasToolCalls) {
        _lengthTruncatedToolCallIds = _truncationCasualtyToolCallIds(result);
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
              ..._browserToolNamesFromDefinitions(allTools),
            },
            stableToolDefinitions: stableLoopToolDefinitions,
            interactionGeneration: generation,
            replayVerifierImmediatelyAfterMutation:
                replayVerifierImmediatelyAfterMutation,
            verifierOnlyContinuation: verifierOnlyContinuation,
          );
          return;
        }
        // No tool calls — content was already streamed in real-time.
        appLog('[Tool] No tool calls, response already streamed');
        final hiddenAssistantEvidence = streamedAssistantContent.isNotEmpty
            ? streamedAssistantContent
            : result.content;
        var hiddenAssistantEvidenceRecorded = false;
        void recordHiddenAssistantEvidenceOnce() {
          if (hiddenAssistantEvidenceRecorded) {
            return;
          }
          _recordHiddenAssistantResponse(hiddenAssistantEvidence);
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
          _recordHiddenAssistantResponse(
            codingContinuationRecoveryResult.content,
          );
        }
        recordHiddenAssistantEvidenceOnce();
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
        final unexecutedCommandAction = _buildUnexecutedCommandActionToolResult(
          candidateResponse: hiddenAssistantEvidence,
          toolResults: const [],
          interactionGeneration: generation,
        );
        if (unexecutedCommandAction != null) {
          _latestCompletedToolResults = [unexecutedCommandAction];
          _latestGoalAutoContinueEvidence =
              ToolResultPromptBuilder.completionEvidence(
                _latestCompletedToolResults,
              ).carryForwardIncompleteFrom(_latestGoalAutoContinueEvidence);
          _appendUnexecutedCommandActionNoticeIfNeeded(
            toolResults: [unexecutedCommandAction],
            interactionGeneration: generation,
          );
        } else {
          final unverifiedInspectionClaim =
              _buildUnverifiedReadOnlyInspectionClaimToolResult(
                candidateResponse: hiddenAssistantEvidence,
                toolResults: const [],
              );
          if (unverifiedInspectionClaim != null) {
            _latestCompletedToolResults = [unverifiedInspectionClaim];
            _appendUnverifiedReadOnlyInspectionClaimNoticeIfNeeded(
              toolResults: [unverifiedInspectionClaim],
              interactionGeneration: generation,
            );
          }
        }
        await _finishStreaming(interactionGeneration: generation);
      }
    } catch (e) {
      // Fall back when the LLM likely does not support tools.
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
          )) {
        return;
      }

      if (!_isCurrentInteractionGeneration(generation)) return;

      if (_shouldFallbackFoundationModelsToolBridgeAfterContextError(e)) {
        appLog(
          '[Tool] Foundation Models tool bridge exceeded the context window; '
          'falling back to normal mode',
        );
        _resetStreamingAssistantForRetry();
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

      // Fall back to normal mode for tool-related failures.
      // Examples include JSON parse errors, empty responses, or invalid payloads.
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
      _handleError(e.toString());
    } finally {
      _mcpToolService?.endFileTurnCheckpoint();
    }
  }

  bool _shouldFallbackFoundationModelsToolBridgeAfterContextError(
    Object error,
  ) {
    return _settings.llmProvider == LlmProvider.appleFoundationModels &&
        ConversationCompactionService.isContextLengthError(error.toString());
  }

  bool get _supportsToolAwareRequests => true;

  List<ToolResultInfo> _budgetToolResultsForPrompt(
    List<ToolResultInfo> toolResults, {
    ToolResultPromptBudgetMode mode = ToolResultPromptBudgetMode.normal,
  }) {
    final budgetedToolResults = ToolResultPromptBuilder.budgetToolResults(
      toolResults,
      mode: mode,
      protectedPaths: mode == ToolResultPromptBudgetMode.compact
          ? _contextSurgeryProtectedPaths()
          : const <String>{},
    );
    _updateContextSurgeryObservation(toolResults: budgetedToolResults);
    return budgetedToolResults;
  }

  bool _hasAdditionalCompactToolResultBudget(List<ToolResultInfo> toolResults) {
    return ToolResultPromptBuilder.hasAdditionalCompactBudgetReduction(
      toolResults,
      protectedPaths: _contextSurgeryProtectedPaths(),
    );
  }

  Future<ToolResultInfo?> _buildCodingDiagnosticFeedbackToolResult(
    List<ToolResultInfo> toolResults, {
    required int interactionGeneration,
    CodingDiagnosticFeedbackBaseline? baseline,
  }) async {
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return null;
    }
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation?.workspaceMode != WorkspaceMode.coding ||
        (currentConversation?.isPlanningSession ?? false)) {
      return null;
    }
    final projectRoot = _getActiveProjectRootPath();
    if (projectRoot == null || projectRoot.isEmpty) {
      return null;
    }

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

  /// Run one authoritative analyzer pass over every changed file just before
  /// composing the final answer.
  ///
  /// The per-batch [_buildCodingDiagnosticFeedbackToolResult] reports only
  /// diagnostics that are new relative to that batch's pre-edit baseline, so an
  /// error that survives a later successful-but-incorrect edit is silenced
  /// (it is also present in the baseline) and the only analyzer feedback left
  /// in the results is the stale pre-fix one. Re-running with no baseline
  /// reports the absolute current state, so the final answer sees the real
  /// post-edit analyzer result instead of a stale or missing one.
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
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation?.workspaceMode != WorkspaceMode.coding ||
        (currentConversation?.isPlanningSession ?? false)) {
      return null;
    }
    final projectRoot = _getActiveProjectRootPath();
    if (projectRoot == null || projectRoot.isEmpty) {
      return null;
    }

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
    final decoded = _tryDecodeMap(feedback.result);
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
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation?.workspaceMode != WorkspaceMode.coding ||
        (currentConversation?.isPlanningSession ?? false)) {
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
    final decoded = _tryDecodeMap(feedback.result);
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
    final feedback = await _buildBackgroundProcessMonitorFeedbackToolResult(
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
      candidateResponse: candidateResponse,
      toolResults: toolResults,
    );
    if (processFeedback != null) {
      return processFeedback;
    }
    return _buildSubagentMonitorFeedbackToolResult(
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
                'result_excerpt': _clipForDiagnostic(result.result),
              },
            )
            .toList(growable: false),
        'claimedResponse': _clipForDiagnostic(candidateResponse),
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
      if (!_toolResultHasSuccessfulExit(result)) {
        continue;
      }
      final decoded = _tryDecodeMap(result.result);
      final jobId = decoded?['job_id']?.toString().trim();
      if (jobId != null && jobId.isNotEmpty) {
        successfulJobIds.add(jobId);
      }
    }
    return relevantJobIds.every(successfulJobIds.contains);
  }

  bool _toolResultContainsReleaseFailureMarker(ToolResultInfo result) {
    if (!_isCommandExecutionTool(result.name)) {
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
    required String candidateResponse,
    required List<ToolResultInfo> toolResults,
  }) async {
    final jobIds = _backgroundProcessJobIdsFromResults(toolResults);
    if (jobIds.isEmpty) {
      return null;
    }
    final snapshots = await _backgroundProcessMonitorService.refreshJobs(
      jobIds,
    );
    final blockingSnapshots = snapshots
        .where((snapshot) {
          return snapshot.isRunning ||
              snapshot.hasFailedExit ||
              !snapshot.ok ||
              snapshot.status == 'unknown';
        })
        .toList(growable: false);
    if (blockingSnapshots.isEmpty) {
      return null;
    }
    final running = blockingSnapshots
        .where((snapshot) => snapshot.isRunning)
        .toList(growable: false);
    final failed = blockingSnapshots
        .where((snapshot) => snapshot.hasFailedExit)
        .toList(growable: false);
    final code = running.isNotEmpty
        ? 'background_process_still_running'
        : failed.isNotEmpty
        ? 'background_process_failed'
        : 'background_process_status_unverified';
    final error = running.isNotEmpty
        ? 'A background process is still running, so the completion claim is not verified yet.'
        : failed.isNotEmpty
        ? 'A background process exited with a non-zero status, so the completion claim is not verified.'
        : 'A background process status could not be verified, so the completion claim is not verified.';

    return ToolResultInfo(
      id: 'background_process_monitor_${DateTime.now().microsecondsSinceEpoch}',
      name: 'background_process_monitor',
      arguments: {'job_ids': jobIds},
      result: jsonEncode({
        'ok': false,
        'code': code,
        'error': error,
        'jobs': blockingSnapshots
            .map((snapshot) => snapshot.toJson())
            .toList(growable: false),
        'claimedResponse': _clipForDiagnostic(candidateResponse),
        'required_action':
            'Use process_list(refresh: true, include_finished: false) to refresh running background jobs, then use process_status, process_tail, or process_wait for the specific job. Inspect stdout_tail, stderr_tail, elapsed_ms, and status to report concise progress before continuing to monitor. Do not just wait silently, and do not claim completion until the relevant process has exited successfully.',
        'progress_report_required': true,
        'progress_report_fields': const [
          'status',
          'elapsed_ms',
          'stdout_tail',
          'stderr_tail',
        ],
      }),
    );
  }

  ToolCallInfo? _buildBackgroundProcessFollowUpToolCall(
    List<ToolResultInfo> toolResults, {
    required int waitMs,
  }) {
    final latestStatusesByJobId = <String, String>{};
    for (final result in toolResults.reversed) {
      final name = result.name.trim().toLowerCase();
      final decoded = _tryDecodeMap(result.result);
      if (decoded == null) {
        continue;
      }
      if (name == 'background_process_monitor' &&
          decoded['code'] == 'background_process_still_running') {
        final jobs = decoded['jobs'];
        if (jobs is! List) {
          continue;
        }
        for (final job in jobs) {
          if (job is! Map) {
            continue;
          }
          final jobId = job['job_id']?.toString().trim();
          if (jobId == null || jobId.isEmpty) {
            continue;
          }
          latestStatusesByJobId.putIfAbsent(
            jobId,
            () => job['status']?.toString().trim().toLowerCase() ?? '',
          );
        }
        continue;
      }
      if (name == 'process_start' ||
          name == 'process_status' ||
          name == 'process_wait' ||
          name == 'local_execute_command') {
        final jobId = decoded['job_id']?.toString().trim();
        if (jobId == null || jobId.isEmpty) {
          continue;
        }
        latestStatusesByJobId.putIfAbsent(
          jobId,
          () => decoded['status']?.toString().trim().toLowerCase() ?? '',
        );
      }
    }
    for (final entry in latestStatusesByJobId.entries) {
      if (entry.value != 'running') {
        continue;
      }
      return ToolCallInfo(
        id: 'background_process_monitor_followup_${DateTime.now().microsecondsSinceEpoch}',
        name: 'process_wait',
        arguments: {'job_id': entry.key, 'wait_ms': waitMs},
      );
    }
    return null;
  }

  int _backgroundProcessMonitorFollowUpWaitMs(int iteration) {
    return (5000 + iteration * 1000).clamp(5000, 15000).toInt();
  }

  ToolResultInfo? _buildSubagentMonitorFeedbackToolResult({
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
      final decoded = _tryDecodeMap(result.result);
      final taskId = decoded?['task_id']?.toString().trim();
      if (taskId == null || taskId.isEmpty) {
        continue;
      }
      if (runningTaskIds.contains(taskId) || failedTaskIds.contains(taskId)) {
        continue;
      }

      final rawStatus = decoded?['status']?.toString().toLowerCase() ?? '';
      final task = notifier.byId(taskId);
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
        'claimedResponse': _clipForDiagnostic(candidateResponse),
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
      final decoded = _tryDecodeMap(result.result);
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
    if (_containsAnyCodeUnitSequence(candidate, const [
      [0x5931, 0x6557],
      [0x30a8, 0x30e9, 0x30fc],
      [0x7570, 0x5e38, 0x7d42, 0x4e86],
    ])) {
      return false;
    }
    return _hiddenAssistantEvidenceScore(candidate) >= 2 ||
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
        _containsAnyCodeUnitSequence(candidate, const [
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
      if (!_isFileMutationToolName(toolCall.name)) {
        continue;
      }
      final path = _toolPathFromArguments(toolCall.arguments);
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
      if (!_isFileMutationToolName(toolResult.name)) {
        continue;
      }
      if (!_isSuccessfulFileMutationToolResult(toolResult)) {
        continue;
      }
      final path =
          _toolResultPayloadPath(toolResult.result) ??
          _toolPathFromArguments(toolResult.arguments);
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

  bool _isFileMutationToolName(String toolName) {
    switch (toolName.trim().toLowerCase()) {
      case 'write_file':
      case 'edit_file' || 'delete_file':
      case 'rollback_last_file_change':
        return true;
    }
    return false;
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
        final payload = _tryDecodeMap(result.result);
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

  bool _isSuccessfulFileMutationToolResult(ToolResultInfo toolResult) {
    final normalized = toolResult.result.trim().toLowerCase();
    if (normalized.isEmpty ||
        normalized.startsWith('error:') ||
        normalized.startsWith('auto-review denied')) {
      return false;
    }
    try {
      final decoded = jsonDecode(toolResult.result);
      if (decoded is! Map<String, dynamic>) {
        return true;
      }
      if (decoded['error'] != null) {
        return false;
      }
      if (decoded['already_applied'] == true) {
        return false;
      }
      final code = decoded['code']?.toString().trim().toLowerCase();
      if (code == 'permission_denied' ||
          code == 'bookmark_restore_failed' ||
          code == 'tool_execution_failed') {
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  String? _toolResultPayloadPath(String result) {
    try {
      final decoded = jsonDecode(result);
      if (decoded is Map<String, dynamic>) {
        final path = decoded['path'];
        if (path is String && path.trim().isNotEmpty) {
          return path.trim();
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  List<Message> _buildToolResultAnswerMessages(
    List<ToolResultInfo> toolResults, {
    ToolResultPromptBudgetMode budgetMode = ToolResultPromptBudgetMode.normal,
    ToolResultCompletionEvidence? completionEvidence,
  }) {
    final budgetedToolResults = _budgetToolResultsForPrompt(
      toolResults,
      mode: budgetMode,
    );
    final timestamp = DateTime.now();
    final messages = <Message>[
      Message(
        id: 'tool_result_${timestamp.microsecondsSinceEpoch}',
        content: ToolResultPromptBuilder.buildAnswerPrompt(
          budgetedToolResults,
          descriptionsByName: _toolDescriptionsByName(),
          completionEvidence: completionEvidence,
        ),
        role: MessageRole.user,
        timestamp: timestamp,
      ),
    ];

    for (var i = 0; i < budgetedToolResults.length; i++) {
      final toolResult = budgetedToolResults[i];
      final decoded = _tryDecodeMap(toolResult.result);
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

  Map<String, String> _toolDescriptionsByName() {
    return ToolResultPromptBuilder.descriptionsByNameFromDefinitions(
      _mcpToolService?.getOpenAiToolDefinitions() ?? const [],
    );
  }

  void _logScheduledToolLifecycleEvent(
    ToolExecutionLifecycleEvent event, {
    required int loopIndex,
  }) {
    _emitRuntimeToolLifecycle(
      generation: _interactionGeneration,
      toolCallId: event.toolCall.id,
      toolName: event.toolCall.name,
      state: _runtimeToolLifecycleState(event.state),
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
    _emitRuntimeToolLifecycle(
      generation: _interactionGeneration,
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
    var currentToolCalls = toolCalls;
    var currentAssistantContent = assistantContent;
    var maxIterations =
        _settings.effectiveModelHarnessConfig?.resolveToolLoopMaxIterations(
          12,
        ) ??
        12;
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
    _turnExitReasonHint = null;
    _finalAnswerFinishReasonOverride = null;
    _appliedTurnTransforms.clear();
    final executedToolResults = <ToolResultInfo>[];
    var commandRetryGeneration = 0;
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

    List<Map<String, dynamic>> selectedDefinitionsFor(
      McpToolService mcpToolService,
    ) {
      final stableDefinitions = stableToolDefinitions;
      if (stableDefinitions != null) {
        return stableDefinitions;
      }
      return ToolDefinitionSearchService.definitionsForSelectedTools(
        mcpToolService.getOpenAiToolDefinitions(),
        selectedToolNames: activeToolNames,
        toolSearchEnabled: toolSearchEnabled,
      );
    }

    while (currentToolCalls.isNotEmpty && iteration < maxIterations) {
      iteration++;
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      if (!ref.mounted) return;

      if (_shouldBlockToolCallsForUserConfirmation(
        currentAssistantContent: currentAssistantContent,
        toolCalls: currentToolCalls,
      )) {
        appLog(
          '[Tool] Blocking git write tool calls because the assistant asked '
          'for user confirmation',
        );
        _turnExitReasonHint = ToolLoopExitReason.userConfirmationBlock;
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
        iteration: iteration,
        interactionGeneration: interactionGeneration,
        verifierOnlyContinuation: verifierOnlyContinuation,
      );
      if (batchResult.didCancel) return;
      commandRetryGeneration = batchResult.commandRetryGeneration;
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
            interactionGeneration: interactionGeneration,
          )) {
        return;
      }
      if (batchResult.hasTextResponse) {
        hasTextResponse = true;
        break;
      }
      if (batchToolResults.isEmpty) {
        if (pendingBatchCalls.isEmpty && currentToolCalls.isNotEmpty) {
          final duplicateRecoveryToolResults =
              _buildDuplicateRecoveryToolResults(
                currentToolCalls: currentToolCalls,
                executedToolResults: executedToolResults,
                fallbackToolResults: lastNonEmptyBatchToolResults,
              );
          if (_containsOnlyPreviouslySuccessfulCurrentSavedValidationToolCalls(
            currentToolCalls,
            executedToolResults,
          )) {
            appLog(
              '[Tool] Duplicate saved validation command already succeeded',
            );
            const fallbackResponse =
                'The saved validation command already succeeded for the current saved task, so the current saved task is complete.';
            currentToolCalls = [];
            _recordHiddenAssistantResponse(fallbackResponse);
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
                  duplicateRecoveryToolResults.isNotEmpty
                      ? duplicateRecoveryToolResults
                      : executedToolResults,
                );
            if (_toolCallExecutionPolicy
                    .shouldUsePreviousOutputForDuplicateCommandCalls(
                      currentToolCalls,
                    ) &&
                previousOutput.isNotEmpty &&
                (fallbackResponse.isEmpty ||
                    _looksLikePendingToolActionResponse(fallbackResponse))) {
              currentToolCalls = [];
              _recordHiddenAssistantResponse(previousOutput);
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
              _recordHiddenAssistantResponse(fallbackResponse);
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
              duplicateRecoveryToolResults.isNotEmpty) {
            attemptedDuplicateInspectionRecovery = true;
            appLog(
              '[Tool] Duplicate read-only follow-up tool calls detected, requesting bounded recovery',
            );
            _appendToLastMessageForGeneration(interactionGeneration, '<think>');
            final mcpToolService = _mcpToolService;
            if (mcpToolService == null) {
              _latestCompletedToolResults = List<ToolResultInfo>.unmodifiable(
                executedToolResults,
              );
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
                  role: MessageRole.user,
                  content: _buildDuplicateInspectionRecoveryPrompt(
                    currentToolCalls,
                    previousToolResults: duplicateRecoveryToolResults,
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
                  toolResults: duplicateRecoveryToolResults,
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
              _recordHiddenAssistantResponse(recoveryResult.content);
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
            _recordHiddenAssistantResponse(fallbackResponse);
            if (_shouldAcceptRecoveryFinalTextResponse(fallbackResponse)) {
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
              duplicateRecoveryToolResults.isNotEmpty) {
            attemptedDuplicateFollowUpRecovery = true;
            appLog(
              '[Tool] Duplicate follow-up tool calls detected, requesting bounded recovery',
            );
            _appendToLastMessageForGeneration(interactionGeneration, '<think>');
            final mcpToolService = _mcpToolService;
            if (mcpToolService == null) {
              _latestCompletedToolResults = List<ToolResultInfo>.unmodifiable(
                executedToolResults,
              );
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
                  role: MessageRole.user,
                  content: _buildDuplicateFollowUpRecoveryPrompt(
                    currentToolCalls,
                    previousToolResults: duplicateRecoveryToolResults,
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
                  toolResults: duplicateRecoveryToolResults,
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
              _recordHiddenAssistantResponse(recoveryResult.content);
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
            _recordHiddenAssistantResponse(fallbackResponse);
            if (_shouldAcceptRecoveryFinalTextResponse(fallbackResponse)) {
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

      // Show a thinking indicator while waiting for the follow-up request.
      _appendToLastMessageForGeneration(interactionGeneration, '<think>');

      // Send the tool results back to the LLM and check for follow-up calls.
      // Use a non-streaming request with tool definitions included.
      final mcpToolService = _mcpToolService;
      if (mcpToolService == null) {
        _latestCompletedToolResults = List<ToolResultInfo>.unmodifiable(
          executedToolResults,
        );
        await _sendWithoutTools(interactionGeneration: interactionGeneration);
        return;
      }
      final tools = selectedDefinitionsFor(mcpToolService);
      final followUpToolResults = _toolResultsForFollowUpRequest(
        batchToolResults: batchToolResults,
        executedToolResults: executedToolResults,
      );
      final savedValidationSucceeded =
          _toolResultsContainSuccessfulCurrentSavedValidation(batchToolResults);
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
      // Remind the model what read-only context it already gathered so it does
      // not re-list directories / re-read files across the loop (and after a
      // recovery re-entry that resets the per-call dedup set).
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

      // Remove the temporary thinking indicator.
      _removeTrailingThinkTagForGeneration(interactionGeneration);

      _lengthTruncatedToolCallIds = _truncationCasualtyToolCallIds(nextResult);

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
        appLog('[Tool] Current git lifecycle goal already succeeded');
      }

      // Continue looping if the LLM asks for another tool call.
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
            _recordHiddenAssistantResponse(completionResponse);
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
              _shouldAcceptRecoveryFinalTextResponse(fallbackResponse)
              ? fallbackResponse
              : _buildGitLifecycleCompletionResponse(executedToolResults);
          _recordHiddenAssistantResponse(completionResponse);
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
          _recordHiddenAssistantResponse(fallbackResponse);
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
          final normalizedSkillResponse =
              _normalizeTerminalSkillToolRoleResponse(
                fallbackResponse,
                batchToolResults,
              );
          _recordHiddenAssistantResponse(normalizedSkillResponse);
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
            _hasSuccessfulLoadSkillResult(batchToolResults) &&
                _looksLikeSkillContinuationWorkIntent(fallbackResponse)
            ? _normalizeTerminalSkillToolRoleResponse(
                fallbackResponse,
                batchToolResults,
              )
            : nextResult.content;
        _appendAssistantToolPreambleIfPresent(
          assistantPreambleContent,
          interactionGeneration: interactionGeneration,
        );
        currentToolCalls = nextToolCalls;
        _recordHiddenAssistantResponse(nextResult.content);
        currentAssistantContent = nextResult.content.isNotEmpty
            ? nextResult.content
            : currentAssistantContent;
        // Preserve declared file mutations for the final pending batch instead
        // of replacing them by replaying stale results to a recovery request.
        if (iteration >= maxIterations &&
            !attemptedToolLoopExhaustionRecovery &&
            !currentToolCalls.any(
              (toolCall) => _isFileMutationToolName(toolCall.name),
            ) &&
            _shouldRequestToolLoopExhaustionRecovery(
              pendingToolCalls: currentToolCalls,
              currentToolResults: batchToolResults,
            )) {
          attemptedToolLoopExhaustionRecovery = true;
          appLog(
            '[Tool] Tool loop exhausted with pending tool calls, requesting bounded recovery',
          );
          _appendToLastMessageForGeneration(interactionGeneration, '<think>');
          final mcpToolService = _mcpToolService;
          if (mcpToolService == null) {
            _latestCompletedToolResults = List<ToolResultInfo>.unmodifiable(
              executedToolResults,
            );
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
            _recordHiddenAssistantResponse(recoveryResult.content);
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
            _recordHiddenAssistantResponse(fallbackResponse);
            if (_shouldAcceptRecoveryFinalTextResponse(fallbackResponse)) {
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
        _recordHiddenAssistantResponse(fallbackResponse);
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
            _recordHiddenAssistantResponse(browserActionRepairResult.content);
            currentAssistantContent =
                browserActionRepairResult.content.isNotEmpty
                ? browserActionRepairResult.content
                : fallbackResponse;
            continue;
          }

          final unexecutedBrowserAction =
              _buildUnexecutedSkippedBrowserActionToolResult(
                candidateResponse: browserActionRepairResult.content.isNotEmpty
                    ? browserActionRepairResult.content
                    : fallbackResponse,
                batchToolResults: batchToolResults,
                interactionGeneration: interactionGeneration,
              );
          if (unexecutedBrowserAction != null) {
            executedToolResults.add(unexecutedBrowserAction);
            _recordHiddenAssistantResponse(browserActionRepairResult.content);
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
              _recordHiddenAssistantResponse(
                pythonAttachmentPathRepairResult.content,
              );
              currentAssistantContent =
                  pythonAttachmentPathRepairResult.content.isNotEmpty
                  ? pythonAttachmentPathRepairResult.content
                  : fallbackResponse;
              continue;
            }
            _recordHiddenAssistantResponse(
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
              _recordHiddenAssistantResponse(
                pythonAttachmentRepairResult.content,
              );
              currentAssistantContent =
                  pythonAttachmentRepairResult.content.isNotEmpty
                  ? pythonAttachmentRepairResult.content
                  : fallbackResponse;
              continue;
            }
            _recordHiddenAssistantResponse(
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
            _recordHiddenAssistantResponse(
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
          _recordHiddenAssistantResponse(monitorResponse);
          final monitorFollowUp = _buildBackgroundProcessFollowUpToolCall(
            executedToolResults,
            waitMs: _backgroundProcessMonitorFollowUpWaitMs(iteration),
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
        final runningProcessFollowUp = _buildBackgroundProcessFollowUpToolCall(
          executedToolResults,
          waitMs: _backgroundProcessMonitorFollowUpWaitMs(iteration),
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
            _recordHiddenAssistantResponse(verificationRepairResult.content);
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
          _recordHiddenAssistantResponse(verificationResponse);
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
              _recordHiddenAssistantResponse(
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
            _recordHiddenAssistantResponse(
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
        if (_shouldAcceptTerminalToolRoleFinalTextResponse(fallbackResponse)) {
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
          final normalizedBrowserSaveResponse =
              _normalizeTerminalBrowserSaveDataResponse(fallbackResponse);
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
            _hasSuccessfulLoadSkillResult(batchToolResults)
            ? batchToolResults
            : executedToolResults;
        if (_shouldAcceptTerminalSkillToolRoleResponse(
          fallbackResponse,
          skillTerminalToolResults,
        )) {
          appLog(
            '[Tool] Accepting terminal skill tool-role response without final answer fallback',
          );
          final normalizedSkillResponse =
              _normalizeTerminalSkillToolRoleResponse(
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
        // Responses through the tool role often claim real-time data is
        // unavailable, so resend the results later as a user message.
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
        _turnExitReasonHint ??= ToolLoopExitReason.pendingBatchExecuted;
      }
    }

    final unexecutedPendingToolResults = _buildUnexecutedPendingToolResults(
      toolCalls: currentToolCalls,
      executedToolCallKeys: executedToolCallKeys,
      commandRetryGeneration: commandRetryGeneration,
    );
    final unexecutedFileSideEffect = _buildUnexecutedFileSideEffectToolResult(
      candidateResponse: currentAssistantContent ?? '',
      toolResults: [...executedToolResults, ...unexecutedPendingToolResults],
      interactionGeneration: interactionGeneration,
    );
    // Re-run the analyzer once over every changed file so the final answer
    // sees the true post-edit diagnostic state, not a stale pre-fix result.
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
    finalCompletionEvidence = _settleFinalEvidenceForSuccessfulSavedValidation(
      finalCompletionEvidence,
      savedValidationSucceeded: savedValidationSucceededInLoop,
    );
    var finalCompletionEvidenceIsCurrent = true;

    // If tool results exist and no text response has been shown yet,
    // resend them as a user message and stream the final answer.
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
      final canPreparePendingActionRecovery = _pendingActionLengthRecoveryPolicy
          .canPrepareActionOnlyRecovery(
            isCodingWorkspace: _isCodingWorkspaceOrMode(),
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

      final shouldRequestPendingActionRecovery =
          _pendingActionLengthRecoveryPolicy.shouldRequestActionOnlyRecovery(
            finishReason: _latestFinishReason(),
            isCodingWorkspace: _isCodingWorkspaceOrMode(),
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
        _appliedTurnTransforms.add('pending_action_length_recovery');
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
          forcedRecoveryPrompt: _pendingActionLengthRecoveryPolicy
              .buildRetryPrompt(finalCompletionEvidence),
        );
        if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
        if (!ref.mounted) return;
        if (recoveryResult?.hasToolCalls == true) {
          appLog(
            '[PendingActionLengthRecovery] Tool-aware retry requested one or '
            'more tool calls',
          );
          _recordHiddenAssistantResponse(streamedFinalAnswer);
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
          _recordHiddenAssistantResponse(streamedFinalAnswer);
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
          _recordHiddenAssistantResponse(monitorResponse);
          final monitorFollowUp = _buildBackgroundProcessFollowUpToolCall(
            executedToolResults,
            waitMs: _backgroundProcessMonitorFollowUpWaitMs(maxIterations),
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
        final unexecutedCommandAction = _buildUnexecutedCommandActionToolResult(
          candidateResponse: streamedFinalAnswer,
          toolResults: finalToolResults,
          interactionGeneration: interactionGeneration,
        );
        if (unexecutedCommandAction != null) {
          finalToolResults.add(unexecutedCommandAction);
          finalCompletionEvidenceIsCurrent = false;
          _appendUnexecutedCommandActionNoticeIfNeeded(
            toolResults: finalToolResults,
            interactionGeneration: interactionGeneration,
          );
        } else {
          final unverifiedInspectionClaim =
              _buildUnverifiedReadOnlyInspectionClaimToolResult(
                candidateResponse: streamedFinalAnswer,
                toolResults: finalToolResults,
              );
          if (unverifiedInspectionClaim != null) {
            finalToolResults.add(unverifiedInspectionClaim);
            finalCompletionEvidenceIsCurrent = false;
            _appendUnverifiedReadOnlyInspectionClaimNoticeIfNeeded(
              toolResults: finalToolResults,
              interactionGeneration: interactionGeneration,
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
      finalCompletionEvidence =
          _settleFinalEvidenceForSuccessfulSavedValidation(
            finalCompletionEvidence,
            savedValidationSucceeded: savedValidationSucceededInLoop,
          );
    }
    finalCompletionEvidence = finalCompletionEvidence
        .carryForwardIncompleteFrom(_latestGoalAutoContinueEvidence);
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
    );
    _latestGoalAutoContinueEvidence = finalCompletionEvidence;
    _latestCompletedToolResults = List<ToolResultInfo>.unmodifiable(
      finalToolResults,
    );
    await _finishStreaming(interactionGeneration: interactionGeneration);
  }

  List<ToolResultInfo> _toolResultsForFollowUpRequest({
    required List<ToolResultInfo> batchToolResults,
    required List<ToolResultInfo> executedToolResults,
  }) {
    if (batchToolResults.isEmpty) {
      return batchToolResults;
    }
    if (batchToolResults.any(
      (toolResult) => toolResult.name == 'ask_user_question',
    )) {
      return batchToolResults;
    }
    final batchToolResultIds = batchToolResults
        .map((toolResult) => toolResult.id)
        .toSet();
    final stickyToolResults = executedToolResults
        .where((toolResult) {
          return toolResult.name == 'ask_user_question' &&
              !batchToolResultIds.contains(toolResult.id);
        })
        .toList(growable: false);
    if (stickyToolResults.isEmpty) {
      return batchToolResults;
    }
    return <ToolResultInfo>[...stickyToolResults, ...batchToolResults];
  }

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
      _emitRuntimeAssistantContent(generation, newContent);
      updatedMessages[lastIndex] = lastMessage.copyWith(content: newContent);
      _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
      return;
    }

    if (!ref.mounted || state.messages.isEmpty) return;

    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];

    final newContent = lastMessage.content + chunk;
    _emitRuntimeAssistantContent(generation, newContent);
    updatedMessages[lastIndex] = lastMessage.copyWith(content: newContent);

    state = state.copyWith(messages: updatedMessages);
    _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);

    // Check whether the content contains completed tool-call tags.
    if (scanForTools) {
      _checkForContentToolCalls(newContent, interactionGeneration: generation);
    }
  }

  String? _lastMessageContentForGeneration(int generation) {
    if (_isActiveResponseDetachedForGeneration(generation)) {
      final activeMessages = _activeResponseMessagesForGeneration(generation);
      if (activeMessages == null || activeMessages.isEmpty) return null;
      return activeMessages.last.content;
    }

    if (!ref.mounted || state.messages.isEmpty) return null;
    return state.messages.last.content;
  }

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
    _markToolCallSeenForContentDedup(toolCall.name, toolCall.arguments);
    final payload = <String, dynamic>{
      'name': toolCall.name,
      'arguments': toolCall.arguments,
    };
    _appendToLastMessageForGeneration(
      interactionGeneration ?? _interactionGeneration,
      '<tool_use>${jsonEncode(payload)}</tool_use>\n',
      scanForTools: false,
    );
  }

  void _appendAssistantToolPreambleIfPresent(
    String content, {
    required int interactionGeneration,
  }) {
    final visibleContent = ContentParser.stripToolArtifacts(content).trim();
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

  /// Tool executions that are still pending.
  final List<Future<void>> _pendingToolExecutions = [];

  /// Detects and runs `tool_call` tags embedded in the content.
  void _checkForContentToolCalls(String content, {int? interactionGeneration}) {
    final toolCalls = ContentParser.extractCompletedToolCalls(content);
    final freshToolCalls = <ToolCallData>[];
    final repeatedToolCalls = <ToolCallData>[];
    for (final toolCall in toolCalls) {
      if (_seenContentToolCallHashes.add(_contentToolCallHash(toolCall))) {
        freshToolCalls.add(toolCall);
      } else {
        repeatedToolCalls.add(toolCall);
      }
    }

    _handleRepeatedContentToolCalls(
      repeatedToolCalls,
      interactionGeneration: interactionGeneration ?? _interactionGeneration,
    );

    _queueContentToolCalls(
      freshToolCalls,
      interactionGeneration: interactionGeneration ?? _interactionGeneration,
    );
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
      final previousResult = _latestSuccessfulContentToolResultFor(toolCall);
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

  ToolResultInfo? _latestSuccessfulContentToolResultFor(ToolCallData toolCall) {
    final toolCallKey = _contentToolCallHash(toolCall);
    for (final result in _latestContentToolResults.reversed) {
      if (_toolResultDedupKey(result) == toolCallKey &&
          !_toolResultLooksFailed(result.result)) {
        return result;
      }
    }
    return null;
  }

  bool _toolResultLooksFailed(String result) {
    final normalized = result.toLowerCase();
    if (normalized.contains('"error"') && normalized.contains('"code"')) {
      return true;
    }
    try {
      final decoded = jsonDecode(result);
      if (decoded is Map) {
        return decoded.containsKey('error');
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  String _buildRepeatedContentToolCallFallback(ToolResultInfo previousResult) {
    return 'The ${previousResult.name} tool already ran with the same arguments. '
        'I will use the previous tool result instead of repeating the call.';
  }

  void _queueContentToolCalls(
    List<ToolCallData> freshToolCalls, {
    required int interactionGeneration,
  }) {
    if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
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
      final hash = '${tc.name}:${jsonEncode(tc.arguments)}';
      if (!_executedContentToolCalls.contains(hash)) {
        appLog('[ContentTool] Starting execution: $hash');
        _executedContentToolCalls.add(hash);
        final future = _enqueueContentToolCall(tc, interactionGeneration);
        _pendingToolExecutions.add(future);
      } else {
        appLog('[ContentTool] Already executed: $hash');
      }
    }
  }

  Future<void> _enqueueContentToolCall(
    ToolCallData tc,
    int interactionGeneration,
  ) {
    final future = _contentToolExecutionTail.then((_) {
      if (!_isCurrentInteractionGeneration(interactionGeneration)) {
        return Future<void>.value();
      }
      return _executeContentToolCall(tc, interactionGeneration);
    });
    _contentToolExecutionTail = future.catchError((_) {});
    return future;
  }

  String _contentToolCallHash(ToolCallData toolCall) {
    return _toolCallDedupKey(toolCall.name, toolCall.arguments);
  }

  String _toolExecutionKey(
    ToolCallInfo toolCall, {
    int commandRetryGeneration = 0,
  }) {
    return _toolCallExecutionPolicy.toolExecutionKey(
      toolCall,
      commandRetryGeneration: commandRetryGeneration,
      resolveProjectPath: _normalizeToolPathForDedup,
    );
  }

  String _toolFailureKey(
    ToolCallInfo toolCall, {
    int commandRetryGeneration = 0,
  }) {
    return _toolCallExecutionPolicy.toolFailureKey(
      toolCall,
      commandRetryGeneration: commandRetryGeneration,
      resolveProjectPath: _normalizeToolPathForDedup,
    );
  }

  bool _shouldAllowRepeatedToolExecution(ToolCallInfo toolCall) {
    return _toolCallExecutionPolicy.shouldAllowRepeatedToolExecution(toolCall);
  }

  bool _containsOnlyReadOnlyInspectionToolCalls(List<ToolCallInfo> toolCalls) {
    return _toolLoopRecoveryPolicy.containsOnlyReadOnlyInspectionToolCalls(
      toolCalls,
      isReadOnlyInspectionToolCall: _isReadOnlyInspectionToolCall,
    );
  }

  bool _looksLikePendingToolActionResponse(String response) {
    final normalized = response.toLowerCase();
    return RegExp(
      r"\b(?:now\s+)?let me\b|\bi (?:will|need to|should|am going to)\b|\bi(?:'ll| will)\b",
    ).hasMatch(normalized);
  }

  bool _containsOnlyPreviouslySuccessfulCurrentSavedValidationToolCalls(
    List<ToolCallInfo> toolCalls,
    List<ToolResultInfo> previousToolResults,
  ) {
    if (toolCalls.isEmpty || previousToolResults.isEmpty) {
      return false;
    }
    final validationCommand = _currentSavedValidationCommandForToolLoop();
    if (validationCommand == null) {
      return false;
    }
    final normalizedValidationCommand = _normalizeToolCommandForComparison(
      validationCommand,
    );

    return toolCalls.every((toolCall) {
      if (toolCall.name == 'run_tests') {
        final testPath = _runTestsPathArgument(toolCall.arguments);
        return previousToolResults.any((result) {
          if (result.name != toolCall.name ||
              _runTestsPathArgument(result.arguments) != testPath ||
              !_toolResultHasSuccessfulExit(result)) {
            return false;
          }
          return _runTestsMatchesSavedValidation(
            arguments: result.arguments,
            normalizedValidationCommand: normalizedValidationCommand,
          );
        });
      }
      if (!_isCommandExecutionTool(toolCall.name)) {
        return false;
      }
      final command = _toolCommandArgument(toolCall.arguments);
      if (command == null) {
        return false;
      }
      final normalizedCommand = _normalizeToolCommandForComparison(command);
      return previousToolResults.any((result) {
        if (result.name != toolCall.name ||
            !_toolResultHasSuccessfulExit(result)) {
          return false;
        }
        final resultCommand = _toolCommandArgument(result.arguments);
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

  bool _toolResultCommandMatches(
    ToolResultInfo result, {
    required String normalizedCommand,
  }) {
    return _toolCallExecutionPolicy.toolResultCommandMatches(
      result,
      normalizedCommand: normalizedCommand,
    );
  }

  bool _toolResultsContainSuccessfulCurrentSavedValidation(
    List<ToolResultInfo> toolResults,
  ) {
    final validationCommand = _currentSavedValidationCommandForToolLoop();
    if (validationCommand == null) {
      return false;
    }
    final normalizedValidationCommand = _normalizeToolCommandForComparison(
      validationCommand,
    );
    return toolResults.any((result) {
      if (_readFileMatchesSavedCatValidation(
        result: result,
        validationCommand: validationCommand,
      )) {
        return true;
      }
      if (!_toolResultHasSuccessfulExit(result)) {
        return false;
      }
      if (result.name == 'run_tests') {
        return _runTestsMatchesSavedValidation(
          arguments: result.arguments,
          normalizedValidationCommand: normalizedValidationCommand,
        );
      }
      final command = _toolCommandArgument(result.arguments);
      if (command == null) {
        return false;
      }
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
  }) {
    if (result.name != 'read_file') {
      return false;
    }
    final validationArgs = GitTools.splitArgs(validationCommand.trim());
    if (validationArgs.length != 2 ||
        validationArgs.first.split('/').last.toLowerCase() != 'cat') {
      return false;
    }
    final decoded = _decodeJsonObject(result.result);
    if (decoded == null || decoded['error'] != null) {
      return false;
    }
    if (decoded['content'] is! String) {
      return false;
    }
    final actualPath =
        _toolResultPayloadPath(result.result) ??
        _toolPathFromArguments(result.arguments);
    if (actualPath == null) {
      return false;
    }
    final normalizedActualPath = _normalizeSavedTaskScopePath(actualPath);
    final normalizedValidationPath = _normalizeSavedTaskScopePath(
      validationArgs[1],
    );
    return normalizedActualPath != null &&
        normalizedValidationPath != null &&
        normalizedActualPath == normalizedValidationPath;
  }

  bool _toolCommandMatchesSavedValidation({
    required ToolResultInfo result,
    required String command,
    required String normalizedValidationCommand,
  }) {
    return _toolCallExecutionPolicy.toolCommandMatchesSavedValidation(
      result: result,
      command: command,
      normalizedValidationCommand: normalizedValidationCommand,
    );
  }

  String? _currentSavedValidationCommandForToolLoop() {
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    final command = conversation == null
        ? null
        : ConversationPlanExecutionCoordinator.validationTask(
            conversation,
          )?.validationCommand.trim();
    return command == null || command.isEmpty ? null : command;
  }

  String _normalizeToolCommandForComparison(String command) {
    return _toolCallExecutionPolicy.normalizeToolCommandForComparison(command);
  }

  String? _runTestsPathArgument(Map<String, dynamic> arguments) {
    return _toolCallExecutionPolicy.runTestsPathArgument(arguments);
  }

  bool _runTestsMatchesSavedValidation({
    required Map<String, dynamic> arguments,
    required String normalizedValidationCommand,
  }) {
    return _toolCallExecutionPolicy.runTestsMatchesSavedValidation(
      arguments: arguments,
      normalizedValidationCommand: normalizedValidationCommand,
    );
  }

  bool _isReadOnlyInspectionToolCall(ToolCallInfo toolCall) {
    return _toolCallExecutionPolicy.isReadOnlyInspectionToolCall(toolCall);
  }

  bool _isReadOnlyCommandExecutionToolCall(ToolCallInfo toolCall) {
    return _toolCallExecutionPolicy.isReadOnlyCommandExecutionToolCall(
      toolCall,
    );
  }

  List<ToolResultInfo> _buildUnexecutedPendingToolResults({
    required List<ToolCallInfo> toolCalls,
    required Set<String> executedToolCallKeys,
    required int commandRetryGeneration,
  }) {
    return _toolLoopRecoveryPolicy.buildUnexecutedPendingToolResults(
      toolCalls: toolCalls,
      executedToolCallKeys: executedToolCallKeys,
      commandRetryGeneration: commandRetryGeneration,
      toolCallKey: (toolCall, generation) =>
          _toolExecutionKey(toolCall, commandRetryGeneration: generation),
    );
  }

  String _buildDuplicateInspectionRecoveryPrompt(
    List<ToolCallInfo> toolCalls, {
    List<ToolResultInfo> previousToolResults = const [],
  }) {
    final repeatedToolNames = toolCalls
        .map((toolCall) => toolCall.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .join(', ');
    final previousCommandValidationFailed =
        _toolResultsContainFailedCommandValidation(previousToolResults);
    final previousExactExitCodeExpectationFailed =
        _toolResultsMentionExactNonZeroExitCodeExpectation(previousToolResults);
    return [
      'You already inspected the same local files for the current saved task.',
      if (repeatedToolNames.isNotEmpty)
        'Do not repeat identical read-only inspection tools again in this turn: $repeatedToolNames.',
      if (previousCommandValidationFailed)
        'The latest validation command failed; use that failure output now instead of inspecting the directory again.',
      if (previousExactExitCodeExpectationFailed)
        'If the failure is only an exact non-zero exit-code mismatch, edit the verification target to accept any non-zero failure code before rerunning validation.',
      'Take the next concrete saved-task action now.',
      'Your next reply must either modify a saved target file or run the saved validation command.',
      'Do not restate the plan, do not ask for confirmation, and do not switch to a future saved task.',
    ].join('\n');
  }

  String _buildDuplicateFollowUpRecoveryPrompt(
    List<ToolCallInfo> toolCalls, {
    List<ToolResultInfo> previousToolResults = const [],
  }) {
    final repeatedToolNames = toolCalls
        .map((toolCall) => toolCall.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .join(', ');
    final repeatedValidationTool = toolCalls.any(_isRepeatableCommandTool);
    final inspectedFailingFile = previousToolResults.any(
      (toolResult) => toolResult.name == 'read_file',
    );
    return [
      'You already attempted the same follow-up tool call for the current task.',
      if (repeatedToolNames.isNotEmpty)
        'Do not repeat identical tool calls again in this turn: $repeatedToolNames.',
      'Use the previous tool results and take the next concrete task step now.',
      'If the user requested local file creation or modification and no successful file mutation result is already provided, your next action must be write_file or edit_file, or a concise blocker that clearly says no files were created.',
      'Do not claim that files were created, edited, saved, moved, or deleted unless the provided tool results include the successful file operation.',
      'If the current saved task still needs work, create or edit the saved target file.',
      if (inspectedFailingFile && repeatedValidationTool)
        'If you just read a failing saved target file, your next action must modify that same file before rerunning the saved validation command.',
      if (repeatedValidationTool)
        'Do not rerun the same validation command until a saved target file edit changes the current task.',
      'If validation already succeeded, reply with a brief completion statement instead of repeating the same tool call.',
      'Do not restate the plan, do not ask for confirmation, and do not switch to a future saved task.',
    ].join('\n');
  }

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
  }) {
    return _toolLoopRecoveryPolicy.buildRecoveryToolResults(
      currentToolResults: currentToolResults,
      executedToolResults: executedToolResults,
      pendingToolCalls: pendingToolCalls,
      pathFromArguments: _toolPathFromArguments,
      toolResultKey: _toolResultDedupKey,
    );
  }

  List<ToolResultInfo> _dedupeRecoveryToolResults(
    List<ToolResultInfo> toolResults,
  ) {
    return _toolLoopRecoveryPolicy.dedupeRecoveryToolResults(
      toolResults,
      toolResultKey: _toolResultDedupKey,
    );
  }

  String _extractAssistantStreamDelta({
    required int messageIndex,
    required int startingLength,
  }) {
    if (messageIndex < 0 || messageIndex >= state.messages.length) {
      return '';
    }
    final content = state.messages[messageIndex].content;
    if (startingLength >= content.length) {
      return '';
    }
    return content.substring(startingLength).trim();
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

  bool _isRepeatableCommandTool(ToolCallInfo toolCall) {
    return _toolCallExecutionPolicy.isRepeatableCommandTool(toolCall);
  }

  bool _advancesCommandRetryGeneration(ToolCallInfo toolCall) {
    return _toolCallExecutionPolicy.advancesCommandRetryGeneration(toolCall);
  }

  String _toolCallDedupKey(String name, Object? arguments) {
    return _toolCallExecutionPolicy.toolCallDedupKey(
      name,
      arguments,
      resolveProjectPath: _normalizeToolPathForDedup,
    );
  }

  String _toolResultDedupKey(ToolResultInfo toolResult) {
    return _toolCallExecutionPolicy.toolResultDedupKey(
      toolResult,
      resolveProjectPath: _normalizeToolPathForDedup,
    );
  }

  String? _normalizeToolPathForDedup(String trimmed) {
    final resolved = FilesystemTools.resolvePath(
      trimmed,
      defaultRoot: _getActiveProjectRootPath(),
    );
    return resolved ?? trimmed;
  }

  String? _toolPathFromArguments(Object? arguments) {
    if (arguments is Map) {
      final rawPath = arguments['path'];
      if (rawPath is String && rawPath.trim().isNotEmpty) {
        return rawPath.trim();
      }
    }
    return null;
  }

  void _markToolCallSeenForContentDedup(String name, Object? arguments) {
    _seenContentToolCallHashes.add(_toolCallDedupKey(name, arguments));
  }

  /// Executes a `tool_call` detected from message content.
  Future<void> _executeContentToolCall(
    ToolCallData tc,
    int interactionGeneration,
  ) async {
    if (!_isCurrentInteractionGeneration(interactionGeneration)) return;

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
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;

      if (!result.isSuccess) {
        appLog('[ContentTool] Execution failed: ${result.errorMessage}');
        final failureResult = _buildContentToolFailureResult(
          tc.name,
          result.errorMessage,
        );
        _recordContentToolResult(toolCall: toolCall, result: failureResult);
        if (ref.mounted && state.messages.isNotEmpty) {
          final updatedMessages = [...state.messages];
          final lastIndex = updatedMessages.length - 1;
          final lastMessage = updatedMessages[lastIndex];

          updatedMessages[lastIndex] = lastMessage.copyWith(
            content:
                '${lastMessage.content}\n\n${_buildContentToolResultTag(tc.name, failureResult)}',
          );

          state = state.copyWith(messages: updatedMessages);
          appLog('[ContentTool] Appended failure result to message');
        }
        _pendingContentToolResults.add(
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
        conversationId: conversationId,
      );
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      _recordContentToolResultInfo(contentToolResult);
      await _recordModelEditApplyTelemetry(contentToolResult);
      final promptResult = contentToolResult.result;

      // Append results without triggering recursive tool-call checks.
      if (ref.mounted && state.messages.isNotEmpty) {
        final updatedMessages = [...state.messages];
        final lastIndex = updatedMessages.length - 1;
        final lastMessage = updatedMessages[lastIndex];

        updatedMessages[lastIndex] = lastMessage.copyWith(
          content:
              '${lastMessage.content}\n\n${_buildContentToolResultTag(tc.name, promptResult)}',
        );

        state = state.copyWith(messages: updatedMessages);
        appLog('[ContentTool] Appended result to message');
      }

      _pendingContentToolResults.add('[Result of ${tc.name}]\n$promptResult');
    } catch (e) {
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      appLog('[ContentTool] Error: $e');
      final failureResult = _buildContentToolFailureResult(tc.name, '$e');
      _recordContentToolResult(toolCall: toolCall, result: failureResult);
      if (ref.mounted && state.messages.isNotEmpty) {
        final updatedMessages = [...state.messages];
        final lastIndex = updatedMessages.length - 1;
        final lastMessage = updatedMessages[lastIndex];

        updatedMessages[lastIndex] = lastMessage.copyWith(
          content:
              '${lastMessage.content}\n\n${_buildContentToolResultTag(tc.name, failureResult)}',
        );

        state = state.copyWith(messages: updatedMessages);
        appLog('[ContentTool] Appended thrown failure result to message');
      }
      _pendingContentToolResults.add('[Result of ${tc.name}]\n$failureResult');
    }
  }

  bool _toolResultsContainEditMismatch(List<ToolResultInfo> toolResults) {
    return _toolLoopRecoveryPolicy.toolResultsContainEditMismatch(toolResults);
  }

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

  // ---------------------------------------------------------------------------
  // SSH tool interception
  // ---------------------------------------------------------------------------

  /// Dispatches a tool call to the MCP tool service, intercepting SSH
  /// tools that require a UI dialog for user confirmation.
  Future<McpToolResult> _dispatchToolCall(
    ToolCallInfo toolCall, {
    int? interactionGeneration,
  }) async {
    return ChatToolDispatcher(
      enforcePlanningPolicy: _enforcePlanningToolPolicy,
      handleComputerUseAction: _handleComputerUseAction,
      handleComputerUseObservation: _handleComputerUseActionWithoutApproval,
      handleBrowserAction: _handleBrowserAction,
      handleBrowserObservation: _handleBrowserActionWithoutApproval,
      handlerRegistry: _buildToolHandlerRegistry(
        interactionGeneration: interactionGeneration,
      ),
      executeFallbackTool: (toolCall) => _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: toolCall.arguments,
      ),
    ).dispatch(toolCall);
  }

  Future<McpToolResult> _handleProjectScopedTool(ToolCallInfo toolCall) async {
    final accessFailure = await _ensureActiveProjectAccess(toolCall.name);
    if (accessFailure != null) return accessFailure;

    return _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: _resolveProjectScopedArguments(
        toolCall.name,
        toolCall.arguments,
      ),
    );
  }

  McpToolResult? _enforcePlanningToolPolicy(ToolCallInfo toolCall) {
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    return _planningToolPolicy.enforce(
      toolCall,
      isPlanningSession: currentConversation?.isPlanningSession ?? false,
      isExternalMcpTool:
          _mcpToolService?.isExternalMcpToolName(toolCall.name) ?? false,
      resolveArguments: _resolveProjectScopedArguments,
    );
  }

  TokenUsage _latestTokenUsage() {
    final ds = _dataSource;
    return switch (ds) {
      ChatRemoteDataSource() => ds.lastUsage,
      SessionLoggingChatDataSource() => ds.lastUsage,
      _ => TokenUsage.zero,
    };
  }

  String? _latestFinishReason() {
    final override = _finalAnswerFinishReasonOverride;
    if (override != null && override.trim().isNotEmpty) {
      return override;
    }
    final ds = _dataSource;
    if (ds is FinishReasonAware) {
      return (ds as FinishReasonAware).lastFinishReason;
    }
    return null;
  }

  MessageResponseMetrics? _takeResponseMetricsForGeneration(int generation) {
    final timer = _responseMetricTimersByGeneration.remove(generation);
    timer?.stop();

    final usage = _latestTokenUsage();
    final finishReason = _latestFinishReason();
    if (timer == null && usage.totalTokens <= 0 && finishReason == null) {
      return null;
    }

    return MessageResponseMetrics(
      promptTokens: usage.promptTokens,
      completionTokens: usage.completionTokens,
      totalTokens: usage.totalTokens,
      elapsedMilliseconds: timer?.elapsedMilliseconds ?? 0,
      finishReason: finishReason,
    );
  }

  void _discardResponseMetricsForGeneration(int generation) {
    _responseMetricTimersByGeneration.remove(generation)?.stop();
  }

  /// Read and accumulate the latest token usage from the data source.
  void _updateTokenUsage() {
    final usage = _latestTokenUsage();
    if (usage.totalTokens <= 0) return;

    // Use the latest usage directly (represents the full conversation context)
    _accumulatedTokenUsage = usage;
    state = state.copyWith(
      promptTokens: _accumulatedTokenUsage.promptTokens,
      completionTokens: _accumulatedTokenUsage.completionTokens,
      totalTokens: _accumulatedTokenUsage.totalTokens,
    );
    _emitRuntimeUsage(_interactionGeneration, _accumulatedTokenUsage);
  }

  void _recoverIncompleteContentToolCallsFromLastMessage({
    required int interactionGeneration,
  }) {
    if (!_isCurrentInteractionGeneration(interactionGeneration) ||
        state.messages.isEmpty) {
      return;
    }

    final lastMessage = state.messages.last;
    if (lastMessage.role != MessageRole.assistant ||
        !ContentParser.hasIncompleteToolCall(lastMessage.content)) {
      return;
    }

    final recoveredToolCalls =
        ContentParser.extractRecoverableIncompleteToolCalls(
          lastMessage.content,
        ).where((tc) {
          return _seenContentToolCallHashes.add(_contentToolCallHash(tc));
        }).toList();

    if (recoveredToolCalls.isEmpty) {
      appLog(
        '[ContentTool] Incomplete tool call could not be parsed; requesting continuation recovery',
      );
      _stripToolArtifactsFromLastAssistantMessage(
        interactionGeneration: interactionGeneration,
      );
      _pendingContentToolResults.add(
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
    if (!ref.mounted || state.messages.isEmpty) return false;

    final lastMessage = state.messages.last;
    if (lastMessage.role != MessageRole.assistant) {
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
      interactionGeneration: interactionGeneration,
    );
    _pendingContentToolResults.add(
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
    final pendingToolExecutionCount = _pendingToolExecutions.length;
    final pendingContentToolResultCount = _pendingContentToolResults.length;

    _recoverIncompleteContentToolCallsFromLastMessage(
      interactionGeneration: interactionGeneration,
    );
    if (_pendingToolExecutions.length > pendingToolExecutionCount ||
        _pendingContentToolResults.length > pendingContentToolResultCount) {
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
    if (!ref.mounted || state.messages.isEmpty) return false;

    final lastMessage = state.messages.last;
    if (lastMessage.role != MessageRole.assistant) {
      return false;
    }

    final toolNames = _extractFencedToolNameBlocks(lastMessage.content);
    if (toolNames.isEmpty) {
      return false;
    }

    appLog(
      '[ContentTool] Ignoring assistant-authored fenced tool_name block(s): '
      '${toolNames.join(", ")}',
    );
    _replaceLastMessageContentForGeneration(
      interactionGeneration ?? _interactionGeneration,
      _stripFencedToolNameBlocks(lastMessage.content),
    );
    _pendingContentToolResults.add(
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

  List<String> _extractFencedToolNameBlocks(String content) {
    final toolNames = <String>[];
    final pattern = RegExp(
      r'```tool_name\s*([\s\S]*?)```',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(content)) {
      final name = (match.group(1) ?? '').trim();
      if (name.isNotEmpty) {
        toolNames.add(name);
      }
    }
    return toolNames;
  }

  String _stripFencedToolNameBlocks(String content) {
    return content
        .replaceAll(
          RegExp(r'```tool_name\s*[\s\S]*?```', caseSensitive: false),
          '',
        )
        .trim();
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

      final strippedContent = ContentParser.stripToolArtifacts(
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

    final strippedContent = ContentParser.stripToolArtifacts(
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
    final strippedSuffix = ContentParser.stripToolArtifacts(
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
    if (_isActiveResponseDetachedForGeneration(generation)) {
      final activeMessages = _activeResponseMessagesForGeneration(generation);
      if (activeMessages == null || activeMessages.isEmpty) return;

      final updatedMessages = [...activeMessages];
      final lastIndex = updatedMessages.length - 1;
      final lastMessage = updatedMessages[lastIndex];
      if (lastMessage.role != MessageRole.assistant) {
        return;
      }

      final content = lastMessage.content;
      const notice =
          'I could not execute the additional tool request above in this final-answer step. '
          'Treat it as unexecuted; ask me to continue with a narrower follow-up '
          'if the missing action still matters.';
      if (content.contains(notice) ||
          !_looksLikeUnexecutedToolRequest(content)) {
        return;
      }

      updatedMessages[lastIndex] = lastMessage.copyWith(
        content: '${content.trimRight()}\n\n$notice',
      );
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

    final content = lastMessage.content;
    const notice =
        'I could not execute the additional tool request above in this final-answer step. '
        'Treat it as unexecuted; ask me to continue with a narrower follow-up '
        'if the missing action still matters.';
    if (content.contains(notice) || !_looksLikeUnexecutedToolRequest(content)) {
      return;
    }

    updatedMessages[lastIndex] = lastMessage.copyWith(
      content: '${content.trimRight()}\n\n$notice',
    );
    state = state.copyWith(messages: updatedMessages);
    _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
  }

  bool _shouldSkipUnexecutedToolRequestNoticeForToolResults({
    required String content,
    required List<ToolResultInfo> toolResults,
  }) {
    if (toolResults.isEmpty ||
        _hasTimedOutCommandResult(toolResults) ||
        _toolResultsContainFailedCommandValidation(toolResults) ||
        _hasUnexecutedCommandActionResult(toolResults) ||
        _hasUnexecutedFileSideEffectResult(toolResults) ||
        !_hasSuccessfulFinalAnswerToolEvidence(toolResults)) {
      return false;
    }

    final candidate = ContentParser.stripToolArtifacts(content).trim();
    if (candidate.isEmpty ||
        _looksLikeStructuredToolRequest(candidate) ||
        _looksLikePlanOnlyFinalToolAnswer(candidate) ||
        _looksLikeFutureCommandExecutionAction(candidate) ||
        _looksLikeFutureFileSideEffectAction(candidate) ||
        _looksLikeCodingFutureAction(candidate)) {
      return false;
    }

    return _looksLikeCompletedCommandExecutionClaim(candidate) ||
        _looksLikeCompletedCodingFinalAnswer(candidate);
  }

  void _appendUnexecutedFileSideEffectNoticeIfNeeded({
    required List<ToolResultInfo> toolResults,
    int? interactionGeneration,
  }) {
    final generation = interactionGeneration ?? _interactionGeneration;
    const notice =
        'The requested file save was not executed because no successful file-operation tool result is available. '
        'Treat any save, create, or download claim above as unverified.';
    if (_isActiveResponseDetachedForGeneration(generation)) {
      final activeMessages = _activeResponseMessagesForGeneration(generation);
      if (activeMessages == null || activeMessages.isEmpty) return;

      final updatedMessages = [...activeMessages];
      final lastIndex = updatedMessages.length - 1;
      final lastMessage = updatedMessages[lastIndex];
      if (lastMessage.role != MessageRole.assistant) {
        return;
      }

      final content = lastMessage.content;
      if (content.contains(notice) ||
          !_looksLikeUnsupportedFileSideEffectClaim(
            content,
            toolResults: toolResults,
          )) {
        return;
      }

      updatedMessages[lastIndex] = lastMessage.copyWith(
        content: '${content.trimRight()}\n\n$notice',
      );
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

    final content = lastMessage.content;
    if (content.contains(notice) ||
        !_looksLikeUnsupportedFileSideEffectClaim(
          content,
          toolResults: toolResults,
        )) {
      return;
    }

    updatedMessages[lastIndex] = lastMessage.copyWith(
      content: '${content.trimRight()}\n\n$notice',
    );
    state = state.copyWith(messages: updatedMessages);
    _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
  }

  void _appendUnexecutedCommandActionNoticeIfNeeded({
    required List<ToolResultInfo> toolResults,
    int? interactionGeneration,
  }) {
    final generation = interactionGeneration ?? _interactionGeneration;
    const notice =
        'The requested command was not executed because no matching successful command-execution tool result is available for that claimed action. '
        'Treat any run, dry-run, test, validation, or command execution claim above as unverified.';
    if (!_hasUnexecutedCommandActionResult(toolResults)) {
      return;
    }
    _appliedTurnTransforms.add('unexecuted_command_action_notice');

    if (_isActiveResponseDetachedForGeneration(generation)) {
      final activeMessages = _activeResponseMessagesForGeneration(generation);
      if (activeMessages == null || activeMessages.isEmpty) return;

      final updatedMessages = [...activeMessages];
      final lastIndex = updatedMessages.length - 1;
      final lastMessage = updatedMessages[lastIndex];
      if (lastMessage.role != MessageRole.assistant) {
        return;
      }
      final content = _messageContentWithUnexecutedCommandActionNotice(
        lastMessage.content,
        notice,
      );
      if (lastMessage.content == content) {
        return;
      }
      updatedMessages[lastIndex] = lastMessage.copyWith(content: content);
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
    final content = _messageContentWithUnexecutedCommandActionNotice(
      lastMessage.content,
      notice,
    );
    if (lastMessage.content == content) {
      return;
    }
    updatedMessages[lastIndex] = lastMessage.copyWith(content: content);
    state = state.copyWith(messages: updatedMessages);
    _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
  }

  void _appendUnverifiedReadOnlyInspectionClaimNoticeIfNeeded({
    required List<ToolResultInfo> toolResults,
    int? interactionGeneration,
  }) {
    final generation = interactionGeneration ?? _interactionGeneration;
    const notice =
        'The local file or project state claim above is unverified because no successful read-only inspection tool result is available for that claim. '
        'Treat any file existence, file content, directory listing, or path verification claim above as unverified.';
    if (!_hasUnverifiedReadOnlyInspectionClaimResult(toolResults)) {
      return;
    }
    _appliedTurnTransforms.add('unverified_read_only_inspection_notice');

    if (_isActiveResponseDetachedForGeneration(generation)) {
      final activeMessages = _activeResponseMessagesForGeneration(generation);
      if (activeMessages == null || activeMessages.isEmpty) return;

      final updatedMessages = [...activeMessages];
      final lastIndex = updatedMessages.length - 1;
      final lastMessage = updatedMessages[lastIndex];
      if (lastMessage.role != MessageRole.assistant) {
        return;
      }
      final content = _messageContentWithUnverifiedReadOnlyInspectionNotice(
        lastMessage.content,
        notice,
      );
      if (lastMessage.content == content) {
        return;
      }
      updatedMessages[lastIndex] = lastMessage.copyWith(content: content);
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
    final content = _messageContentWithUnverifiedReadOnlyInspectionNotice(
      lastMessage.content,
      notice,
    );
    if (lastMessage.content == content) {
      return;
    }
    updatedMessages[lastIndex] = lastMessage.copyWith(content: content);
    state = state.copyWith(messages: updatedMessages);
    _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
  }

  void _replaceTimedOutCommandSuccessClaimIfNeeded({
    required List<ToolResultInfo> toolResults,
    int? interactionGeneration,
  }) {
    if (!_hasTimedOutCommandResult(toolResults)) {
      return;
    }
    final generation = interactionGeneration ?? _interactionGeneration;
    const notice =
        'A command timed out, so any success, pass, or completion claim is unverified. '
        'Treat the command result as incomplete until a successful command-execution tool result is available.';
    if (_isActiveResponseDetachedForGeneration(generation)) {
      final activeMessages = _activeResponseMessagesForGeneration(generation);
      if (activeMessages == null || activeMessages.isEmpty) return;

      final updatedMessages = [...activeMessages];
      final lastIndex = updatedMessages.length - 1;
      final lastMessage = updatedMessages[lastIndex];
      if (lastMessage.role != MessageRole.assistant ||
          !_looksLikeCommandSuccessClaim(lastMessage.content)) {
        return;
      }
      updatedMessages[lastIndex] = lastMessage.copyWith(
        content: _messageContentWithPrependedClaimCorrectionNotice(
          lastMessage.content,
          notice,
        ),
      );
      _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
      return;
    }

    if (!ref.mounted || state.messages.isEmpty) return;

    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];
    if (lastMessage.role != MessageRole.assistant ||
        !_looksLikeCommandSuccessClaim(lastMessage.content)) {
      return;
    }
    updatedMessages[lastIndex] = lastMessage.copyWith(
      content: _messageContentWithPrependedClaimCorrectionNotice(
        lastMessage.content,
        notice,
      ),
    );
    state = state.copyWith(messages: updatedMessages);
    _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
  }

  void _replaceFailedCommandSuccessClaimIfNeeded({
    required List<ToolResultInfo> toolResults,
    int? interactionGeneration,
  }) {
    final failedExitCode = _firstFailedCommandExitCode(toolResults);
    if (failedExitCode == null) {
      return;
    }
    final generation = interactionGeneration ?? _interactionGeneration;
    final notice =
        'A command exited with non-zero exit code $failedExitCode, so any '
        'success, upload, release, pass, or completion claim is unverified. '
        'Treat the command as failed until a later command-execution tool '
        'result exits successfully.';
    if (_isActiveResponseDetachedForGeneration(generation)) {
      final activeMessages = _activeResponseMessagesForGeneration(generation);
      if (activeMessages == null || activeMessages.isEmpty) return;

      final updatedMessages = [...activeMessages];
      final lastIndex = updatedMessages.length - 1;
      final lastMessage = updatedMessages[lastIndex];
      if (lastMessage.role != MessageRole.assistant ||
          !_looksLikeCommandSuccessClaim(lastMessage.content)) {
        return;
      }
      updatedMessages[lastIndex] = lastMessage.copyWith(
        content: _messageContentWithPrependedClaimCorrectionNotice(
          lastMessage.content,
          notice,
        ),
      );
      _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
      return;
    }

    if (!ref.mounted || state.messages.isEmpty) return;

    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];
    if (lastMessage.role != MessageRole.assistant ||
        !_looksLikeCommandSuccessClaim(lastMessage.content)) {
      return;
    }
    updatedMessages[lastIndex] = lastMessage.copyWith(
      content: _messageContentWithPrependedClaimCorrectionNotice(
        lastMessage.content,
        notice,
      ),
    );
    state = state.copyWith(messages: updatedMessages);
    _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
  }

  bool _hasTimedOutCommandResult(List<ToolResultInfo> toolResults) {
    return toolResults.any(_toolResultTimedOut);
  }

  int? _firstFailedCommandExitCode(List<ToolResultInfo> toolResults) {
    int? unrecoveredExitCode;
    for (final toolResult in toolResults) {
      if (!_isCommandExecutionTool(toolResult.name)) {
        continue;
      }
      final normalizedName = toolResult.name.trim().toLowerCase();
      if (normalizedName == 'process_start' ||
          normalizedName == 'process_status' ||
          normalizedName == 'process_wait') {
        continue;
      }
      if (_toolResultTimedOut(toolResult)) {
        continue;
      }
      final decoded = _tryDecodeMap(toolResult.result);
      final exitCode = _exitCodeValue(decoded?['exit_code']);
      if (exitCode != null && exitCode != 0) {
        unrecoveredExitCode ??= exitCode;
      } else if (exitCode == 0) {
        unrecoveredExitCode = null;
      }
    }
    return unrecoveredExitCode;
  }

  bool _looksLikeUnexecutedToolRequest(String content) {
    if (_looksLikeStructuredToolRequest(content)) {
      return true;
    }

    final trimmed = content.trim();
    return _looksLikePlanOnlyFinalToolAnswer(trimmed) ||
        _looksLikeUnsupportedCommandExecutionAction(trimmed) ||
        _looksLikeFutureFileSideEffectAction(trimmed);
  }

  bool _looksLikeStructuredToolRequest(String content) {
    if (ContentParser.extractCompletedToolCalls(content).isNotEmpty) {
      return true;
    }
    if (_looksLikeBracketedToolRequest(content)) {
      return true;
    }

    final fencedJsonBlocks = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    ).allMatches(content);
    for (final block in fencedJsonBlocks) {
      final snippet = block.group(1);
      if (snippet != null && _jsonLooksLikeCommandProposal(snippet)) {
        return true;
      }
    }

    final trimmed = content.trim();
    return (trimmed.startsWith('[') || trimmed.startsWith('{')) &&
        _jsonLooksLikeCommandProposal(trimmed);
  }

  bool _looksLikeBracketedToolRequest(String content) {
    return _bracketedToolRequestName(content) != null;
  }

  String? _bracketedToolRequestName(String content) {
    final match = RegExp(
      r'\[Tool:\s*([A-Za-z_][\w.-]*)\]\s*(?:\r?\n)+\s*Arguments:\s*(?:\{|\[)',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(content);
    return match?.group(1);
  }

  bool _looksLikePlanOnlyFinalToolAnswer(String content) {
    if (content.isEmpty || content.length > 1600) {
      return false;
    }

    final numberedStepMatches = RegExp(
      r'^\s*\d+[.)]\s+\S',
      multiLine: true,
    ).allMatches(content).toList(growable: false);
    final numberedStepCount = numberedStepMatches.length;
    final lowerContent = content.toLowerCase();
    final hasPlanHeading = RegExp(
      r'^\s*(?:#{1,6}\s*)?(?:\*\*)?\s*(?:investigation\s+plan|plan|next\s+steps?|checklist)\b',
      caseSensitive: false,
      multiLine: true,
    ).hasMatch(content);
    final futureActionScanStart = hasPlanHeading || numberedStepMatches.isEmpty
        ? 0
        : numberedStepMatches.first.start;
    final hasFutureAction = _containsAnyAtOrAfter(lowerContent, const [
      'i will inspect',
      'i will check',
      'i will confirm',
      'i will trace',
      'i will verify',
      "i'll inspect",
      "i'll check",
      'we will inspect',
      'we will check',
      'need to inspect',
      'need to check',
      'need to confirm',
      'first, i will',
      'next, i will',
    ], futureActionScanStart);
    final hasCjkFutureAction = _containsCjkFutureActionMarker(
      content,
      startIndex: futureActionScanStart,
    );

    if ((hasPlanHeading || numberedStepCount >= 2) &&
        (hasFutureAction || hasCjkFutureAction)) {
      return true;
    }
    return hasPlanHeading && numberedStepCount >= 2 && content.length <= 600;
  }

  bool _containsAny(String value, List<String> markers) {
    return markers.any(value.contains);
  }

  bool _containsAnyAtOrAfter(
    String value,
    List<String> markers,
    int startIndex,
  ) {
    final clampedStart = startIndex.clamp(0, value.length).toInt();
    for (final marker in markers) {
      if (value.indexOf(marker, clampedStart) >= 0) {
        return true;
      }
    }
    return false;
  }

  bool _containsCjkBlockerMarker(String value) {
    final markers = [
      String.fromCharCodes([0x5fc5, 0x8981, 0x3067, 0x3059]),
      String.fromCharCodes([0x304a, 0x9858, 0x3044, 0x3057, 0x307e, 0x3059]),
      String.fromCharCodes([
        0x6559,
        0x3048,
        0x3066,
        0x304f,
        0x3060,
        0x3055,
        0x3044,
      ]),
    ];
    return markers.any(value.contains);
  }

  bool _containsCjkMissingEvidenceMarker(String value) {
    final markers = [
      String.fromCharCodes([0x30bd, 0x30fc, 0x30b9, 0x30b3, 0x30fc, 0x30c9]),
      String.fromCharCodes([0x30ea, 0x30dd, 0x30b8, 0x30c8, 0x30ea]),
      String.fromCharCodes([0x30d1, 0x30b9]),
      String.fromCharCodes([0x30a2, 0x30af, 0x30bb, 0x30b9]),
      String.fromCharCodes([0x629c, 0x7c8b]),
    ];
    return markers.any(value.contains);
  }

  bool _jsonLooksLikeCommandProposal(String snippet) {
    try {
      return _jsonValueLooksLikeCommandProposal(jsonDecode(snippet));
    } on FormatException {
      return false;
    }
  }

  bool _jsonValueLooksLikeCommandProposal(Object? value) {
    if (value is List && value.isNotEmpty) {
      final mapItems = value.whereType<Map<Object?, Object?>>().toList();
      return mapItems.length == value.length &&
          mapItems.any(_jsonMapLooksLikeCommandProposal);
    }
    if (value is Map<Object?, Object?>) {
      return _jsonMapLooksLikeCommandProposal(value);
    }
    return false;
  }

  bool _jsonMapLooksLikeCommandProposal(Map<Object?, Object?> value) {
    final keys = value.keys
        .whereType<String>()
        .map((key) => key.toLowerCase())
        .toSet();
    if (keys.contains('command')) {
      return !keys.contains('exit_code') &&
          !keys.contains('stdout') &&
          !keys.contains('stderr');
    }
    if (!keys.contains('name') || !keys.contains('arguments')) {
      return false;
    }

    final name = value.entries
        .firstWhere(
          (entry) =>
              entry.key is String &&
              (entry.key! as String).toLowerCase() == 'name',
          orElse: () => const MapEntry<Object?, Object?>(null, null),
        )
        .value
        ?.toString()
        .toLowerCase();
    return name == 'local_execute_command' ||
        name == 'run_tests' ||
        name == 'git_execute_command' ||
        name == 'ssh_execute_command';
  }

  void _appendToolContinuationLimitNotice() {
    if (!ref.mounted || state.messages.isEmpty) return;

    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];
    updatedMessages[lastIndex] = lastMessage.copyWith(
      content:
          '${lastMessage.content}\n\n[Tool continuation limit reached. Please ask again with a more specific request.]',
    );
    state = state.copyWith(messages: updatedMessages);
  }

  Future<void> _finishStreaming({int? interactionGeneration}) async {
    final generation = interactionGeneration ?? _interactionGeneration;
    if (!_isCurrentInteractionGeneration(generation)) return;

    if (_isActiveResponseDetachedForGeneration(generation)) {
      await _finishDetachedActiveResponse(generation);
      return;
    }

    _recoverIncompleteContentToolCallsFromLastMessage(
      interactionGeneration: generation,
    );

    // Wait for pending tool executions before finalizing the response.
    if (_pendingToolExecutions.isNotEmpty) {
      final pendingToolExecutions = List<Future<void>>.from(
        _pendingToolExecutions,
      );
      _pendingToolExecutions.clear();
      appLog(
        '[ChatNotifier] Waiting for pending tool executions: ${pendingToolExecutions.length}',
      );
      await Future.wait(pendingToolExecutions);
      if (!_isCurrentInteractionGeneration(generation)) return;
      appLog('[ChatNotifier] Tool executions completed');
    }

    if (_pendingContentToolResults.isNotEmpty) {
      final toolResults = List<String>.from(_pendingContentToolResults);
      _pendingContentToolResults.clear();

      if (_contentToolContinuationCount >= _maxContentToolContinuations) {
        _appendToolContinuationLimitNotice();
      } else {
        _contentToolContinuationCount += 1;
        await _continueAfterContentToolResults(
          toolResults,
          interactionGeneration: generation,
        );
        return;
      }
    }

    if (_pendingContentToolResults.isEmpty) {
      final recoveredUntrustedToolResult =
          _recoverUntrustedAssistantToolResultsFromLastMessage(
            interactionGeneration: generation,
          );
      if (recoveredUntrustedToolResult) {
        final toolResults = List<String>.from(_pendingContentToolResults);
        _pendingContentToolResults.clear();
        if (_contentToolContinuationCount >= _maxContentToolContinuations) {
          _appendToolContinuationLimitNotice();
        } else {
          _contentToolContinuationCount += 1;
          await _continueAfterContentToolResults(
            toolResults,
            interactionGeneration: generation,
          );
          return;
        }
      }
    }

    if (_pendingContentToolResults.isEmpty) {
      final recoveredToolNameBlock =
          _recoverAssistantToolNameBlocksFromLastMessage(
            interactionGeneration: generation,
          );
      if (recoveredToolNameBlock) {
        final toolResults = List<String>.from(_pendingContentToolResults);
        _pendingContentToolResults.clear();
        if (_contentToolContinuationCount >= _maxContentToolContinuations) {
          _appendToolContinuationLimitNotice();
        } else {
          _contentToolContinuationCount += 1;
          await _continueAfterContentToolResults(
            toolResults,
            interactionGeneration: generation,
          );
          return;
        }
      }
    }

    if (!_isCurrentInteractionGeneration(generation) ||
        state.messages.isEmpty) {
      return;
    }

    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];
    final fallbackContent = _pendingContentToolContinuationFallback?.trim();
    final shouldUseContentToolContinuationFallback =
        lastMessage.role == MessageRole.assistant &&
        !_assistantMessageHasVisibleContent(lastMessage.content) &&
        fallbackContent != null &&
        fallbackContent.isNotEmpty;
    final shouldDropLastAssistant =
        lastMessage.role == MessageRole.assistant &&
        !_assistantMessageHasVisibleContent(lastMessage.content) &&
        !shouldUseContentToolContinuationFallback;

    // Capture token usage before building per-message metrics so both the
    // global usage indicator and completed bubble agree on the same response.
    _updateTokenUsage();
    final responseMetrics = shouldDropLastAssistant
        ? null
        : _takeResponseMetricsForGeneration(generation);
    if (shouldDropLastAssistant) {
      _discardResponseMetricsForGeneration(generation);
    }

    if (shouldUseContentToolContinuationFallback) {
      updatedMessages[lastIndex] = lastMessage.copyWith(
        content: fallbackContent,
        isStreaming: false,
        responseMetrics: responseMetrics,
      );
    } else if (shouldDropLastAssistant) {
      updatedMessages.removeAt(lastIndex);
    } else {
      // UX: if the answer was cut off at the max-token limit, flag it so the
      // user knows the response (and any code/file content in it) is incomplete
      // rather than silently presenting a truncated answer.
      final finalizedContent =
          _isCompletionTruncated(_latestFinishReason() ?? '')
          ? TruncationNotice.withMaxTokenNotice(lastMessage.content)
          : lastMessage.content;
      updatedMessages[lastIndex] = lastMessage.copyWith(
        content: finalizedContent,
        isStreaming: false,
        responseMetrics: responseMetrics,
      );
    }
    _pendingContentToolContinuationFallback = null;

    if (!_isCurrentInteractionGeneration(generation)) return;

    // Hidden prompt responses are ephemeral — remove from visible history
    // so they are spoken but not persisted in the conversation.
    if (_hiddenPrompt != null && !_persistHiddenPromptAssistantResponse) {
      state = state.copyWith(messages: updatedMessages, isLoading: false);
      if (!shouldDropLastAssistant && updatedMessages.isNotEmpty) {
        _recordHiddenAssistantResponse(updatedMessages.last.content);
      }
      final cleaned = shouldDropLastAssistant
          ? updatedMessages
          : updatedMessages.sublist(0, lastIndex);
      state = state.copyWith(messages: cleaned);
      _hiddenPrompt = null;
      _persistHiddenPromptAssistantResponse = false;
      _onResponseCompleted('');
      _completeRuntimeTurn(generation, content: '');
      if (!_isCurrentInteractionGeneration(generation)) return;
      await _drainQueuedChatMessagesIfIdle();
      return;
    }
    if (_hiddenPrompt != null) {
      _hiddenPrompt = null;
      _persistHiddenPromptAssistantResponse = false;
    }

    final recoveredBeforeFinalization =
        await _recoverBeforeTurnFinalizationIfNeeded(
          generation: generation,
          finalizedMessages: updatedMessages,
          shouldDropLastAssistant: shouldDropLastAssistant,
        );
    if (recoveredBeforeFinalization) {
      return;
    }
    if (!_isCurrentInteractionGeneration(generation)) return;
    if (!shouldDropLastAssistant && updatedMessages.isNotEmpty) {
      final finalMessageIndex = updatedMessages.length - 1;
      final finalMessage = updatedMessages[finalMessageIndex];
      final guardedContent = _messageContentWithVerificationClaimNotice(
        _messageContentWithNarratedTranscriptClaimNotice(
          _messageContentWithUnwrittenFileClaimNotice(finalMessage.content),
        ),
      );
      if (guardedContent != finalMessage.content) {
        updatedMessages[finalMessageIndex] = finalMessage.copyWith(
          content: guardedContent,
        );
      }
    }
    await _logTurnExitReason(
      generation: generation,
      finalizedMessages: updatedMessages,
      shouldDropLastAssistant: shouldDropLastAssistant,
    );
    if (!_isCurrentInteractionGeneration(generation)) return;
    state = state.copyWith(messages: updatedMessages, isLoading: false);
    final explicitTerminalSuccessSummary =
        _explicitTerminalSuccessSummariesByGeneration.remove(generation);

    // Persist messages.
    _contentToolContinuationCount = 0;
    _clearActiveResponseForGeneration(generation);
    await _saveMessages();
    if (!_isCurrentInteractionGeneration(generation)) return;

    if (shouldDropLastAssistant || updatedMessages.isEmpty) {
      _clearTurnDiffCapture();
      _onResponseCompleted('');
      _completeRuntimeTurn(generation, content: '');
      if (!_isCurrentInteractionGeneration(generation)) return;
      await _drainQueuedChatMessagesIfIdle();
      _clearGoalAutoContinueIndicator();
      return;
    }

    // Trigger auto-read when enabled.
    final finalizedLastMessage = updatedMessages.last;
    if (finalizedLastMessage.role == MessageRole.assistant) {
      await _persistPendingTurnDiffForAssistant(finalizedLastMessage.id);
    } else {
      _clearTurnDiffCapture();
    }
    _reconcileGoalAutoContinueEvidenceForFinalization();
    await ref
        .read(conversationsNotifierProvider.notifier)
        .recordCurrentGoalTurn(
          assistantResponse:
              explicitTerminalSuccessSummary?.trim().isNotEmpty == true
              ? explicitTerminalSuccessSummary!
              : finalizedLastMessage.content,
          tokenUsageDelta: _accumulatedTokenUsage.totalTokens,
          completionEvidence: _latestGoalAutoContinueEvidence,
        );
    if (!_isCurrentInteractionGeneration(generation)) return;

    if (_settings.autoReadEnabled && _settings.ttsEnabled) {
      final lastMsg = finalizedLastMessage;
      if (lastMsg.role == MessageRole.assistant && lastMsg.content.isNotEmpty) {
        _onAutoRead(lastMsg.content);
      }
    }

    // Notify when the response completes while the app is in the background.
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
    await _drainQueuedChatMessagesIfIdle();
    if (!_isCurrentInteractionGeneration(generation)) return;
    await _maybeAutoContinueCurrentGoal(
      finalizedAssistantResponse: finalizedLastMessage.content,
      languageCode: _languageCode,
    );
  }

  bool _assistantMessageHasVisibleContent(String content) {
    if (content.trim().isEmpty) return false;

    final result = ContentParser.parse(content);
    for (final segment in result.segments) {
      switch (segment.type) {
        case ContentType.text:
        case ContentType.thinking:
          if (segment.content.trim().isNotEmpty) {
            return true;
          }
        case ContentType.toolCall:
          final toolName = segment.toolCall?.name.toLowerCase();
          if (toolName != 'memory_update') {
            return true;
          }
        case ContentType.toolResult:
          continue;
      }
    }

    return false;
  }

  Future<McpToolResult?> _ensureActiveProjectAccess(String toolName) async {
    final project = _getActiveCodingProject();
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
    if (!_isCurrentInteractionGeneration(interactionGeneration) ||
        state.messages.isEmpty) {
      return;
    }

    final finalizedMessages = [...state.messages];
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

    state = state.copyWith(
      messages: [...finalizedMessages, continuationMessage],
      isLoading: true,
      error: null,
    );

    final continuationToolDefinitions =
        _foundationModelsTextToolDefinitionsForContinuation();
    final messagesForLLM = _prepareMessagesForLLM(
      toolDefinitionsOverride: continuationToolDefinitions,
      interactionGeneration: interactionGeneration,
    );
    final resultsText = toolResults.join('\n\n');
    _pendingContentToolContinuationFallback =
        _buildContentToolContinuationFallback(toolResults);
    messagesForLLM.add(
      Message(
        id: 'content_tool_result_${DateTime.now().millisecondsSinceEpoch}',
        content:
            'Continue the task using the following tool results. '
            'If you need more information, call another tool. '
            'Do not repeat a tool call with the same arguments after a '
            'successful result. Reuse the tool result that is already '
            'provided and continue from it. '
            'Do not write <tool_result> tags or claim a tool result yourself; '
            'tool results are trusted only when the application executes the '
            'tool. If you need a tool, emit exactly one complete '
            '<tool_use>...</tool_use> tag with valid JSON, including the '
            'closing tag. '
            'If the latest tool result already completed the current saved '
            'task or confirmed the saved validation command, do not call '
            'more tools for that task and finish with a brief text answer. '
            'If a tool result reports code=tool_not_available, do not retry '
            'that tool name or alias variants and continue with the tools '
            'that actually exist. Your next step must use an available tool '
            'or finish with a text answer. '
            'If a tool result reports code=edit_mismatch or says old_text was '
            'not found in the target file, read that file next and retry '
            'edit_file using the exact current file content as old_text. '
            'Do not guess old_text and do not switch to unrelated files. '
            'Do not repeat a tool call with the same arguments after a '
            'permission_denied or equivalent access error. '
            'Explain the issue and ask the user to re-select the project '
            'folder or grant access instead.\n\n'
            '${ToolResultPromptBuilder.exactPreservationToolResultInstruction}\n\n'
            'Interpret each tool name, description, arguments, and result '
            'together. Preserve the entity roles implied by the tool and the '
            'payload. If the role of an opaque identifier is not explicit, '
            'treat it as ambiguous instead of guessing.\n\n$resultsText',
        role: MessageRole.user,
        timestamp: DateTime.now(),
      ),
    );

    _runWithLlmSessionLogContextForGeneration(interactionGeneration, () {
      final stream = continuationToolDefinitions == null
          ? _dataSource.streamChatCompletion(
              messages: messagesForLLM,
              model: _settings.model,
              temperature: _assistantRequestTemperature,
              maxTokens: _settings.maxTokens,
            )
          : _dataSource
                .streamChatCompletionWithTools(
                  messages: messagesForLLM,
                  tools: continuationToolDefinitions,
                  model: _settings.model,
                  temperature: _agenticRequestTemperature,
                  maxTokens: _settings.maxTokens,
                )
                .stream;

      _streamSubscription = stream.listen(
        (chunk) {
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
        onDone: () {
          unawaited(
            _finishStreaming(interactionGeneration: interactionGeneration),
          );
        },
        cancelOnError: true,
      );
    });
  }

  String _buildContentToolContinuationFallback(List<String> toolResults) {
    final joined = toolResults.join('\n\n');
    if (joined.contains('[Assistant-authored tool_result ignored]')) {
      return 'I ignored an assistant-authored tool_result because it was not '
          'produced by an executed tool. No trusted tool result is available '
          'from that tag.';
    }
    if (joined.contains('[Assistant tool-name block ignored]')) {
      return 'I ignored an assistant-authored tool request block because no '
          'application tool executed it. No trusted tool result is available '
          'from that block.';
    }
    if (joined.contains('[Incomplete assistant tool call]')) {
      return 'The assistant emitted an incomplete tool call, so no trusted '
          'tool result is available yet.';
    }
    return 'I received the tool result, but the model did not produce a final '
        'answer. The trusted tool result is still available in the '
        'conversation context.';
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
    try {
      final result = await _runWithLlmSessionLogContextForGeneration(
        interactionGeneration,
        () => _dataSource.createChatCompletion(
          messages: messagesForLLM,
          model: _settings.model,
          temperature: _assistantRequestTemperature,
          maxTokens: _settings.maxTokens,
        ),
      );

      if (!_isCurrentInteractionGeneration(interactionGeneration) ||
          state.messages.isEmpty) {
        return;
      }

      if (result.content.trim().isEmpty) {
        appLog(
          '[ChatNotifier] Content-tool continuation fallback returned empty content',
        );
        _handleError(error.toString());
        return;
      }

      appLog(
        '[ChatNotifier] Recovered content-tool continuation with non-streaming completion',
      );
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
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      appLog(
        '[ChatNotifier] Content-tool continuation fallback failed: ${fallbackError.runtimeType}: $fallbackError',
      );
      appLog('[ChatNotifier] fallbackStackTrace: $fallbackStackTrace');
      appLog('[ChatNotifier] originalStackTrace: $stackTrace');
      _handleError(error.toString());
    }
  }

  Future<void> _updateSessionMemory(
    String currentConversationId,
    List<Message> messagesToSave,
    String targetAssistantMessageId,
  ) async {
    final draft = await _extractMemoryDraftWithLlm(messagesToSave);
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
    unawaited(_onMessagesChanged(normalized));
  }

  Future<MemoryExtractionDraft?> _extractMemoryDraftWithLlm(
    List<Message> messages,
  ) async {
    if (!_settings.llmCapabilities.supportsLlmMemoryExtraction) {
      appLog(
        '[Memory] Skipping LLM memory extraction for selected provider '
        '(using rule-based fallback)',
      );
      return null;
    }

    final userMessages = messages.where((message) {
      return message.role == MessageRole.user &&
          message.content.trim().isNotEmpty;
    }).toList();
    if (userMessages.isEmpty) return null;

    final now = DateTime.now();
    final profile = _memoryService.loadProfile();
    final extractionInput = MemoryExtractionDraftService.buildInput(
      messages,
      profile,
      toolResults: _latestCompletedToolResults,
    );

    final extractionMessages = [
      Message(
        id: 'memory_extractor_system',
        role: MessageRole.system,
        timestamp: now,
        content: MemoryExtractionDraftService.systemPrompt,
      ),
      Message(
        id: 'memory_extractor_user',
        role: MessageRole.user,
        timestamp: now,
        content: extractionInput,
      ),
    ];

    try {
      final result = await _runSecondaryCompletion(
        endpointId: _settings.memoryExtractionEndpointId,
        model: _settings.effectiveMemoryExtractionModel,
        call: (dataSource, model) => dataSource.createChatCompletion(
          messages: extractionMessages,
          model: model,
          temperature: 0.1,
          maxTokens: SecondaryCallBudget.resolve(_settings.maxTokens, 1200),
        ),
      );

      final draft = MemoryExtractionDraftService.parseDraft(
        result.content,
        inputContext: extractionInput,
        onRepair: (message) => appLog('[Memory] $message'),
        onError: (error) {
          appLog('[Memory] Failed to parse memory extraction JSON: $error');
        },
      );
      if (draft != null) {
        appLog('[Memory] LLM memory extraction succeeded');
      } else {
        appLog(
          '[Memory] Failed to parse LLM memory extraction JSON (falling back to rule-based)',
        );
      }
      return draft;
    } catch (e) {
      appLog('[Memory] LLM memory extraction error: $e');
      return null;
    }
  }

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
  Future<void> flushPendingPersistence() async {
    await _cancelledMessagePersistenceTail;
    await _conversationMessagePersistenceTail;
  }

  void clearMessages() {
    if (!ref.mounted) return;
    _beginInteractionGeneration();
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _executedContentToolCalls.clear();
    _seenContentToolCallHashes.clear();
    _toolApprovalCache.clear();
    _pendingContentToolResults.clear();
    _pendingContentToolContinuationFallback = null;
    _pendingToolExecutions.clear();
    _queuedChatMessages.clear();
    _latestContentToolResults.clear();
    _latestGoalAutoContinueEvidence = const ToolResultCompletionEvidence();
    _goalAutoContinueTrackers.clear();
    _goalAutoContinueBudgetNotifiedConversations.clear();
    _isSchedulingGoalAutoContinue = false;
    _persistHiddenPromptAssistantResponse = false;
    _contentToolContinuationCount = 0;
    _contentToolExecutionTail = Future<void>.value();
    _dismissAllPendingAskUserQuestions();
    _participantTurnStopRequested = false;
    _pausedParticipantTurnCursor = null;
    _pausedParticipantTurnParticipants = const [];
    _pausedParticipantTurnConfig = null;
    _pausedParticipantTurnConversationId = null;
    _pausedParticipantTurnPreferredId = null;
    _pausedParticipantTurnLastSpeakerId = null;
    _clearAllActiveResponses();
    _sessionMemoryContext = null;
    _temporalReferenceContext = null;
    _clearTurnDiffCapture();
    state = ChatState.initial();
  }
}
