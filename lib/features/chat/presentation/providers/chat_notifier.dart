import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/agents_md_loader.dart';
import '../../../../core/services/ble_service.dart';
import '../../../../core/services/macos_computer_use_audit_log.dart';
import '../../../../core/services/macos_computer_use_tool_policy.dart';
import '../../../../core/services/notification_providers.dart';
import '../../../../core/services/ssh_credentials_manager.dart';
import '../../../../core/services/ssh_service.dart';
import '../../../../core/services/voice_providers.dart';
import '../../../../core/types/assistant_mode.dart';
import '../../../../core/types/workspace_mode.dart';
import '../../../../core/utils/content_parser.dart';
import '../../../../core/utils/logger.dart';
import '../../data/repositories/chat_memory_repository.dart';
import '../../data/repositories/tool_result_artifact_store.dart';
import '../../domain/services/conversation_goal_suggestion_service.dart';
import '../../domain/services/conversation_plan_document_builder.dart';
import '../../domain/services/conversation_planning_prompt_service.dart';
import '../../domain/services/system_prompt_builder.dart';
import '../../domain/services/session_memory_service.dart';
import '../../domain/services/skill_prompt_index_builder.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/chat_datasource.dart';
import '../../data/datasources/chat_remote_datasource.dart';
import '../../data/datasources/demo_datasource.dart';
import '../../data/datasources/filesystem_tools.dart';
import '../../data/datasources/git_tools.dart';
import '../../data/datasources/local_shell_tools.dart';
import '../../data/datasources/mcp_tool_service.dart';
import '../../data/datasources/llm_session_log_store.dart';
import '../../data/datasources/session_logging_chat_datasource.dart';
import '../../domain/entities/coding_project.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_compaction_artifact.dart';
import '../../domain/entities/conversation_plan_artifact.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/skill.dart';
import '../../domain/entities/turn_diff.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../../domain/services/conversation_compaction_service.dart';
import '../../domain/services/coding_approval_auto_review_service.dart';
import '../../domain/services/coding_command_output_guardrail_service.dart';
import '../../domain/services/coding_diagnostic_feedback_service.dart';
import '../../domain/services/coding_verification_feedback_service.dart';
import '../../domain/services/conversation_plan_execution_coordinator.dart';
import '../../domain/services/dart_project_tooling.dart';
import '../../domain/services/memory_extraction_draft_service.dart';
import '../../domain/services/temporal_context_builder.dart';
import '../../domain/services/tool_definition_search_service.dart';
import '../../domain/services/tool_execution_scheduler.dart';
import '../../domain/services/tool_result_prompt_builder.dart';
import '../../domain/services/turn_diff_service.dart';
import '../../../settings/domain/services/local_command_permission_service.dart';
import 'chat_state.dart';
import 'coding_projects_notifier.dart';
import 'conversations_notifier.dart';
import 'macos_computer_use_approval_copy.dart';
import 'mcp_tool_provider.dart';
import 'skills_notifier.dart';
import 'tool_approval_cache.dart';

part 'chat_notifier_ble_handlers.dart';
part 'chat_notifier_computer_use_handlers.dart';
part 'chat_notifier_git_handlers.dart';
part 'chat_notifier_local_file_handlers.dart';
part 'chat_notifier_ssh_handlers.dart';

final chatRemoteDataSourceProvider = Provider<ChatDataSource>((ref) {
  final settings = ref.watch(settingsNotifierProvider);
  if (settings.demoMode) {
    return DemoDataSource();
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

final codingDiagnosticFeedbackServiceProvider =
    Provider<CodingDiagnosticFeedbackService>((ref) {
      return CodingDiagnosticFeedbackService();
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

sealed class _WorkflowProposalResponse {
  const _WorkflowProposalResponse();
}

final class _WorkflowProposalDraftResponse extends _WorkflowProposalResponse {
  const _WorkflowProposalDraftResponse(this.proposal);

  final WorkflowProposalDraft proposal;
}

final class _WorkflowProposalDecisionResponse
    extends _WorkflowProposalResponse {
  const _WorkflowProposalDecisionResponse(this.decisions);

  final List<WorkflowPlanningDecision> decisions;
}

final class _WorkflowProposalCancelled implements Exception {
  const _WorkflowProposalCancelled();

  @override
  String toString() => 'workflow proposal generation was cancelled';
}

final class _PlanningResearchFileNote {
  const _PlanningResearchFileNote({
    required this.path,
    required this.highlights,
  });

  final String path;
  final List<String> highlights;
}

final class _PlanningResearchContext {
  const _PlanningResearchContext({
    this.rootEntries = const <String>[],
    this.keyFiles = const <String>[],
    this.matchedLines = const <String>[],
    this.fileNotes = const <_PlanningResearchFileNote>[],
    this.risks = const <String>[],
  });

  final List<String> rootEntries;
  final List<String> keyFiles;
  final List<String> matchedLines;
  final List<_PlanningResearchFileNote> fileNotes;
  final List<String> risks;

  bool get hasContent {
    return rootEntries.isNotEmpty ||
        keyFiles.isNotEmpty ||
        matchedLines.isNotEmpty ||
        fileNotes.isNotEmpty ||
        risks.isNotEmpty;
  }

  String toPromptBlock() {
    final buffer = StringBuffer();

    if (rootEntries.isNotEmpty) {
      buffer.writeln('Project root snapshot:');
      for (final entry in rootEntries) {
        buffer.writeln('- $entry');
      }
    }

    if (keyFiles.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('Relevant files discovered:');
      for (final path in keyFiles) {
        buffer.writeln('- $path');
      }
    }

    if (matchedLines.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('Relevant code or text matches:');
      for (final line in matchedLines) {
        buffer.writeln('- $line');
      }
    }

    if (fileNotes.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('File highlights:');
      for (final note in fileNotes) {
        buffer.writeln('- ${note.path}');
        for (final highlight in note.highlights) {
          buffer.writeln('  $highlight');
        }
      }
    }

    if (risks.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('Research risks:');
      for (final risk in risks) {
        buffer.writeln('- $risk');
      }
    }

    return buffer.toString().trimRight();
  }
}

class ChatNotifier extends Notifier<ChatState> {
  late ChatDataSource _dataSource;
  McpToolService? _mcpToolService;
  late SessionMemoryService _memoryService;
  late AppSettings _settings;
  late CodingDiagnosticFeedbackService _codingDiagnosticFeedbackService;
  late CodingVerificationFeedbackService _codingVerificationFeedbackService;
  String? conversationId;
  String _languageCode = 'en';
  String? _sessionMemoryContext;
  String? _temporalReferenceContext;
  Message? _hiddenPrompt;
  bool _isVoiceMode = false;
  TokenUsage _accumulatedTokenUsage = TokenUsage.zero;
  AssistantMode? _assistantModeOverride;
  List<ToolResultInfo> _latestCompletedToolResults = const [];
  final List<ToolResultInfo> _latestContentToolResults = [];
  final List<TurnDiffFile> _pendingTurnDiffFiles = [];
  late ToolResultArtifactStore _toolResultArtifactStore;
  String? _latestHiddenAssistantResponse;
  String? _activeTurnUserPrompt;
  DateTime? _activeTurnStartedAt;
  static const Set<String> _planningResearchStopWords = {
    'about',
    'after',
    'before',
    'build',
    'coding',
    'current',
    'feature',
    'first',
    'generate',
    'implementation',
    'implement',
    'mode',
    'next',
    'project',
    'proposal',
    'review',
    'saved',
    'should',
    'slice',
    'start',
    'task',
    'tasks',
    'that',
    'them',
    'there',
    'these',
    'this',
    'thread',
    'update',
    'using',
    'workflow',
    'would',
  };
  static const int _maxRepeatedCodingVerificationRepairAttempts = 2;

  @override
  ChatState build() {
    _settings = ref.read(settingsNotifierProvider);
    _dataSource = _withChatSessionLogging(
      ref.read(chatRemoteDataSourceProvider),
      _settings,
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

    // Connect MCP tool service.
    _mcpToolService?.connect();

    // Load initial messages from the currently selected conversation.
    final conversationsState = ref.read(conversationsNotifierProvider);
    final initialMessages =
        conversationsState.currentConversation?.messages ?? const <Message>[];
    conversationId = conversationsState.currentConversation?.id;

    // React to settings changes.
    ref.listen<AppSettings>(settingsNotifierProvider, (previous, next) {
      updateConnectionSettings(next);
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
    return ref
        .read(conversationsNotifierProvider.notifier)
        .updateCurrentConversation(messages);
  }

  Future<void> _onConversationMessagesChanged(
    String conversationId,
    List<Message> messages,
  ) {
    return ref
        .read(conversationsNotifierProvider.notifier)
        .updateConversationMessages(conversationId, messages);
  }

  void _persistCurrentNonStreamingMessages() {
    final messagesToSave = state.messages
        .where((message) => !message.isStreaming)
        .map(_sanitizeMessageForModelHistory)
        .where(_shouldKeepMessageForModelHistory)
        .toList(growable: false);
    unawaited(_onMessagesChanged(messagesToSave));
  }

  /// Speaks the assistant response via TTS when auto-read is enabled.
  /// Replaces the previous `onAutoRead` callback.
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
    ref.read(backgroundTaskServiceProvider).beginBackgroundTask();
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

  void updateConnectionSettings(AppSettings settings) {
    _settings = settings;
    _dataSource = _withChatSessionLogging(
      _buildChatDataSource(settings),
      settings,
    );
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

  ChatDataSource _buildChatDataSource(AppSettings settings) {
    if (settings.demoMode) {
      return DemoDataSource();
    }

    return ChatRemoteDataSource(
      baseUrl: settings.baseUrl,
      apiKey: settings.apiKey,
      reasoningEffort: settings.reasoningEffort.apiValue,
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
      _pendingContentToolResults.clear();
      _pendingToolExecutions.clear();
      if (!sameConversation) {
        _queuedChatMessages.clear();
        _latestContentToolResults.clear();
        _latestCompletedToolResults = const [];
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

  /// Builds the system message, including the current date and time.
  Message _createSystemMessage({List<String>? toolNamesOverride}) {
    final now = DateTime.now();
    final activeCodingProject = _getActiveCodingProject();
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    final toolNames = toolNamesOverride == null
        ? <String>[]
        : List<String>.from(toolNamesOverride);
    final mcpToolService = _mcpToolService;
    if (toolNamesOverride == null &&
        mcpToolService != null &&
        (_settings.mcpEnabled || _temporalReferenceContext != null)) {
      for (final tool in mcpToolService.getOpenAiToolDefinitions()) {
        final function = tool['function'];
        if (function is Map) {
          final name = function['name'];
          if (name is String && name.isNotEmpty) {
            toolNames.add(name);
          }
        }
      }
    }

    final resolvedLanguage = _settings.language == 'system'
        ? _languageCode
        : _settings.language;
    final resolvedAssistantMode = _resolveAssistantMode(
      currentConversation: currentConversation,
    );
    final agentsMarkdown =
        (_settings.enableAgentsMd &&
            resolvedAssistantMode != AssistantMode.general)
        ? ref
              .read(agentsMdLoaderProvider)
              .loadForProject(activeCodingProject?.rootPath)
        : null;

    return Message(
      id: 'system',
      content: SystemPromptBuilder.build(
        now: now,
        assistantMode: resolvedAssistantMode,
        languageCode: resolvedLanguage,
        toolNames: toolNames,
        sessionMemoryContext: _sessionMemoryContext,
        projectName: activeCodingProject?.name,
        projectRootPath: activeCodingProject?.rootPath,
        goal: currentConversation?.goal,
        workflowStage:
            currentConversation?.workflowStage ??
            ConversationWorkflowStage.idle,
        workflowSpec: currentConversation?.workflowSpec,
        planArtifact: currentConversation?.planArtifact,
        isVoiceMode: _isVoiceMode,
        agentsMarkdown: agentsMarkdown,
        skillsContext: _buildSkillsPromptContext(toolNames),
      ),
      role: MessageRole.system,
      timestamp: now,
    );
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
    return _getActiveCodingProject()?.rootPath.trim();
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

  Future<_PlanningResearchContext> _buildPlanningResearchContext({
    required Conversation currentConversation,
    ConversationWorkflowStage? workflowStageOverride,
    ConversationWorkflowSpec? workflowSpecOverride,
  }) async {
    final toolService = _mcpToolService;
    final projectRoot = _getActiveProjectRootPath();
    if (toolService == null ||
        currentConversation.workspaceMode != WorkspaceMode.coding ||
        projectRoot == null ||
        projectRoot.isEmpty) {
      return const _PlanningResearchContext();
    }

    appLog('[Workflow] Planning research pass started');

    final rootEntries = await _collectPlanningResearchRootEntries();
    final manifestFiles = await _collectPlanningResearchImportantFiles();
    final queryTerms = _buildPlanningResearchQueries(
      currentConversation: currentConversation,
      workflowStageOverride: workflowStageOverride,
      workflowSpecOverride: workflowSpecOverride,
    );
    final matchedFiles = await _collectPlanningResearchNamedMatches(queryTerms);
    final matchedLines = await _collectPlanningResearchTextMatches(queryTerms);

    final candidatePaths = <String>[
      ...manifestFiles,
      ...matchedFiles,
      ...matchedLines
          .map(_extractPlanningResearchPathFromMatch)
          .whereType<String>(),
    ].where((path) => path.trim().isNotEmpty).toSet().toList(growable: false);

    final fileNotes = await _collectPlanningResearchFileNotes(
      candidatePaths: candidatePaths,
      queryTerms: queryTerms,
    );
    final risks = _buildPlanningResearchRisks(
      rootEntries: rootEntries,
      keyFiles: manifestFiles,
      matchedFiles: matchedFiles,
      matchedLines: matchedLines,
      fileNotes: fileNotes,
      queryTerms: queryTerms,
    );

    final context = _PlanningResearchContext(
      rootEntries: rootEntries,
      keyFiles: {
        ...manifestFiles,
        ...matchedFiles,
      }.take(6).toList(growable: false),
      matchedLines: matchedLines.take(6).toList(growable: false),
      fileNotes: fileNotes.take(3).toList(growable: false),
      risks: risks.take(3).toList(growable: false),
    );

    if (!context.hasContent) {
      appLog('[Workflow] Planning research pass found no grounded context');
    } else {
      appLog(
        '[Workflow] Planning research pass collected '
        '${context.keyFiles.length} file(s), '
        '${context.matchedLines.length} match(es), '
        '${context.fileNotes.length} note(s)',
      );
    }

    return context;
  }

  Future<List<String>> _collectPlanningResearchRootEntries() async {
    final decoded = await _runPlanningResearchTool(
      name: 'list_directory',
      arguments: const {'path': '', 'recursive': false},
    );
    final entries = decoded?['entries'];
    if (entries is! List) {
      return const <String>[];
    }
    return entries
        .whereType<String>()
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .take(8)
        .toList(growable: false);
  }

  Future<List<String>> _collectPlanningResearchImportantFiles() async {
    const patterns = <String>[
      'pubspec.yaml',
      'README*',
      'analysis_options.yaml',
      'package.json',
      'Cargo.toml',
      'pyproject.toml',
      'requirements*.txt',
    ];
    final matches = <String>{};

    for (final pattern in patterns) {
      final decoded = await _runPlanningResearchTool(
        name: 'find_files',
        arguments: {'path': '', 'pattern': pattern, 'recursive': false},
      );
      final rawMatches = decoded?['matches'];
      if (rawMatches is! List) {
        continue;
      }
      for (final match in rawMatches.whereType<String>()) {
        if (matches.length >= 4) {
          break;
        }
        final trimmed = match.trim();
        if (trimmed.isNotEmpty) {
          matches.add(trimmed);
        }
      }
      if (matches.length >= 4) {
        break;
      }
    }

    return matches.toList(growable: false);
  }

  List<String> _buildPlanningResearchQueries({
    required Conversation currentConversation,
    ConversationWorkflowStage? workflowStageOverride,
    ConversationWorkflowSpec? workflowSpecOverride,
  }) {
    final workflowSpec =
        workflowSpecOverride ?? currentConversation.effectiveWorkflowSpec;
    final seedTexts = <String>[
      ...currentConversation.messages.reversed
          .where((message) => message.role == MessageRole.user)
          .map((message) => _extractPlainTextForProposal(message.content))
          .where((text) => text.isNotEmpty)
          .take(2),
      workflowSpec.goal,
      ...workflowSpec.acceptanceCriteria.take(1),
      ...workflowSpec.openQuestions.take(2),
      if (workflowStageOverride != null) workflowStageOverride.name,
    ];

    final phraseQueries = <String>[];
    final keywordQueries = <String>[];
    final seen = <String>{};

    for (final seed in seedTexts) {
      final words = seed
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9_/\\ -]'), ' ')
          .split(RegExp(r'\s+'))
          .map((word) => word.trim())
          .where(
            (word) =>
                word.length >= 4 &&
                !_planningResearchStopWords.contains(word) &&
                !RegExp(r'^\d+$').hasMatch(word),
          )
          .toList(growable: false);

      for (var index = 0; index < words.length - 1; index++) {
        if (phraseQueries.length >= 2) {
          break;
        }
        final phrase = '${words[index]} ${words[index + 1]}';
        if (seen.add(phrase)) {
          phraseQueries.add(phrase);
        }
      }

      for (final word in words) {
        if (keywordQueries.length >= 4) {
          break;
        }
        if (seen.add(word)) {
          keywordQueries.add(word);
        }
      }

      if (phraseQueries.length >= 2 && keywordQueries.length >= 4) {
        break;
      }
    }

    return [
      ...phraseQueries,
      ...keywordQueries,
    ].take(4).toList(growable: false);
  }

  Future<List<String>> _collectPlanningResearchNamedMatches(
    List<String> queryTerms,
  ) async {
    final matches = <String>{};
    for (final term in queryTerms) {
      if (term.contains(' ') || term.length < 5) {
        continue;
      }
      final decoded = await _runPlanningResearchTool(
        name: 'find_files',
        arguments: {'path': '', 'pattern': '*$term*', 'recursive': true},
      );
      final rawMatches = decoded?['matches'];
      if (rawMatches is! List) {
        continue;
      }
      for (final match in rawMatches.whereType<String>()) {
        if (matches.length >= 4) {
          break;
        }
        final trimmed = match.trim();
        if (trimmed.isNotEmpty) {
          matches.add(trimmed);
        }
      }
      if (matches.length >= 4) {
        break;
      }
    }
    return matches.toList(growable: false);
  }

  Future<List<String>> _collectPlanningResearchTextMatches(
    List<String> queryTerms,
  ) async {
    final matches = <String>{};
    for (final query in queryTerms.take(2)) {
      final decoded = await _runPlanningResearchTool(
        name: 'search_files',
        arguments: {'path': '', 'query': query, 'case_sensitive': false},
      );
      final rawMatches = decoded?['matches'];
      if (rawMatches is! List) {
        continue;
      }
      for (final match in rawMatches.whereType<String>()) {
        if (matches.length >= 6) {
          break;
        }
        final compact = _compactPlanningResearchLine(match);
        if (compact.isNotEmpty) {
          matches.add(compact);
        }
      }
      if (matches.length >= 6) {
        break;
      }
    }
    return matches.toList(growable: false);
  }

  Future<List<_PlanningResearchFileNote>> _collectPlanningResearchFileNotes({
    required List<String> candidatePaths,
    required List<String> queryTerms,
  }) async {
    final notes = <_PlanningResearchFileNote>[];
    for (final path in candidatePaths.take(3)) {
      final decoded = await _runPlanningResearchTool(
        name: 'read_file',
        arguments: {'path': path},
      );
      final content = (decoded?['content'] as String?)?.trim();
      if (content == null || content.isEmpty) {
        continue;
      }
      final highlights = _extractPlanningResearchHighlights(
        content,
        queryTerms: queryTerms,
      );
      if (highlights.isEmpty) {
        continue;
      }
      notes.add(
        _PlanningResearchFileNote(
          path: path,
          highlights: highlights.take(3).toList(growable: false),
        ),
      );
    }
    return notes;
  }

  Future<Map<String, dynamic>?> _runPlanningResearchTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    final toolService = _mcpToolService;
    if (toolService == null) {
      return null;
    }

    final result = await _dispatchToolCall(
      ToolCallInfo(
        id: 'planning_research_${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        arguments: arguments,
      ),
    );

    if (!result.isSuccess || result.result.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(result.result);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      appLog('[Workflow] Planning research tool $name returned non-JSON text');
    }
    return null;
  }

  String _compactPlanningResearchLine(String value, {int maxLength = 140}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 3)}...';
  }

  String? _extractPlanningResearchPathFromMatch(String match) {
    final lineMatch = RegExp(r'^(.+?):\d+:').firstMatch(match.trim());
    final path = lineMatch?.group(1)?.trim();
    if (path == null || path.isEmpty) {
      return null;
    }
    return path;
  }

  List<String> _extractPlanningResearchHighlights(
    String content, {
    required List<String> queryTerms,
  }) {
    final normalizedQueryTerms = queryTerms
        .map((term) => term.toLowerCase())
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    final lines = const LineSplitter()
        .convert(content)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) {
      return const <String>[];
    }

    final highlights = <String>[];
    final seen = <String>{};

    void addLine(String line) {
      final compact = _compactPlanningResearchLine(line, maxLength: 120);
      if (compact.isNotEmpty && seen.add(compact)) {
        highlights.add(compact);
      }
    }

    for (final line in lines) {
      final lowerLine = line.toLowerCase();
      if (normalizedQueryTerms.any(lowerLine.contains)) {
        addLine(line);
      }
      if (highlights.length >= 3) {
        return highlights;
      }
    }

    for (final line in lines) {
      if (RegExp(
            r'^(name|description|dependencies|environment)\s*:',
            caseSensitive: false,
          ).hasMatch(line) ||
          RegExp(
            r'^(class|abstract class|enum|mixin|typedef|extension)\s+',
            caseSensitive: false,
          ).hasMatch(line) ||
          RegExp(
            r'^(void|Future<|Future\s|Widget\s)',
            caseSensitive: false,
          ).hasMatch(line)) {
        addLine(line);
      }
      if (highlights.length >= 3) {
        return highlights;
      }
    }

    for (final line in lines) {
      if (line.startsWith('//') ||
          line.startsWith('/*') ||
          line.startsWith('*')) {
        continue;
      }
      addLine(line);
      if (highlights.length >= 3) {
        return highlights;
      }
    }

    return highlights;
  }

  List<String> _buildPlanningResearchRisks({
    required List<String> rootEntries,
    required List<String> keyFiles,
    required List<String> matchedFiles,
    required List<String> matchedLines,
    required List<_PlanningResearchFileNote> fileNotes,
    required List<String> queryTerms,
  }) {
    final risks = <String>[];

    if (rootEntries.isEmpty) {
      risks.add(
        'The selected project root looked empty during planning, so the first slice may need a new scaffold.',
      );
    }

    if (queryTerms.isNotEmpty &&
        matchedFiles.isEmpty &&
        matchedLines.isEmpty &&
        fileNotes.isEmpty) {
      risks.add(
        'No existing files matched the main request keywords, so the plan may rely on net-new files or inferred architecture.',
      );
    }

    if (keyFiles.isEmpty) {
      risks.add(
        'No common manifest or README was found at the project root, so setup and validation commands may need manual verification.',
      );
    }

    return risks;
  }

  List<Message> _buildWorkflowProposalMessages({
    required Conversation currentConversation,
    required String languageCode,
    _PlanningResearchContext researchContext = const _PlanningResearchContext(),
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
    _PlanningResearchContext researchContext = const _PlanningResearchContext(),
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
    _PlanningResearchContext researchContext = const _PlanningResearchContext(),
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

      if (result case _WorkflowProposalDraftResponse(:final proposal)) {
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

      if (result case _WorkflowProposalDecisionResponse(:final decisions)) {
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

  WorkflowProposalDraft _removeAnsweredOpenQuestions(
    WorkflowProposalDraft proposal,
    List<WorkflowPlanningDecisionAnswer> decisionAnswers,
  ) {
    if (decisionAnswers.isEmpty ||
        proposal.workflowSpec.openQuestions.isEmpty) {
      return proposal;
    }

    final answeredQuestions = decisionAnswers
        .map((answer) => _normalizeWorkflowDecisionText(answer.question))
        .where((value) => value.isNotEmpty)
        .toSet();
    if (answeredQuestions.isEmpty) {
      return proposal;
    }

    final remainingOpenQuestions = proposal.workflowSpec.openQuestions
        .where(
          (question) => !answeredQuestions.contains(
            _normalizeWorkflowDecisionText(question),
          ),
        )
        .toList(growable: false);
    if (remainingOpenQuestions.length ==
        proposal.workflowSpec.openQuestions.length) {
      return proposal;
    }

    return WorkflowProposalDraft(
      workflowStage: proposal.workflowStage,
      workflowSpec: proposal.workflowSpec.copyWith(
        openQuestions: remainingOpenQuestions,
      ),
    );
  }

  List<WorkflowPlanningDecision> _promoteChoiceLikeOpenQuestions(
    List<String> openQuestions, {
    required List<WorkflowPlanningDecisionAnswer> decisionAnswers,
  }) {
    if (openQuestions.isEmpty) {
      return const <WorkflowPlanningDecision>[];
    }

    final answeredQuestions = decisionAnswers
        .map((answer) => _normalizeWorkflowDecisionText(answer.question))
        .where((value) => value.isNotEmpty)
        .toSet();
    final decisions = <WorkflowPlanningDecision>[];

    for (final question in openQuestions.take(3)) {
      final normalizedQuestion = _normalizeWorkflowDecisionText(question);
      if (normalizedQuestion.isEmpty ||
          answeredQuestions.contains(normalizedQuestion)) {
        continue;
      }

      final decision =
          _buildOrderedChoiceDecisionFromOpenQuestion(question) ??
          _buildAlternativeChoiceDecisionFromOpenQuestion(question) ??
          _buildYesNoDecisionFromOpenQuestion(question);
      if (decision != null) {
        decisions.add(decision);
      }
    }

    return decisions;
  }

  List<WorkflowPlanningDecision> _promoteOpenQuestionsToPlanningPrompts(
    List<String> openQuestions, {
    required List<WorkflowPlanningDecisionAnswer> decisionAnswers,
  }) {
    if (decisionAnswers.isNotEmpty) {
      return const <WorkflowPlanningDecision>[];
    }
    return _promoteChoiceLikeOpenQuestions(
      openQuestions,
      decisionAnswers: decisionAnswers,
    );
  }

  WorkflowPlanningDecision? _buildOrderedChoiceDecisionFromOpenQuestion(
    String question,
  ) {
    final trimmedQuestion = question.trim();
    if (trimmedQuestion.isEmpty) {
      return null;
    }

    final normalizedQuestion = _normalizeWorkflowDecisionText(trimmedQuestion);
    if (normalizedQuestion.isEmpty) {
      return null;
    }

    final isJapanese = _containsJapaneseText(trimmedQuestion);
    final rawOptions = isJapanese
        ? _extractJapaneseOrderedOptions(trimmedQuestion)
        : _extractEnglishOrderedOptions(trimmedQuestion);
    if (rawOptions.length < 2) {
      return null;
    }

    final options = rawOptions
        .map(_cleanDecisionOptionLabel)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (options.length < 2) {
      return null;
    }

    final normalizedOptions = options
        .map(_normalizeWorkflowDecisionText)
        .where((item) => item.isNotEmpty)
        .toSet();
    if (normalizedOptions.length < 2) {
      return null;
    }

    return WorkflowPlanningDecision(
      id: normalizedQuestion,
      question: trimmedQuestion,
      help: isJapanese
          ? 'この選択は実装の順序を決めます。'
          : 'Choose the implementation order that should guide the plan.',
      options: options
          .map(
            (option) => WorkflowPlanningDecisionOption(
              id: _decisionOptionId(option),
              label: option,
              description: '',
            ),
          )
          .toList(growable: false),
    );
  }

  WorkflowPlanningDecision? _buildAlternativeChoiceDecisionFromOpenQuestion(
    String question,
  ) {
    final trimmedQuestion = question.trim();
    if (trimmedQuestion.isEmpty) {
      return null;
    }

    final normalizedQuestion = _normalizeWorkflowDecisionText(trimmedQuestion);
    if (normalizedQuestion.isEmpty) {
      return null;
    }

    final isJapanese = _containsJapaneseText(trimmedQuestion);
    final rawOptions = isJapanese
        ? _extractJapaneseAlternativeOptions(trimmedQuestion)
        : _extractEnglishAlternativeOptions(trimmedQuestion);
    if (rawOptions.length < 2) {
      return null;
    }

    final options = rawOptions
        .map(_cleanDecisionOptionLabel)
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (options.length < 2) {
      return null;
    }

    final normalizedOptions = options
        .map(_normalizeWorkflowDecisionText)
        .where((item) => item.isNotEmpty)
        .toSet();
    if (normalizedOptions.length < 2) {
      return null;
    }

    return WorkflowPlanningDecision(
      id: normalizedQuestion,
      question: trimmedQuestion,
      help: isJapanese
          ? 'この選択は plan の方向を分けます。'
          : 'Choose the direction that should drive this plan.',
      options: options
          .map(
            (option) => WorkflowPlanningDecisionOption(
              id: _decisionOptionId(option),
              label: option,
              description: '',
            ),
          )
          .toList(growable: false),
    );
  }

  WorkflowPlanningDecision? _buildYesNoDecisionFromOpenQuestion(
    String question,
  ) {
    final trimmedQuestion = question.trim();
    if (trimmedQuestion.isEmpty) {
      return null;
    }

    final normalizedQuestion = _normalizeWorkflowDecisionText(trimmedQuestion);
    if (normalizedQuestion.isEmpty ||
        !_looksLikeYesNoOpenQuestion(trimmedQuestion)) {
      return null;
    }

    final isJapanese = _containsJapaneseText(trimmedQuestion);
    return WorkflowPlanningDecision(
      id: normalizedQuestion,
      question: trimmedQuestion,
      help: isJapanese
          ? 'この判断は plan の進め方に影響します。'
          : 'This choice changes how the plan should proceed.',
      options: [
        WorkflowPlanningDecisionOption(
          id: isJapanese ? 'yes' : 'yes',
          label: isJapanese ? 'はい' : 'Yes',
          description: isJapanese
              ? 'この前提を採用して plan を進めます。'
              : 'Proceed with this assumption in the plan.',
        ),
        WorkflowPlanningDecisionOption(
          id: isJapanese ? 'no' : 'no',
          label: isJapanese ? 'いいえ' : 'No',
          description: isJapanese
              ? 'この前提は採用せず、別の方向で plan を立てます。'
              : 'Do not assume this direction in the plan.',
        ),
      ],
    );
  }

  List<String> _extractEnglishOrderedOptions(String question) {
    final trimmedQuestion = question.trim().replaceFirst(
      RegExp(r'[?.!]+$'),
      '',
    );

    final thenPattern = RegExp(
      r'(.+?\bfirst\b\s*,?\s*then\s+.+?)(?:\s*,?\s*or\s+|\s+or\s+)(.+?\bfirst\b\s*,?\s*then\s+.+)$',
      caseSensitive: false,
    );
    final thenMatch = thenPattern.firstMatch(trimmedQuestion);
    if (thenMatch != null) {
      return [
        thenMatch.group(1)?.trim() ?? '',
        thenMatch.group(2)?.trim() ?? '',
      ];
    }

    final firstOrPattern = RegExp(
      r'(.+?\bfirst\b)(?:\s*,?\s*or\s+|\s+or\s+)(.+?\bfirst\b)$',
      caseSensitive: false,
    );
    final firstOrMatch = firstOrPattern.firstMatch(trimmedQuestion);
    if (firstOrMatch != null) {
      return [
        firstOrMatch.group(1)?.trim() ?? '',
        firstOrMatch.group(2)?.trim() ?? '',
      ];
    }

    return const [];
  }

  List<String> _extractJapaneseOrderedOptions(String question) {
    final trimmedQuestion = question.trim().replaceFirst(
      RegExp(r'[？?！!]+$'),
      '',
    );

    final firstPattern = RegExp(
      r'(.+?(?:先行|先に.+|から始める))(?:\s*(?:または|あるいは|か)\s*)(.+?(?:先行|先に.+|から始める))(?:か|ですか|ますか)?$',
    );
    final firstMatch = firstPattern.firstMatch(trimmedQuestion);
    if (firstMatch != null) {
      return [
        firstMatch.group(1)?.trim() ?? '',
        firstMatch.group(2)?.trim() ?? '',
      ];
    }

    final sequencePattern = RegExp(
      r'(.+?先に.+?そのあと.+?)(?:\s*(?:または|あるいは|か)\s*)(.+?先に.+?そのあと.+?)(?:か|ですか|ますか)?$',
    );
    final sequenceMatch = sequencePattern.firstMatch(trimmedQuestion);
    if (sequenceMatch != null) {
      return [
        sequenceMatch.group(1)?.trim() ?? '',
        sequenceMatch.group(2)?.trim() ?? '',
      ];
    }

    return const [];
  }

  List<String> _extractEnglishAlternativeOptions(String question) {
    final trimmedQuestion = question.trim().replaceFirst(
      RegExp(r'[?.!]+$'),
      '',
    );
    final lowerQuestion = trimmedQuestion.toLowerCase();
    if (lowerQuestion.contains('e.g.') ||
        lowerQuestion.contains('i.e.') ||
        lowerQuestion.contains('for example')) {
      return const [];
    }
    if (!lowerQuestion.contains(' or ') && !lowerQuestion.contains(':')) {
      return const [];
    }

    final colonIndex = trimmedQuestion.indexOf(':');
    if (colonIndex >= 0 && colonIndex < trimmedQuestion.length - 1) {
      final afterColon = trimmedQuestion.substring(colonIndex + 1).trim();
      final colonOptions = _splitEnglishChoiceList(afterColon);
      if (colonOptions.length >= 2) {
        return colonOptions;
      }
    }

    final actionMatch = RegExp(
      r'^(?:should|do we|can we|could we|would we|will we|must we|may we|which(?: one)?(?: should we)?|what(?: should we)?)(?:\s+'
      r'(?:use|build|choose|prefer|ship|target|keep|adopt|start with|focus on|support|make|treat|implement|prioritize))(?:\s+first)?\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmedQuestion);
    if (actionMatch != null) {
      final options = _splitEnglishChoiceList(
        actionMatch.group(1)?.trim() ?? '',
      );
      if (options.length >= 2) {
        return options;
      }
    }

    final genericMatch = RegExp(
      r'^(?:should|do we|can we|could we|would we|will we|must we|may we|which(?: one)?(?: should we)?|what(?: should we)?)(?:\s+prioritize(?:\s+first)?)?\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmedQuestion);
    if (genericMatch != null) {
      final options = _splitEnglishChoiceList(
        _stripEnglishChoicePrefix(genericMatch.group(1)?.trim() ?? ''),
      );
      if (options.length >= 2) {
        return options;
      }
    }

    return const [];
  }

  List<String> _extractJapaneseAlternativeOptions(String question) {
    final trimmedQuestion = question.trim().replaceFirst(
      RegExp(r'[？?！!]+$'),
      '',
    );
    final normalizedQuestion = trimmedQuestion.replaceAll('，', '、');

    final listQuestionMatch = RegExp(
      r'^(.+?)\s+の(?:(?:うち)|(?:なかで)|(?:中で))?(?:どれ|どちら|いずれ)',
    ).firstMatch(normalizedQuestion);
    if (listQuestionMatch != null) {
      final options = _splitJapaneseChoiceList(
        listQuestionMatch.group(1) ?? '',
      );
      if (options.length >= 2) {
        return options;
      }
    }

    final eitherMatch = RegExp(
      r'^(.+?)\s*(?:または|あるいは)\s*(.+?)(?:\s*(?:を|の|で))?(?:使いますか|採用しますか|選びますか|選択しますか|優先しますか|にしますか|にするべきですか|にすべきですか|でしょうか|ですか|ますか)?$',
    ).firstMatch(normalizedQuestion);
    if (eitherMatch != null) {
      return [
        eitherMatch.group(1)?.trim() ?? '',
        eitherMatch.group(2)?.trim() ?? '',
      ];
    }

    final whichMatch = RegExp(
      r'^(.+?)\s+と\s+(.+?)\s+のどちら',
    ).firstMatch(normalizedQuestion);
    if (whichMatch != null) {
      return [
        whichMatch.group(1)?.trim() ?? '',
        whichMatch.group(2)?.trim() ?? '',
      ];
    }

    final altKaMatch = RegExp(
      r'^(.+?)\s+か\s+(.+?)\s+か(?:\s*(?:を|の|で))?(?:選びますか|選択しますか|優先しますか|にしますか|でしょうか|ですか|ますか)?$',
    ).firstMatch(normalizedQuestion);
    if (altKaMatch != null) {
      return [
        altKaMatch.group(1)?.trim() ?? '',
        altKaMatch.group(2)?.trim() ?? '',
      ];
    }

    return const [];
  }

  List<String> _splitEnglishChoiceList(String value) {
    final normalized = value
        .trim()
        .replaceAllMapped(
          RegExp(r'\s*,\s*(?:or|and)\s+', caseSensitive: false),
          (_) => ',',
        )
        .replaceAllMapped(
          RegExp(r'\s+(?:or|and)\s+', caseSensitive: false),
          (_) => ',',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty || !normalized.contains(',')) {
      return const [];
    }

    return normalized
        .split(',')
        .map((item) => item.trim())
        .map(_stripEnglishChoicePrefix)
        .map(_stripChoiceSuffix)
        .where((item) => item.isNotEmpty)
        .take(4)
        .toList(growable: false);
  }

  List<String> _splitJapaneseChoiceList(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty) {
      return const [];
    }

    normalized = normalized
        .replaceAll(RegExp(r'\s*(?:または|あるいは)\s*'), '、')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    normalized = normalized.replaceAll(' と ', '、');
    normalized = normalized.replaceAll('か ', '、');

    if (!normalized.contains('、')) {
      return const [];
    }

    return normalized
        .split('、')
        .map((item) => item.trim())
        .map(_stripJapaneseChoicePrefix)
        .map(_stripChoiceSuffix)
        .where((item) => item.isNotEmpty)
        .take(4)
        .toList(growable: false);
  }

  String _stripEnglishChoicePrefix(String value) {
    return value
        .replaceFirst(
          RegExp(
            r'^(?:we|this|the plan|the workflow|the implementation|it)\s+'
            r'(?:use|build|choose|prefer|ship|target|keep|adopt|support|make|treat|implement|do|start|handle|tackle|prioritize)\s+',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  String _stripJapaneseChoicePrefix(String value) {
    return value
        .replaceFirst(RegExp(r'^(?:まず|先に|優先して|今回は|この段階では)\s*'), '')
        .trim();
  }

  String _stripChoiceSuffix(String value) {
    return value
        .trim()
        .replaceFirst(
          RegExp(
            r'\s+(?:first|initially|to start|to begin with)$',
            caseSensitive: false,
          ),
          '',
        )
        .replaceFirst(RegExp(r'(?:を)?(?:先に|優先|優先して)$'), '')
        .trim();
  }

  String _cleanDecisionOptionLabel(String value) {
    return _stripJapaneseChoicePrefix(
      _stripEnglishChoicePrefix(
        value
            .trim()
            .replaceFirst(RegExp(r'^(?:the|a|an)\s+', caseSensitive: false), '')
            .replaceFirst(RegExp(r'[?？!！]+$'), '')
            .replaceFirst(
              RegExp(
                r'^(?:should|do we|can we|could we|would we|will we|must we|may we|which(?: one)?(?: should we)?|what(?: should we)?)(?:\s+should we)?\s+',
                caseSensitive: false,
              ),
              '',
            )
            .trim(),
      ),
    ).trim();
  }

  String _decisionOptionId(String label) {
    return _normalizeWorkflowDecisionText(label).replaceAll(' ', '-');
  }

  bool _looksLikeYesNoOpenQuestion(String question) {
    final trimmedQuestion = question.trim();
    if (trimmedQuestion.isEmpty) {
      return false;
    }

    final normalizedQuestion = trimmedQuestion.toLowerCase();
    if (normalizedQuestion.contains(' or ') ||
        trimmedQuestion.contains('または') ||
        trimmedQuestion.contains('あるいは')) {
      return false;
    }

    if (_containsJapaneseText(trimmedQuestion)) {
      return RegExp(
        r'(すべきか|するべきか|しますか|必要がありますか|必要ですか|必要か|可能ですか|よいですか|いいですか|採用しますか|使いますか|許可しますか|優先しますか)',
      ).hasMatch(trimmedQuestion);
    }

    return [
      'should ',
      'do we ',
      'is ',
      'are ',
      'can ',
      'could ',
      'would ',
      'will ',
      'must ',
      'may ',
    ].any(normalizedQuestion.startsWith);
  }

  bool _containsJapaneseText(String value) {
    return RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(value);
  }

  String _normalizeWorkflowDecisionText(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[?？!！]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<_WorkflowProposalResponse> _requestWorkflowProposalAttempt({
    required Conversation currentConversation,
    required String languageCode,
    _PlanningResearchContext researchContext = const _PlanningResearchContext(),
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
          maxTokens: _settings.maxTokens > 1100 ? 1100 : _settings.maxTokens,
          minimalRetry: false,
        ),
        (
          compact: true,
          maxTokens: _settings.maxTokens > 800 ? 800 : _settings.maxTokens,
          minimalRetry: true,
        ),
        (
          compact: true,
          maxTokens: _settings.maxTokens > 650 ? 650 : _settings.maxTokens,
          minimalRetry: true,
        ),
      ] else ...[
        (
          compact: false,
          maxTokens: _settings.maxTokens > 1600 ? 1600 : _settings.maxTokens,
          minimalRetry: false,
        ),
        (
          compact: true,
          maxTokens: _settings.maxTokens > 900 ? 900 : _settings.maxTokens,
          minimalRetry: true,
        ),
        (
          compact: true,
          maxTokens: _settings.maxTokens > 700 ? 700 : _settings.maxTokens,
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
          return _WorkflowProposalDraftResponse(fallbackProposal);
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

  void _mergeWorkflowDecisionAnswers(
    List<WorkflowPlanningDecisionAnswer> current,
    List<WorkflowPlanningDecisionAnswer> updates,
  ) {
    for (final answer in updates) {
      final existingIndex = current.indexWhere(
        (item) => item.decisionId == answer.decisionId,
      );
      if (existingIndex >= 0) {
        current[existingIndex] = answer;
      } else {
        current.add(answer);
      }
    }
  }

  List<WorkflowPlanningDecision> _filterUnansweredWorkflowDecisions(
    List<WorkflowPlanningDecision> decisions, {
    required List<WorkflowPlanningDecisionAnswer> decisionAnswers,
  }) {
    if (decisions.isEmpty) {
      return const <WorkflowPlanningDecision>[];
    }

    final answeredDecisionIds = decisionAnswers
        .map((answer) => answer.decisionId.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final answeredQuestions = decisionAnswers
        .map((answer) => _normalizeWorkflowDecisionText(answer.question))
        .where((value) => value.isNotEmpty)
        .toSet();
    final emittedKeys = <String>{};
    final unresolved = <WorkflowPlanningDecision>[];

    for (final decision in decisions) {
      final normalizedQuestion = _normalizeWorkflowDecisionText(
        decision.question,
      );
      if (normalizedQuestion.isEmpty) {
        continue;
      }
      final emittedKey = decision.id.trim().isNotEmpty
          ? 'id:${decision.id.trim()}'
          : 'question:$normalizedQuestion';
      if (emittedKeys.contains(emittedKey)) {
        continue;
      }
      emittedKeys.add(emittedKey);

      if (answeredDecisionIds.contains(decision.id.trim()) ||
          answeredQuestions.contains(normalizedQuestion)) {
        continue;
      }
      unresolved.add(decision);
    }

    return unresolved;
  }

  WorkflowProposalDraft? _buildWorkflowProposalFallback({
    WorkflowProposalDraft? latestProposal,
    required List<WorkflowPlanningDecision> outstandingDecisions,
  }) {
    final unresolvedQuestions = outstandingDecisions
        .map((decision) => decision.question.trim())
        .where((question) => question.isNotEmpty)
        .toList(growable: false);

    if (latestProposal != null) {
      final mergedOpenQuestions = <String>[
        ...latestProposal.workflowSpec.openQuestions,
      ];
      final existingQuestions = mergedOpenQuestions
          .map(_normalizeWorkflowDecisionText)
          .where((value) => value.isNotEmpty)
          .toSet();

      for (final question in unresolvedQuestions) {
        final normalized = _normalizeWorkflowDecisionText(question);
        if (normalized.isEmpty || existingQuestions.contains(normalized)) {
          continue;
        }
        existingQuestions.add(normalized);
        mergedOpenQuestions.add(question);
      }

      return WorkflowProposalDraft(
        workflowStage: mergedOpenQuestions.isNotEmpty
            ? ConversationWorkflowStage.clarify
            : latestProposal.workflowStage,
        workflowSpec: latestProposal.workflowSpec.copyWith(
          openQuestions: mergedOpenQuestions.take(6).toList(growable: false),
        ),
      );
    }

    if (unresolvedQuestions.isEmpty) {
      return null;
    }

    return WorkflowProposalDraft(
      workflowStage: ConversationWorkflowStage.clarify,
      workflowSpec: ConversationWorkflowSpec(
        openQuestions: unresolvedQuestions.take(6).toList(growable: false),
      ),
    );
  }

  WorkflowProposalDraft? _buildWorkflowProposalTruncationFallback({
    required Conversation currentConversation,
    required String rawContent,
    required List<WorkflowPlanningDecisionAnswer> decisionAnswers,
  }) {
    final reasoningContent = _extractProposalReasoningContent(rawContent);
    final visibleContent = _normalizeProposalContent(rawContent);
    final goal =
        _extractNarrativeWorkflowGoal(reasoningContent) ??
        _extractNarrativeWorkflowGoal(visibleContent) ??
        _deriveWorkflowFallbackGoalFromConversation(currentConversation);
    if (goal == null || goal.trim().isEmpty) {
      return null;
    }

    final constraints = <String>[
      ..._extractNarrativeWorkflowList(
        reasoningContent,
        keys: const ['constraints', 'guardrails'],
      ),
      ...decisionAnswers
          .map((answer) {
            final question = answer.question.trim();
            final optionLabel = answer.optionLabel.trim();
            if (question.isEmpty || optionLabel.isEmpty) {
              return '';
            }
            return 'Resolved decision: $question -> $optionLabel';
          })
          .where((line) => line.isNotEmpty),
    ].take(3).toList(growable: false);

    final acceptanceCriteria = <String>[
      ..._extractNarrativeWorkflowList(
        reasoningContent,
        keys: const ['acceptance criteria', 'completion criteria'],
      ),
    ];
    if (acceptanceCriteria.isEmpty) {
      acceptanceCriteria.add(
        'Produce a concrete saved task plan that implements and validates the requested feature.',
      );
      if (decisionAnswers.isNotEmpty) {
        acceptanceCriteria.add(
          'Reflect the resolved planning decisions in the saved tasks.',
        );
      }
    }

    final proposal = WorkflowProposalDraft(
      workflowStage: ConversationWorkflowStage.plan,
      workflowSpec: ConversationWorkflowSpec(
        goal: goal,
        constraints: constraints,
        acceptanceCriteria: acceptanceCriteria.take(3).toList(growable: false),
      ),
    );
    return proposal.workflowSpec.hasContent ? proposal : null;
  }

  String? _deriveWorkflowFallbackGoalFromConversation(
    Conversation currentConversation,
  ) {
    String rawGoal = '';
    for (final message in currentConversation.messages.reversed) {
      if (message.role != MessageRole.user) {
        continue;
      }
      rawGoal = message.content.trim();
      if (rawGoal.isNotEmpty) {
        break;
      }
    }
    if (rawGoal.isEmpty) {
      return null;
    }

    final sanitized = _sanitizeNarrativeWorkflowGoal(rawGoal);
    if (sanitized != null && sanitized.isNotEmpty) {
      return sanitized;
    }
    return rawGoal.length > 180 ? rawGoal.substring(0, 180).trim() : rawGoal;
  }

  Future<WorkflowTaskProposalDraft> _requestTaskProposal({
    required Conversation currentConversation,
    required String languageCode,
    _PlanningResearchContext researchContext = const _PlanningResearchContext(),
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
        maxTokens: _settings.maxTokens > 1800 ? 1800 : _settings.maxTokens,
        minimalRetry: false,
      ),
      (
        compact: true,
        maxTokens: _settings.maxTokens > 1200 ? 1200 : _settings.maxTokens,
        minimalRetry: true,
      ),
      (
        compact: true,
        maxTokens: _settings.maxTokens > 900 ? 900 : _settings.maxTokens,
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
    _PlanningResearchContext researchContext = const _PlanningResearchContext(),
    List<WorkflowPlanningDecisionAnswer> decisionAnswers = const [],
    String? additionalPlanningContext,
    bool compact = false,
  }) {
    return ConversationPlanningPromptService.buildWorkflowProposalRequest(
      currentConversation: currentConversation,
      messages: state.messages,
      languageCode: languageCode,
      project: _getActiveCodingProject(),
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
    _PlanningResearchContext researchContext = const _PlanningResearchContext(),
    ConversationWorkflowStage? workflowStageOverride,
    ConversationWorkflowSpec? workflowSpecOverride,
    String? additionalPlanningContext,
    bool compact = false,
  }) {
    return ConversationPlanningPromptService.buildTaskProposalRequest(
      currentConversation: currentConversation,
      messages: state.messages,
      languageCode: languageCode,
      project: _getActiveCodingProject(),
      researchContextBlock: researchContext.hasContent
          ? researchContext.toPromptBlock()
          : null,
      workflowStageOverride: workflowStageOverride,
      workflowSpecOverride: workflowSpecOverride,
      additionalPlanningContext: additionalPlanningContext,
      compact: compact,
    );
  }

  String _extractPlainTextForProposal(String content) {
    final parsed = ContentParser.parse(content);
    final buffer = StringBuffer();
    for (final segment in parsed.segments) {
      if (segment.type == ContentType.text) {
        buffer.write(segment.content);
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  _WorkflowProposalResponse? _parseWorkflowProposalResponse(String rawContent) {
    final normalizedContent = _normalizeProposalContent(rawContent);
    final decoded = _extractJsonMap(normalizedContent);
    if (decoded != null) {
      final decisionResponse = _parseWorkflowDecisionResponseMap(decoded);
      if (decisionResponse != null) {
        return decisionResponse;
      }
      final proposalResponse = _parseWorkflowProposalMap(decoded);
      if (proposalResponse != null) {
        return _WorkflowProposalDraftResponse(proposalResponse);
      }
    }
    final proposalFromSections = _parseWorkflowProposalFromSections(
      normalizedContent,
    );
    if (proposalFromSections != null) {
      return _WorkflowProposalDraftResponse(proposalFromSections);
    }
    final looseProposal = _parseWorkflowProposalFromLooseJson(
      normalizedContent,
    );
    if (looseProposal != null) {
      return _WorkflowProposalDraftResponse(looseProposal);
    }
    return null;
  }

  _WorkflowProposalResponse? _parseWorkflowProposalResponseWithFallback(
    String rawContent,
  ) {
    final direct = _parseWorkflowProposalResponse(rawContent);
    if (direct != null) {
      return direct;
    }

    final visibleNarrativeSource = _normalizeProposalContent(rawContent);
    if (visibleNarrativeSource.isNotEmpty) {
      final directNarrative = _parseWorkflowProposalFromNarrative(
        visibleNarrativeSource,
      );
      if (directNarrative != null) {
        return _WorkflowProposalDraftResponse(directNarrative);
      }
    }

    final reasoningContent = _extractProposalReasoningContent(rawContent);
    if (reasoningContent.isEmpty) {
      return null;
    }

    final fromReasoning = _parseWorkflowProposalResponse(reasoningContent);
    if (fromReasoning case _WorkflowProposalDecisionResponse()) {
      return fromReasoning;
    }
    if (fromReasoning case _WorkflowProposalDraftResponse(:final proposal)) {
      if (_isReasoningWorkflowProposalPlausible(proposal)) {
        return fromReasoning;
      }
    }

    final structuredReasoning = _extractStructuredWorkflowProposalReasoning(
      reasoningContent,
    );
    if (structuredReasoning.isEmpty) {
      return null;
    }
    final sanitized = _parseWorkflowProposalResponse(structuredReasoning);
    if (sanitized case _WorkflowProposalDraftResponse(:final proposal)) {
      return _isReasoningWorkflowProposalPlausible(proposal) ? sanitized : null;
    }
    if (sanitized != null) {
      return sanitized;
    }

    final narrative = _parseWorkflowProposalFromNarrative(reasoningContent);
    if (narrative != null) {
      return _WorkflowProposalDraftResponse(narrative);
    }
    return null;
  }

  WorkflowTaskProposalDraft? _parseTaskProposal(String rawContent) {
    final normalizedContent = _normalizeProposalContent(rawContent);
    final decoded = _extractJsonMap(normalizedContent);
    final fromJson = decoded == null ? null : _parseTaskProposalMap(decoded);
    if (fromJson != null) {
      return fromJson;
    }
    return _parseTaskProposalFromSections(normalizedContent);
  }

  WorkflowTaskProposalDraft? _parseTaskProposalWithFallback(String rawContent) {
    final direct = _parseTaskProposal(rawContent);
    final looseJson = _parseTaskProposalFromLooseJson(rawContent);
    if (direct != null) {
      if (looseJson != null && looseJson.tasks.length > direct.tasks.length) {
        return looseJson;
      }
      return direct;
    }

    if (looseJson != null) {
      return looseJson;
    }

    final reasoningContent = _extractProposalReasoningContent(rawContent);
    if (reasoningContent.isEmpty) {
      return null;
    }

    final fromReasoning = _parseTaskProposal(reasoningContent);
    if (fromReasoning != null &&
        _isReasoningTaskProposalPlausible(fromReasoning)) {
      return fromReasoning;
    }

    final structuredReasoning = _extractStructuredTaskProposalReasoning(
      reasoningContent,
    );
    if (structuredReasoning.isNotEmpty) {
      final sanitized = _parseTaskProposal(structuredReasoning);
      if (sanitized != null && _isReasoningTaskProposalPlausible(sanitized)) {
        return sanitized;
      }
    }

    final inlineReasoning = _parseTaskProposalFromInlineReasoningPlan(
      reasoningContent,
    );
    if (inlineReasoning != null &&
        _isReasoningTaskProposalPlausible(inlineReasoning)) {
      return inlineReasoning;
    }

    final inlineVisible = _parseTaskProposalFromInlineReasoningPlan(
      _normalizeProposalContent(rawContent),
    );
    if (inlineVisible != null &&
        _isReasoningTaskProposalPlausible(inlineVisible)) {
      return inlineVisible;
    }
    return null;
  }

  WorkflowTaskProposalDraft? _buildTaskProposalTruncationFallback({
    required Conversation currentConversation,
    required String rawContent,
    required bool projectLooksEmpty,
    ConversationWorkflowSpec? workflowSpecOverride,
  }) {
    final reasoningContent = _extractProposalReasoningContent(rawContent);
    final visibleContent = _normalizeProposalContent(rawContent);
    final workflowSpec =
        workflowSpecOverride ?? currentConversation.effectiveWorkflowSpec;
    final rawGoal = workflowSpec.goal.trim().isNotEmpty
        ? workflowSpec.goal.trim()
        : _deriveWorkflowFallbackGoalFromConversation(currentConversation);
    if (rawGoal == null || rawGoal.isEmpty) {
      return null;
    }

    final inferredTasks = _buildHeuristicTaskProposalFallbackTasks(
      contextLines: <String>[
        rawGoal,
        ...workflowSpec.constraints,
        ...workflowSpec.acceptanceCriteria,
        ...workflowSpec.openQuestions,
        reasoningContent,
        visibleContent,
      ],
      projectLooksEmpty: projectLooksEmpty,
    );
    if (inferredTasks.isEmpty) {
      return null;
    }

    return WorkflowTaskProposalDraft(tasks: inferredTasks);
  }

  WorkflowTaskProposalDraft? _buildTaskProposalQualityGateFallback({
    required Conversation currentConversation,
    required bool projectLooksEmpty,
    required _PlanningResearchContext researchContext,
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

  Map<String, dynamic>? _extractJsonMap(String rawContent) {
    final trimmed = rawContent.trim();
    if (trimmed.isEmpty) return null;

    final fencedMatch = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(trimmed);
    final candidate = fencedMatch?.group(1)?.trim() ?? trimmed;

    final direct = _tryDecodeMap(candidate);
    if (direct != null) return direct;
    final repairedDirect = _tryRepairAndDecodeMap(candidate);
    if (repairedDirect != null) return repairedDirect;

    final firstBrace = candidate.indexOf('{');
    final lastBrace = candidate.lastIndexOf('}');
    if (firstBrace < 0) {
      return null;
    }
    if (lastBrace > firstBrace) {
      final sliced = candidate.substring(firstBrace, lastBrace + 1).trim();
      final slicedDirect = _tryDecodeMap(sliced);
      if (slicedDirect != null) return slicedDirect;
      return _tryRepairAndDecodeMap(sliced);
    }
    return _tryRepairAndDecodeMap(candidate.substring(firstBrace).trim());
  }

  Map<String, dynamic>? _tryDecodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _tryRepairAndDecodeMap(String value) {
    final repaired = _repairJsonCandidate(value);
    if (repaired == null) return null;
    return _tryDecodeMap(repaired);
  }

  String? _repairJsonCandidate(String value) {
    var candidate = value.trim();
    if (candidate.isEmpty || !candidate.contains('{')) {
      return null;
    }

    final start = candidate.indexOf('{');
    candidate = candidate.substring(start).trimRight();
    if (candidate.isEmpty) return null;

    final buffer = StringBuffer();
    final closers = <String>[];
    var inString = false;
    var isEscaped = false;

    for (var i = 0; i < candidate.length; i++) {
      final char = candidate[i];
      buffer.write(char);

      if (inString) {
        if (isEscaped) {
          isEscaped = false;
          continue;
        }
        if (char == r'\') {
          isEscaped = true;
          continue;
        }
        if (char == '"') {
          inString = false;
        }
        continue;
      }

      if (char == '"') {
        inString = true;
        continue;
      }
      if (char == '{') {
        closers.add('}');
      } else if (char == '[') {
        closers.add(']');
      } else if (char == '}' || char == ']') {
        if (closers.isNotEmpty && closers.last == char) {
          closers.removeLast();
        }
      }
    }

    var repaired = buffer.toString().trimRight();
    if (inString && !isEscaped) {
      repaired = '$repaired"';
    }
    repaired = repaired.replaceFirst(RegExp(r'[\s,:]+$'), '');
    if (repaired.isEmpty) {
      return null;
    }
    if (repaired.endsWith('"') && repaired.split('"').length.isOdd) {
      repaired = '$repaired"';
    }

    for (final closer in closers.reversed) {
      repaired = '$repaired$closer';
    }
    return repaired;
  }

  bool _isCompletionTruncated(String finishReason) {
    final normalized = finishReason.trim().toLowerCase();
    return normalized == 'length';
  }

  ConversationWorkflowStage? _parseWorkflowStage(Object? rawStage) {
    final normalized = rawStage?.toString().trim().toLowerCase();
    return switch (normalized) {
      'clarify' => ConversationWorkflowStage.clarify,
      'clarification' => ConversationWorkflowStage.clarify,
      'question' => ConversationWorkflowStage.clarify,
      'questions' => ConversationWorkflowStage.clarify,
      '確認' => ConversationWorkflowStage.clarify,
      'plan' => ConversationWorkflowStage.plan,
      'planning' => ConversationWorkflowStage.plan,
      '計画' => ConversationWorkflowStage.plan,
      'tasks' => ConversationWorkflowStage.tasks,
      'task' => ConversationWorkflowStage.tasks,
      'tasking' => ConversationWorkflowStage.tasks,
      'タスク' => ConversationWorkflowStage.tasks,
      'タスク化' => ConversationWorkflowStage.tasks,
      'implement' => ConversationWorkflowStage.implement,
      'implementation' => ConversationWorkflowStage.implement,
      'coding' => ConversationWorkflowStage.implement,
      '実装' => ConversationWorkflowStage.implement,
      'review' => ConversationWorkflowStage.review,
      'validation' => ConversationWorkflowStage.review,
      'レビュー' => ConversationWorkflowStage.review,
      _ => null,
    };
  }

  ConversationWorkflowStage? _inferWorkflowStageFromProposal(
    Map<String, dynamic> decoded,
  ) {
    final openQuestions = _asStringList(decoded['openQuestions']);
    if (openQuestions.isNotEmpty) {
      return ConversationWorkflowStage.clarify;
    }
    return ConversationWorkflowStage.plan;
  }

  ConversationWorkflowStage _inferWorkflowStageFromLooseProposalContent(
    String rawContent,
  ) {
    final openQuestions = _extractLooseJsonStringList(
      rawContent,
      keys: const ['openQuestions', 'open_questions', 'questions', '未解決の確認事項'],
    );
    return openQuestions.isNotEmpty
        ? ConversationWorkflowStage.clarify
        : ConversationWorkflowStage.plan;
  }

  String _asCleanString(Object? value) {
    return value?.toString().trim() ?? '';
  }

  List<String> _asStringList(Object? value) {
    if (value is! List) {
      return const [];
    }
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .take(6)
        .toList(growable: false);
  }

  WorkflowProposalDraft? _parseWorkflowProposalMap(
    Map<String, dynamic> decoded,
  ) {
    final workflowStage =
        _parseWorkflowStage(
          decoded['workflowStage'] ??
              decoded['stage'] ??
              decoded['workflow_stage'] ??
              decoded['ワークフローステージ'] ??
              decoded['ステージ'],
        ) ??
        _inferWorkflowStageFromProposal(decoded);
    if (workflowStage == null ||
        workflowStage == ConversationWorkflowStage.idle) {
      return null;
    }

    final workflowSpec = ConversationWorkflowSpec(
      goal: _asCleanString(decoded['goal'] ?? decoded['目的']),
      constraints: _asStringList(decoded['constraints'] ?? decoded['制約']),
      acceptanceCriteria: _asStringList(
        decoded['acceptanceCriteria'] ??
            decoded['acceptance_criteria'] ??
            decoded['acceptance'] ??
            decoded['完了条件'],
      ),
      openQuestions: _asStringList(
        decoded['openQuestions'] ??
            decoded['open_questions'] ??
            decoded['questions'] ??
            decoded['未解決の確認事項'],
      ),
    );

    if (!workflowSpec.hasContent) {
      return null;
    }

    return WorkflowProposalDraft(
      workflowStage: workflowStage,
      workflowSpec: workflowSpec,
    );
  }

  _WorkflowProposalDecisionResponse? _parseWorkflowDecisionResponseMap(
    Map<String, dynamic> decoded,
  ) {
    final kind = _asCleanString(decoded['kind']).toLowerCase();
    if (kind.isNotEmpty && kind != 'decision') {
      return null;
    }

    final rawDecisions =
        decoded['decisions'] ?? decoded['planningDecisions'] ?? decoded['選択'];
    if (rawDecisions is! List) {
      return null;
    }

    final decisions = <WorkflowPlanningDecision>[];
    for (final entry in rawDecisions.take(3)) {
      if (entry is! Map) continue;
      final item = Map<String, dynamic>.from(entry);
      final question = _asCleanString(
        item['question'] ?? item['title'] ?? item['prompt'] ?? item['質問'],
      );
      final rawOptions = item['options'] ?? item['choices'] ?? item['選択肢'];
      final inputMode = _asCleanString(item['inputMode']).toLowerCase();
      final allowFreeText =
          inputMode == 'freetext' ||
          inputMode == 'free_text' ||
          item['allowFreeText'] == true;
      if (question.isEmpty) {
        continue;
      }

      final options = <WorkflowPlanningDecisionOption>[];
      if (rawOptions is List) {
        for (final optionEntry in rawOptions.take(4)) {
          if (optionEntry is! Map) continue;
          final option = Map<String, dynamic>.from(optionEntry);
          final label = _asCleanString(
            option['label'] ??
                option['title'] ??
                option['name'] ??
                option['候補'],
          );
          if (label.isEmpty) continue;
          final optionId = _asCleanString(
            option['id'] ?? option['value'] ?? option['key'],
          );
          options.add(
            WorkflowPlanningDecisionOption(
              id: optionId.isEmpty ? label : optionId,
              label: label,
              description: _asCleanString(
                option['description'] ?? option['detail'] ?? option['説明'],
              ),
            ),
          );
        }
      }

      if (!allowFreeText && options.length < 2) {
        continue;
      }

      final decisionId = _asCleanString(
        item['id'] ?? item['key'] ?? item['name'],
      );
      decisions.add(
        WorkflowPlanningDecision(
          id: decisionId.isEmpty ? question : decisionId,
          question: question,
          help: _asCleanString(
            item['help'] ??
                item['description'] ??
                item['details'] ??
                item['補足'],
          ),
          allowFreeText: allowFreeText,
          freeTextPlaceholder: _asCleanString(
            item['placeholder'] ?? item['inputPlaceholder'] ?? item['入力例'],
          ),
          options: options,
        ),
      );
    }

    if (decisions.isEmpty) {
      return null;
    }
    return _WorkflowProposalDecisionResponse(decisions);
  }

  WorkflowTaskProposalDraft? _parseTaskProposalMap(
    Map<String, dynamic> decoded,
  ) {
    final rawTasks = decoded['tasks'] ?? decoded['taskList'] ?? decoded['タスク'];
    if (rawTasks is! List) return null;

    final tasks = <ConversationWorkflowTask>[];
    for (final entry in rawTasks.take(6)) {
      if (entry is! Map) continue;
      final item = Map<String, dynamic>.from(entry);
      final title = _asCleanString(
        item['title'] ?? item['task'] ?? item['taskTitle'] ?? item['タスク名'],
      );
      if (title.isEmpty) continue;
      tasks.add(
        ConversationWorkflowTask(
          id: _uuid.v4(),
          title: title,
          status: ConversationWorkflowTaskStatus.pending,
          targetFiles: _asStringList(
            item['targetFiles'] ?? item['files'] ?? item['対象ファイル'],
          ),
          validationCommand: _asCleanString(
            item['validationCommand'] ?? item['validation'] ?? item['確認コマンド'],
          ),
          notes: _asCleanString(item['notes'] ?? item['memo'] ?? item['メモ']),
        ),
      );
    }

    final sanitizedTasks = _sanitizeTaskProposalTasks(tasks);
    if (sanitizedTasks.isEmpty) return null;
    return WorkflowTaskProposalDraft(tasks: sanitizedTasks);
  }

  WorkflowTaskProposalDraft? _parseTaskProposalFromLooseJson(
    String rawContent,
  ) {
    final titlePattern = RegExp(
      r'''["']?(?:title|task|taskTitle|タスク名)["']?\s*:\s*(?:"([^"]+)"|'([^']+)')''',
      caseSensitive: false,
      dotAll: true,
    );
    final titleMatches = titlePattern
        .allMatches(rawContent)
        .toList(growable: false);
    if (titleMatches.isEmpty) {
      return null;
    }

    final tasks = <ConversationWorkflowTask>[];
    for (
      var index = 0;
      index < titleMatches.length && tasks.length < 6;
      index++
    ) {
      final match = titleMatches[index];
      final rawTitle = (match.group(1) ?? match.group(2) ?? '').trim();
      if (rawTitle.isEmpty) {
        continue;
      }

      final fragmentStart = rawContent.lastIndexOf('{', match.start);
      final safeStart = fragmentStart >= 0 ? fragmentStart : match.start;
      final safeEnd = index + 1 < titleMatches.length
          ? titleMatches[index + 1].start
          : rawContent.length;
      final fragment = rawContent.substring(safeStart, safeEnd).trim();

      tasks.add(
        ConversationWorkflowTask(
          id: _uuid.v4(),
          title: rawTitle,
          status: ConversationWorkflowTaskStatus.pending,
          targetFiles: _extractLooseJsonStringList(
            fragment,
            keys: const ['targetFiles', 'files', '対象ファイル'],
          ),
          validationCommand:
              _extractLooseJsonScalar(
                fragment,
                keys: const ['validationCommand', 'validation', '確認コマンド'],
              ) ??
              '',
          notes:
              _extractLooseJsonScalar(
                fragment,
                keys: const ['notes', 'memo', 'メモ'],
              ) ??
              '',
        ),
      );
    }

    final sanitizedTasks = _sanitizeTaskProposalTasks(tasks);
    if (sanitizedTasks.isEmpty) {
      return null;
    }
    return WorkflowTaskProposalDraft(tasks: sanitizedTasks);
  }

  WorkflowProposalDraft? _parseWorkflowProposalFromSections(String rawContent) {
    final sections = _collectProposalSections(rawContent);
    final workflowStage =
        _parseWorkflowStage(sections['workflowStage']?.firstOrNull) ??
        _inferWorkflowStageFromSectionKeys(sections);
    if (workflowStage == null ||
        workflowStage == ConversationWorkflowStage.idle) {
      return null;
    }

    final workflowSpec = ConversationWorkflowSpec(
      goal: sections['goal']?.join(' ').trim() ?? '',
      constraints: sections['constraints'] ?? const [],
      acceptanceCriteria: sections['acceptanceCriteria'] ?? const [],
      openQuestions: sections['openQuestions'] ?? const [],
    );
    if (!workflowSpec.hasContent) {
      return null;
    }

    return WorkflowProposalDraft(
      workflowStage: workflowStage,
      workflowSpec: workflowSpec,
    );
  }

  WorkflowProposalDraft? _parseWorkflowProposalFromLooseJson(
    String rawContent,
  ) {
    final workflowStage =
        _parseWorkflowStage(
          _extractLooseJsonScalar(
            rawContent,
            keys: const [
              'workflowStage',
              'stage',
              'workflow_stage',
              'ワークフローステージ',
              'ステージ',
            ],
          ),
        ) ??
        _inferWorkflowStageFromLooseProposalContent(rawContent);
    if (workflowStage == ConversationWorkflowStage.idle) {
      return null;
    }

    final workflowSpec = ConversationWorkflowSpec(
      goal:
          _extractLooseJsonScalar(rawContent, keys: const ['goal', '目的']) ?? '',
      constraints: _extractLooseJsonStringList(
        rawContent,
        keys: const ['constraints', '制約'],
      ),
      acceptanceCriteria: _extractLooseJsonStringList(
        rawContent,
        keys: const [
          'acceptanceCriteria',
          'acceptance_criteria',
          'acceptance',
          '完了条件',
        ],
      ),
      openQuestions: _extractLooseJsonStringList(
        rawContent,
        keys: const [
          'openQuestions',
          'open_questions',
          'questions',
          '未解決の確認事項',
        ],
      ),
    );
    if (!workflowSpec.hasContent) {
      return null;
    }

    return WorkflowProposalDraft(
      workflowStage: workflowStage,
      workflowSpec: workflowSpec,
    );
  }

  WorkflowProposalDraft? _parseWorkflowProposalFromNarrative(
    String rawContent,
  ) {
    final goal = _extractNarrativeWorkflowGoal(rawContent);
    if (goal == null) {
      return null;
    }

    final acceptanceCriteria = _extractNarrativeWorkflowList(
      rawContent,
      keys: const ['acceptance criteria', 'completion criteria'],
    );
    final constraints = _extractNarrativeWorkflowList(
      rawContent,
      keys: const ['constraints', 'guardrails'],
    );
    final openQuestions = _extractNarrativeWorkflowList(
      rawContent,
      keys: const ['open questions', 'unresolved questions'],
    );

    final proposal = WorkflowProposalDraft(
      workflowStage: openQuestions.isNotEmpty
          ? ConversationWorkflowStage.clarify
          : ConversationWorkflowStage.plan,
      workflowSpec: ConversationWorkflowSpec(
        goal: goal,
        constraints: constraints,
        acceptanceCriteria: acceptanceCriteria,
        openQuestions: openQuestions,
      ),
    );
    if (!proposal.workflowSpec.hasContent ||
        !_isReasoningWorkflowProposalPlausible(proposal)) {
      return null;
    }
    return proposal;
  }

  String? _extractLooseJsonScalar(
    String rawContent, {
    required List<String> keys,
  }) {
    for (final key in keys) {
      final quotedPattern = RegExp(
        "[\\\"']?${RegExp.escape(key)}[\\\"']?\\s*:\\s*(?:\\\"([^\\\"]*)\\\"|'([^']*)'|([A-Za-z_]+))",
        caseSensitive: false,
        dotAll: true,
      );
      final quotedMatch = quotedPattern.firstMatch(rawContent);
      if (quotedMatch == null) {
        continue;
      }
      final value =
          quotedMatch.group(1) ??
          quotedMatch.group(2) ??
          quotedMatch.group(3) ??
          '';
      final normalized = value.trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return null;
  }

  List<String> _extractLooseJsonStringList(
    String rawContent, {
    required List<String> keys,
  }) {
    for (final key in keys) {
      final listPattern = RegExp(
        "[\\\"']?${RegExp.escape(key)}[\\\"']?\\s*:\\s*\\[(.*?)(?:\\]\\s*(?:,|\\}|\$)|\$)",
        caseSensitive: false,
        dotAll: true,
      );
      final match = listPattern.firstMatch(rawContent);
      if (match == null) {
        continue;
      }
      final body = match.group(1)?.trim() ?? '';
      if (body.isEmpty) {
        continue;
      }

      final items = RegExp("\\\"([^\\\"]*)\\\"|'([^']*)'", dotAll: true)
          .allMatches(body)
          .map((entry) {
            return (entry.group(1) ?? entry.group(2) ?? '').trim();
          })
          .where((item) => item.isNotEmpty)
          .take(6)
          .toList(growable: false);

      if (items.isNotEmpty) {
        return items;
      }
    }
    return const [];
  }

  String? _extractNarrativeWorkflowGoal(String rawContent) {
    final normalizedContent = rawContent.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalizedContent.isEmpty) {
      return null;
    }

    const userGoalPrefixes = <String>[
      'The user wants a workflow proposal for ',
      'The user wants to ',
    ];
    final lowerContent = normalizedContent.toLowerCase();
    for (final prefix in userGoalPrefixes) {
      final start = lowerContent.indexOf(prefix.toLowerCase());
      if (start < 0) {
        continue;
      }
      final candidate = _sanitizeNarrativeWorkflowGoal(
        _trimNarrativeWorkflowGoalCandidate(
          normalizedContent.substring(start + prefix.length),
        ),
      );
      if (candidate != null) {
        return candidate;
      }
    }

    final quotedRequestMatch = RegExp(
      r'''The user(?:'s)? request is ["'](.+?)["']''',
      caseSensitive: false,
    ).firstMatch(normalizedContent);
    if (quotedRequestMatch != null) {
      final candidate = _sanitizeNarrativeWorkflowGoal(
        quotedRequestMatch.group(1) ?? '',
      );
      if (candidate != null) {
        return candidate;
      }
    }

    final userWantsMatch = RegExp(
      r'''The user wants (?:a workflow proposal for |to )(.+?)(?:(?:[.!?](?:\s|$))|(?:\s+The project name is\b)|(?:\s+Project name is\b)|(?:\s+The current state is\b)|(?:\s+The project root\b)|(?:\s+The research context\b)|(?:\s+The user's\b)|$)''',
      caseSensitive: false,
    ).firstMatch(normalizedContent);
    if (userWantsMatch != null) {
      final candidate = _sanitizeNarrativeWorkflowGoal(
        userWantsMatch.group(1) ?? '',
      );
      if (candidate != null) {
        return candidate;
      }
    }

    final goalMatch = RegExp(
      r'''Goal\s*:\s*(.+?)(?:\.|$)''',
      caseSensitive: false,
    ).firstMatch(normalizedContent);
    if (goalMatch != null) {
      final candidate = _sanitizeNarrativeWorkflowGoal(
        goalMatch.group(1) ?? '',
      );
      if (candidate != null) {
        return candidate;
      }
    }

    return null;
  }

  String _trimNarrativeWorkflowGoalCandidate(String rawValue) {
    var candidate = rawValue.trim();
    if (candidate.isEmpty) {
      return '';
    }

    const contextMarkers = <String>[
      ' The project name is ',
      ' Project name is ',
      ' The current state is ',
      ' The project root ',
      ' The research context ',
      " The user's request is ",
      ' Current State:',
      ' Recent Context:',
    ];

    final lowerCandidate = candidate.toLowerCase();
    var cutIndex = candidate.length;
    for (final marker in contextMarkers) {
      final index = lowerCandidate.indexOf(marker.trim().toLowerCase());
      if (index > 0 && index < cutIndex) {
        cutIndex = index;
      }
    }
    candidate = candidate.substring(0, cutIndex).trim();

    final sentenceBreak = RegExp(r'(?<=[.!?])\s+').firstMatch(candidate);
    if (sentenceBreak != null && sentenceBreak.start > 24) {
      candidate = candidate.substring(0, sentenceBreak.start).trim();
    }

    return candidate;
  }

  String? _sanitizeNarrativeWorkflowGoal(String rawValue) {
    final candidate = _sanitizeReasoningProposalValue(
      rawValue,
      preferSingleSentence: true,
    );
    if (candidate.isEmpty) {
      return null;
    }

    final normalized = candidate.toLowerCase();
    const blockedFragments = <String>[
      'workflow proposal',
      'current coding thread',
      'single valid json object',
      'return only',
      'research context',
      'project name is',
      'the project is currently empty',
      'the prompt asks',
    ];
    if (blockedFragments.any(normalized.contains)) {
      return null;
    }

    if (!RegExp(
      r'\b(create|build|implement|add|ship|make|refine|improve|develop|diagnose|ping)\b',
      caseSensitive: false,
    ).hasMatch(candidate)) {
      return null;
    }
    return candidate;
  }

  List<String> _extractNarrativeWorkflowList(
    String rawContent, {
    required List<String> keys,
  }) {
    final normalizedContent = rawContent.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalizedContent.isEmpty) {
      return const [];
    }

    for (final key in keys) {
      final match = RegExp(
        '${RegExp.escape(key)}\\s*[:\\-]\\s*(.+?)(?:\\.|\\\$)',
        caseSensitive: false,
      ).firstMatch(normalizedContent);
      if (match == null) {
        continue;
      }
      final value = _sanitizeReasoningProposalValue(match.group(1) ?? '');
      if (value.isEmpty) {
        continue;
      }
      return [value];
    }
    return const [];
  }

  WorkflowTaskProposalDraft? _parseTaskProposalFromSections(String rawContent) {
    final tasks = <ConversationWorkflowTask>[];
    String currentTitle = '';
    final currentTargetFiles = <String>[];
    String currentValidationCommand = '';
    String currentNotes = '';
    String? currentField;

    void commitCurrentTask() {
      final normalizedTitle = currentTitle.trim();
      if (normalizedTitle.isEmpty) return;
      tasks.add(
        ConversationWorkflowTask(
          id: _uuid.v4(),
          title: normalizedTitle,
          status: ConversationWorkflowTaskStatus.pending,
          targetFiles: List<String>.from(currentTargetFiles),
          validationCommand: currentValidationCommand.trim(),
          notes: currentNotes.trim(),
        ),
      );
      currentTitle = '';
      currentTargetFiles.clear();
      currentValidationCommand = '';
      currentNotes = '';
      currentField = null;
    }

    for (final rawLine in rawContent.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final taskTitle = _matchTaskTitleLine(line, currentField: currentField);
      if (taskTitle != null) {
        commitCurrentTask();
        currentTitle = taskTitle;
        currentField = null;
        continue;
      }

      final taskField = _matchTaskFieldLine(line);
      if (taskField != null) {
        currentField = taskField.$1;
        final value = _stripMarkdownListMarker(taskField.$2);
        if (value.isNotEmpty) {
          switch (currentField) {
            case 'targetFiles':
              currentTargetFiles.add(value);
              break;
            case 'validationCommand':
              currentValidationCommand = value;
              break;
            case 'notes':
              currentNotes = _appendTextValue(currentNotes, value);
              break;
          }
        }
        continue;
      }

      if (currentTitle.isEmpty || currentField == null) {
        continue;
      }

      final value = _stripMarkdownListMarker(line);
      if (value.isEmpty) continue;
      switch (currentField) {
        case 'targetFiles':
          currentTargetFiles.add(value);
          break;
        case 'validationCommand':
          currentValidationCommand = _appendTextValue(
            currentValidationCommand,
            value,
          );
          break;
        case 'notes':
          currentNotes = _appendTextValue(currentNotes, value);
          break;
      }
    }

    commitCurrentTask();
    final sanitizedTasks = _sanitizeTaskProposalTasks(tasks);
    if (sanitizedTasks.isEmpty) return null;
    return WorkflowTaskProposalDraft(
      tasks: sanitizedTasks.take(6).toList(growable: false),
    );
  }

  WorkflowTaskProposalDraft? _parseTaskProposalFromInlineReasoningPlan(
    String rawContent,
  ) {
    final normalizedContent = rawContent.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalizedContent.isEmpty) {
      return null;
    }

    final candidate = _extractInlineTaskPlanCandidate(normalizedContent);
    final taskMatches = RegExp(
      r'(?:^|(?<=\s))\d+[.)]\s+',
    ).allMatches(candidate).toList(growable: false);
    if (taskMatches.length < 2) {
      return null;
    }

    final tasks = <ConversationWorkflowTask>[];
    for (var index = 0; index < taskMatches.length; index++) {
      final start = taskMatches[index].end;
      final end = index + 1 < taskMatches.length
          ? taskMatches[index + 1].start
          : candidate.length;
      final rawTitle = candidate.substring(start, end).trim();
      final title = _sanitizeInlineReasoningTaskTitle(rawTitle);
      if (title.isEmpty) {
        continue;
      }
      tasks.add(
        ConversationWorkflowTask(
          id: _uuid.v4(),
          title: title,
          status: ConversationWorkflowTaskStatus.pending,
          targetFiles: const <String>[],
          validationCommand: '',
          notes: '',
        ),
      );
      if (tasks.length == 6) {
        break;
      }
    }

    final sanitizedTasks = _sanitizeTaskProposalTasks(tasks);
    if (sanitizedTasks.length < 2) {
      return null;
    }
    return WorkflowTaskProposalDraft(tasks: sanitizedTasks);
  }

  Map<String, List<String>> _collectProposalSections(String rawContent) {
    final sections = <String, List<String>>{
      'workflowStage': <String>[],
      'goal': <String>[],
      'constraints': <String>[],
      'acceptanceCriteria': <String>[],
      'openQuestions': <String>[],
    };

    String? currentSection;
    for (final rawLine in rawContent.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final match = _matchWorkflowSectionLine(line);
      if (match != null) {
        currentSection = match.$1;
        final value = _stripMarkdownListMarker(match.$2);
        if (value.isNotEmpty) {
          sections[currentSection]!.add(value);
        }
        continue;
      }

      if (currentSection == null) continue;
      final value = _stripMarkdownListMarker(line);
      if (value.isEmpty) continue;
      sections[currentSection]!.add(value);
    }
    return sections;
  }

  (String, String)? _matchWorkflowSectionLine(String line) {
    final normalizedLine = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
    for (final entry in {
      'workflowStage': ['workflow stage', 'stage', 'ワークフローステージ', 'ステージ'],
      'goal': ['goal', '目的'],
      'constraints': ['constraints', 'constraint', '制約'],
      'acceptanceCriteria': [
        'acceptance criteria',
        'acceptance',
        '完了条件',
        '受け入れ条件',
      ],
      'openQuestions': ['open questions', 'questions', '未解決の確認事項', '確認事項'],
    }.entries) {
      for (final label in entry.value) {
        final inlineMatch = RegExp(
          '^(?:[-*]\\s*)?${RegExp.escape(label)}\\s*[:：-]\\s*(.*)\$',
          caseSensitive: false,
        ).firstMatch(normalizedLine);
        if (inlineMatch != null) {
          return (entry.key, inlineMatch.group(1)?.trim() ?? '');
        }
        if (normalizedLine.toLowerCase() == label.toLowerCase()) {
          return (entry.key, '');
        }
      }
    }
    return null;
  }

  ConversationWorkflowStage? _inferWorkflowStageFromSectionKeys(
    Map<String, List<String>> sections,
  ) {
    if ((sections['openQuestions'] ?? const []).isNotEmpty) {
      return ConversationWorkflowStage.clarify;
    }
    if ((sections['acceptanceCriteria'] ?? const []).isNotEmpty ||
        (sections['constraints'] ?? const []).isNotEmpty ||
        (sections['goal'] ?? const []).isNotEmpty) {
      return ConversationWorkflowStage.plan;
    }
    return null;
  }

  String _normalizeProposalContent(String rawContent) {
    return rawContent
        .replaceAll(
          RegExp(
            r'<(?:think|thinking|thought)>[\s\S]*?</(?:think|thinking|thought)>',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(r'</?(?:think|thinking|thought)>', caseSensitive: false),
          ' ',
        )
        .trim();
  }

  String _extractProposalReasoningContent(String rawContent) {
    final matches = RegExp(
      r'<(?:think|thinking|thought)>([\s\S]*?)</(?:think|thinking|thought)>',
      caseSensitive: false,
    ).allMatches(rawContent);
    if (matches.isEmpty) {
      return '';
    }

    return matches
        .map((match) => (match.group(1) ?? '').trim())
        .where((chunk) => chunk.isNotEmpty)
        .join('\n')
        .trim();
  }

  String _extractStructuredWorkflowProposalReasoning(String rawContent) {
    final buffer = StringBuffer();
    String? currentSection;

    for (final rawLine in rawContent.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final sectionMatch = _matchWorkflowSectionLine(line);
      if (sectionMatch != null) {
        currentSection = sectionMatch.$1;
        final cleanedValue = _sanitizeReasoningProposalValue(
          _stripMarkdownListMarker(sectionMatch.$2),
          preferSingleSentence: currentSection == 'goal',
        );
        final label = _workflowSectionDisplayLabel(currentSection);
        if (cleanedValue.isEmpty) {
          buffer.writeln('$label:');
        } else {
          buffer.writeln('$label: $cleanedValue');
        }
        if (!_isWorkflowListSection(currentSection)) {
          currentSection = null;
        }
        continue;
      }

      if (currentSection == null || !_isWorkflowListSection(currentSection)) {
        continue;
      }
      if (!_looksLikeStructuredReasoningListItem(line)) {
        continue;
      }

      final cleanedValue = _sanitizeReasoningProposalValue(
        _stripMarkdownListMarker(line),
      );
      if (cleanedValue.isEmpty) {
        continue;
      }
      buffer.writeln('- $cleanedValue');
    }

    return buffer.toString().trim();
  }

  String _extractStructuredTaskProposalReasoning(String rawContent) {
    final buffer = StringBuffer();
    String? currentField;
    var taskCount = 0;

    for (final rawLine in rawContent.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final taskTitle = _matchTaskTitleLine(line, currentField: currentField);
      if (taskTitle != null) {
        taskCount++;
        if (buffer.isNotEmpty) {
          buffer.writeln();
        }
        buffer.writeln(
          '$taskCount. ${_sanitizeReasoningProposalValue(taskTitle, preferSingleSentence: true)}',
        );
        currentField = null;
        continue;
      }

      final taskField = _matchTaskFieldLine(line);
      if (taskField != null) {
        currentField = taskField.$1;
        final cleanedValue = _sanitizeReasoningProposalValue(
          _stripMarkdownListMarker(taskField.$2),
          preferSingleSentence: currentField != 'notes',
        );
        final label = _taskFieldDisplayLabel(currentField);
        if (cleanedValue.isEmpty) {
          buffer.writeln('$label:');
        } else {
          buffer.writeln('$label: $cleanedValue');
        }
        continue;
      }

      if (currentField == null ||
          !_looksLikeStructuredReasoningListItem(line)) {
        continue;
      }

      final cleanedValue = _sanitizeReasoningProposalValue(
        _stripMarkdownListMarker(line),
      );
      if (cleanedValue.isEmpty) {
        continue;
      }
      buffer.writeln('- $cleanedValue');
    }

    return buffer.toString().trim();
  }

  bool _looksLikeStructuredReasoningListItem(String line) {
    return RegExp(r'^(?:[-*•]|\d+[.)])\s+').hasMatch(line.trim());
  }

  bool _isWorkflowListSection(String section) {
    return section == 'constraints' ||
        section == 'acceptanceCriteria' ||
        section == 'openQuestions';
  }

  String _workflowSectionDisplayLabel(String section) {
    return switch (section) {
      'workflowStage' => 'Workflow Stage',
      'goal' => 'Goal',
      'constraints' => 'Constraints',
      'acceptanceCriteria' => 'Acceptance Criteria',
      'openQuestions' => 'Open Questions',
      _ => section,
    };
  }

  String _taskFieldDisplayLabel(String field) {
    return switch (field) {
      'targetFiles' => 'Target files',
      'validationCommand' => 'Validation command',
      'notes' => 'Notes',
      _ => field,
    };
  }

  String _sanitizeReasoningProposalValue(
    String value, {
    bool preferSingleSentence = false,
  }) {
    var candidate = value
        .trim()
        .replaceAll(RegExp("^[`\"']+|[`\"']+\$"), '')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (candidate.isEmpty) {
      return '';
    }

    const suspiciousMarkers = <String>[
      'Recent Context:',
      'Previous session',
      'Previous sessions',
      'Current State:',
      'The current state is',
      'The project name is',
      'Project name is',
      'The project root',
      'The research context',
      'The current workspace',
      'The workspace is',
      'The repository is',
      "The user's request is",
      'Self-Correction',
      'Actually,',
      'Actually ',
      'Wait,',
      'Wait ',
      "Let's check",
      "Let's refine",
      "The user's intent",
      'The prompt asks',
      'kind:',
      'workflowStage:',
      'acceptanceCriteria:',
      'openQuestions:',
      'decisions:',
      "'kind'",
      '"kind"',
      "'workflowStage'",
      '"workflowStage"',
      "'goal'",
      '"goal"',
      "'constraints'",
      '"constraints"',
      "'acceptanceCriteria'",
      '"acceptanceCriteria"',
      "'openQuestions'",
      '"openQuestions"',
      "'decisions'",
      '"decisions"',
    ];

    final lowerCandidate = candidate.toLowerCase();
    var cutIndex = candidate.length;
    for (final marker in suspiciousMarkers) {
      final index = lowerCandidate.indexOf(marker.toLowerCase());
      if (index > 0 && index < cutIndex) {
        cutIndex = index;
      }
    }
    candidate = candidate.substring(0, cutIndex).trim();

    if (preferSingleSentence && candidate.length > 160) {
      final sentenceBreak = RegExp(r'(?<=[.!?])\s+').firstMatch(candidate);
      if (sentenceBreak != null && sentenceBreak.start > 32) {
        candidate = candidate.substring(0, sentenceBreak.start).trim();
      }
    }

    return candidate.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _extractInlineTaskPlanCandidate(String rawContent) {
    final planMatch = RegExp(
      r'(?:^|[\s(])(?:plan|tasks?)\s*[:：-]\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(rawContent);
    return (planMatch?.group(1) ?? rawContent).trim();
  }

  String _sanitizeInlineReasoningTaskTitle(String rawValue) {
    var candidate = _sanitizeReasoningProposalValue(
      rawValue,
      preferSingleSentence: true,
    );
    if (candidate.isEmpty) {
      return '';
    }

    final fieldMatch = RegExp(
      r'\b(?:target files?|validation command|validation|notes?)\s*[:：-]',
      caseSensitive: false,
    ).firstMatch(candidate);
    if (fieldMatch != null && fieldMatch.start > 0) {
      candidate = candidate.substring(0, fieldMatch.start).trim();
    }

    candidate = candidate.replaceFirst(
      RegExp(r'^(?:task|title)\s*[:：-]\s*', caseSensitive: false),
      '',
    );
    return candidate.trim();
  }

  bool _isReasoningWorkflowProposalPlausible(WorkflowProposalDraft proposal) {
    final fields = <String>[
      proposal.workflowSpec.goal,
      ...proposal.workflowSpec.constraints,
      ...proposal.workflowSpec.acceptanceCriteria,
      ...proposal.workflowSpec.openQuestions,
    ].map((item) => item.trim()).where((item) => item.isNotEmpty);

    if (proposal.workflowSpec.goal.trim().length > 220) {
      return false;
    }

    final suspiciousPattern = RegExp(
      "(recent context|current state|self-correction|(?:kind|workflowstage|acceptancecriteria|openquestions|decisions)\\s*:|[`'\\\"]\\s*(kind|workflowstage|goal|constraints|acceptancecriteria|openquestions|decisions)\\s*[`'\\\"]\\s*:)",
      caseSensitive: false,
    );
    for (final field in fields) {
      if (field.length > 280 || suspiciousPattern.hasMatch(field)) {
        return false;
      }
    }
    return true;
  }

  bool _isReasoningTaskProposalPlausible(WorkflowTaskProposalDraft proposal) {
    final suspiciousPattern = RegExp(
      "(recent context|current state|self-correction|the prompt says|saved task|task id|(?:title|targetfiles|validationcommand|notes|tasks)\\s*:|[`'\\\"]\\s*(title|targetfiles|validationcommand|notes|tasks)\\s*[`'\\\"]\\s*:)",
      caseSensitive: false,
    );
    for (final task in proposal.tasks) {
      if (task.title.trim().isEmpty ||
          task.title.length > 180 ||
          suspiciousPattern.hasMatch(task.title)) {
        return false;
      }
      if (task.validationCommand.length > 240 ||
          suspiciousPattern.hasMatch(task.validationCommand) ||
          task.notes.length > 320 ||
          suspiciousPattern.hasMatch(task.notes)) {
        return false;
      }
      if (task.targetFiles.any(
        (path) => path.length > 220 || suspiciousPattern.hasMatch(path),
      )) {
        return false;
      }
    }
    return proposal.tasks.isNotEmpty;
  }

  WorkflowTaskProposalDraft? _preferTaskProposalRetryCandidate({
    required WorkflowTaskProposalDraft? current,
    required WorkflowTaskProposalDraft candidate,
  }) {
    if (current == null) {
      return candidate;
    }

    final currentScore = _scoreTaskProposalRetryCandidate(current);
    final candidateScore = _scoreTaskProposalRetryCandidate(candidate);
    if (candidateScore > currentScore) {
      return candidate;
    }
    return current;
  }

  int _scoreTaskProposalRetryCandidate(WorkflowTaskProposalDraft proposal) {
    var score = proposal.tasks.length * 20;
    for (final task in proposal.tasks) {
      final implementationTargets = task.targetFiles
          .where(_looksLikeImplementationTargetFile)
          .toList(growable: false);
      if (!_looksLikeGenericScaffoldOnlyTask(task)) {
        score += 12;
      }
      if (implementationTargets.isNotEmpty) {
        score += 8;
      }
      if (!_hasWeakImplementationValidationCommand(
        task.validationCommand,
        implementationTargets,
      )) {
        score += 6;
      }
    }
    return score;
  }

  List<ConversationWorkflowTask> _buildHeuristicTaskProposalFallbackTasks({
    required List<String> contextLines,
    required bool projectLooksEmpty,
  }) {
    final context = contextLines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join(' ')
        .toLowerCase();
    final looksLikePython =
        context.contains('python') ||
        context.contains('pyproject') ||
        context.contains('requirements.txt') ||
        context.contains('argparse') ||
        context.contains('.py');
    if (!looksLikePython) {
      return const <ConversationWorkflowTask>[];
    }

    final supportsContinuous =
        context.contains('continuous') ||
        context.contains('loop') ||
        context.contains('infinite');
    final supportsJson = context.contains('json');
    final supportsMultiHost =
        context.contains('multiple hosts') ||
        context.contains('multi-host') ||
        context.contains('host list') ||
        context.contains('file-based host');

    final tasks = <ConversationWorkflowTask>[];
    if (projectLooksEmpty) {
      tasks.add(
        ConversationWorkflowTask(
          id: _uuid.v4(),
          title: 'Initialize project structure and requirements.txt',
          status: ConversationWorkflowTaskStatus.pending,
          targetFiles: const ['requirements.txt', 'README.md'],
          validationCommand: 'ls',
          notes: 'Create the initial project files for the CLI script.',
        ),
      );
    }

    tasks.add(
      ConversationWorkflowTask(
        id: _uuid.v4(),
        title: 'Implement core ping functionality and CLI arguments in main.py',
        status: ConversationWorkflowTaskStatus.pending,
        targetFiles: const ['main.py'],
        validationCommand: 'python3 main.py --help',
        notes: 'Use subprocess to call the system ping command.',
      ),
    );

    if (supportsMultiHost) {
      tasks.add(
        ConversationWorkflowTask(
          id: _uuid.v4(),
          title: 'Add multi-host input handling in main.py',
          status: ConversationWorkflowTaskStatus.pending,
          targetFiles: const ['main.py'],
          validationCommand: 'python3 main.py --help',
          notes: 'Support host lists or repeated host arguments.',
        ),
      );
    }

    if (supportsContinuous) {
      tasks.add(
        ConversationWorkflowTask(
          id: _uuid.v4(),
          title: 'Add continuous ping loop and interval options in main.py',
          status: ConversationWorkflowTaskStatus.pending,
          targetFiles: const ['main.py'],
          validationCommand: 'python3 main.py --help',
          notes: 'Add loop control flags without changing future tasks.',
        ),
      );
    }

    if (supportsJson) {
      tasks.add(
        ConversationWorkflowTask(
          id: _uuid.v4(),
          title: 'Add JSON output support in main.py',
          status: ConversationWorkflowTaskStatus.pending,
          targetFiles: const ['main.py'],
          validationCommand: 'python3 main.py --help',
          notes: 'Keep machine-readable output behind a flag.',
        ),
      );
    }

    if (tasks.length < 2) {
      tasks.add(
        ConversationWorkflowTask(
          id: _uuid.v4(),
          title:
              'Add error handling for invalid or unreachable hosts in main.py',
          status: ConversationWorkflowTaskStatus.pending,
          targetFiles: const ['main.py'],
          validationCommand: 'python3 main.py --help',
          notes: 'Handle invalid host input and ping failures gracefully.',
        ),
      );
    }

    return tasks.take(4).toList(growable: false);
  }

  WorkflowTaskProposalDraft _finalizeTaskProposalDraft(
    WorkflowTaskProposalDraft proposal, {
    required _PlanningResearchContext researchContext,
  }) {
    final sanitizedTasks = _sanitizeTaskProposalTasks(proposal.tasks);
    final reorderedTasks = _reorderTaskProposalTasks(
      sanitizedTasks,
      projectLooksEmpty: _projectLooksEmptyForTaskPlanning(researchContext),
    );
    return WorkflowTaskProposalDraft(tasks: reorderedTasks);
  }

  List<ConversationWorkflowTask> _sanitizeTaskProposalTasks(
    Iterable<ConversationWorkflowTask> tasks,
  ) {
    final sanitizedTasks = <ConversationWorkflowTask>[];
    final emittedTitles = <String>{};

    for (final task in tasks) {
      final normalizedTitle = _normalizeTaskProposalTitle(task.title);
      if (normalizedTitle.isEmpty ||
          _isTaskProposalObservationTitle(normalizedTitle) ||
          _isTaskProposalLowQualityTitle(normalizedTitle)) {
        continue;
      }
      final normalizedTargetFiles = _normalizeTaskProposalTargetFiles(
        task.targetFiles,
      );
      final normalizedValidationCommand =
          _normalizeTaskProposalValidationCommand(task.validationCommand);
      final normalizedNotes = _normalizeTaskProposalTextField(task.notes);
      if (_looksLikeImplementationTaskTitle(normalizedTitle) &&
          task.targetFiles.isNotEmpty &&
          normalizedTargetFiles.isEmpty) {
        continue;
      }
      final dedupeKey = normalizedTitle.toLowerCase();
      if (!emittedTitles.add(dedupeKey)) {
        continue;
      }
      final normalizedTask = task.copyWith(
        title: normalizedTitle,
        targetFiles: normalizedTargetFiles,
        validationCommand: normalizedValidationCommand,
        notes: normalizedNotes,
      );
      if (sanitizedTasks.any(
        (existingTask) =>
            _taskProposalTasksLookNearDuplicate(existingTask, normalizedTask),
      )) {
        continue;
      }
      sanitizedTasks.add(normalizedTask);
      if (sanitizedTasks.length == 6) {
        break;
      }
    }

    return sanitizedTasks.toList(growable: false);
  }

  String _normalizeTaskProposalTitle(String value) {
    var candidate = value
        .trim()
        .replaceAll(RegExp('^[`"\']+|[`"\']+\$'), '')
        .replaceAll('`', '')
        .replaceAll('"', '')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (candidate.isEmpty) {
      return '';
    }

    candidate = candidate.replaceFirst(
      RegExp(r'^(?:task\s*\d+\s*[:.-]\s*)', caseSensitive: false),
      '',
    );
    candidate = candidate.replaceFirst(
      RegExp(r'^(?:next step\s*[:.-]\s*)', caseSensitive: false),
      '',
    );
    candidate = candidate.replaceFirst(
      RegExp(r'^(?:i need to|need to)\s+', caseSensitive: false),
      '',
    );
    candidate = candidate.replaceFirst(
      RegExp(r'^(?:we need to|please)\s+', caseSensitive: false),
      '',
    );
    candidate = candidate.replaceFirst(
      RegExp(
        r'^(?:subsequent|following|next)\s+tasks?\s+(?:should|must|will)\s+(?:involve|include|cover)\s*:?\s*',
        caseSensitive: false,
      ),
      '',
    );
    candidate = candidate.replaceFirst(RegExp(r'[.。]+$'), '').trim();
    if (candidate.isEmpty) {
      return '';
    }

    final firstCharacter = candidate[0];
    if (RegExp(r'[a-z]').hasMatch(firstCharacter)) {
      candidate = '${firstCharacter.toUpperCase()}${candidate.substring(1)}';
    }
    return candidate;
  }

  bool _isTaskProposalObservationTitle(String title) {
    final normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }

    if (_isTaskProposalPlaceholderTitle(normalized)) {
      return true;
    }

    const blockedPrefixes = <String>[
      'the project root seems ',
      'the project root is ',
      'the workspace seems ',
      'the workspace is ',
      'the repository seems ',
      'the repository is ',
      'current state:',
      'current state ',
      'recent context:',
      'recent context ',
      'research context:',
      'research context ',
      'there is ',
      'there are ',
    ];
    if (blockedPrefixes.any(normalized.startsWith)) {
      return true;
    }

    const blockedFragments = <String>[
      'based on research context',
      'current state',
      'recent context',
      'research context',
      'proposal image',
      'looks empty',
      'seems empty',
    ];
    return blockedFragments.any(normalized.contains);
  }

  bool _isTaskProposalLowQualityTitle(String title) {
    final normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }

    if (title.contains('?') || title.contains('？')) {
      return true;
    }
    if (title.endsWith(':') || title.endsWith('：')) {
      return true;
    }

    const blockedPrefixes = <String>[
      'should ',
      'which ',
      'what ',
      'how ',
      'why ',
      'when ',
      'where ',
      'who ',
    ];
    if (blockedPrefixes.any(normalized.startsWith)) {
      return true;
    }

    const blockedFragments = <String>[
      "i'll assume",
      'if i were implementing',
      'for simplicity',
      'or just pick one',
      'what would you like to do next',
      'i will assume',
      'the prompt says',
      'saved task',
      'task id',
    ];
    return blockedFragments.any(normalized.contains);
  }

  List<String> _normalizeTaskProposalTargetFiles(Iterable<String> paths) {
    final normalizedPaths = <String>[];
    final emitted = <String>{};

    for (final rawPath in paths) {
      final normalizedPath = _normalizeTaskProposalTargetFile(rawPath);
      if (normalizedPath.isEmpty) {
        continue;
      }
      final dedupeKey = normalizedPath.toLowerCase();
      if (!emitted.add(dedupeKey)) {
        continue;
      }
      normalizedPaths.add(normalizedPath);
    }

    return normalizedPaths.toList(growable: false);
  }

  String _normalizeTaskProposalTargetFile(String value) {
    var candidate = value.trim().replaceAll('\\', '/');
    if (candidate.isEmpty) {
      return '';
    }
    if (_looksLikePlaceholderTaskProposalValue(candidate)) {
      return '';
    }

    candidate = candidate.replaceFirst(RegExp(r'^\./'), '');
    if (!_looksLikeTaskProposalTargetPath(candidate)) {
      return '';
    }
    final lowerCandidate = candidate.toLowerCase();
    if (lowerCandidate == 'readme.py' ||
        lowerCandidate.endsWith('/readme.py')) {
      return candidate.replaceFirst(
        RegExp(r'readme\.py$', caseSensitive: false),
        'README.md',
      );
    }
    return candidate;
  }

  bool _looksLikeTaskProposalTargetPath(String value) {
    final candidate = value.trim();
    if (candidate.isEmpty || candidate.length > 180) {
      return false;
    }

    final lowerCandidate = candidate.toLowerCase();
    if (RegExp(r'\s').hasMatch(candidate)) {
      return false;
    }
    if (lowerCandidate.startsWith('ls-') ||
        lowerCandidate.startsWith('cat-') ||
        lowerCandidate.startsWith('python-') ||
        lowerCandidate.startsWith('python3-')) {
      return false;
    }

    const knownRootFiles = <String>{
      '.dockerignore',
      '.gitignore',
      'dockerfile',
      'license',
      'makefile',
      'package.json',
      'pyproject.toml',
      'readme',
      'readme.md',
      'requirements.txt',
      'pubspec.yaml',
    };
    if (knownRootFiles.contains(lowerCandidate)) {
      return true;
    }
    if (candidate.contains('/')) {
      return true;
    }
    return RegExp(
      r'^[A-Za-z0-9_.-]+\.[A-Za-z][A-Za-z0-9_.-]{0,15}$',
    ).hasMatch(candidate);
  }

  String _normalizeTaskProposalTextField(String value) {
    final candidate = value.trim();
    if (_looksLikePlaceholderTaskProposalValue(candidate)) {
      return '';
    }
    return candidate;
  }

  String _normalizeTaskProposalValidationCommand(String value) {
    final candidate = _normalizeTaskProposalTextField(value);
    if (candidate.isEmpty) {
      return '';
    }

    final portablePython = candidate.replaceFirst(
      RegExp(r'^python(\s+|$)'),
      'python3 ',
    );
    final portableLs = portablePython.replaceFirst(
      RegExp(r'^ls\s+-F(\s+|$)'),
      'ls ',
    );
    final normalized = portableLs.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (_looksLikeUnboundedPingValidationCommand(normalized)) {
      return '$normalized -c 1';
    }
    return normalized;
  }

  bool _looksLikePlaceholderTaskProposalValue(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'string' ||
        normalized == 'todo' ||
        normalized == 'tbd' ||
        normalized == 'n/a';
  }

  bool _taskProposalNeedsRetry(
    WorkflowTaskProposalDraft original,
    WorkflowTaskProposalDraft finalized,
    bool projectLooksEmpty,
  ) {
    if (finalized.tasks.isEmpty) {
      return true;
    }

    final removedCount = original.tasks.length - finalized.tasks.length;
    if (removedCount >= 2 && finalized.tasks.length <= 1) {
      return true;
    }

    if (projectLooksEmpty && finalized.tasks.length < 2) {
      return true;
    }

    if (projectLooksEmpty &&
        !_taskProposalHasImplementationFollowUp(finalized.tasks)) {
      return true;
    }

    if (projectLooksEmpty &&
        _taskProposalHasWeakImplementationValidation(finalized.tasks)) {
      return true;
    }

    if (projectLooksEmpty &&
        _taskProposalHasUnsupportedPythonVerificationValidation(
          finalized.tasks,
        )) {
      return true;
    }

    if (projectLooksEmpty &&
        _taskProposalHasThirdPartyPythonRuntimeDependencyRisk(
          finalized.tasks,
        )) {
      return true;
    }

    if (projectLooksEmpty &&
        _taskProposalHasFragmentedSingleFileImplementation(finalized.tasks)) {
      return true;
    }

    if (_taskProposalHasUnboundedPingVerificationValidation(finalized.tasks)) {
      return true;
    }

    if (_taskProposalHasDuplicateVerificationTasks(finalized.tasks)) {
      return true;
    }

    if (_taskProposalHasNearDuplicateTasks(finalized.tasks)) {
      return true;
    }

    if (finalized.tasks.length == 1 &&
        _looksLikeGenericScaffoldOnlyTask(finalized.tasks.first)) {
      return true;
    }

    return false;
  }

  bool _taskProposalNeedsRetryForWorkflow(
    WorkflowTaskProposalDraft original,
    WorkflowTaskProposalDraft finalized,
    bool projectLooksEmpty,
    ConversationWorkflowSpec workflowSpec,
  ) {
    final violatesExplicitFirstSlice =
        _taskProposalViolatesExplicitFirstSliceTargets(
          finalized.tasks,
          workflowSpec,
          projectLooksEmpty: projectLooksEmpty,
        );
    if (violatesExplicitFirstSlice) {
      return true;
    }

    if (!_taskProposalNeedsRetry(original, finalized, projectLooksEmpty)) {
      return false;
    }
    if (_workflowAllowsExplicitSingleTaskProposal(
      finalized,
      workflowSpec,
      projectLooksEmpty: projectLooksEmpty,
    )) {
      return false;
    }
    return !_workflowAllowsSingleReadmeTask(finalized, workflowSpec);
  }

  bool _workflowAllowsExplicitSingleTaskProposal(
    WorkflowTaskProposalDraft finalized,
    ConversationWorkflowSpec workflowSpec, {
    required bool projectLooksEmpty,
  }) {
    if (!projectLooksEmpty ||
        finalized.tasks.length != 1 ||
        !_workflowPrefersExplicitSingleTask(workflowSpec)) {
      return false;
    }

    final task = finalized.tasks.single;
    if (_looksLikeVerificationTaskProposal(task) ||
        _looksLikeGenericScaffoldOnlyTask(task) ||
        task.validationCommand.trim().isEmpty) {
      return false;
    }

    final targets = task.targetFiles
        .map((path) => path.trim().replaceAll('\\', '/').toLowerCase())
        .where((path) => path.isNotEmpty)
        .toSet();
    if (targets.isEmpty) {
      return false;
    }

    final requiredTargets = _explicitSingleTaskTargetFiles(workflowSpec);
    if (requiredTargets.isNotEmpty &&
        requiredTargets.any((target) => !targets.contains(target))) {
      return false;
    }

    return task.targetFiles.any(_looksLikeImplementationTargetFile);
  }

  bool _workflowPrefersExplicitSingleTask(
    ConversationWorkflowSpec workflowSpec,
  ) {
    final context = _workflowSpecText(workflowSpec);
    if (context.isEmpty) {
      return false;
    }

    final exactTaskConstraint =
        context.contains('exactly one implementation task') ||
        context.contains('exactly one task') ||
        context.contains('single implementation task') ||
        context.contains('single approved task') ||
        context.contains('one implementation task');
    if (exactTaskConstraint) {
      return true;
    }

    final singleFileConstraint =
        context.contains('single-file') ||
        context.contains('single file') ||
        context.contains('only create') ||
        context.contains('create only') ||
        context.contains('no other files') ||
        context.contains('root-level');
    return singleFileConstraint &&
        _explicitSingleTaskTargetFiles(workflowSpec).isNotEmpty;
  }

  Set<String> _explicitSingleTaskTargetFiles(
    ConversationWorkflowSpec workflowSpec,
  ) {
    final context = _workflowSpecText(workflowSpec);
    if (context.isEmpty) {
      return const <String>{};
    }

    const knownSingleTaskFiles = <String>{
      'ping_cli.py',
      'main.py',
      'health_check.py',
      'health_checker.py',
    };
    return knownSingleTaskFiles.where((path) => context.contains(path)).toSet();
  }

  String _workflowSpecText(ConversationWorkflowSpec workflowSpec) {
    return [
      workflowSpec.goal,
      ...workflowSpec.constraints,
      ...workflowSpec.acceptanceCriteria,
      ...workflowSpec.openQuestions,
    ].join(' ').toLowerCase();
  }

  bool _taskProposalViolatesExplicitFirstSliceTargets(
    List<ConversationWorkflowTask> tasks,
    ConversationWorkflowSpec workflowSpec, {
    required bool projectLooksEmpty,
  }) {
    if (!projectLooksEmpty || tasks.isEmpty) {
      return false;
    }

    final requiredTargets = _explicitFirstSliceTargetFiles(workflowSpec);
    if (requiredTargets.isEmpty) {
      return false;
    }

    final firstTask = tasks.first;
    if (_looksLikeVerificationTaskProposal(firstTask)) {
      return true;
    }

    final firstTaskTargets = firstTask.targetFiles
        .map((path) => path.trim().replaceAll('\\', '/').toLowerCase())
        .where((path) => path.isNotEmpty)
        .toSet();
    return requiredTargets.any((target) => !firstTaskTargets.contains(target));
  }

  Set<String> _explicitFirstSliceTargetFiles(
    ConversationWorkflowSpec workflowSpec,
  ) {
    final context = [
      workflowSpec.goal,
      ...workflowSpec.constraints,
      ...workflowSpec.acceptanceCriteria,
      ...workflowSpec.openQuestions,
    ].join(' ').toLowerCase();
    if (context.isEmpty) {
      return const <String>{};
    }

    final mentionsFirstSlice =
        context.contains('first slice') ||
        context.contains('initial slice') ||
        context.contains('first implementation slice') ||
        context.contains('initial implementation slice');
    final constrainsSlice =
        mentionsFirstSlice &&
        (context.contains(' only') ||
            context.contains('limited to') ||
            context.contains('create only') ||
            context.contains('contain exactly') ||
            context.contains('must contain'));
    final requiresReadmeAndRequirements =
        context.contains('requirements.txt') &&
        (context.contains('readme.md') || context.contains('readme'));
    if (!constrainsSlice && !requiresReadmeAndRequirements) {
      return const <String>{};
    }

    const knownFirstSliceFiles = <String>{
      'requirements.txt',
      'readme.md',
      'pyproject.toml',
      '.gitignore',
      'main.py',
      'ping_cli.py',
    };
    return knownFirstSliceFiles.where((path) => context.contains(path)).toSet();
  }

  bool _workflowAllowsSingleReadmeTask(
    WorkflowTaskProposalDraft finalized,
    ConversationWorkflowSpec workflowSpec,
  ) {
    if (finalized.tasks.length != 1) {
      return false;
    }

    final task = finalized.tasks.single;
    final targetFiles = task.targetFiles
        .map((path) => path.trim().toLowerCase())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (targetFiles.isEmpty ||
        !targetFiles.every((path) => path == 'readme.md')) {
      return false;
    }

    final context = [
      workflowSpec.goal,
      ...workflowSpec.constraints,
      ...workflowSpec.acceptanceCriteria,
      ...workflowSpec.openQuestions,
    ].join(' ').toLowerCase();
    final explicitlyReadmeOnly =
        context.contains('readme.md only') ||
        context.contains('limited to readme.md') ||
        context.contains('readme first slice') ||
        context.contains('exactly one task') ||
        context.contains('single task') ||
        context.contains('no python source files') ||
        context.contains('no source files');
    return explicitlyReadmeOnly && task.validationCommand.trim().isNotEmpty;
  }

  bool _taskProposalHasImplementationFollowUp(
    List<ConversationWorkflowTask> tasks,
  ) {
    return tasks.any((task) => !_looksLikeGenericScaffoldOnlyTask(task));
  }

  bool _taskProposalHasDuplicateVerificationTasks(
    List<ConversationWorkflowTask> tasks,
  ) {
    final seenSignatures = <String>{};
    final seenValidationSignatures = <String>{};
    for (final task in tasks) {
      if (!_looksLikeVerificationTaskProposal(task)) {
        continue;
      }
      final signature = _verificationTaskSignature(task);
      if (signature.isNotEmpty && !seenSignatures.add(signature)) {
        return true;
      }
      final validationSignature = _verificationTaskValidationSignature(task);
      if (validationSignature.isNotEmpty &&
          !seenValidationSignatures.add(validationSignature)) {
        return true;
      }
    }
    return false;
  }

  bool _taskProposalHasUnsupportedPythonVerificationValidation(
    List<ConversationWorkflowTask> tasks,
  ) {
    for (final task in tasks) {
      if (!_looksLikeVerificationTaskProposal(task)) {
        continue;
      }
      final normalizedValidation = task.validationCommand.trim().toLowerCase();
      if (normalizedValidation.startsWith('pytest') ||
          normalizedValidation.startsWith('python -m pytest') ||
          normalizedValidation.startsWith('python3 -m pytest')) {
        return true;
      }
    }
    return false;
  }

  bool _taskProposalHasUnboundedPingVerificationValidation(
    List<ConversationWorkflowTask> tasks,
  ) {
    for (final task in tasks) {
      final normalizedContext = '${task.title.trim()} ${task.notes.trim()}'
          .toLowerCase();
      if (!normalizedContext.contains('ping')) {
        continue;
      }

      final normalizedValidation = task.validationCommand.trim().toLowerCase();
      if (normalizedValidation.isEmpty) {
        continue;
      }
      if (_looksLikeBoundedPingValidationCommand(normalizedValidation)) {
        continue;
      }
      if (_looksLikeUnboundedPingValidationCommand(normalizedValidation)) {
        return true;
      }
    }
    return false;
  }

  bool _taskProposalHasThirdPartyPythonRuntimeDependencyRisk(
    List<ConversationWorkflowTask> tasks,
  ) {
    const riskyFragments = <String>[
      'ping3',
      'icmplib',
      'ping library',
      'third-party',
      'external dependency',
      'external package',
    ];

    for (final task in tasks) {
      if (!_looksLikeImplementationTaskTitle(task.title)) {
        continue;
      }

      final hasPythonTarget = task.targetFiles.any(
        (path) => path.trim().toLowerCase().endsWith('.py'),
      );
      if (!hasPythonTarget) {
        continue;
      }

      final hasDependencyManifestTarget = task.targetFiles.any((path) {
        final normalizedPath = path.trim().toLowerCase();
        return normalizedPath.endsWith('requirements.txt') ||
            normalizedPath.endsWith('pyproject.toml') ||
            normalizedPath.endsWith('setup.py') ||
            normalizedPath.endsWith('setup.cfg');
      });
      if (hasDependencyManifestTarget) {
        continue;
      }

      final normalizedContext = '${task.title.trim()} ${task.notes.trim()}'
          .toLowerCase();
      if (riskyFragments.any(normalizedContext.contains)) {
        return true;
      }
    }

    return false;
  }

  bool _taskProposalHasFragmentedSingleFileImplementation(
    List<ConversationWorkflowTask> tasks,
  ) {
    final implementationCounts = <String, int>{};

    for (final task in tasks) {
      if (_looksLikeVerificationTaskProposal(task) ||
          !_looksLikeImplementationTaskTitle(task.title)) {
        continue;
      }

      final normalizedTargets = _taskProposalDuplicateTargets(task)
          .map((path) => path.toLowerCase())
          .where(_looksLikeImplementationTargetFile)
          .toSet();
      if (normalizedTargets.length != 1) {
        continue;
      }

      final target = normalizedTargets.first;
      implementationCounts.update(
        target,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      if (implementationCounts[target]! >= 2) {
        return true;
      }
    }

    return false;
  }

  bool _taskProposalHasNearDuplicateTasks(
    List<ConversationWorkflowTask> tasks,
  ) {
    for (var index = 0; index < tasks.length; index += 1) {
      for (
        var nextIndex = index + 1;
        nextIndex < tasks.length;
        nextIndex += 1
      ) {
        if (_taskProposalTasksLookNearDuplicate(
          tasks[index],
          tasks[nextIndex],
        )) {
          return true;
        }
      }
    }
    return false;
  }

  bool _taskProposalTasksLookNearDuplicate(
    ConversationWorkflowTask left,
    ConversationWorkflowTask right,
  ) {
    if (_looksLikeVerificationTaskProposal(left) ||
        _looksLikeVerificationTaskProposal(right)) {
      return false;
    }

    final leftTargets = _taskProposalDuplicateTargets(left)
        .map((path) => path.toLowerCase())
        .where((path) => path.isNotEmpty)
        .toSet();
    final rightTargets = _taskProposalDuplicateTargets(right)
        .map((path) => path.toLowerCase())
        .where((path) => path.isNotEmpty)
        .toSet();
    if (leftTargets.isEmpty || rightTargets.isEmpty) {
      return false;
    }

    final sharedTargets = leftTargets.intersection(rightTargets);
    if (sharedTargets.isEmpty) {
      return false;
    }

    final leftTokens = _taskProposalSemanticTitleTokens(left.title);
    final rightTokens = _taskProposalSemanticTitleTokens(right.title);
    if (leftTokens.length < 2 || rightTokens.length < 2) {
      return false;
    }

    final overlap = leftTokens.intersection(rightTokens);
    if (overlap.length < 2) {
      return false;
    }

    final smallerTokenCount = leftTokens.length <= rightTokens.length
        ? leftTokens.length
        : rightTokens.length;
    if (smallerTokenCount < 2) {
      return false;
    }

    return overlap.length == smallerTokenCount ||
        overlap.length / smallerTokenCount >= 0.75;
  }

  Iterable<String> _taskProposalDuplicateTargets(
    ConversationWorkflowTask task,
  ) {
    final normalizedTargets = _normalizeTaskProposalTargetFiles(
      task.targetFiles,
    );
    if (normalizedTargets.isNotEmpty) {
      return normalizedTargets;
    }
    return _extractTaskProposalTitleTargetHints(task.title);
  }

  Iterable<String> _extractTaskProposalTitleTargetHints(String title) {
    final matches = RegExp(
      r'(?:(?:^|[\s`"(]))([A-Za-z0-9_./-]+\.[A-Za-z][A-Za-z0-9]{0,7}|__init__\.py|\.gitignore)(?=$|[\s`)",.:;])',
    ).allMatches(title);
    final paths = <String>[];
    for (final match in matches) {
      final value = match.group(1)?.trim();
      if (value == null || value.isEmpty) {
        continue;
      }
      final normalized = _normalizeTaskProposalTargetFiles(<String>[value]);
      if (normalized.isEmpty) {
        continue;
      }
      paths.addAll(normalized);
    }
    return paths;
  }

  Set<String> _taskProposalSemanticTitleTokens(String title) {
    const ignoredTokens = <String>{
      'a',
      'an',
      'and',
      'add',
      'build',
      'core',
      'create',
      'file',
      'files',
      'for',
      'functionality',
      'implement',
      'implementation',
      'in',
      'interface',
      'main',
      'module',
      'on',
      'script',
      'task',
      'the',
      'to',
      'tool',
      'update',
      'with',
      'write',
    };
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(RegExp(r'\s+'))
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty && !ignoredTokens.contains(token))
        .toSet();
  }

  bool _taskProposalHasWeakImplementationValidation(
    List<ConversationWorkflowTask> tasks,
  ) {
    for (final task in tasks) {
      if (_looksLikeScaffoldTask(task)) {
        continue;
      }
      final implementationTargets = task.targetFiles
          .where(_looksLikeImplementationTargetFile)
          .toList(growable: false);
      if (implementationTargets.isEmpty) {
        continue;
      }
      if (_hasWeakImplementationValidationCommand(
        task.validationCommand,
        implementationTargets,
      )) {
        return true;
      }
    }
    return false;
  }

  bool _looksLikeGenericScaffoldOnlyTask(ConversationWorkflowTask task) {
    if (!_looksLikeScaffoldTask(task)) {
      return false;
    }

    final normalizedTitle = task.title.trim().toLowerCase();
    const genericSignals = <String>[
      'initialize project structure',
      'initialize project scaffolding',
      'initialize the project structure',
      'initialize the project scaffolding',
      'set up project structure',
      'setup project structure',
      'create initial project structure',
      'create project scaffolding',
      'project structure',
      'project scaffolding',
    ];
    if (genericSignals.contains(normalizedTitle)) {
      return true;
    }

    return !task.targetFiles.any(_looksLikeImplementationTargetFile);
  }

  bool _looksLikeVerificationTaskProposal(ConversationWorkflowTask task) {
    final normalized = '${task.title.trim()} ${task.notes.trim()}'
        .toLowerCase();
    const titleSignals = <String>[
      'verify ',
      'verification',
      'real host',
      'live host',
      'smoke test',
      'manual test',
    ];
    return titleSignals.any(normalized.contains);
  }

  String _verificationTaskSignature(ConversationWorkflowTask task) {
    final normalizedTitle = task.title.trim().toLowerCase();
    if (normalizedTitle.isEmpty) {
      return '';
    }
    final canonicalTitle = normalizedTitle
        .replaceAll(RegExp(r'\b(real|live|actual)\b'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(RegExp(r'\s+'))
        .where(
          (token) =>
              token.isNotEmpty &&
              !const <String>{
                'verify',
                'verification',
                'validate',
                'validating',
                'with',
                'a',
                'an',
                'the',
                'for',
                'using',
                'execution',
                'functionality',
                'output',
                'outputs',
                'result',
                'results',
              }.contains(token),
        )
        .join(' ');
    final targetKey = _taskProposalDuplicateTargets(task)
        .map((path) => path.toLowerCase())
        .where((path) => path.isNotEmpty)
        .join('|');
    if (canonicalTitle.isEmpty) {
      return targetKey;
    }
    return '$canonicalTitle::$targetKey';
  }

  String _verificationTaskValidationSignature(ConversationWorkflowTask task) {
    final targetKey = _taskProposalDuplicateTargets(task)
        .map((path) => path.toLowerCase())
        .where((path) => path.isNotEmpty)
        .join('|');
    final validationKey = _normalizeTaskProposalValidationCommand(
      task.validationCommand,
    ).toLowerCase();
    if (targetKey.isEmpty || validationKey.isEmpty) {
      return '';
    }
    return '$targetKey::$validationKey';
  }

  bool _looksLikeImplementationTargetFile(String path) {
    final normalizedPath = path.trim().toLowerCase();
    if (normalizedPath.isEmpty) {
      return false;
    }

    if (normalizedPath == 'readme.md' ||
        normalizedPath == '.gitignore' ||
        normalizedPath == 'requirements.txt' ||
        normalizedPath == 'pyproject.toml') {
      return false;
    }

    if (normalizedPath.endsWith('/__init__.py')) {
      return false;
    }

    return normalizedPath.endsWith('.py') ||
        normalizedPath.endsWith('.dart') ||
        normalizedPath.endsWith('.ts') ||
        normalizedPath.endsWith('.tsx') ||
        normalizedPath.endsWith('.js') ||
        normalizedPath.endsWith('.jsx') ||
        normalizedPath.endsWith('.rs') ||
        normalizedPath.endsWith('.go') ||
        normalizedPath.endsWith('.java') ||
        normalizedPath.endsWith('.kt');
  }

  bool _looksLikeImplementationTaskTitle(String title) {
    final normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    const signals = <String>[
      'implement ',
      'build ',
      'create cli',
      'add cli',
      'core ',
      'functionality',
      'entrypoint',
    ];
    return signals.any(normalized.contains);
  }

  bool _hasWeakImplementationValidationCommand(
    String validationCommand,
    List<String> implementationTargets,
  ) {
    final normalized = validationCommand.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }
    if (normalized.contains('module importable') ||
        normalized.contains('sys.path.append(') ||
        normalized.contains('sys.path.insert(')) {
      return true;
    }
    if (normalized.startsWith('ls ') ||
        normalized == 'ls' ||
        normalized.startsWith('find ') ||
        normalized.startsWith('cat ') ||
        normalized.startsWith('test -f ') ||
        normalized.startsWith('test -d ')) {
      return true;
    }

    final targetSignals = implementationTargets
        .map((path) => path.trim().toLowerCase())
        .where((path) => path.isNotEmpty)
        .expand(
          (path) => <String>{
            path,
            path.split('/').last,
            path.split('/').last.replaceFirst(RegExp(r'\.[^.]+$'), ''),
          },
        )
        .where((signal) => signal.isNotEmpty)
        .toSet();
    if (targetSignals.any(normalized.contains)) {
      return false;
    }

    const acceptablePrefixes = <String>[
      'pytest',
      'python -m pytest',
      'python3 -m pytest',
      'dart test',
      'flutter test',
      'cargo test',
      'go test',
      'npm test',
      'pnpm test',
      'yarn test',
    ];
    if (acceptablePrefixes.any(normalized.startsWith)) {
      return false;
    }

    return true;
  }

  bool _looksLikeBoundedPingValidationCommand(String normalizedValidation) {
    return normalizedValidation.contains('--help') ||
        RegExp(r'(^|\s)-c(\s|$)').hasMatch(normalizedValidation) ||
        RegExp(r'(^|\s)--count(?:=|\s)').hasMatch(normalizedValidation) ||
        normalizedValidation.contains('unittest') ||
        normalizedValidation.contains('test_') ||
        normalizedValidation.contains('verify_');
  }

  bool _looksLikeUnboundedPingValidationCommand(String normalizedValidation) {
    final launchesPythonEntryPoint = RegExp(
      r'^(python|python3)\s+\S+\.py(?:\s|$)',
    ).hasMatch(normalizedValidation);
    if (!launchesPythonEntryPoint) {
      return false;
    }

    final includesHostTarget =
        normalizedValidation.contains('127.0.0.1') ||
        normalizedValidation.contains('localhost') ||
        RegExp(
          r'(^|\s)(?:\d{1,3}\.){3}\d{1,3}(\s|$)',
        ).hasMatch(normalizedValidation) ||
        RegExp(
          r'(^|\s)[a-z0-9.-]+\.[a-z]{2,}(\s|$)',
        ).hasMatch(normalizedValidation);
    if (!includesHostTarget) {
      return false;
    }

    return !normalizedValidation.contains('--help');
  }

  bool _isTaskProposalPlaceholderTitle(String normalizedTitle) {
    const placeholderTitles = <String>[
      'subsequent tasks should involve',
      'subsequent tasks should include',
      'following tasks should involve',
      'following tasks should include',
      'next tasks should involve',
      'next tasks should include',
      'subsequent task should involve',
      'subsequent task should include',
    ];
    final compact = normalizedTitle.replaceAll(':', '').trim();
    if (placeholderTitles.contains(compact)) {
      return true;
    }
    return RegExp(
      r'^(?:subsequent|following|next)\s+tasks?\s+(?:should|must|will)\s+(?:involve|include|cover)(?::)?$',
      caseSensitive: false,
    ).hasMatch(normalizedTitle);
  }

  List<ConversationWorkflowTask> _reorderTaskProposalTasks(
    List<ConversationWorkflowTask> tasks, {
    required bool projectLooksEmpty,
  }) {
    if (!projectLooksEmpty || tasks.length < 2) {
      return tasks.toList(growable: false);
    }

    final scaffoldIndex = tasks.indexWhere(_looksLikeScaffoldTask);
    if (scaffoldIndex <= 0) {
      return tasks.toList(growable: false);
    }

    final reordered = <ConversationWorkflowTask>[
      tasks[scaffoldIndex],
      ...tasks.take(scaffoldIndex),
      ...tasks.skip(scaffoldIndex + 1),
    ];
    return reordered.take(6).toList(growable: false);
  }

  bool _looksLikeScaffoldTask(ConversationWorkflowTask task) {
    final normalizedTitle = task.title.trim().toLowerCase();
    const titleSignals = <String>[
      'scaffold',
      'bootstrap',
      'initialize project',
      'initialize the project',
      'project structure',
      'initial file',
      'initial files',
      'entrypoint',
      'create main.py',
      'setup project',
      'set up project',
    ];
    if (titleSignals.any(normalizedTitle.contains)) {
      return true;
    }

    final normalizedPaths = task.targetFiles
        .map((path) => path.trim().toLowerCase())
        .where((path) => path.isNotEmpty)
        .toSet();
    return normalizedPaths.contains('pyproject.toml') ||
        normalizedPaths.contains('requirements.txt') ||
        normalizedPaths.contains('readme.md');
  }

  bool _projectLooksEmptyForTaskPlanning(_PlanningResearchContext context) {
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

  String _stripMarkdownListMarker(String value) {
    return value.replaceFirst(RegExp(r'^(?:[-*•]|\d+[.)])\s*'), '').trim();
  }

  String _appendTextValue(String current, String next) {
    if (current.isEmpty) return next;
    return '$current $next';
  }

  String _proposalPreview(String rawContent) {
    var normalized = _normalizeProposalContent(
      rawContent,
    ).replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      normalized = _extractProposalReasoningContent(
        rawContent,
      ).replaceAll(RegExp(r'\s+'), ' ');
    }
    if (normalized.length <= 220) {
      return normalized;
    }
    return '${normalized.substring(0, 220)}...';
  }

  String? _matchTaskTitleLine(String line, {String? currentField}) {
    final normalizedLine = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
    final labeledMatch = RegExp(
      r'^(?:title|task title|task|タイトル|タスク名)\s*[:：-]\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(normalizedLine);
    if (labeledMatch != null) {
      final value = _stripMarkdownListMarker(labeledMatch.group(1) ?? '');
      return value.isEmpty ? null : value;
    }

    final bulletMatch = RegExp(
      r'^([-*•]|\d+[.)])\s+(.+)$',
    ).firstMatch(normalizedLine);
    if (bulletMatch == null) return null;
    final marker = bulletMatch.group(1) ?? '';
    if (currentField != null && !RegExp(r'^\d+[.)]$').hasMatch(marker)) {
      return null;
    }

    final candidate = (bulletMatch.group(2) ?? '').trim();
    final lowerCandidate = candidate.toLowerCase();
    if (lowerCandidate.startsWith('target files') ||
        lowerCandidate.startsWith('validation') ||
        lowerCandidate.startsWith('notes') ||
        lowerCandidate.startsWith('files') ||
        candidate.startsWith('対象ファイル') ||
        candidate.startsWith('確認コマンド') ||
        candidate.startsWith('メモ')) {
      return null;
    }
    return candidate;
  }

  (String, String)? _matchTaskFieldLine(String line) {
    final normalizedLine = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
    for (final entry in {
      'targetFiles': ['target files', 'files', '対象ファイル'],
      'validationCommand': [
        'validation command',
        'validation',
        'check',
        '確認コマンド',
        '確認方法',
      ],
      'notes': ['notes', 'memo', 'メモ'],
    }.entries) {
      for (final label in entry.value) {
        final match = RegExp(
          '^(?:[-*]\\s*)?${RegExp.escape(label)}\\s*[:：-]\\s*(.*)\$',
          caseSensitive: false,
        ).firstMatch(normalizedLine);
        if (match != null) {
          return (entry.key, match.group(1)?.trim() ?? '');
        }
      }
    }
    return null;
  }

  @visibleForTesting
  WorkflowProposalDraft? parseWorkflowProposalForTest(String rawContent) {
    final response = _parseWorkflowProposalResponseWithFallback(rawContent);
    return switch (response) {
      _WorkflowProposalDraftResponse(:final proposal) => proposal,
      _ => null,
    };
  }

  @visibleForTesting
  List<WorkflowPlanningDecision>? parseWorkflowDecisionsForTest(
    String rawContent,
  ) {
    final response = _parseWorkflowProposalResponseWithFallback(rawContent);
    return switch (response) {
      _WorkflowProposalDecisionResponse(:final decisions) => decisions,
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
      researchContext: const _PlanningResearchContext(),
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
      'read_file' || 'write_file' || 'edit_file' => () {
        final resolvedPath = resolvePathArg('path');
        final resolvedArguments = toolName == 'write_file'
            ? _normalizeWriteFileArgumentAliases(arguments)
            : <String, dynamic>{...arguments};
        if (resolvedPath != null) {
          resolvedArguments['path'] = resolvedPath;
        }
        return resolvedArguments;
      }(),
      'local_execute_command' => () {
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
      'git_execute_command' => () {
        final resolvedWorkingDirectory = resolvePathArg(
          'working_directory',
          allowEmpty: true,
          aliases: const ['cwd'],
        );
        final resolvedArguments = <String, dynamic>{...arguments};
        if (resolvedWorkingDirectory != null) {
          resolvedArguments['working_directory'] = resolvedWorkingDirectory;
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
    final messages = sourceMessages
        .where((m) => !m.isStreaming)
        .map(_sanitizeMessageForModelHistory)
        .where(_shouldKeepMessageForModelHistory)
        .toList();
    final shouldForceCompaction =
        forceCompaction || _forcePromptCompactionForNextRequest;
    _forcePromptCompactionForNextRequest = false;
    final promptMessages = <Message>[
      _createSystemMessage(
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

    final strippedContent = ContentParser.stripToolArtifacts(message.content);
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

  final _uuid = const Uuid();
  StreamSubscription<String>? _streamSubscription;

  /// Tracks executed `tool_call`s to avoid duplicate execution.
  final Set<String> _executedContentToolCalls = {};
  final Set<String> _seenContentToolCallHashes = {};
  final List<String> _pendingContentToolResults = [];
  final List<QueuedChatMessage> _queuedChatMessages = [];
  final ToolApprovalCache _toolApprovalCache = ToolApprovalCache();
  static const int _maxContentToolContinuations = 5;
  int _contentToolContinuationCount = 0;
  Future<void> _contentToolExecutionTail = Future<void>.value();
  bool _forcePromptCompactionForNextRequest = false;
  bool _isDrainingQueuedMessages = false;
  int _interactionGeneration = 0;
  String? _activeResponseConversationId;
  List<Message>? _activeResponseMessages;
  final Map<int, String> _activeResponseConversationIdsByGeneration =
      <int, String>{};
  final Map<int, List<Message>> _activeResponseMessagesByGeneration =
      <int, List<Message>>{};
  final Map<int, LlmSessionLogContext> _llmSessionLogContextsByGeneration =
      <int, LlmSessionLogContext>{};
  final Map<int, McpToolResult> _askUserQuestionResultsByGeneration =
      <int, McpToolResult>{};
  final Map<String, PendingAskUserQuestion> _pendingAskUserQuestionsByThread =
      <String, PendingAskUserQuestion>{};
  ChatInteractionOrigin _activeInteractionOrigin = ChatInteractionOrigin.local;

  bool get _isRemoteInteraction =>
      _activeInteractionOrigin == ChatInteractionOrigin.remote;

  int _beginInteractionGeneration() {
    _interactionGeneration += 1;
    return _interactionGeneration;
  }

  bool _isCurrentInteractionGeneration(int generation) {
    return ref.mounted &&
        (generation == _interactionGeneration ||
            _activeResponseConversationIdsByGeneration.containsKey(generation));
  }

  bool get _hasActiveResponse =>
      _activeResponseConversationId != null ||
      _activeResponseConversationIdsByGeneration.isNotEmpty;

  bool get _isActiveResponseDetached =>
      _activeResponseConversationId != null &&
      conversationId != _activeResponseConversationId;

  int? _activeResponseGenerationForConversation(String? targetConversationId) {
    if (targetConversationId == null) return null;
    int? matchedGeneration;
    for (final entry in _activeResponseConversationIdsByGeneration.entries) {
      if (entry.value == targetConversationId &&
          (matchedGeneration == null || entry.key > matchedGeneration)) {
        matchedGeneration = entry.key;
      }
    }
    return matchedGeneration;
  }

  String? _activeResponseConversationIdForGeneration(int generation) {
    return _activeResponseConversationIdsByGeneration[generation] ??
        (generation == _interactionGeneration
            ? _activeResponseConversationId
            : null);
  }

  List<Message>? _activeResponseMessagesForGeneration(int generation) {
    return _activeResponseMessagesByGeneration[generation] ??
        (generation == _interactionGeneration ? _activeResponseMessages : null);
  }

  bool _isActiveResponseDetachedForGeneration(int generation) {
    final targetConversationId = _activeResponseConversationIdForGeneration(
      generation,
    );
    return targetConversationId != null &&
        conversationId != targetConversationId;
  }

  void _registerActiveResponse({
    required int generation,
    required String? targetConversationId,
    required List<Message> messages,
  }) {
    if (targetConversationId == null) return;
    _activeResponseConversationIdsByGeneration[generation] =
        targetConversationId;
    _cacheActiveResponseMessagesForGeneration(generation, messages);
    if (generation == _interactionGeneration) {
      _activeResponseConversationId = targetConversationId;
      _activeResponseMessages = List<Message>.unmodifiable(messages);
    }
  }

  void _cacheActiveResponseMessagesForGeneration(
    int generation,
    List<Message> messages,
  ) {
    if (!_activeResponseConversationIdsByGeneration.containsKey(generation)) {
      return;
    }
    final cached = List<Message>.unmodifiable(messages);
    _activeResponseMessagesByGeneration[generation] = cached;
    if (generation == _interactionGeneration) {
      _activeResponseMessages = cached;
    }
  }

  void _clearActiveResponseForGeneration(int generation) {
    _activeResponseConversationIdsByGeneration.remove(generation);
    _activeResponseMessagesByGeneration.remove(generation);
    _llmSessionLogContextsByGeneration.remove(generation);
    _askUserQuestionResultsByGeneration.remove(generation);
    if (generation == _interactionGeneration) {
      _activeResponseConversationId = null;
      _activeResponseMessages = null;
    }
  }

  void _clearAllActiveResponses() {
    _activeResponseConversationIdsByGeneration.clear();
    _activeResponseMessagesByGeneration.clear();
    _llmSessionLogContextsByGeneration.clear();
    _askUserQuestionResultsByGeneration.clear();
    _activeResponseConversationId = null;
    _activeResponseMessages = null;
  }

  Future<void> sendMessage(
    String content, {
    String? imageBase64,
    String? imageMimeType,
    String languageCode = 'en',
    bool isVoiceMode = false,
    bool bypassPlanMode = false,
    ChatInteractionOrigin origin = ChatInteractionOrigin.local,
  }) async {
    // Do not send empty input with no attached image.
    if (content.trim().isEmpty && imageBase64 == null) return;
    if (!ref.mounted) return;

    final queuedMessage = QueuedChatMessage(
      id: _uuid.v4(),
      content: content,
      imageBase64: imageBase64,
      imageMimeType: imageMimeType,
      languageCode: languageCode,
      isVoiceMode: isVoiceMode,
      bypassPlanMode: bypassPlanMode,
      origin: origin,
    );
    if (state.isLoading) {
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
    final languageCode = queuedMessage.languageCode;
    final isVoiceMode = queuedMessage.isVoiceMode;
    final bypassPlanMode = queuedMessage.bypassPlanMode;
    _activeInteractionOrigin = queuedMessage.origin;
    final interactionGeneration = _beginInteractionGeneration();

    _hiddenPrompt = null;
    _languageCode = languageCode;
    _isVoiceMode = isVoiceMode;
    _toolApprovalCache.clear();
    _pendingContentToolResults.clear();
    _pendingToolExecutions.clear();
    _latestContentToolResults.clear();
    _contentToolContinuationCount = 0;
    _contentToolExecutionTail = Future<void>.value();
    _latestCompletedToolResults = const [];
    _latestHiddenAssistantResponse = null;
    _beginTurnDiffCapture(content);

    _temporalReferenceContext = TemporalContextBuilder.build(
      now: DateTime.now(),
      userInput: content,
    );
    final shouldUseTemporalTool = _temporalReferenceContext != null;
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    var currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    conversationId = currentConversation?.id;
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
    );

    if (!ref.mounted) return;
    state = state.copyWith(
      messages: [...state.messages, userMessage],
      isLoading: true,
      error: null,
    );
    _llmSessionLogContextsByGeneration[interactionGeneration] =
        _buildLlmSessionLogContext(targetConversationId: conversationId);
    _registerActiveResponse(
      generation: interactionGeneration,
      targetConversationId: conversationId,
      messages: state.messages,
    );
    _persistCurrentNonStreamingMessages();

    await conversationsNotifier.ensureCurrentPlanArtifactBackfilled();
    if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
    currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    conversationId = currentConversation?.id;
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
        return;
      }
      currentConversation = ref
          .read(conversationsNotifierProvider)
          .currentConversation;
      conversationId = currentConversation?.id;
      if (currentConversation == null) {
        state = state.copyWith(isLoading: false);
        return;
      }
      await _runPlanProposalFlow(
        currentConversation: currentConversation,
        languageCode: languageCode,
      );
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

    // Request extended background execution time on iOS.
    _onSendStarted();

    _assistantModeOverride = bypassPlanMode ? AssistantMode.coding : null;

    try {
      // Use tool-aware flow when the MCP tool service is available.
      if (_mcpToolService != null &&
          (_settings.mcpEnabled || shouldUseTemporalTool)) {
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
  }) async {
    if (!ref.mounted) return;

    _temporalReferenceContext = null;
    _isVoiceMode = isVoiceMode;
    _languageCode = languageCode;
    _latestHiddenAssistantResponse = null;
    final interactionGeneration = _beginInteractionGeneration();
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

    _onSendStarted();

    // Use tool-aware flow when the MCP tool service is available.
    if (_mcpToolService != null && _settings.mcpEnabled) {
      appLog('[Tool] Sending hidden prompt in tool-aware mode');
      await _sendWithTools(interactionGeneration: interactionGeneration);
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
      final result = await _dataSource.createChatCompletion(
        messages: ConversationGoalSuggestionService.buildMessages(
          conversation: currentConversation,
          languageCode: languageCode,
          pendingUserMessage: pendingUserMessage,
          clarificationQuestion: clarificationQuestion,
          clarificationAnswer: clarificationAnswer,
        ),
        model: _settings.model,
        temperature: 0.1,
        maxTokens: _settings.maxTokens > 600 ? 600 : _settings.maxTokens,
      );
      final suggestion = ConversationGoalSuggestionService.parse(
        result.content,
      );
      if (suggestion != null) {
        appLog(
          '[Goal] Suggested goal response: '
          '${ConversationGoalSuggestionService.encodeForDebug(suggestion)}',
        );
        return suggestion;
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

  int _hiddenAssistantEvidenceScore(String response) {
    final normalized = response.toLowerCase();
    var score = 0;
    if (normalized.contains('complete') || normalized.contains('completed')) {
      score += 2;
    }
    if (normalized.contains('validation passed') ||
        normalized.contains('tests passed') ||
        normalized.contains('was successful')) {
      score += 2;
    }
    if (normalized.contains('next task') ||
        normalized.contains('saved task') ||
        normalized.contains('in the plan')) {
      score += 1;
    }
    return score;
  }

  bool _shouldAcceptRecoveryFinalTextResponse(String response) {
    final candidate = response.trim();
    if (candidate.isEmpty) {
      return false;
    }
    return _hiddenAssistantEvidenceScore(candidate) >= 2;
  }

  bool _shouldAcceptTerminalToolRoleFinalTextResponse(String response) {
    final candidate = response.trim();
    if (candidate.isEmpty) {
      return false;
    }

    final normalized = candidate.toLowerCase();
    if (_hiddenAssistantEvidenceScore(candidate) < 2) {
      return false;
    }
    if (!normalized.contains('complete')) {
      return false;
    }
    final mentionsTaskReference =
        normalized.contains('task "') ||
        normalized.contains('task `') ||
        RegExp(r'task [0-9a-f-]{8,}').hasMatch(normalized);
    if (!mentionsTaskReference) {
      return false;
    }
    if (normalized.contains('next task') ||
        normalized.contains('shall i proceed') ||
        normalized.contains('i will ') ||
        normalized.contains('i can continue')) {
      return false;
    }
    return true;
  }

  bool _shouldAcceptTerminalSkillToolRoleResponse(
    String response,
    List<ToolResultInfo> toolResults,
  ) {
    final candidate = response.trim();
    if (candidate.isEmpty || candidate.length > 3000) {
      return false;
    }
    if (!_hasSuccessfulLoadSkillResult(toolResults)) {
      return false;
    }
    if (_looksLikeStructuredToolRequest(candidate)) {
      return false;
    }
    if (_looksLikePlanOnlyFinalToolAnswer(candidate) &&
        !_matchesLoadedSkillExplicitMarker(
          response: candidate,
          toolResults: toolResults,
        )) {
      return false;
    }
    return true;
  }

  bool _shouldAcceptConstrainedSkillResponseBeforeFollowUpTools(
    String response,
    List<ToolResultInfo> toolResults,
  ) {
    return _shouldAcceptTerminalSkillToolRoleResponse(response, toolResults) &&
        _matchesLoadedSkillExplicitMarker(
          response: response,
          toolResults: toolResults,
        );
  }

  String _normalizeTerminalSkillToolRoleResponse(
    String response,
    List<ToolResultInfo> toolResults,
  ) {
    var candidate = response.trim();
    if (!_hasSuccessfulLoadSkillResult(toolResults)) {
      return candidate;
    }
    candidate = _stripTrailingOptionalSkillFollowUp(candidate);
    candidate = _stripTrailingSkillContinuationIntent(candidate);
    return candidate.trim();
  }

  String _stripTrailingOptionalSkillFollowUp(String content) {
    final dividerMatches = RegExp(
      r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$',
      multiLine: true,
    ).allMatches(content).toList(growable: false);
    if (dividerMatches.isNotEmpty) {
      final lastDivider = dividerMatches.last;
      final trailing = content.substring(lastDivider.end).trim();
      if (_looksLikeOptionalSkillFollowUp(trailing)) {
        return content.substring(0, lastDivider.start).trimRight();
      }
    }

    final paragraphs = content.split(RegExp(r'\n\s*\n'));
    if (paragraphs.length < 2) {
      return content;
    }
    final trailing = paragraphs.last.trim();
    if (!_looksLikeOptionalSkillFollowUp(trailing)) {
      return content;
    }
    final prefix = content.substring(0, content.lastIndexOf(paragraphs.last));
    return prefix.trimRight();
  }

  bool _looksLikeOptionalSkillFollowUp(String content) {
    final candidate = content.trim();
    if (candidate.isEmpty || candidate.length > 500) {
      return false;
    }
    if (candidate.split(RegExp(r'\n\s*\n')).length > 1) {
      return false;
    }

    final normalized = candidate.toLowerCase();
    final hasQuestion =
        normalized.contains('?') ||
        candidate.contains(String.fromCharCode(0xff1f));
    if (!hasQuestion) {
      return false;
    }

    if (_containsAny(normalized, const [
      'would you like me',
      'do you want me',
      'should i',
      'shall i',
      'can i proceed',
      'i can proceed',
      'proceed with',
      'execute these',
      'run these',
      'run the checks',
      'continue with',
      'current project',
      'project directory',
      'repository',
    ])) {
      return true;
    }

    return _containsCjkOptionalSkillFollowUpMarker(candidate);
  }

  String _stripTrailingSkillContinuationIntent(String content) {
    final dividerMatches = RegExp(
      r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$',
      multiLine: true,
    ).allMatches(content).toList(growable: false);
    if (dividerMatches.isNotEmpty) {
      final lastDivider = dividerMatches.last;
      final trailing = content.substring(lastDivider.end).trim();
      if (_looksLikeSkillContinuationIntent(trailing)) {
        return content.substring(0, lastDivider.start).trimRight();
      }
    }

    final paragraphs = content.split(RegExp(r'\n\s*\n'));
    if (paragraphs.length < 2) {
      return content;
    }
    final trailing = paragraphs.last.trim();
    if (!_looksLikeSkillContinuationIntent(trailing)) {
      return content;
    }
    final prefix = content.substring(0, content.lastIndexOf(paragraphs.last));
    return prefix.trimRight();
  }

  bool _looksLikeSkillContinuationIntent(String content) {
    final candidate = content.trim();
    if (candidate.isEmpty || candidate.length > 500) {
      return false;
    }
    if (candidate.split(RegExp(r'\n\s*\n')).length > 1) {
      return false;
    }

    final normalized = candidate.toLowerCase();
    if (_containsAny(normalized, const [
      'first, i will',
      'first i will',
      'next, i will',
      'now i will',
      'i will now',
      'i will inspect',
      'i will check',
      'i will run',
      'i will execute',
      'i will retrieve',
      'i will get',
      "i'll inspect",
      "i'll check",
      "i'll run",
      'let me inspect',
      'let me check',
      'let me run',
      'let me verify',
      'i am going to',
      "i'm going to",
      'start by checking',
      'begin by checking',
    ])) {
      return true;
    }

    return _containsCjkSkillContinuationIntentMarker(candidate);
  }

  bool _containsCjkSkillContinuationIntentMarker(String value) {
    final startMarkers = [
      String.fromCharCodes([0x307e, 0x305a]),
      String.fromCharCodes([0x6b21, 0x306b]),
      String.fromCharCodes([0x3053, 0x308c, 0x304b, 0x3089]),
      String.fromCharCodes([0x5b9f, 0x969b, 0x306b]),
      String.fromCharCodes([0x73fe, 0x5728, 0x306e]),
    ];
    final actionMarkers = [
      String.fromCharCodes([0x898b, 0x3066]),
      String.fromCharCodes([0x898b, 0x307e, 0x3059]),
      String.fromCharCodes([0x898b, 0x307e, 0x3057, 0x3087, 0x3046]),
      String.fromCharCodes([0x9032, 0x3081]),
      String.fromCharCodes([0x78ba, 0x8a8d]),
      String.fromCharCodes([0x53d6, 0x5f97]),
      String.fromCharCodes([0x5b9f, 0x884c]),
      String.fromCharCodes([0x691c, 0x8a3c]),
    ];
    return startMarkers.any(value.contains) &&
        actionMarkers.any(value.contains);
  }

  bool _containsCjkOptionalSkillFollowUpMarker(String value) {
    final executionMarkers = [
      String.fromCharCodes([0x5b9f, 0x884c]),
      String.fromCharCodes([0x9032, 0x3081]),
    ];
    final permissionMarkers = [
      String.fromCharCodes([0x3088, 0x308d, 0x3057, 0x3044]),
      String.fromCharCodes([0x3067, 0x3057, 0x3087, 0x3046, 0x304b]),
      String.fromCharCodes([0x3057, 0x307e, 0x3059, 0x304b]),
      String.fromCharCodes([0x304f, 0x3060, 0x3055, 0x3044]),
    ];
    return executionMarkers.any(value.contains) &&
        permissionMarkers.any(value.contains);
  }

  bool _hasSuccessfulLoadSkillResult(List<ToolResultInfo> toolResults) {
    return toolResults.any(
      (toolResult) =>
          toolResult.name.trim().toLowerCase() == 'load_skill' &&
          _toolResultLooksSuccessfulForFinalAnswer(toolResult.result),
    );
  }

  bool _toolResultLooksSuccessfulForFinalAnswer(String result) {
    final trimmed = result.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase().startsWith('error:')) {
      return false;
    }
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<Object?, Object?>) {
        final keys = decoded.keys
            .whereType<String>()
            .map((key) => key.toLowerCase())
            .toSet();
        if (keys.contains('error')) {
          return false;
        }
        Object? codeValue;
        for (final entry in decoded.entries) {
          final key = entry.key;
          if (key is String && key.toLowerCase() == 'code') {
            codeValue = entry.value;
            break;
          }
        }
        final code = codeValue?.toString().toLowerCase();
        if (code != null &&
            (code.contains('denied') ||
                code.contains('failure') ||
                code.contains('failed') ||
                code.contains('not_executed'))) {
          return false;
        }
      }
    } on FormatException {
      return true;
    }
    return true;
  }

  bool _matchesLoadedSkillExplicitMarker({
    required String response,
    required List<ToolResultInfo> toolResults,
  }) {
    final responseMarkers = RegExp(
      r'\b[A-Z][A-Z0-9_]{5,}\b',
    ).allMatches(response).map((match) => match.group(0)).nonNulls.toSet();
    if (responseMarkers.isEmpty) {
      return false;
    }
    for (final toolResult in toolResults) {
      if (toolResult.name.trim().toLowerCase() != 'load_skill') {
        continue;
      }
      for (final marker in responseMarkers) {
        if (toolResult.result.contains(marker)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _shouldAcceptTerminalToolRoleBlockerResponse(String response) {
    final candidate = response.trim();
    if (candidate.isEmpty || candidate.length > 3000) {
      return false;
    }
    if (_looksLikeUnexecutedToolRequest(candidate) ||
        _looksLikePlanOnlyFinalToolAnswer(candidate)) {
      return false;
    }

    final normalized = candidate.toLowerCase();
    final hasBlockerMarker = _containsAny(normalized, const [
      'blocked',
      'blocker',
      'cannot continue',
      "can't continue",
      'unable to continue',
      'required before',
      'is required',
      'are required',
      'not available',
      'not present',
      'missing',
      'does not exist',
      'permission denied',
      'access denied',
      'need access',
      'need the source',
      'need the repository',
      'need the path',
      'need the file',
      'need the logs',
      'please provide',
    ]);
    final hasMissingEvidenceMarker = _containsAny(normalized, const [
      'source code',
      'repository',
      'repo',
      'path',
      'file',
      'logs',
      'runtime data',
      'permission',
      'access',
      'credentials',
      'external dependency',
      'external package',
      'implementation',
    ]);
    final hasCjkBlockerMarker = _containsCjkBlockerMarker(candidate);
    final hasCjkMissingEvidenceMarker = _containsCjkMissingEvidenceMarker(
      candidate,
    );
    return (hasBlockerMarker && hasMissingEvidenceMarker) ||
        (hasCjkBlockerMarker && hasCjkMissingEvidenceMarker);
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

    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (currentConversation == null) return;

    await _runPlanProposalFlow(
      currentConversation: currentConversation,
      languageCode: languageCode,
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
    state = state.copyWith(
      isLoading: false,
      isGeneratingWorkflowProposal: false,
      isGeneratingTaskProposal: false,
      pendingWorkflowDecision: PendingWorkflowDecision(
        id: const Uuid().v4(),
        decision: decision,
        completer: completer,
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

  Future<McpToolResult> _handleAskUserQuestion(
    ToolCallInfo toolCall, {
    int? interactionGeneration,
  }) async {
    final existingResult = interactionGeneration == null
        ? null
        : _askUserQuestionResultsByGeneration[interactionGeneration];
    if (existingResult != null) {
      appLog(
        '[AskUserQuestion] Reusing completed answer for repeated question in the same turn',
      );
      return _buildRepeatedAskUserQuestionResult(existingResult);
    }

    final question = _trimStringArgument(toolCall.arguments, 'question');
    if (question.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'question is required',
      );
    }

    final options = _parseAskUserQuestionOptions(toolCall.arguments['options']);
    final allowOther = toolCall.arguments['allow_other'] as bool? ?? true;
    if (options.isEmpty && !allowOther) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'at least one option or allow_other is required',
      );
    }

    final answer = await requestAskUserQuestion(
      question: question,
      help: _trimStringArgument(toolCall.arguments, 'help'),
      options: options,
      allowMultiple: toolCall.arguments['allow_multiple'] as bool? ?? false,
      allowOther: allowOther,
      otherPlaceholder: _trimStringArgument(
        toolCall.arguments,
        'other_placeholder',
      ),
      targetConversationId: interactionGeneration == null
          ? null
          : _activeResponseConversationIdForGeneration(interactionGeneration),
    );
    if (answer == null || !answer.hasAnswer) {
      final result = McpToolResult(
        toolName: toolCall.name,
        result: jsonEncode({'question': question, 'status': 'cancelled'}),
        isSuccess: false,
        errorMessage: 'User dismissed the question',
      );
      if (interactionGeneration != null) {
        _askUserQuestionResultsByGeneration[interactionGeneration] = result;
      }
      return result;
    }

    final result = McpToolResult(
      toolName: toolCall.name,
      result: jsonEncode({'status': 'answered', ...answer.toJson()}),
      isSuccess: true,
    );
    if (interactionGeneration != null) {
      _askUserQuestionResultsByGeneration[interactionGeneration] = result;
    }
    return result;
  }

  McpToolResult _buildRepeatedAskUserQuestionResult(McpToolResult previous) {
    final decoded = _decodeJsonObject(previous.result);
    final result = decoded == null
        ? previous.result
        : jsonEncode({
            ...decoded,
            'reused': true,
            'note':
                'The user already answered ask_user_question during this turn. Continue using the existing answer and do not ask again.',
          });
    return McpToolResult(
      toolName: previous.toolName,
      result: result,
      isSuccess: previous.isSuccess,
      errorMessage: previous.errorMessage,
    );
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

  Future<AskUserQuestionAnswer?> requestAskUserQuestion({
    required String question,
    required String help,
    required List<AskUserQuestionOption> options,
    required bool allowMultiple,
    required bool allowOther,
    required String otherPlaceholder,
    String? targetConversationId,
  }) {
    final resolvedTargetConversationId =
        targetConversationId ?? _activeResponseConversationId ?? conversationId;
    final existingPending = resolvedTargetConversationId == null
        ? state.pendingAskUserQuestion
        : _pendingAskUserQuestionsByThread[resolvedTargetConversationId];
    if (existingPending != null) {
      appLog('[AskUserQuestion] Ignoring question while another is pending');
      return Future<AskUserQuestionAnswer?>.value();
    }
    final completer = Completer<AskUserQuestionAnswer?>();
    final pending = PendingAskUserQuestion(
      id: const Uuid().v4(),
      conversationId: resolvedTargetConversationId,
      question: question,
      help: help,
      options: options,
      allowMultiple: allowMultiple,
      allowOther: allowOther,
      otherPlaceholder: otherPlaceholder,
      completer: completer,
    );
    if (resolvedTargetConversationId != null) {
      _pendingAskUserQuestionsByThread[resolvedTargetConversationId] = pending;
    }
    if (resolvedTargetConversationId == null ||
        conversationId == resolvedTargetConversationId) {
      state = state.copyWith(pendingAskUserQuestion: pending);
    }
    return completer.future;
  }

  void resolveAskUserQuestion({
    required String id,
    AskUserQuestionAnswer? answer,
  }) {
    final pending = state.pendingAskUserQuestion?.id == id
        ? state.pendingAskUserQuestion
        : _pendingAskUserQuestionsByThread.values
              .where((item) => item.id == id)
              .firstOrNull;
    if (pending == null) return;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(answer);
    }
    final pendingConversationId = pending.conversationId;
    if (pendingConversationId != null) {
      _pendingAskUserQuestionsByThread.remove(pendingConversationId);
    }
    if (state.pendingAskUserQuestion?.id == id) {
      state = state.copyWith(pendingAskUserQuestion: null);
    }
  }

  void _dismissAllPendingAskUserQuestions() {
    final pendingQuestions = <PendingAskUserQuestion>[
      ..._pendingAskUserQuestionsByThread.values,
      if (state.pendingAskUserQuestion != null &&
          !_pendingAskUserQuestionsByThread.values.any(
            (pending) => pending.id == state.pendingAskUserQuestion!.id,
          ))
        state.pendingAskUserQuestion!,
    ];

    for (final pending in pendingQuestions) {
      if (!pending.completer.isCompleted) {
        pending.completer.complete();
      }
    }
    _pendingAskUserQuestionsByThread.clear();
    if (state.pendingAskUserQuestion != null) {
      state = state.copyWith(pendingAskUserQuestion: null);
    }
  }

  String _trimStringArgument(Map<String, dynamic> arguments, String key) {
    return (arguments[key] as String?)?.trim() ?? '';
  }

  List<AskUserQuestionOption> _parseAskUserQuestionOptions(dynamic rawOptions) {
    if (rawOptions is! List) {
      return const [];
    }

    final options = <AskUserQuestionOption>[];
    final usedIds = <String>{};
    for (
      var index = 0;
      index < rawOptions.length && options.length < 8;
      index++
    ) {
      final rawOption = rawOptions[index];
      String label;
      String id;
      String description = '';
      String preview = '';

      if (rawOption is String) {
        label = rawOption.trim();
        id = _askUserQuestionOptionId(label, index);
      } else if (rawOption is Map) {
        label = (rawOption['label'] as String?)?.trim() ?? '';
        id = (rawOption['id'] as String?)?.trim().isNotEmpty == true
            ? (rawOption['id'] as String).trim()
            : _askUserQuestionOptionId(label, index);
        description = (rawOption['description'] as String?)?.trim() ?? '';
        preview = (rawOption['preview'] as String?)?.trim() ?? '';
      } else {
        continue;
      }

      if (label.isEmpty) {
        continue;
      }
      var uniqueId = id;
      var suffix = 2;
      while (!usedIds.add(uniqueId)) {
        uniqueId = '$id-$suffix';
        suffix++;
      }
      options.add(
        AskUserQuestionOption(
          id: uniqueId,
          label: _clipAskUserQuestionText(label, 120),
          description: _clipAskUserQuestionText(description, 500),
          preview: _clipAskUserQuestionText(preview, 2000),
        ),
      );
    }
    return options;
  }

  String _askUserQuestionOptionId(String label, int index) {
    final normalized = label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (normalized.isNotEmpty) {
      return normalized.length > 40 ? normalized.substring(0, 40) : normalized;
    }
    return 'option-${index + 1}';
  }

  String _clipAskUserQuestionText(String value, int maxLength) {
    final normalized = value.trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 3)}...';
  }

  Future<void> _runPlanProposalFlow({
    required Conversation currentConversation,
    required String languageCode,
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
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        isLoading: false,
        isGeneratingTaskProposal: false,
        taskProposalDraft: null,
        taskProposalError: error.toString(),
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
          temperature: _settings.temperature,
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
          temperature: _settings.temperature,
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

  Future<String> _streamToolResultAnswerWithContextRetry({
    required List<ToolResultInfo> toolResults,
    required int interactionGeneration,
  }) async {
    Future<String> streamAnswer({
      required bool forceCompaction,
      required ToolResultPromptBudgetMode budgetMode,
    }) async {
      return _runWithLlmSessionLogContextForGeneration(
        interactionGeneration,
        () async {
          final streamedAnswer = StringBuffer();
          final messagesForLLM = _prepareMessagesForLLM(
            forceCompaction: forceCompaction,
            toolDefinitionsOverride: const <Map<String, dynamic>>[],
            interactionGeneration: interactionGeneration,
          );
          messagesForLLM.addAll(
            _buildToolResultAnswerMessages(toolResults, budgetMode: budgetMode),
          );

          _appendToLastMessageForGeneration(interactionGeneration, '<think>');

          final stream = _dataSource.streamChatCompletion(
            messages: messagesForLLM,
            model: _settings.model,
            temperature: _settings.temperature,
            maxTokens: _settings.maxTokens,
          );

          var isFirstChunk = true;
          await for (final chunk in stream) {
            if (!_isCurrentInteractionGeneration(interactionGeneration)) {
              return '';
            }
            if (!ref.mounted) return '';
            if (isFirstChunk) {
              isFirstChunk = false;
              _removeTrailingThinkTagForGeneration(interactionGeneration);
              final activeMessages =
                  _activeResponseMessagesForGeneration(interactionGeneration) ??
                  state.messages;
              if (activeMessages.isNotEmpty &&
                  activeMessages.last.content.isNotEmpty) {
                _appendToLastMessageForGeneration(
                  interactionGeneration,
                  '\n',
                  scanForTools: false,
                );
              }
            }
            _appendToLastMessageForGeneration(
              interactionGeneration,
              chunk,
              scanForTools: false,
            );
            streamedAnswer.write(chunk);
          }
          if (isFirstChunk) {
            _removeTrailingThinkTagForGeneration(interactionGeneration);
          }
          _stripToolArtifactsFromLastAssistantMessage(
            interactionGeneration: interactionGeneration,
          );
          _appendUnexecutedToolRequestNoticeIfNeeded(
            interactionGeneration: interactionGeneration,
          );
          return ContentParser.stripToolArtifacts(
            streamedAnswer.toString(),
          ).trim();
        },
      );
    }

    try {
      return await streamAnswer(
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
        '[Compaction] Retrying final tool-result answer after context-length '
        'error with ${hasCompactableHistory ? 'forced prompt compaction' : 'unchanged prompt history'} '
        'and compact tool results',
      );
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return '';
      _removeTrailingThinkTagForGeneration(interactionGeneration);
      return streamAnswer(
        forceCompaction: hasCompactableHistory,
        budgetMode: ToolResultPromptBudgetMode.compact,
      );
    }
  }

  /// Sends a request with tool support (function calling).
  Future<void> _sendWithTools({
    bool allowContextRetry = true,
    int? interactionGeneration,
  }) async {
    if (!ref.mounted) return;
    final generation = interactionGeneration ?? _interactionGeneration;
    try {
      // Fetch tool definitions from the MCP tool service.
      final allTools = _mcpToolService?.getOpenAiToolDefinitions() ?? [];
      if (allTools.isEmpty) {
        // Fall back to normal streaming when no tools are available.
        await _sendWithoutTools(
          allowContextRetry: allowContextRetry,
          interactionGeneration: generation,
        );
        return;
      }
      appLog(
        '[Tool] Tool definitions: ${allTools.map((t) => (t['function'] as Map?)?['name']).toList()}',
      );

      final initialToolSelection =
          ToolDefinitionSearchService.buildInitialSelection(allTools);
      if (initialToolSelection.toolSearchEnabled) {
        appLog(
          '[ToolSearch] Enabled dynamic tool loading. Initial tools: '
          '${ToolDefinitionSearchService.toolNamesFromDefinitions(initialToolSelection.toolDefinitions).toList()}',
        );
      }
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
          temperature: _settings.temperature,
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
        await _executeToolCalls(
          result.toolCalls!,
          assistantContent: result.content.isNotEmpty ? result.content : null,
          toolSearchEnabled: initialToolSelection.toolSearchEnabled,
          selectedToolNames: initialToolSelection.selectedToolNames,
          interactionGeneration: generation,
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
            interactionGeneration: generation,
          );
          return;
        }
        // No tool calls — content was already streamed in real-time.
        appLog('[Tool] No tool calls, response already streamed');
        final hiddenAssistantEvidence = streamedAssistantContent.isNotEmpty
            ? streamedAssistantContent
            : result.content;
        _recordHiddenAssistantResponse(hiddenAssistantEvidence);
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
            ),
          )) {
        return;
      }

      if (!_isCurrentInteractionGeneration(generation)) return;

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
    }
  }

  List<ToolResultInfo> _budgetToolResultsForPrompt(
    List<ToolResultInfo> toolResults, {
    ToolResultPromptBudgetMode mode = ToolResultPromptBudgetMode.normal,
  }) {
    return ToolResultPromptBuilder.budgetToolResults(toolResults, mode: mode);
  }

  bool _hasAdditionalCompactToolResultBudget(List<ToolResultInfo> toolResults) {
    return ToolResultPromptBuilder.hasAdditionalCompactBudgetReduction(
      toolResults,
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

    final changedPaths = _changedFileMutationPaths(toolResults);
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
          '[CodingDiagnostics] Added analyzer feedback for '
          '${changedPaths.length} changed file(s)',
        );
        _logCodingDiagnosticFeedbackSummary(feedback);
      }
      return feedback;
    } catch (error, stackTrace) {
      appLog('[CodingDiagnostics] Failed to collect analyzer feedback: $error');
      appLog('[CodingDiagnostics] stackTrace: $stackTrace');
      return null;
    }
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

    final changedPaths = _changedFileMutationCallPaths(toolCalls);
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

  Future<ToolResultInfo?> _buildCodingVerificationFeedbackToolResult(
    List<ToolResultInfo> toolResults, {
    required int interactionGeneration,
    required CodingVerificationTrigger trigger,
  }) async {
    if (!_codingVerificationEnabledFor(trigger)) {
      return null;
    }
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

    final changedPaths = _changedFileMutationPaths(toolResults);
    if (changedPaths.isEmpty) {
      return null;
    }

    try {
      final verification = await _codingVerificationFeedbackService
          .buildFeedbackRun(
            projectRoot: projectRoot,
            changedPaths: changedPaths,
            trigger: trigger,
          );
      if (!_isCurrentInteractionGeneration(interactionGeneration)) {
        return null;
      }
      await _recordCodingVerificationValidationProgress(verification.snapshot);
      final feedback = verification.toolResult;
      if (feedback != null) {
        appLog(
          '[CodingVerification] Added test feedback for '
          '${changedPaths.length} changed file(s)',
        );
        _logCodingVerificationFeedbackSummary(feedback);
      }
      return verification.toolResult;
    } catch (error, stackTrace) {
      appLog('[CodingVerification] Failed to collect test feedback: $error');
      appLog('[CodingVerification] stackTrace: $stackTrace');
      return null;
    }
  }

  Future<ChatCompletionResult?>
  _requestCodingVerificationRepairForCompletionClaim({
    required String candidateResponse,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolResultInfo> batchToolResults,
    required Set<String> attemptedMutationSignatures,
    required Map<String, int> verificationFailureCounts,
    required List<Map<String, dynamic>> tools,
    required int interactionGeneration,
  }) async {
    if (!_codingVerificationEnabledFor(
      CodingVerificationTrigger.completionClaim,
    )) {
      return null;
    }
    if (!_shouldVerifyCodingCompletionClaim(candidateResponse)) {
      return null;
    }
    final mutationSignature = _codingVerificationMutationSignature(
      executedToolResults,
    );
    if (mutationSignature == null) {
      return null;
    }
    if (!attemptedMutationSignatures.add(mutationSignature)) {
      appLog(
        '[CodingVerification] Skipping duplicate completion verification '
        'for unchanged file mutations',
      );
      return null;
    }
    final feedback = await _buildCodingVerificationFeedbackToolResult(
      executedToolResults,
      interactionGeneration: interactionGeneration,
      trigger: CodingVerificationTrigger.completionClaim,
    );
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return null;
    }
    if (feedback == null) {
      return null;
    }
    final failureSignature = _codingVerificationFailureSignature(feedback);
    if (failureSignature != null) {
      final failureCount =
          (verificationFailureCounts[failureSignature] ?? 0) + 1;
      verificationFailureCounts[failureSignature] = failureCount;
      if (failureCount > _maxRepeatedCodingVerificationRepairAttempts) {
        appLog(
          '[CodingVerification] Repeated failing test signature reached the '
          'repair limit; surfacing blocker',
        );
        return ChatCompletionResult(
          content: _codingVerificationConvergenceBlocker(feedback),
          finishReason: 'stop',
        );
      }
    }

    final promptFeedback = await _toolResultArtifactStore.persistIfLarge(
      feedback,
      conversationId:
          _activeResponseConversationIdForGeneration(interactionGeneration) ??
          conversationId,
    );
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return null;
    }
    batchToolResults.add(promptFeedback);
    executedToolResults.add(promptFeedback);

    appLog(
      '[CodingVerification] Completion claim blocked by failing tests; '
      'requesting repair',
    );
    _appendToLastMessageForGeneration(interactionGeneration, '<think>');
    try {
      return await _createToolResultCompletionWithContextRetry(
        logLabel: 'coding verification feedback',
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

  bool _codingVerificationEnabledFor(CodingVerificationTrigger trigger) {
    if (!_settings.enableCodingVerificationFeedback) {
      return false;
    }
    return switch (trigger) {
      CodingVerificationTrigger.completionClaim =>
        _settings.runsCodingVerificationOnCompletionClaim,
      CodingVerificationTrigger.explicitRequest =>
        _settings.codingVerificationTriggerPolicy !=
            CodingVerificationTriggerPolicy.off,
      CodingVerificationTrigger.quietPeriod =>
        _settings.codingVerificationTriggerPolicy ==
            CodingVerificationTriggerPolicy.onCompletionClaim,
    };
  }

  Future<void> _recordCodingVerificationValidationProgress(
    CodingVerificationSnapshot? snapshot,
  ) async {
    if (snapshot == null) {
      return;
    }
    final conversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (conversation == null || conversation.projectedExecutionTasks.isEmpty) {
      return;
    }
    final task =
        ConversationPlanExecutionCoordinator.validationTask(conversation) ??
        ConversationPlanExecutionCoordinator.executionFocusTask(conversation);
    if (task == null) {
      return;
    }

    final status = switch (snapshot.validationStatus) {
      ConversationExecutionValidationStatus.passed =>
        ConversationWorkflowTaskStatus.completed,
      ConversationExecutionValidationStatus.failed =>
        ConversationWorkflowTaskStatus.blocked,
      ConversationExecutionValidationStatus.unknown =>
        task.status == ConversationWorkflowTaskStatus.pending
            ? ConversationWorkflowTaskStatus.inProgress
            : task.status,
    };
    final validationSummary = _codingVerificationValidationSummary(snapshot);
    final conversationsNotifier = ref.read(
      conversationsNotifierProvider.notifier,
    );
    await conversationsNotifier.updateCurrentExecutionTaskProgress(
      taskId: task.id,
      status: status,
      allowStatusRegression: true,
      validationStatus: snapshot.validationStatus,
      lastValidationAt: DateTime.now(),
      lastValidationCommand: _codingVerificationCommandSummary(snapshot),
      lastValidationSummary: validationSummary,
      summary: _codingVerificationProgressSummary(snapshot),
      blockedReason:
          snapshot.validationStatus ==
              ConversationExecutionValidationStatus.failed
          ? validationSummary
          : '',
      eventType: ConversationExecutionTaskEventType.validated,
      eventSummary: validationSummary,
    );

    if (!conversation.shouldPreferPlanDocument) {
      return;
    }
    await conversationsNotifier.updateCurrentWorkflow(
      workflowStage: status == ConversationWorkflowTaskStatus.completed
          ? ConversationWorkflowStage.review
          : ConversationWorkflowStage.implement,
      preserveWorkflowProjection: true,
    );
  }

  String _codingVerificationCommandSummary(
    CodingVerificationSnapshot snapshot,
  ) {
    final command = snapshot.selectedAttempt?.command;
    if (command != null) {
      return [command.executable, ...command.arguments].join(' ');
    }
    final targets = snapshot.targetBatches
        .expand((batch) => batch.targets)
        .toList(growable: false);
    if (targets.isEmpty) {
      return 'coding verification';
    }
    return 'coding verification ${targets.join(' ')}';
  }

  String _codingVerificationProgressSummary(
    CodingVerificationSnapshot snapshot,
  ) {
    final counts = _codingVerificationCountsSummary(snapshot);
    final suffix = counts.isEmpty ? '' : ' ($counts)';
    return switch (snapshot.validationStatus) {
      ConversationExecutionValidationStatus.passed =>
        'Coding verification passed$suffix.',
      ConversationExecutionValidationStatus.failed =>
        'Coding verification failed$suffix.',
      ConversationExecutionValidationStatus.unknown =>
        'Coding verification was inconclusive${snapshot.reason == null ? '' : ': ${snapshot.reason}'}$suffix.',
    };
  }

  String _codingVerificationValidationSummary(
    CodingVerificationSnapshot snapshot,
  ) {
    if (snapshot.validationStatus ==
            ConversationExecutionValidationStatus.failed &&
        snapshot.failures.isNotEmpty) {
      final failure = snapshot.failures.first;
      final locationParts = [
        failure.absolutePath == null
            ? null
            : DartProjectPath.relativePath(
                failure.absolutePath!,
                snapshot.projectRoot,
              ),
        if (failure.line != null) 'line ${failure.line}',
      ].whereType<String>().where((part) => part.trim().isNotEmpty);
      final location = locationParts.join(':');
      final label = [
        if (location.isNotEmpty) location,
        if (failure.testName.trim().isNotEmpty) failure.testName.trim(),
      ].join(' ');
      final message = failure.message.trim().isEmpty
          ? 'Test failed.'
          : failure.message.trim();
      return label.isEmpty ? message : '$label: $message';
    }
    return _codingVerificationProgressSummary(snapshot);
  }

  String _codingVerificationCountsSummary(CodingVerificationSnapshot snapshot) {
    final parts = <String>[
      if (snapshot.passedCount > 0) '${snapshot.passedCount} passed',
      if (snapshot.failedCount > 0) '${snapshot.failedCount} failed',
      if (snapshot.skippedCount > 0) '${snapshot.skippedCount} skipped',
    ];
    return parts.join(', ');
  }

  bool _shouldVerifyCodingCompletionClaim(String response) {
    final candidate = response.trim();
    if (candidate.isEmpty) {
      return false;
    }
    final normalized = candidate.toLowerCase();
    if (normalized.contains('not complete') ||
        normalized.contains('not completed') ||
        normalized.contains('incomplete')) {
      return false;
    }
    return _hiddenAssistantEvidenceScore(candidate) >= 2 ||
        normalized.contains('done');
  }

  String? _codingVerificationMutationSignature(
    List<ToolResultInfo> toolResults,
  ) {
    final entries = <Map<String, String>>[];
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
      if (path == null || !path.toLowerCase().endsWith('.dart')) {
        continue;
      }
      final resolved = FilesystemTools.resolvePath(
        path,
        defaultRoot: _getActiveProjectRootPath(),
      );
      entries.add({
        'id': toolResult.id,
        'name': toolResult.name,
        'path': resolved ?? path,
      });
    }
    if (entries.isEmpty) {
      return null;
    }
    return jsonEncode(entries);
  }

  String? _codingVerificationFailureSignature(ToolResultInfo feedback) {
    final decoded = _tryDecodeMap(feedback.result);
    if (decoded == null) {
      return null;
    }
    final failingTests = decoded['failing_tests'];
    if (failingTests is! List || failingTests.isEmpty) {
      return null;
    }
    final entries = <Map<String, Object?>>[];
    for (final test in failingTests) {
      if (test is! Map) {
        continue;
      }
      entries.add({
        'relative_path': test['relative_path'] ?? test['path'],
        'test_name': test['test_name'],
        'line': test['line'],
        'column': test['column'],
        'message': test['message'],
      });
    }
    if (entries.isEmpty) {
      return null;
    }
    return jsonEncode({
      'provider': decoded['provider'],
      'validation_status': decoded['validation_status'],
      'failures': entries,
    });
  }

  String _codingVerificationConvergenceBlocker(ToolResultInfo feedback) {
    final decoded = _tryDecodeMap(feedback.result);
    final failingTests = decoded?['failing_tests'];
    final buffer = StringBuffer(
      'The coding task is not complete. The same failing tests persisted after '
      '$_maxRepeatedCodingVerificationRepairAttempts repair attempts, so I am '
      'stopping the automatic repair loop.',
    );
    if (failingTests is List && failingTests.isNotEmpty) {
      buffer.writeln();
      buffer.writeln();
      buffer.writeln('Remaining failing tests:');
      for (final test in failingTests.take(5)) {
        if (test is! Map) {
          continue;
        }
        final path = test['relative_path'] ?? test['path'];
        final name = test['test_name'];
        final line = test['line'];
        final message = test['message'];
        final location = [
          if (path is String && path.isNotEmpty) path,
          if (line != null) 'line $line',
        ].join(':');
        final label = [
          if (location.isNotEmpty) location,
          if (name is String && name.isNotEmpty) name,
        ].join(' ');
        buffer.write('- ');
        if (label.isNotEmpty) {
          buffer.write(label);
          buffer.write(': ');
        }
        buffer.write(
          message is String && message.isNotEmpty ? message : 'Test failed.',
        );
        buffer.writeln();
      }
    }
    return buffer.toString().trimRight();
  }

  void _logCodingVerificationFeedbackSummary(ToolResultInfo feedback) {
    final decoded = _tryDecodeMap(feedback.result);
    if (decoded == null) {
      return;
    }
    final telemetry = decoded['telemetry'];
    final telemetryMap = telemetry is Map<String, dynamic> ? telemetry : null;
    final counts = decoded['counts'];
    final countsMap = counts is Map<String, dynamic> ? counts : null;
    final summary = <String, Object?>{
      'toolName': feedback.name,
      'provider': decoded['provider'],
      'trigger': decoded['trigger'],
      'validationStatus': decoded['validation_status'],
      'files': decoded['changed_paths'],
      if (countsMap != null) ...{
        'passedCount': countsMap['passed'],
        'failedCount': countsMap['failed'],
        'skippedCount': countsMap['skipped'],
      },
      if (telemetryMap != null) ...{
        'durationMs': telemetryMap['duration_ms'],
        'commandAttemptCount': telemetryMap['command_attempt_count'],
        'fallbackCommandCount': telemetryMap['fallback_command_count'],
        'timedOutCommandCount': telemetryMap['timed_out_command_count'],
        'startErrorCommandCount': telemetryMap['start_error_command_count'],
      },
    };
    appLog(
      '[CodingVerification] Test feedback summary: ${jsonEncode(summary)}',
    );
  }

  List<String> _changedFileMutationCallPaths(List<ToolCallInfo> toolCalls) {
    final paths = <String>[];
    final seen = <String>{};
    for (final toolCall in toolCalls) {
      if (!_isFileMutationToolName(toolCall.name)) {
        continue;
      }
      final path = _toolPathFromArguments(toolCall.arguments);
      if (path == null || !path.toLowerCase().endsWith('.dart')) {
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

  List<String> _changedFileMutationPaths(List<ToolResultInfo> toolResults) {
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
      if (path == null || !path.toLowerCase().endsWith('.dart')) {
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
      case 'edit_file':
      case 'rollback_last_file_change':
        return true;
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
    _logToolLifecycleEvent(
      toolCall: event.toolCall,
      lifecycleState: event.state.name,
      loopIndex: loopIndex,
      schedulerMode: event.schedulerMode,
      resultStatus: event.resultStatus,
      durationMs: event.durationMs,
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
    final payload = <String, Object?>{
      'toolCallId': toolCall.id,
      'toolName': toolCall.name,
      'lifecycleState': lifecycleState,
      'loopIndex': loopIndex,
    };
    if (schedulerMode != null) {
      payload['schedulerClass'] = schedulerMode.name;
    }
    if (resultStatus != null) {
      payload['resultStatus'] = resultStatus;
    }
    if (skipReason != null) {
      payload['skipReason'] = skipReason;
    }
    if (durationMs != null) {
      payload['durationMs'] = durationMs;
    }
    appLog('[Tool] Lifecycle ${jsonEncode(payload)}');
  }

  /// Executes tool calls, supporting a repeated tool-call loop.
  ///
  /// Continues looping while the LLM keeps requesting tools, until it returns
  /// a text response. Because qwen35-35b does not reliably use tool-role
  /// messages as real-time data, tool results are resent as a user message.
  Future<void> _executeToolCalls(
    List<ToolCallInfo> toolCalls, {
    String? assistantContent,
    bool toolSearchEnabled = false,
    Set<String> selectedToolNames = const <String>{},
    Map<String, int>? completionVerificationFailureCounts,
    required int interactionGeneration,
  }) async {
    var currentToolCalls = toolCalls;
    var currentAssistantContent = assistantContent;
    // Allow longer implementation and validation repair loops before falling
    // back to a final answer request. Live runs regularly need more than
    // eight bounded tool turns to converge on a validated saved task.
    var maxIterations = 12;
    var iteration = 0;
    var hasTextResponse = false;
    final executedToolCallKeys = <String>{};
    final toolFailureCounts = <String, int>{};
    final executedToolResults = <ToolResultInfo>[];
    var commandRetryGeneration = 0;
    var attemptedDuplicateInspectionRecovery = false;
    var attemptedDuplicateFollowUpRecovery = false;
    var attemptedToolLoopExhaustionRecovery = false;
    final attemptedCompletionVerificationMutationSignatures = <String>{};
    final verificationFailureCounts =
        completionVerificationFailureCounts ?? <String, int>{};
    var lastNonEmptyBatchToolResults = const <ToolResultInfo>[];
    final activeToolNames = <String>{...selectedToolNames};

    List<Map<String, dynamic>> selectedDefinitionsFor(
      McpToolService mcpToolService,
    ) {
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

      appLog('[Tool] Tool loop [$iteration/$maxIterations]');
      final batchToolResults = <ToolResultInfo>[];
      final pendingBatchCalls = <ToolCallInfo>[];

      for (final toolCall in currentToolCalls) {
        final toolCallKey = _toolExecutionKey(
          toolCall,
          commandRetryGeneration: commandRetryGeneration,
        );
        if (executedToolCallKeys.contains(toolCallKey) &&
            !_shouldAllowRepeatedToolExecution(toolCall)) {
          appLog(
            '[Tool] Duplicate tool call detected, skipping: ${toolCall.name} ${toolCall.arguments}',
          );
          _logToolLifecycleEvent(
            toolCall: toolCall,
            lifecycleState: 'skipped',
            loopIndex: iteration,
            schedulerMode: ToolExecutionScheduler.executionModeFor(toolCall),
            resultStatus: 'skipped',
            skipReason: 'duplicate_tool_call',
          );
          continue;
        }

        appLog('[Tool] Executing tool: ${toolCall.name}');
        appLog('[Tool] Arguments: ${toolCall.arguments}');

        _appendToolUseToLastMessage(
          toolCall,
          interactionGeneration: interactionGeneration,
        );
        pendingBatchCalls.add(toolCall);
      }

      final diagnosticBaseline = await _captureCodingDiagnosticFeedbackBaseline(
        pendingBatchCalls,
        interactionGeneration: interactionGeneration,
      );
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;

      final scheduledResults = await ToolExecutionScheduler.executeBatch(
        toolCalls: pendingBatchCalls,
        execute: (toolCall) => _dispatchToolCall(
          toolCall,
          interactionGeneration: interactionGeneration,
        ),
        onLifecycle: (event) =>
            _logScheduledToolLifecycleEvent(event, loopIndex: iteration),
        onBatch: (telemetry) {
          appLog(
            '[Tool] Scheduler ${telemetry.mode.name} batch '
            '(size=${telemetry.batchSize}, tools=${telemetry.toolNames.join(', ')})'
            '${telemetry.note == null ? '' : ' • ${telemetry.note}'}',
          );
        },
      );

      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;

      for (final scheduledResult in scheduledResults) {
        final toolCall = scheduledResult.toolCall;
        final toolCallKey = _toolExecutionKey(
          toolCall,
          commandRetryGeneration: commandRetryGeneration,
        );
        if (scheduledResult.error != null) {
          final error = scheduledResult.error!;
          appLog('[Tool] Error: $error');
          _appendToLastMessageForGeneration(
            interactionGeneration,
            '[Search error: $error]\n',
          );
          hasTextResponse = true;
          break;
        }

        final result = scheduledResult.result!;
        final toolResult = result.isSuccess
            ? result.result
            : (result.result.trim().isNotEmpty
                  ? result.result
                  : 'Error: ${result.errorMessage}');

        final promptToolResult = await _toolResultArtifactStore.persistIfLarge(
          ToolResultInfo(
            id: toolCall.id,
            name: toolCall.name,
            arguments: toolCall.arguments,
            result: toolResult,
          ),
          conversationId:
              _activeResponseConversationIdForGeneration(
                interactionGeneration,
              ) ??
              conversationId,
        );
        batchToolResults.add(promptToolResult);
        executedToolResults.add(batchToolResults.last);

        if (result.isSuccess) {
          executedToolCallKeys.add(toolCallKey);
          toolFailureCounts.remove(toolCallKey);
          if (_advancesCommandRetryGeneration(toolCall)) {
            commandRetryGeneration += 1;
          }
        } else {
          final failureCount = (toolFailureCounts[toolCallKey] ?? 0) + 1;
          toolFailureCounts[toolCallKey] = failureCount;
          if (failureCount >= 2) {
            appLog(
              '[Tool] Same tool (${toolCall.name}) failed $failureCount times consecutively, ending loop',
            );
            _appendToLastMessageForGeneration(
              interactionGeneration,
              '\nFailed to execute tool (${toolCall.name}). Please check your server configuration.\nError: ${result.errorMessage}\n',
            );
            hasTextResponse = true;
            break;
          }
        }
      }

      if (hasTextResponse) {
        break;
      }
      final diagnosticFeedback = await _buildCodingDiagnosticFeedbackToolResult(
        batchToolResults,
        interactionGeneration: interactionGeneration,
        baseline: diagnosticBaseline,
      );
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      if (diagnosticFeedback != null) {
        final promptDiagnosticFeedback = await _toolResultArtifactStore
            .persistIfLarge(
              diagnosticFeedback,
              conversationId:
                  _activeResponseConversationIdForGeneration(
                    interactionGeneration,
                  ) ??
                  conversationId,
            );
        if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
        batchToolResults.add(promptDiagnosticFeedback);
        executedToolResults.add(promptDiagnosticFeedback);
      }
      final commandOutputFeedback =
          await _buildCodingCommandOutputGuardrailToolResult(
            batchToolResults,
            interactionGeneration: interactionGeneration,
          );
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      if (commandOutputFeedback != null) {
        final promptCommandOutputFeedback = await _toolResultArtifactStore
            .persistIfLarge(
              commandOutputFeedback,
              conversationId:
                  _activeResponseConversationIdForGeneration(
                    interactionGeneration,
                  ) ??
                  conversationId,
            );
        if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
        batchToolResults.add(promptCommandOutputFeedback);
        executedToolResults.add(promptCommandOutputFeedback);
      }
      if (batchToolResults.isEmpty) {
        if (pendingBatchCalls.isEmpty && currentToolCalls.isNotEmpty) {
          final duplicateRecoveryToolResults =
              _buildDuplicateRecoveryToolResults(
                currentToolCalls: currentToolCalls,
                executedToolResults: executedToolResults,
                fallbackToolResults: lastNonEmptyBatchToolResults,
              );
          if (_containsOnlyPreviouslySuccessfulCommandToolCalls(
            currentToolCalls,
            executedToolResults,
          )) {
            appLog(
              '[Tool] Duplicate command follow-up already has a successful result',
            );
            final fallbackResponse =
                _buildDuplicateSuccessfulCommandFallbackResponse(
                  toolCalls: currentToolCalls,
                  previousToolResults: executedToolResults,
                  currentAssistantContent: currentAssistantContent,
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
          if (!attemptedDuplicateInspectionRecovery &&
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
          if (!attemptedDuplicateFollowUpRecovery &&
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
          appLog(
            '[Tool] Skipped duplicate follow-up tool calls, falling back to prior tool results',
          );
        }
        currentToolCalls = [];
        break;
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
      final nextResult = await _createToolResultCompletionWithContextRetry(
        logLabel: 'tool-result follow-up',
        interactionGeneration: interactionGeneration,
        buildMessages: (forceCompaction) => _prepareMessagesForLLM(
          forceCompaction: forceCompaction,
          toolDefinitionsOverride: tools,
          interactionGeneration: interactionGeneration,
        ),
        toolResults: batchToolResults,
        assistantContent: currentAssistantContent,
        tools: tools,
      );

      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      if (!ref.mounted) return;

      // Remove the temporary thinking indicator.
      _removeTrailingThinkTagForGeneration(interactionGeneration);

      final savedValidationSucceeded =
          _toolResultsContainSuccessfulCurrentSavedValidation(batchToolResults);
      if (savedValidationSucceeded) {
        appLog('[Tool] Saved validation command succeeded');
      }

      // Continue looping if the LLM asks for another tool call.
      if (nextResult.hasToolCalls) {
        final nextToolCalls = nextResult.toolCalls!;
        final fallbackResponse = nextResult.content.trim();
        if (savedValidationSucceeded) {
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
        currentToolCalls = nextToolCalls;
        _recordHiddenAssistantResponse(nextResult.content);
        currentAssistantContent = nextResult.content.isNotEmpty
            ? nextResult.content
            : null;
        if (iteration >= maxIterations &&
            _hasUnseenReadOnlyInspectionToolCalls(
              currentToolCalls,
              executedToolCallKeys,
              commandRetryGeneration: commandRetryGeneration,
            )) {
          appLog(
            '[Tool] Tool loop reached limit with pending read-only inspection; '
            'executing one final inspection batch',
          );
          final finalInspectionResults =
              await _executeFinalReadOnlyInspectionToolCalls(
                toolCalls: currentToolCalls,
                executedToolCallKeys: executedToolCallKeys,
                commandRetryGeneration: commandRetryGeneration,
                loopIndex: iteration + 1,
                interactionGeneration: interactionGeneration,
              );
          if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
          if (!ref.mounted) return;
          if (finalInspectionResults.isNotEmpty) {
            executedToolResults.addAll(finalInspectionResults);
          }
          currentToolCalls = [];
          break;
        }
        if (iteration >= maxIterations &&
            !attemptedToolLoopExhaustionRecovery &&
            batchToolResults.isNotEmpty) {
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
            maxIterations +=
                _toolResultsContainEditMismatch(recoveryToolResults) ? 4 : 2;
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
              maxIterations += 2;
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
        if (_shouldAcceptTerminalSkillToolRoleResponse(
          fallbackResponse,
          batchToolResults,
        )) {
          appLog(
            '[Tool] Accepting terminal skill tool-role response without final answer fallback',
          );
          final normalizedSkillResponse =
              _normalizeTerminalSkillToolRoleResponse(
                fallbackResponse,
                batchToolResults,
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
        iteration >= maxIterations &&
        _hasUnseenReadOnlyInspectionToolCalls(
          currentToolCalls,
          executedToolCallKeys,
          commandRetryGeneration: commandRetryGeneration,
        )) {
      appLog(
        '[Tool] Tool loop reached limit with pending read-only inspection; '
        'executing one final inspection batch',
      );
      final finalInspectionResults =
          await _executeFinalReadOnlyInspectionToolCalls(
            toolCalls: currentToolCalls,
            executedToolCallKeys: executedToolCallKeys,
            commandRetryGeneration: commandRetryGeneration,
            loopIndex: iteration + 1,
            interactionGeneration: interactionGeneration,
          );
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      if (!ref.mounted) return;
      if (finalInspectionResults.isNotEmpty) {
        executedToolResults.addAll(finalInspectionResults);
      }
      currentToolCalls = [];
    }

    final unexecutedPendingToolResults = _buildUnexecutedPendingToolResults(
      toolCalls: currentToolCalls,
      executedToolCallKeys: executedToolCallKeys,
      commandRetryGeneration: commandRetryGeneration,
    );
    final finalToolResults = <ToolResultInfo>[
      ...executedToolResults,
      ...unexecutedPendingToolResults,
    ];

    // If tool results exist and no text response has been shown yet,
    // resend them as a user message and stream the final answer.
    if (!hasTextResponse && finalToolResults.isNotEmpty) {
      appLog('[Tool] Resending tool results as user message');

      if (!ref.mounted) return;

      final preStreamContent = _lastMessageContentForGeneration(
        interactionGeneration,
      );
      final streamedFinalAnswer = await _streamToolResultAnswerWithContextRetry(
        toolResults: finalToolResults,
        interactionGeneration: interactionGeneration,
      );
      if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
      if (!ref.mounted) return;

      final mcpToolService = _mcpToolService;
      if (mcpToolService != null) {
        final streamVerificationBatchToolResults = <ToolResultInfo>[];
        final tools = selectedDefinitionsFor(mcpToolService);
        final verificationRepairResult =
            await _requestCodingVerificationRepairForCompletionClaim(
              candidateResponse: streamedFinalAnswer,
              executedToolResults: executedToolResults,
              batchToolResults: streamVerificationBatchToolResults,
              attemptedMutationSignatures:
                  attemptedCompletionVerificationMutationSignatures,
              verificationFailureCounts: verificationFailureCounts,
              tools: tools,
              interactionGeneration: interactionGeneration,
            );
        if (!_isCurrentInteractionGeneration(interactionGeneration)) return;
        if (!ref.mounted) return;
        if (verificationRepairResult != null) {
          if (preStreamContent != null) {
            _replaceLastMessageContentForGeneration(
              interactionGeneration,
              preStreamContent,
            );
          }
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
              completionVerificationFailureCounts: verificationFailureCounts,
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

    _latestCompletedToolResults = List<ToolResultInfo>.unmodifiable(
      executedToolResults,
    );
    await _finishStreaming(interactionGeneration: interactionGeneration);
  }

  Future<List<ToolResultInfo>> _executeFinalReadOnlyInspectionToolCalls({
    required List<ToolCallInfo> toolCalls,
    required Set<String> executedToolCallKeys,
    required int commandRetryGeneration,
    required int loopIndex,
    required int interactionGeneration,
  }) async {
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return const [];
    }
    final pendingToolCalls = <ToolCallInfo>[];
    for (final toolCall in toolCalls) {
      if (!_isReadOnlyInspectionToolCall(toolCall)) {
        continue;
      }
      final toolCallKey = _toolExecutionKey(
        toolCall,
        commandRetryGeneration: commandRetryGeneration,
      );
      if (executedToolCallKeys.contains(toolCallKey)) {
        appLog(
          '[Tool] Skipping duplicate final inspection call: '
          '${toolCall.name} ${toolCall.arguments}',
        );
        _logToolLifecycleEvent(
          toolCall: toolCall,
          lifecycleState: 'skipped',
          loopIndex: loopIndex,
          schedulerMode: ToolExecutionScheduler.executionModeFor(toolCall),
          resultStatus: 'skipped',
          skipReason: 'duplicate_tool_call',
        );
        continue;
      }

      appLog('[Tool] Executing final inspection tool: ${toolCall.name}');
      appLog('[Tool] Arguments: ${toolCall.arguments}');
      _appendToolUseToLastMessage(
        toolCall,
        interactionGeneration: interactionGeneration,
      );
      pendingToolCalls.add(toolCall);
    }

    if (pendingToolCalls.isEmpty) {
      return const [];
    }

    final scheduledResults = await ToolExecutionScheduler.executeBatch(
      toolCalls: pendingToolCalls,
      execute: (toolCall) => _dispatchToolCall(
        toolCall,
        interactionGeneration: interactionGeneration,
      ),
      onLifecycle: (event) =>
          _logScheduledToolLifecycleEvent(event, loopIndex: loopIndex),
      onBatch: (telemetry) {
        appLog(
          '[Tool] Scheduler ${telemetry.mode.name} final inspection batch '
          '(size=${telemetry.batchSize}, tools=${telemetry.toolNames.join(', ')})'
          '${telemetry.note == null ? '' : ' • ${telemetry.note}'}',
        );
      },
    );
    if (!_isCurrentInteractionGeneration(interactionGeneration)) {
      return const [];
    }

    final toolResults = <ToolResultInfo>[];
    for (final scheduledResult in scheduledResults) {
      final toolCall = scheduledResult.toolCall;
      final toolCallKey = _toolExecutionKey(
        toolCall,
        commandRetryGeneration: commandRetryGeneration,
      );
      final result = scheduledResult.result;
      final toolResult = switch ((result, scheduledResult.error)) {
        (final McpToolResult result, null) =>
          result.isSuccess
              ? result.result
              : (result.result.trim().isNotEmpty
                    ? result.result
                    : 'Error: ${result.errorMessage}'),
        (_, final Object error?) => 'Error: $error',
        _ => 'Error: Tool execution did not return a result',
      };

      final promptToolResult = await _toolResultArtifactStore.persistIfLarge(
        ToolResultInfo(
          id: toolCall.id,
          name: toolCall.name,
          arguments: toolCall.arguments,
          result: toolResult,
        ),
        conversationId:
            _activeResponseConversationIdForGeneration(interactionGeneration) ??
            conversationId,
      );
      if (!_isCurrentInteractionGeneration(interactionGeneration)) {
        return const [];
      }
      toolResults.add(promptToolResult);

      if (result?.isSuccess ?? false) {
        executedToolCallKeys.add(toolCallKey);
      }
    }
    return toolResults;
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
      updatedMessages[lastIndex] = lastMessage.copyWith(content: newContent);
      _cacheActiveResponseMessagesForGeneration(generation, updatedMessages);
      return;
    }

    if (!ref.mounted || state.messages.isEmpty) return;

    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];

    final newContent = lastMessage.content + chunk;
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

  /// Tool executions that are still pending.
  final List<Future<void>> _pendingToolExecutions = [];

  /// Detects and runs `tool_call` tags embedded in the content.
  void _checkForContentToolCalls(String content, {int? interactionGeneration}) {
    final toolCalls = ContentParser.extractCompletedToolCalls(content);
    final freshToolCalls = toolCalls.where((tc) {
      return _seenContentToolCallHashes.add(_contentToolCallHash(tc));
    }).toList();

    _queueContentToolCalls(
      freshToolCalls,
      interactionGeneration: interactionGeneration ?? _interactionGeneration,
    );
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
    final baseKey = _toolCallDedupKey(toolCall.name, toolCall.arguments);
    if (_isRepeatableCommandTool(toolCall)) {
      return '$baseKey#commandRetryGeneration=$commandRetryGeneration';
    }
    return baseKey;
  }

  bool _shouldAllowRepeatedToolExecution(ToolCallInfo toolCall) {
    // Exact repeated shell/git commands without an intervening file mutation are
    // usually loop noise. Legitimate validation retries get a fresh dedup key
    // through commandRetryGeneration after the task edits a file.
    return toolCall.name == 'read_file';
  }

  bool _containsOnlyReadOnlyInspectionToolCalls(List<ToolCallInfo> toolCalls) {
    if (toolCalls.isEmpty) {
      return false;
    }
    return toolCalls.every(_isReadOnlyInspectionToolCall);
  }

  bool _hasUnseenReadOnlyInspectionToolCalls(
    List<ToolCallInfo> toolCalls,
    Set<String> executedToolCallKeys, {
    required int commandRetryGeneration,
  }) {
    if (!_containsOnlyReadOnlyInspectionToolCalls(toolCalls)) {
      return false;
    }
    return toolCalls.any((toolCall) {
      final toolCallKey = _toolExecutionKey(
        toolCall,
        commandRetryGeneration: commandRetryGeneration,
      );
      return !executedToolCallKeys.contains(toolCallKey);
    });
  }

  bool _containsOnlyPreviouslySuccessfulCommandToolCalls(
    List<ToolCallInfo> toolCalls,
    List<ToolResultInfo> previousToolResults,
  ) {
    if (toolCalls.isEmpty || previousToolResults.isEmpty) {
      return false;
    }
    return toolCalls.every((toolCall) {
      if (toolCall.name == 'run_tests') {
        final testPath = _runTestsPathArgument(toolCall.arguments);
        return previousToolResults.any(
          (result) =>
              result.name == toolCall.name &&
              _runTestsPathArgument(result.arguments) == testPath &&
              _toolResultHasSuccessfulExit(result),
        );
      }
      if (!_isCommandExecutionTool(toolCall.name)) {
        return false;
      }
      final command = _toolCommandArgument(toolCall.arguments);
      if (command == null) {
        return false;
      }
      return previousToolResults.any(
        (result) =>
            result.name == toolCall.name &&
            _toolCommandArgument(result.arguments) == command &&
            _toolResultHasSuccessfulExit(result),
      );
    });
  }

  String _buildDuplicateSuccessfulCommandFallbackResponse({
    required List<ToolCallInfo> toolCalls,
    required List<ToolResultInfo> previousToolResults,
    required String? currentAssistantContent,
  }) {
    if (_containsOnlyPreviouslySuccessfulCurrentSavedValidationToolCalls(
      toolCalls,
      previousToolResults,
    )) {
      return 'The saved validation command already succeeded for the current saved task, so the current saved task is complete.';
    }

    final candidate = currentAssistantContent?.trim() ?? '';
    if (candidate.isNotEmpty &&
        !_looksLikePendingToolActionResponse(candidate)) {
      return candidate;
    }

    final repeatedCommands = toolCalls
        .map((toolCall) => _toolCommandArgument(toolCall.arguments))
        .whereType<String>()
        .toSet()
        .join(', ');
    final previousOutput = _successfulCommandOutputForRepeatedCalls(
      toolCalls: toolCalls,
      previousToolResults: previousToolResults,
    );
    if (previousOutput != null) {
      final commandLabel = repeatedCommands.isEmpty
          ? 'the repeated command'
          : repeatedCommands;
      return 'The repeated command already succeeded ($commandLabel), so I used the previous successful result:\n\n```text\n$previousOutput\n```';
    }
    if (repeatedCommands.isEmpty) {
      return 'The repeated command already succeeded, so I used the previous result and stopped the duplicate command loop.';
    }
    return 'The repeated command already succeeded ($repeatedCommands), so I used the previous result and stopped the duplicate command loop.';
  }

  bool _looksLikePendingToolActionResponse(String response) {
    final normalized = response.toLowerCase();
    return RegExp(
      r"\b(?:now\s+)?let me\b|\bi (?:will|need to|should|am going to)\b|\bi(?:'ll| will)\b",
    ).hasMatch(normalized);
  }

  String? _successfulCommandOutputForRepeatedCalls({
    required List<ToolCallInfo> toolCalls,
    required List<ToolResultInfo> previousToolResults,
  }) {
    for (final toolCall in toolCalls) {
      final matchingResult = previousToolResults.reversed.where((result) {
        if (result.name != toolCall.name ||
            !_toolResultHasSuccessfulExit(result)) {
          return false;
        }
        if (toolCall.name == 'run_tests') {
          return _runTestsPathArgument(result.arguments) ==
              _runTestsPathArgument(toolCall.arguments);
        }
        final command = _toolCommandArgument(toolCall.arguments);
        if (command == null) {
          return false;
        }
        final resultCommand = _toolCommandArgument(result.arguments);
        return resultCommand != null &&
            _normalizeToolCommandForComparison(resultCommand) ==
                _normalizeToolCommandForComparison(command);
      }).firstOrNull;
      if (matchingResult == null) {
        continue;
      }
      final output = _toolResultOutputText(matchingResult).trim();
      if (output.isEmpty) {
        continue;
      }
      const maxOutputLength = 2000;
      if (output.length <= maxOutputLength) {
        return output;
      }
      return '${output.substring(0, maxOutputLength).trimRight()}\n...[truncated]';
    }
    return null;
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

  bool _isCommandExecutionTool(String toolName) {
    switch (toolName.trim().toLowerCase()) {
      case 'local_execute_command':
      case 'run_tests':
      case 'git_execute_command':
      case 'ssh_execute_command':
        return true;
    }
    return false;
  }

  String? _toolCommandArgument(Map<String, dynamic> arguments) {
    final command = arguments['command']?.toString().trim();
    return command == null || command.isEmpty ? null : command;
  }

  bool _toolResultHasSuccessfulExit(ToolResultInfo result) {
    if (!_isCommandExecutionTool(result.name)) {
      return false;
    }
    final decoded = _tryDecodeMap(result.result);
    final exitCode = decoded?['exit_code'];
    if (exitCode is num) {
      return exitCode == 0;
    }
    if (exitCode is String) {
      return int.tryParse(exitCode.trim()) == 0;
    }
    return RegExp(
      r'^exit_code:\s*0\s*$',
      multiLine: true,
    ).hasMatch(result.result);
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

  bool _toolCommandMatchesSavedValidation({
    required ToolResultInfo result,
    required String command,
    required String normalizedValidationCommand,
  }) {
    final normalizedCommand = _normalizeToolCommandForComparison(command);
    if (normalizedCommand == normalizedValidationCommand) {
      return true;
    }
    final isValidationWrapper = normalizedCommand.startsWith(
      '$normalizedValidationCommand && ',
    );
    if (!isValidationWrapper) {
      return false;
    }
    if (_toolResultOutputSuggestsValidationFailure(result)) {
      return false;
    }
    if (!normalizedCommand.contains(' || ')) {
      return true;
    }
    if (_toolResultOutputText(result).trim().isEmpty) {
      return false;
    }
    return !_toolResultOutputSuggestsValidationFailure(result);
  }

  bool _toolResultOutputSuggestsValidationFailure(ToolResultInfo result) {
    final output = _toolResultOutputText(result).toLowerCase();
    return output.contains('validation failed') ||
        output.contains('validation failure');
  }

  String _toolResultOutputText(ToolResultInfo result) {
    final decoded = _tryDecodeMap(result.result);
    return [
      decoded?['stdout']?.toString(),
      decoded?['stderr']?.toString(),
    ].whereType<String>().join('\n');
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
    return LocalShellTools.normalizeCommand(
      command,
    ).replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  }

  String? _runTestsPathArgument(Map<String, dynamic> arguments) {
    final testPath = arguments['test_path']?.toString().trim();
    if (testPath != null && testPath.isNotEmpty) {
      return testPath;
    }
    final path = arguments['path']?.toString().trim();
    return path == null || path.isEmpty ? null : path;
  }

  bool _runTestsMatchesSavedValidation({
    required Map<String, dynamic> arguments,
    required String normalizedValidationCommand,
  }) {
    final normalizedValidation = normalizedValidationCommand.replaceAll(
      RegExp("[\"']"),
      '',
    );
    final testPath = _runTestsPathArgument(arguments);
    if (testPath == null) {
      return normalizedValidation.contains('run_tests') ||
          normalizedValidation.contains('flutter test') ||
          normalizedValidation.contains('dart test');
    }

    final normalizedPath = _normalizeToolCommandForComparison(
      testPath,
    ).replaceAll(RegExp("[\"']"), '');
    return normalizedPath.isNotEmpty &&
        (normalizedValidation.contains(normalizedPath) ||
            normalizedValidation.contains('run_tests'));
  }

  bool _isReadOnlyInspectionTool(String toolName) {
    switch (toolName.trim().toLowerCase()) {
      case 'list_directory':
      case 'read_file':
      case 'find_files':
      case 'search_files':
        return true;
    }
    return false;
  }

  bool _isReadOnlyInspectionToolCall(ToolCallInfo toolCall) {
    if (_isReadOnlyInspectionTool(toolCall.name)) {
      return true;
    }
    if (toolCall.name.trim().toLowerCase() != 'local_execute_command') {
      return false;
    }
    final command = _toolCommandArgument(toolCall.arguments);
    return command != null && LocalShellTools.isReadOnly(command);
  }

  List<ToolResultInfo> _buildUnexecutedPendingToolResults({
    required List<ToolCallInfo> toolCalls,
    required Set<String> executedToolCallKeys,
    required int commandRetryGeneration,
  }) {
    if (toolCalls.isEmpty) {
      return const [];
    }

    final pending = <ToolResultInfo>[];
    for (final toolCall in toolCalls) {
      final toolCallKey = _toolExecutionKey(
        toolCall,
        commandRetryGeneration: commandRetryGeneration,
      );
      if (executedToolCallKeys.contains(toolCallKey)) {
        continue;
      }
      pending.add(
        ToolResultInfo(
          id: toolCall.id,
          name: toolCall.name,
          arguments: toolCall.arguments,
          result: jsonEncode({
            'code': 'tool_call_not_executed',
            'error':
                'Tool call was requested after the bounded tool loop stopped and was not executed before the final answer.',
            'reason': 'bounded_tool_loop_exhausted',
            'tool_name': toolCall.name,
          }),
        ),
      );
    }
    return pending;
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
    final pendingToolNames = toolCalls
        .map((toolCall) => toolCall.name.trim())
        .where((name) => name.isNotEmpty)
        .toSet()
        .join(', ');
    final hasEditMismatch = _toolResultsContainEditMismatch(
      previousToolResults,
    );
    final hasMatchingReadContext = previousToolResults.any(
      (toolResult) => toolResult.name == 'read_file',
    );
    return [
      'You hit the bounded tool loop limit while working on the current saved task.',
      if (pendingToolNames.isNotEmpty)
        'Pending tool calls at the limit: $pendingToolNames.',
      'Do not restate the plan, do not ask for confirmation, and do not switch to a future saved task.',
      'Use the latest tool results and finish the current saved task now.',
      if (hasEditMismatch)
        'A recent edit_file failed because old_text did not match the current file.',
      if (hasEditMismatch && hasMatchingReadContext)
        'A recent read_file result for the same path is already provided below. Use that exact file content and return only one edit_file call for the same file, or a brief blocker statement if the edit is unsafe.',
      if (hasEditMismatch && hasMatchingReadContext)
        'Do not call read_file again for the same path in this turn.',
      if (hasEditMismatch && !hasMatchingReadContext)
        'If the latest tool result reports code=edit_mismatch, read that exact file once and then retry edit_file with the exact current file content as old_text.',
      'If one final tool call is still required, return only the single most important tool call for the current saved task.',
      'Otherwise reply with a brief completion or blocker statement for the current saved task.',
    ].join('\n');
  }

  List<ToolResultInfo> _buildToolLoopRecoveryToolResults({
    required List<ToolResultInfo> currentToolResults,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolCallInfo> pendingToolCalls,
  }) {
    final recoveryToolResults = <ToolResultInfo>[];
    if (_toolResultsContainEditMismatch(currentToolResults)) {
      final pendingPaths = pendingToolCalls
          .map((toolCall) => _toolPathFromArguments(toolCall.arguments))
          .whereType<String>()
          .toSet();
      if (pendingPaths.isNotEmpty) {
        final seenPaths = <String>{};
        for (final toolResult in executedToolResults.reversed) {
          if (toolResult.name != 'read_file') {
            continue;
          }
          final toolPath = _toolPathFromArguments(toolResult.arguments);
          if (toolPath == null ||
              !pendingPaths.contains(toolPath) ||
              !seenPaths.add(toolPath)) {
            continue;
          }
          recoveryToolResults.insert(0, toolResult);
        }
      }
    }
    recoveryToolResults.addAll(currentToolResults);
    return _dedupeRecoveryToolResults(recoveryToolResults);
  }

  List<ToolResultInfo> _buildDuplicateRecoveryToolResults({
    required List<ToolCallInfo> currentToolCalls,
    required List<ToolResultInfo> executedToolResults,
    required List<ToolResultInfo> fallbackToolResults,
  }) {
    final recoveryToolResults = <ToolResultInfo>[];
    for (final toolCall in currentToolCalls) {
      final matchingResult = executedToolResults.reversed
          .where(
            (toolResult) => _toolResultMatchesToolCall(toolResult, toolCall),
          )
          .firstOrNull;
      if (matchingResult != null) {
        recoveryToolResults.add(matchingResult);
      }
    }
    recoveryToolResults.addAll(fallbackToolResults);
    return _dedupeRecoveryToolResults(recoveryToolResults);
  }

  List<ToolResultInfo> _dedupeRecoveryToolResults(
    List<ToolResultInfo> toolResults,
  ) {
    final deduped = <ToolResultInfo>[];
    final seenKeys = <String>{};
    for (final toolResult in toolResults) {
      final key = '${_toolResultDedupKey(toolResult)}:${toolResult.result}';
      if (seenKeys.add(key)) {
        deduped.add(toolResult);
      }
    }
    return deduped;
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

  bool _isRepeatableCommandTool(ToolCallInfo toolCall) {
    return toolCall.name == 'local_execute_command' ||
        toolCall.name == 'run_tests' ||
        toolCall.name == 'git_execute_command';
  }

  bool _advancesCommandRetryGeneration(ToolCallInfo toolCall) {
    final normalizedName = toolCall.name.trim().toLowerCase();
    return normalizedName == 'write_file' ||
        normalizedName == 'edit_file' ||
        normalizedName == 'rollback_last_file_change' ||
        normalizedName.startsWith('write_') ||
        normalizedName.startsWith('edit_');
  }

  String _toolCallDedupKey(String name, Object? arguments) {
    final normalizedName = name.trim().toLowerCase();
    final normalizedArguments = _normalizeToolArgumentsForDedup(
      normalizedName,
      arguments,
    );
    return '$normalizedName:${_normalizeToolExecutionValue(normalizedArguments)}';
  }

  String _toolResultDedupKey(ToolResultInfo toolResult) {
    return _toolCallDedupKey(toolResult.name, toolResult.arguments);
  }

  bool _toolResultMatchesToolCall(
    ToolResultInfo toolResult,
    ToolCallInfo toolCall,
  ) {
    return _toolResultDedupKey(toolResult) ==
        _toolCallDedupKey(toolCall.name, toolCall.arguments);
  }

  Object? _normalizeToolArgumentsForDedup(String toolName, Object? arguments) {
    if (arguments is! Map) {
      return arguments;
    }
    final normalized = <String, dynamic>{...arguments};
    if (_usesProjectScopedPathArgument(toolName)) {
      final normalizedPath = _normalizeToolPathForDedup(normalized['path']);
      if (normalizedPath != null) {
        normalized['path'] = normalizedPath;
      }
    }
    return normalized;
  }

  bool _usesProjectScopedPathArgument(String toolName) {
    switch (toolName.trim().toLowerCase()) {
      case 'list_directory':
      case 'read_file':
      case 'find_files':
      case 'search_files':
      case 'write_file':
      case 'edit_file':
      case 'rollback_last_file_change':
        return true;
    }
    return false;
  }

  String? _normalizeToolPathForDedup(Object? rawPath) {
    if (rawPath is! String) {
      return null;
    }
    final trimmed = rawPath.trim();
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

  String _normalizeToolExecutionValue(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      final normalized = <String, String>{};
      for (final entry in entries) {
        normalized[entry.key.toString()] = _normalizeToolExecutionValue(
          entry.value,
        );
      }
      return jsonEncode(normalized);
    }

    if (value is List) {
      return jsonEncode(
        value.map(_normalizeToolExecutionValue).toList(growable: false),
      );
    }

    return jsonEncode(value);
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

  void _recordContentToolResult({
    required ToolCallInfo toolCall,
    required String result,
  }) {
    _recordContentToolResultInfo(
      ToolResultInfo(
        id: toolCall.id,
        name: toolCall.name,
        arguments: Map<String, dynamic>.unmodifiable(toolCall.arguments),
        result: result,
      ),
    );
  }

  void _recordContentToolResultInfo(ToolResultInfo toolResult) {
    _latestContentToolResults.add(toolResult);
  }

  String _buildContentToolFailureResult(String toolName, String? errorMessage) {
    final error = (errorMessage ?? 'Tool execution failed').trim();
    final code = _contentToolFailureCode(error);
    return jsonEncode({'toolName': toolName, 'error': error, 'code': code});
  }

  String _contentToolFailureCode(String errorMessage) {
    final normalized = errorMessage.toLowerCase();
    if (normalized.contains('no matching tool available')) {
      return 'tool_not_available';
    }
    if (normalized.contains('old_text was not found in the target file')) {
      return 'edit_mismatch';
    }
    if (normalized.contains('permission_denied')) {
      return 'permission_denied';
    }
    if (normalized.contains('timeout')) {
      return 'timeout';
    }
    return 'tool_execution_failed';
  }

  bool _toolResultsContainEditMismatch(List<ToolResultInfo> toolResults) {
    return toolResults.any((toolResult) {
      final normalized = toolResult.result.toLowerCase();
      return normalized.contains('"code":"edit_mismatch"') ||
          normalized.contains('old_text was not found in the target file');
    });
  }

  bool _toolResultsContainFailedCommandValidation(
    List<ToolResultInfo> toolResults,
  ) {
    return toolResults.any((toolResult) {
      final normalizedName = toolResult.name.trim().toLowerCase();
      if (normalizedName != 'local_execute_command' &&
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

  String _buildContentToolResultTag(String toolName, String result) {
    final payload = _buildContentToolResultPayload(toolName, result);
    return '<tool_result>${jsonEncode(payload)}</tool_result>';
  }

  McpToolResult? _lookupToolApprovalResult(
    String toolName,
    Map<String, dynamic> arguments,
  ) {
    final cached = _toolApprovalCache.lookup(toolName, arguments);
    if (cached != null) {
      appLog(
        '[Tool] Reusing cached approval result for $toolName: ${jsonEncode(arguments)}',
      );
    }
    return cached;
  }

  McpToolResult _rememberToolApprovalResult(
    String toolName,
    Map<String, dynamic> arguments,
    McpToolResult result,
  ) {
    return _toolApprovalCache.remember(toolName, arguments, result);
  }

  bool get _hasFullCodingApprovalAccess =>
      _settings.codingApprovalMode == CodingApprovalMode.fullAccess;

  bool get _usesCodingApprovalAutoReview =>
      _settings.codingApprovalMode == CodingApprovalMode.autoReview;

  Future<CodingApprovalAutoReviewDecision?> _reviewCodingApproval({
    required ToolCallInfo toolCall,
    required String actionKind,
    required Map<String, dynamic> arguments,
    String? path,
    String? workingDirectory,
    String? reason,
    String? warningTitle,
    String? warningMessage,
    String? preview,
  }) async {
    if (!_usesCodingApprovalAutoReview) {
      return null;
    }

    final request = CodingApprovalAutoReviewRequest(
      actionKind: actionKind,
      toolName: toolCall.name,
      arguments: arguments,
      path: path,
      workingDirectory: workingDirectory,
      reason: reason,
      warningTitle: warningTitle,
      warningMessage: warningMessage,
      preview: preview,
      conversationTail: CodingApprovalAutoReviewService.buildConversationTail(
        state.messages,
      ),
    );

    try {
      final response = await _dataSource.createChatCompletion(
        messages: CodingApprovalAutoReviewService.buildMessages(request),
        model: _settings.model,
        temperature: 0,
        maxTokens: 512,
      );
      final decision = CodingApprovalAutoReviewService.parseDecision(
        response.content,
      );
      if (decision == null) {
        appLog('[AutoReview] Reviewer returned malformed output.');
        return null;
      }
      appLog(
        '[AutoReview] ${decision.outcome.name} ${toolCall.name}: '
        '${decision.rationale}',
      );
      return decision;
    } catch (error) {
      appLog('[AutoReview] Reviewer failed: $error');
      return null;
    }
  }

  McpToolResult _autoReviewDeniedResult({
    required String toolName,
    required CodingApprovalAutoReviewDecision decision,
  }) {
    return McpToolResult(
      toolName: toolName,
      result:
          'Auto-review denied this action. Rationale: ${decision.rationale}',
      isSuccess: false,
      errorMessage: 'Auto-review denied: ${decision.rationale}',
    );
  }

  Map<String, dynamic> _buildContentToolResultPayload(
    String toolName,
    String result,
  ) {
    final details = <String>[];
    String? summary;

    try {
      final decoded = jsonDecode(result);
      if (decoded is Map<String, dynamic>) {
        summary = _summarizeToolResultMap(decoded, details);
      } else if (decoded is List) {
        summary = '${decoded.length} item(s)';
        details.addAll(
          decoded.take(3).map((item) => _compactToolResultValue(item)),
        );
      }
    } catch (_) {
      final lines = result
          .split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (lines.isNotEmpty) {
        summary = _truncateToolResultText(lines.first, maxLength: 72);
        details.addAll(
          lines
              .skip(1)
              .take(2)
              .map((line) => _truncateToolResultText(line, maxLength: 96)),
        );
      }
    }

    summary ??= 'Completed';
    return {
      'name': toolName,
      'summary': summary,
      if (details.isNotEmpty) 'details': details,
    };
  }

  String _summarizeToolResultMap(
    Map<String, dynamic> data,
    List<String> details,
  ) {
    final path = data['path'];
    final entries = data['entries'];
    final matches = data['matches'];
    final content = data['content'];

    if (entries is List) {
      details.addAll(
        entries
            .take(3)
            .map((entry) => _truncateToolResultText(entry.toString())),
      );
      final count = data['entry_count'] ?? entries.length;
      return '$count item(s) in ${_compactToolResultValue(path)}';
    }

    if (matches is List) {
      details.addAll(
        matches
            .take(3)
            .map((match) => _truncateToolResultText(match.toString())),
      );
      final count = data['match_count'] ?? matches.length;
      if (data.containsKey('query')) {
        return '$count match(es) for ${_compactToolResultValue(data['query'])}';
      }
      if (data.containsKey('pattern')) {
        return '$count file(s) for ${_compactToolResultValue(data['pattern'])}';
      }
      return '$count match(es)';
    }

    if (content is String) {
      final lines = content
          .split(RegExp(r'[\r\n]+'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      details.addAll(
        lines
            .take(2)
            .map((line) => _truncateToolResultText(line, maxLength: 96)),
      );
      return _compactToolResultValue(path);
    }

    if (data.containsKey('bytes_written')) {
      details.add('bytes: ${data['bytes_written']}');
      if (data['created'] == true) {
        details.add('created');
      }
      return _compactToolResultValue(path);
    }

    if (data.containsKey('replacements')) {
      details.add('replacements: ${data['replacements']}');
      if (data['replace_all'] == true) {
        details.add('replace all');
      }
      return _compactToolResultValue(path);
    }

    final prioritizedEntries = data.entries
        .where(
          (entry) => entry.value != null && entry.value.toString().isNotEmpty,
        )
        .take(3);
    details.addAll(
      prioritizedEntries.map(
        (entry) =>
            '${entry.key}: ${_truncateToolResultText(_compactToolResultValue(entry.value), maxLength: 72)}',
      ),
    );
    return _compactToolResultValue(
      path ?? data['query'] ?? data['pattern'] ?? 'Completed',
    );
  }

  String _compactToolResultValue(dynamic value) {
    if (value == null) return 'unknown';
    if (value is String) return value;
    return jsonEncode(value);
  }

  String _truncateToolResultText(String value, {int maxLength = 88}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 1)}...';
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
    final planningPolicyResult = _enforcePlanningToolPolicy(toolCall);
    if (planningPolicyResult != null) {
      return planningPolicyResult;
    }

    if (MacosComputerUseToolPolicy.requiresUserApproval(toolCall.name)) {
      return _handleComputerUseAction(toolCall);
    }
    if (MacosComputerUseToolPolicy.isComputerUseTool(toolCall.name)) {
      return _handleComputerUseActionWithoutApproval(toolCall);
    }

    switch (toolCall.name) {
      case 'list_directory':
      case 'read_file':
      case 'find_files':
      case 'search_files':
        return _handleProjectScopedTool(toolCall);
      case 'write_file':
        return _handleWriteFile(toolCall);
      case 'edit_file':
        return _handleEditFile(toolCall);
      case 'rollback_last_file_change':
        return _handleRollbackLastFileChange(toolCall);
      case 'local_execute_command':
        return _handleLocalExecuteCommand(toolCall);
      case 'run_tests':
        return _handleRunTests(toolCall);
      case 'ssh_connect':
        return _handleSshConnect(toolCall);
      case 'ssh_execute_command':
        return _handleSshExecuteCommand(toolCall);
      case 'git_execute_command':
        return _handleGitExecuteCommand(toolCall);
      case 'ble_connect':
        return _handleBleConnect(toolCall);
      case 'ask_user_question':
        return _handleAskUserQuestion(
          toolCall,
          interactionGeneration: interactionGeneration,
        );
      default:
        return _mcpToolService!.executeTool(
          name: toolCall.name,
          arguments: toolCall.arguments,
        );
    }
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
    if (!(currentConversation?.isPlanningSession ?? false)) {
      return null;
    }

    if (MacosComputerUseToolPolicy.isComputerUseTool(toolCall.name)) {
      return MacosComputerUseToolPolicy.isAllowedInPlanning(toolCall.name)
          ? null
          : _buildPlanningToolDeniedResult(
              toolCall,
              detail:
                  'Planning mode allows only macOS computer-use observation tools.',
            );
    }

    switch (toolCall.name) {
      case 'list_directory':
      case 'read_file':
      case 'find_files':
      case 'search_files':
      case ToolDefinitionSearchService.toolName:
      case 'get_current_datetime':
      case 'ask_user_question':
      case 'os_get_system_info':
      case 'search_past_conversations':
      case 'recall_memory':
      case 'ping':
      case 'whois_lookup':
      case 'dns_lookup':
      case 'port_check':
      case 'ssl_certificate':
      case 'http_status':
      case 'http_get':
      case 'http_head':
      case 'web_search':
      case 'web_url_read':
      case 'wifi_scan':
      case 'wifi_get_scan_results':
      case 'wifi_get_connection_info':
      case 'os_log_read':
      case 'lan_scan':
      case 'lan_get_scan_results':
        return null;
      case 'local_execute_command':
        final resolvedArguments = _resolveProjectScopedArguments(
          toolCall.name,
          toolCall.arguments,
        );
        final command = LocalShellTools.normalizeCommand(
          (resolvedArguments['command'] as String?)?.trim() ?? '',
        );
        return LocalShellTools.isReadOnly(command)
            ? null
            : _buildPlanningToolDeniedResult(
                toolCall,
                detail: command.isEmpty
                    ? 'Planning mode only allows read-only local commands.'
                    : 'Planning mode blocked local command: $command',
              );
      case 'git_execute_command':
        final resolvedArguments = _resolveProjectScopedArguments(
          toolCall.name,
          toolCall.arguments,
        );
        final command = GitTools.normalizeCommand(
          (resolvedArguments['command'] as String?)?.trim() ?? '',
        );
        return GitTools.isReadOnly(command)
            ? null
            : _buildPlanningToolDeniedResult(
                toolCall,
                detail: command.isEmpty
                    ? 'Planning mode only allows read-only git commands.'
                    : 'Planning mode blocked git command: git $command',
              );
      default:
        return _isPlanningDeniedToolName(toolCall.name)
            ? _buildPlanningToolDeniedResult(toolCall)
            : null;
    }
  }

  bool _isPlanningDeniedToolName(String toolName) {
    if (toolName.startsWith('ssh_') || toolName.startsWith('ble_')) {
      return true;
    }
    if (toolName.startsWith('computer_')) {
      return !MacosComputerUseToolPolicy.isAllowedInPlanning(toolName);
    }

    return switch (toolName) {
      'write_file' ||
      'edit_file' ||
      'rollback_last_file_change' ||
      'run_tests' ||
      'http_post' ||
      'http_put' ||
      'http_patch' ||
      'http_delete' => true,
      _ => false,
    };
  }

  McpToolResult _buildPlanningToolDeniedResult(
    ToolCallInfo toolCall, {
    String? detail,
  }) {
    final payload = jsonEncode({
      'error':
          'Planning mode allows only read-only tools. Approve the plan and '
          'start implementation before retrying this action.',
      'code': 'permission_denied',
      'reason': 'planning_mode_requires_read_only_tools',
      'tool': toolCall.name,
      if (detail != null && detail.isNotEmpty) 'detail': detail,
    });

    return McpToolResult(
      toolName: toolCall.name,
      result: payload,
      isSuccess: false,
      errorMessage:
          detail ?? 'Planning mode blocks non-read-only tool execution',
    );
  }

  /// Read and accumulate the latest token usage from the data source.
  void _updateTokenUsage() {
    final ds = _dataSource;
    final usage = switch (ds) {
      ChatRemoteDataSource() => ds.lastUsage,
      SessionLoggingChatDataSource() => ds.lastUsage,
      _ => TokenUsage.zero,
    };
    if (usage.totalTokens <= 0) return;

    // Use the latest usage directly (represents the full conversation context)
    _accumulatedTokenUsage = usage;
    state = state.copyWith(
      promptTokens: _accumulatedTokenUsage.promptTokens,
      completionTokens: _accumulatedTokenUsage.completionTokens,
      totalTokens: _accumulatedTokenUsage.totalTokens,
    );
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
      'tag; otherwise answer from verified prior tool results only.',
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

  bool _looksLikeUnexecutedToolRequest(String content) {
    if (_looksLikeStructuredToolRequest(content)) {
      return true;
    }

    final trimmed = content.trim();
    return _looksLikePlanOnlyFinalToolAnswer(trimmed);
  }

  bool _looksLikeStructuredToolRequest(String content) {
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

  bool _containsCjkFutureActionMarker(String value, {int startIndex = 0}) {
    final markers = [
      String.fromCharCodes([0x78ba, 0x8a8d, 0x3057, 0x307e, 0x3059]),
      String.fromCharCodes([0x8abf, 0x67fb, 0x3057, 0x307e, 0x3059]),
      String.fromCharCodes([0x8ffd, 0x8de1, 0x3057, 0x307e, 0x3059]),
      String.fromCharCodes([0x691c, 0x8a3c, 0x3057, 0x307e, 0x3059]),
      String.fromCharCodes([0x8abf, 0x67fb, 0x8a08, 0x753b]),
    ];
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

  Future<void> _finishDetachedActiveResponse(int generation) async {
    if (!_isCurrentInteractionGeneration(generation)) return;

    final targetConversationId = _activeResponseConversationIdForGeneration(
      generation,
    );
    final activeMessages = _activeResponseMessagesForGeneration(generation);
    if (targetConversationId == null ||
        activeMessages == null ||
        activeMessages.isEmpty) {
      _clearActiveResponseForGeneration(generation);
      return;
    }

    final updatedMessages = [...activeMessages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];
    final shouldDropLastAssistant =
        lastMessage.role == MessageRole.assistant &&
        !_assistantMessageHasVisibleContent(lastMessage.content);

    if (shouldDropLastAssistant) {
      updatedMessages.removeAt(lastIndex);
    } else {
      updatedMessages[lastIndex] = lastMessage.copyWith(isStreaming: false);
    }

    final messagesToSave = updatedMessages
        .where((message) => !message.isStreaming)
        .map(_sanitizeMessageForModelHistory)
        .where(_shouldKeepMessageForModelHistory)
        .toList(growable: false);

    await _onConversationMessagesChanged(targetConversationId, messagesToSave);
    if (!_isCurrentInteractionGeneration(generation)) return;

    if (conversationId == targetConversationId) {
      state = state.copyWith(
        messages: updatedMessages,
        isLoading: false,
        pendingAskUserQuestion: null,
      );
    }

    String completedContent = '';
    if (!shouldDropLastAssistant && updatedMessages.isNotEmpty) {
      final finalizedLastMessage = updatedMessages.last;
      if (finalizedLastMessage.role == MessageRole.assistant) {
        completedContent = finalizedLastMessage.content;
      }
    }

    _clearActiveResponseForGeneration(generation);
    _contentToolContinuationCount = 0;
    _onResponseCompleted(completedContent);
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

    if (!_isCurrentInteractionGeneration(generation) ||
        state.messages.isEmpty) {
      return;
    }

    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];
    final shouldDropLastAssistant =
        lastMessage.role == MessageRole.assistant &&
        !_assistantMessageHasVisibleContent(lastMessage.content);

    if (shouldDropLastAssistant) {
      updatedMessages.removeAt(lastIndex);
    } else {
      updatedMessages[lastIndex] = lastMessage.copyWith(isStreaming: false);
    }

    // Capture token usage from the data source
    _updateTokenUsage();

    if (!_isCurrentInteractionGeneration(generation)) return;
    state = state.copyWith(messages: updatedMessages, isLoading: false);

    // Hidden prompt responses are ephemeral — remove from visible history
    // so they are spoken but not persisted in the conversation.
    if (_hiddenPrompt != null) {
      if (!shouldDropLastAssistant && updatedMessages.isNotEmpty) {
        _recordHiddenAssistantResponse(updatedMessages.last.content);
      }
      final cleaned = shouldDropLastAssistant
          ? updatedMessages
          : updatedMessages.sublist(0, lastIndex);
      state = state.copyWith(messages: cleaned);
      _hiddenPrompt = null;
      _onResponseCompleted('');
      if (!_isCurrentInteractionGeneration(generation)) return;
      await _drainQueuedChatMessagesIfIdle();
      return;
    }

    // Persist messages.
    _contentToolContinuationCount = 0;
    _clearActiveResponseForGeneration(generation);
    await _saveMessages();
    if (!_isCurrentInteractionGeneration(generation)) return;

    if (shouldDropLastAssistant || updatedMessages.isEmpty) {
      _clearTurnDiffCapture();
      _onResponseCompleted('');
      if (!_isCurrentInteractionGeneration(generation)) return;
      await _drainQueuedChatMessagesIfIdle();
      return;
    }

    // Trigger auto-read when enabled.
    final finalizedLastMessage = updatedMessages.last;
    if (finalizedLastMessage.role == MessageRole.assistant) {
      await _persistPendingTurnDiffForAssistant(finalizedLastMessage.id);
    } else {
      _clearTurnDiffCapture();
    }
    await ref
        .read(conversationsNotifierProvider.notifier)
        .recordCurrentGoalTurn(
          assistantResponse: finalizedLastMessage.content,
          tokenUsageDelta: _accumulatedTokenUsage.totalTokens,
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
    } else {
      _onResponseCompleted('');
    }
    if (!_isCurrentInteractionGeneration(generation)) return;
    await _drainQueuedChatMessagesIfIdle();
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

    final messagesForLLM = _prepareMessagesForLLM(
      interactionGeneration: interactionGeneration,
    );
    final resultsText = toolResults.join('\n\n');
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
            'Interpret each tool name, description, arguments, and result '
            'together. Preserve the entity roles implied by the tool and the '
            'payload. If the role of an opaque identifier is not explicit, '
            'treat it as ambiguous instead of guessing.\n\n$resultsText',
        role: MessageRole.user,
        timestamp: DateTime.now(),
      ),
    );

    _runWithLlmSessionLogContextForGeneration(interactionGeneration, () {
      final stream = _dataSource.streamChatCompletion(
        messages: messagesForLLM,
        model: _settings.model,
        temperature: _settings.temperature,
        maxTokens: _settings.maxTokens,
      );

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
          temperature: _settings.temperature,
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

  /// Persists the current conversation messages.
  Future<void> _saveMessages() async {
    // Save only messages that are no longer streaming.
    final messagesToSave = state.messages
        .where((m) => !m.isStreaming)
        .map(_sanitizeMessageForModelHistory)
        .where(_shouldKeepMessageForModelHistory)
        .toList();
    String? targetAssistantMessageId;
    for (var i = messagesToSave.length - 1; i >= 0; i--) {
      if (messagesToSave[i].role == MessageRole.assistant) {
        targetAssistantMessageId = messagesToSave[i].id;
        break;
      }
    }

    await _onMessagesChanged(messagesToSave);

    final currentConversationId = conversationId;
    if (currentConversationId != null && targetAssistantMessageId != null) {
      unawaited(
        _updateSessionMemory(
          currentConversationId,
          messagesToSave,
          targetAssistantMessageId,
        ),
      );
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
      final result = await _dataSource.createChatCompletion(
        messages: extractionMessages,
        model: _settings.model,
        temperature: 0.1,
        maxTokens: _settings.maxTokens > 1200 ? 1200 : _settings.maxTokens,
      );

      final draft = MemoryExtractionDraftService.parseDraft(
        result.content,
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

  void _handleError(String error) {
    appLog('[ChatNotifier] _handleError called');
    appLog('[ChatNotifier]   raw error: $error');
    if (!ref.mounted || state.messages.isEmpty) {
      appLog(
        '[ChatNotifier]   skipped: mounted=${ref.mounted}, messages.isEmpty=${state.messages.isEmpty}',
      );
      return;
    }

    // Reformat error messages into clearer user-facing categories.
    final displayError = _buildDisplayError(error);

    appLog('[ChatNotifier]   displayError: $displayError');

    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];

    updatedMessages[lastIndex] = lastMessage.copyWith(
      isStreaming: false,
      error: displayError,
    );

    state = state.copyWith(
      messages: updatedMessages,
      isLoading: false,
      error: displayError,
    );
    _clearTurnDiffCapture();
  }

  String _buildDisplayError(String rawError) {
    final cleanedError = _cleanRawError(rawError);
    final lower = cleanedError.toLowerCase();

    if (cleanedError.contains("Only 'text' content type is supported")) {
      return 'This LLM server does not support image input. Please send text only.\nDetails: $cleanedError';
    }
    if (lower.contains('failed host lookup') ||
        lower.contains('socketexception')) {
      return 'Could not connect to LLM server. Check your network connection and endpoint URL. (${_settings.baseUrl})\nDetails: $cleanedError';
    }
    if (lower.contains('connection refused')) {
      return 'Could not connect to LLM server. Make sure the server is running. (${_settings.baseUrl})\nDetails: $cleanedError';
    }
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return 'LLM request timed out. Please wait and try again.\nDetails: $cleanedError';
    }
    if (lower.contains('401') || lower.contains('unauthorized')) {
      return 'Authentication failed. Please check your API key.\nDetails: $cleanedError';
    }
    if (lower.contains('403') || lower.contains('forbidden')) {
      return 'Access denied. Please check your API key permissions or server settings.\nDetails: $cleanedError';
    }
    if (lower.contains('404') || lower.contains('not found')) {
      return 'Endpoint or model not found. Please check your settings.\nDetails: $cleanedError';
    }
    if (lower.contains('429') || lower.contains('rate limit')) {
      return 'Too many requests. Please wait a moment and try again.\nDetails: $cleanedError';
    }
    if (lower.contains('500') ||
        lower.contains('502') ||
        lower.contains('503') ||
        lower.contains('504') ||
        lower.contains('server error') ||
        lower.contains('internal server error')) {
      return 'An error occurred on the LLM server. Please check the server logs.\nDetails: $cleanedError';
    }
    if (lower.contains('json') ||
        lower.contains('decode') ||
        lower.contains('parse') ||
        lower.contains('unexpected')) {
      return 'Could not parse the response from the LLM server.\nDetails: $cleanedError';
    }

    return cleanedError;
  }

  String _cleanRawError(String rawError) {
    var cleaned = rawError.trim();
    const prefixes = [
      'Exception: ',
      'Bad state: ',
      'ClientException: ',
      'Invalid argument(s): ',
    ];

    for (final prefix in prefixes) {
      if (cleaned.startsWith(prefix)) {
        cleaned = cleaned.substring(prefix.length);
      }
    }

    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  void cancelStreaming() {
    final generation = _interactionGeneration;
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _dismissAllPendingAskUserQuestions();
    _clearAllActiveResponses();

    if (ref.mounted && state.messages.isNotEmpty) {
      final lastMessage = state.messages.last;
      if (lastMessage.isStreaming) {
        unawaited(_finishStreaming(interactionGeneration: generation));
      }
    }
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
    _pendingToolExecutions.clear();
    _queuedChatMessages.clear();
    _latestContentToolResults.clear();
    _contentToolContinuationCount = 0;
    _contentToolExecutionTail = Future<void>.value();
    _dismissAllPendingAskUserQuestions();
    _clearAllActiveResponses();
    _sessionMemoryContext = null;
    _temporalReferenceContext = null;
    _clearTurnDiffCapture();
    state = ChatState.initial();
  }
}
