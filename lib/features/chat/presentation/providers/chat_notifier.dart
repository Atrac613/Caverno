import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/ble_service.dart';
import '../../../../core/services/notification_providers.dart';
import '../../../../core/services/ssh_credentials_manager.dart';
import '../../../../core/services/ssh_service.dart';
import '../../../../core/services/voice_providers.dart';
import '../../../../core/types/assistant_mode.dart';
import '../../../../core/types/workspace_mode.dart';
import '../../../../core/utils/content_parser.dart';
import '../../../../core/utils/logger.dart';
import '../../data/repositories/chat_memory_repository.dart';
import '../../domain/services/system_prompt_builder.dart';
import '../../domain/services/session_memory_service.dart';
import '../../../settings/domain/entities/app_settings.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/datasources/chat_datasource.dart';
import '../../data/datasources/chat_remote_datasource.dart';
import '../../data/datasources/demo_datasource.dart';
import '../../data/datasources/filesystem_tools.dart';
import '../../data/datasources/git_tools.dart';
import '../../data/datasources/local_shell_tools.dart';
import '../../data/datasources/mcp_tool_service.dart';
import '../../domain/entities/coding_project.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../../domain/entities/session_memory.dart';
import '../../domain/services/temporal_context_builder.dart';
import 'chat_state.dart';
import 'coding_projects_notifier.dart';
import 'conversations_notifier.dart';
import 'mcp_tool_provider.dart';
import 'tool_approval_cache.dart';

final chatRemoteDataSourceProvider = Provider<ChatDataSource>((ref) {
  final settings = ref.watch(settingsNotifierProvider);
  if (settings.demoMode) {
    return DemoDataSource();
  }
  return ChatRemoteDataSource(
    baseUrl: settings.baseUrl,
    apiKey: settings.apiKey,
  );
});

final sessionMemoryServiceProvider = Provider<SessionMemoryService>((ref) {
  final repository = ref.watch(chatMemoryRepositoryProvider);
  return SessionMemoryService(repository);
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

class ChatNotifier extends Notifier<ChatState> {
  late ChatDataSource _dataSource;
  McpToolService? _mcpToolService;
  late SessionMemoryService _memoryService;
  late AppSettings _settings;
  String? conversationId;
  String _languageCode = 'en';
  String? _sessionMemoryContext;
  String? _temporalReferenceContext;
  Message? _hiddenPrompt;
  bool _isVoiceMode = false;
  TokenUsage _accumulatedTokenUsage = TokenUsage.zero;
  AssistantMode? _assistantModeOverride;

  @override
  ChatState build() {
    _settings = ref.read(settingsNotifierProvider);
    _dataSource = ref.read(chatRemoteDataSourceProvider);
    _mcpToolService = ref.read(mcpToolServiceProvider);
    _memoryService = ref.read(sessionMemoryServiceProvider);

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

    // React to conversation switches.
    ref.listen<ConversationsState>(conversationsNotifierProvider, (
      previous,
      next,
    ) {
      syncConversation(
        conversationId: next.currentConversation?.id,
        messages: next.currentConversation?.messages ?? const [],
      );
    });

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
  void _onMessagesChanged(List<Message> messages) {
    ref
        .read(conversationsNotifierProvider.notifier)
        .updateCurrentConversation(messages);
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
    if (settings.demoMode) {
      _dataSource = DemoDataSource();
    } else {
      _dataSource = ChatRemoteDataSource(
        baseUrl: settings.baseUrl,
        apiKey: settings.apiKey,
      );
    }
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

    cancelStreaming();
    _executedContentToolCalls.clear();
    _seenContentToolCallHashes.clear();
    _toolApprovalCache.clear();
    _pendingContentToolResults.clear();
    _contentToolContinuationCount = 0;
    _sessionMemoryContext = null;
    _temporalReferenceContext = null;
    this.conversationId = conversationId;
    state = ChatState(messages: messages, isLoading: false, error: null);
    _accumulatedTokenUsage = TokenUsage.zero;
  }

  /// Builds the system message, including the current date and time.
  Message _createSystemMessage() {
    final now = DateTime.now();
    final activeCodingProject = _getActiveCodingProject();
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    final toolNames = <String>[];
    final mcpToolService = _mcpToolService;
    if (mcpToolService != null &&
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
    final resolvedAssistantMode =
        _assistantModeOverride ?? _settings.assistantMode;

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
        workflowStage:
            currentConversation?.workflowStage ??
            ConversationWorkflowStage.idle,
        workflowSpec: currentConversation?.workflowSpec,
        isVoiceMode: _isVoiceMode,
      ),
      role: MessageRole.system,
      timestamp: now,
    );
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

  List<Message> _buildWorkflowProposalMessages({
    required Conversation currentConversation,
    required String languageCode,
    List<WorkflowPlanningDecisionAnswer> decisionAnswers = const [],
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
          decisionAnswers: decisionAnswers,
          compact: compact,
        ),
      ),
    ];
  }

  List<Message> _buildTaskProposalMessages({
    required Conversation currentConversation,
    required String languageCode,
    ConversationWorkflowStage? workflowStageOverride,
    ConversationWorkflowSpec? workflowSpecOverride,
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
          workflowStageOverride: workflowStageOverride,
          workflowSpecOverride: workflowSpecOverride,
          compact: compact,
        ),
      ),
    ];
  }

  Future<WorkflowProposalDraft> _requestWorkflowProposal({
    required Conversation currentConversation,
    required String languageCode,
  }) async {
    final decisionAnswers = <WorkflowPlanningDecisionAnswer>[];
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
        decisionAnswers: decisionAnswers,
      );

      if (result case _WorkflowProposalDraftResponse(:final proposal)) {
        final sanitizedProposal = _removeAnsweredOpenQuestions(
          proposal,
          decisionAnswers,
        );
        final promotedDecisions = _promoteOpenQuestionsToPlanningPrompts(
          sanitizedProposal.workflowSpec.openQuestions,
          decisionAnswers: decisionAnswers,
        );
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
        final resolvedAnswers = await _collectWorkflowDecisionAnswers(
          decisions,
        );
        if (resolvedAnswers == null) {
          throw const _WorkflowProposalCancelled();
        }
        _mergeWorkflowDecisionAnswers(decisionAnswers, resolvedAnswers);
      }
    }

    throw const FormatException(
      'workflow proposal required too many planning decision rounds',
    );
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
          _buildYesNoDecisionFromOpenQuestion(question) ??
          _buildFreeTextDecisionFromOpenQuestion(question);
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

  WorkflowPlanningDecision? _buildFreeTextDecisionFromOpenQuestion(
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
    return WorkflowPlanningDecision(
      id: normalizedQuestion,
      question: trimmedQuestion,
      help: isJapanese
          ? '短く入力してもらえれば plan を続けられます。'
          : 'A short answer here is enough to continue the plan.',
      allowFreeText: true,
      freeTextPlaceholder: isJapanese ? 'ここに回答を入力' : 'Type your answer here',
      options: const [],
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
    if (!lowerQuestion.contains(' or ') &&
        !lowerQuestion.contains(',') &&
        !lowerQuestion.contains(':')) {
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
    required List<WorkflowPlanningDecisionAnswer> decisionAnswers,
  }) async {
    final attempts = <({bool compact, int maxTokens})>[
      (
        compact: false,
        maxTokens: _settings.maxTokens > 1600 ? 1600 : _settings.maxTokens,
      ),
      (
        compact: true,
        maxTokens: _settings.maxTokens > 2200 ? 2200 : _settings.maxTokens,
      ),
    ];

    String? lastError;
    for (var index = 0; index < attempts.length; index++) {
      final attempt = attempts[index];
      final result = await _dataSource.createChatCompletion(
        messages: _buildWorkflowProposalMessages(
          currentConversation: currentConversation,
          languageCode: languageCode,
          decisionAnswers: decisionAnswers,
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

      final preview = _proposalPreview(result.content);
      final truncated = _isCompletionTruncated(result.finishReason);
      appLog(
        '[Workflow] Workflow proposal parse failed (attempt ${index + 1}/${attempts.length}, truncated: $truncated): $preview',
      );
      lastError = truncated
          ? 'workflow proposal was truncated: $preview'
          : 'workflow proposal parse failed: $preview';
      if (!truncated && index == 0) {
        continue;
      }
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

  Future<WorkflowTaskProposalDraft> _requestTaskProposal({
    required Conversation currentConversation,
    required String languageCode,
    ConversationWorkflowStage? workflowStageOverride,
    ConversationWorkflowSpec? workflowSpecOverride,
  }) async {
    final attempts = <({bool compact, int maxTokens})>[
      (
        compact: false,
        maxTokens: _settings.maxTokens > 1800 ? 1800 : _settings.maxTokens,
      ),
      (
        compact: true,
        maxTokens: _settings.maxTokens > 2400 ? 2400 : _settings.maxTokens,
      ),
    ];

    String? lastError;
    for (var index = 0; index < attempts.length; index++) {
      final attempt = attempts[index];
      final result = await _dataSource.createChatCompletion(
        messages: _buildTaskProposalMessages(
          currentConversation: currentConversation,
          languageCode: languageCode,
          workflowStageOverride: workflowStageOverride,
          workflowSpecOverride: workflowSpecOverride,
          compact: attempt.compact,
        ),
        model: _settings.model,
        temperature: 0.1,
        maxTokens: attempt.maxTokens,
      );

      final proposal = _parseTaskProposalWithFallback(result.content);
      if (proposal != null) {
        if (index > 0) {
          appLog('[Workflow] Task proposal recovered on retry');
        }
        return proposal;
      }

      final preview = _proposalPreview(result.content);
      final truncated = _isCompletionTruncated(result.finishReason);
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

    throw FormatException(lastError ?? 'task proposal parse failed');
  }

  String _buildWorkflowProposalRequest({
    required Conversation currentConversation,
    required String languageCode,
    List<WorkflowPlanningDecisionAnswer> decisionAnswers = const [],
    bool compact = false,
  }) {
    final project = _getActiveCodingProject();
    final savedSpec = currentConversation.effectiveWorkflowSpec;
    final transcript = _buildProposalTranscript();
    final buffer = StringBuffer()
      ..writeln('Create a workflow proposal for the current coding thread.')
      ..writeln('Return only a single valid JSON object with no markdown.')
      ..writeln(
        'Write all text fields in ${_proposalLanguageName(languageCode)}.',
      )
      ..writeln(
        'Keep JSON keys and workflowStage enum values in English exactly as shown in the schema.',
      )
      ..writeln(
        'Schema: {"kind":"proposal|decision","workflowStage":"clarify|plan|tasks|implement|review","goal":string,"constraints":[string],"acceptanceCriteria":[string],"openQuestions":[string],"decisions":[{"id":string,"question":string,"help":string,"inputMode":"singleChoice|freeText","placeholder":string,"options":[{"id":string,"label":string,"description":string}]}]}',
      )
      ..writeln('Rules:')
      ..writeln('- Prefer concise, high-signal wording.')
      ..writeln(
        '- If a user choice would materially change the plan, return kind="decision" instead of guessing.',
      )
      ..writeln(
        '- Reserve openQuestions for missing facts, unresolved dependencies, or research gaps that cannot be answered as a simple user choice.',
      )
      ..writeln(
        '- In decision mode, return one to three single-choice decisions with two to four mutually exclusive options each.',
      )
      ..writeln(
        '- If the user must answer in their own words instead of picking from known options, return inputMode="freeText" with an empty options array.',
      )
      ..writeln(
        '- In proposal mode, return kind="proposal" and set decisions to an empty array.',
      )
      ..writeln(
        compact
            ? '- Keep constraints and acceptanceCriteria to at most three items.'
            : '- Keep each list to at most five items.',
      )
      ..writeln(
        compact
            ? '- Keep openQuestions to at most two items and use short phrases.'
            : '- If important information is missing, use openQuestions.',
      )
      ..writeln(
        compact
            ? '- Keep goal to one short sentence and keep the whole response under 220 tokens.'
            : '- Do not include tasks in this response.',
      )
      ..writeln(
        compact
            ? '- Do not include tasks in this response.'
            : '- Keep list items short and easy to review.',
      )
      ..writeln(
        compact
            ? '- If important information is missing, prefer short openQuestions.'
            : '- If important information is missing, use openQuestions.',
      )
      ..writeln(
        '- Do not put yes/no, direct preference choices, or direct user-input prompts into openQuestions when they should be decisions instead.',
      )
      ..writeln('- Never output explanatory prose outside JSON.');

    if (project != null) {
      buffer
        ..writeln()
        ..writeln('Project:')
        ..writeln('- name: ${project.name}')
        ..writeln('- rootPath: ${project.normalizedRootPath}');
    }
    if (currentConversation.hasWorkflowContext) {
      buffer
        ..writeln()
        ..writeln('Current saved workflow:')
        ..writeln('- stage: ${currentConversation.workflowStage.name}')
        ..writeln('- goal: ${savedSpec.goal}')
        ..writeln('- constraints: ${savedSpec.constraints.join(' | ')}')
        ..writeln(
          '- acceptanceCriteria: ${savedSpec.acceptanceCriteria.join(' | ')}',
        )
        ..writeln('- openQuestions: ${savedSpec.openQuestions.join(' | ')}');
    }
    if (decisionAnswers.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Selected planning decisions:');
      for (final answer in decisionAnswers) {
        buffer.writeln('- ${answer.question}: ${answer.optionLabel}');
      }
    }

    buffer
      ..writeln()
      ..writeln('Recent conversation:')
      ..writeln(transcript.isEmpty ? '- (empty)' : transcript);

    return buffer.toString().trimRight();
  }

  String _buildTaskProposalRequest({
    required Conversation currentConversation,
    required String languageCode,
    ConversationWorkflowStage? workflowStageOverride,
    ConversationWorkflowSpec? workflowSpecOverride,
    bool compact = false,
  }) {
    final project = _getActiveCodingProject();
    final savedSpec =
        workflowSpecOverride ?? currentConversation.effectiveWorkflowSpec;
    final savedStage =
        workflowStageOverride ?? currentConversation.workflowStage;
    final transcript = _buildProposalTranscript();
    final buffer = StringBuffer()
      ..writeln('Create a task proposal for the current coding thread.')
      ..writeln('Return only a single valid JSON object with no markdown.')
      ..writeln(
        'Write all text fields in ${_proposalLanguageName(languageCode)}.',
      )
      ..writeln('Keep JSON keys in English exactly as shown in the schema.')
      ..writeln(
        'Schema: {"tasks":[{"title":string,"targetFiles":[string],"validationCommand":string,"notes":string}]}',
      )
      ..writeln('Rules:')
      ..writeln('- Return the full suggested task list for the current thread.')
      ..writeln(
        compact
            ? '- Keep the list to at most four tasks.'
            : '- Keep the list to at most six tasks.',
      )
      ..writeln(
        compact
            ? '- Keep titles concrete, short, and implementation-oriented.'
            : '- Keep titles concrete and implementation-oriented.',
      )
      ..writeln('- Use repo-relative file paths when you can infer them.')
      ..writeln(
        compact
            ? '- Keep notes brief and keep the whole response under 260 tokens.'
            : '- validationCommand and notes may be empty strings.',
      )
      ..writeln('- Never output explanatory prose outside JSON.');

    if (project != null) {
      buffer
        ..writeln()
        ..writeln('Project:')
        ..writeln('- name: ${project.name}')
        ..writeln('- rootPath: ${project.normalizedRootPath}');
    }

    buffer
      ..writeln()
      ..writeln('Saved workflow:')
      ..writeln('- stage: ${savedStage.name}')
      ..writeln('- goal: ${savedSpec.goal}')
      ..writeln('- constraints: ${savedSpec.constraints.join(' | ')}')
      ..writeln(
        '- acceptanceCriteria: ${savedSpec.acceptanceCriteria.join(' | ')}',
      )
      ..writeln('- openQuestions: ${savedSpec.openQuestions.join(' | ')}');

    if (savedSpec.tasks.isNotEmpty) {
      buffer.writeln('- existingTasks:');
      for (final task in savedSpec.tasks) {
        buffer.writeln(
          '  - [${task.status.name}] ${task.title} | files: ${task.targetFiles.join(', ')} | validate: ${task.validationCommand} | notes: ${task.notes}',
        );
      }
    }

    buffer
      ..writeln()
      ..writeln('Recent conversation:')
      ..writeln(transcript.isEmpty ? '- (empty)' : transcript);

    return buffer.toString().trimRight();
  }

  String _buildProposalTranscript() {
    final visibleMessages = state.messages
        .where((message) => !message.isStreaming)
        .toList();
    final tail = visibleMessages.length > 12
        ? visibleMessages.sublist(visibleMessages.length - 12)
        : visibleMessages;
    final buffer = StringBuffer();

    for (final message in tail) {
      final plainText = _extractPlainTextForProposal(message.content);
      if (plainText.isEmpty) continue;
      final clipped = plainText.length > 500
          ? '${plainText.substring(0, 500)}...'
          : plainText;
      buffer.writeln('- ${message.role.name}: $clipped');
    }

    return buffer.toString().trimRight();
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
    return null;
  }

  _WorkflowProposalResponse? _parseWorkflowProposalResponseWithFallback(
    String rawContent,
  ) {
    final direct = _parseWorkflowProposalResponse(rawContent);
    if (direct != null) {
      return direct;
    }

    final reasoningContent = _extractProposalReasoningContent(rawContent);
    if (reasoningContent.isEmpty) {
      return null;
    }
    return _parseWorkflowProposalResponse(reasoningContent);
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
    if (direct != null) {
      return direct;
    }

    final reasoningContent = _extractProposalReasoningContent(rawContent);
    if (reasoningContent.isEmpty) {
      return null;
    }
    return _parseTaskProposal(reasoningContent);
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

    if (tasks.isEmpty) return null;
    return WorkflowTaskProposalDraft(tasks: tasks);
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
    if (tasks.isEmpty) return null;
    return WorkflowTaskProposalDraft(tasks: tasks.take(6).toList());
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

  String _proposalLanguageName(String languageCode) {
    return switch (languageCode) {
      'ja' => 'Japanese',
      'en' => 'English',
      _ => 'English',
    };
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
    return _promoteChoiceLikeOpenQuestions(
      openQuestions,
      decisionAnswers: decisionAnswers,
    );
  }

  @visibleForTesting
  WorkflowTaskProposalDraft? parseTaskProposalForTest(String rawContent) {
    return _parseTaskProposalWithFallback(rawContent);
  }

  Map<String, dynamic> _resolveProjectScopedArguments(
    String toolName,
    Map<String, dynamic> arguments,
  ) {
    final projectRoot = _getActiveProjectRootPath();

    String? resolvePathArg(
      String key, {
      bool allowEmpty = false,
      List<String> aliases = const [],
    }) {
      String? rawValue = (arguments[key] as String?)?.trim();
      for (final alias in aliases) {
        if (rawValue != null && rawValue.isNotEmpty) {
          break;
        }
        rawValue = (arguments[alias] as String?)?.trim();
      }
      if ((rawValue == null || rawValue.isEmpty) && !allowEmpty) {
        return null;
      }
      return FilesystemTools.resolvePath(rawValue, defaultRoot: projectRoot);
    }

    return switch (toolName) {
      'list_directory' || 'find_files' || 'search_files' => () {
        final resolvedPath = resolvePathArg('path', allowEmpty: true);
        final resolvedArguments = <String, dynamic>{...arguments};
        if (resolvedPath != null) {
          resolvedArguments['path'] = resolvedPath;
        }
        return resolvedArguments;
      }(),
      'read_file' || 'write_file' || 'edit_file' => () {
        final resolvedPath = resolvePathArg('path');
        final resolvedArguments = <String, dynamic>{...arguments};
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

  /// Prepares the message list sent to the LLM, including system messages.
  List<Message> _prepareMessagesForLLM() {
    final messages = state.messages.where((m) => !m.isStreaming).toList();
    final promptMessages = <Message>[_createSystemMessage()];
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
    final result = [...promptMessages, ...messages];
    if (_hiddenPrompt != null) {
      result.add(_hiddenPrompt!);
    }
    return result;
  }

  final _uuid = const Uuid();
  StreamSubscription<String>? _streamSubscription;

  /// Tracks executed `tool_call`s to avoid duplicate execution.
  final Set<String> _executedContentToolCalls = {};
  final Set<String> _seenContentToolCallHashes = {};
  final List<String> _pendingContentToolResults = [];
  final ToolApprovalCache _toolApprovalCache = ToolApprovalCache();
  static const int _maxContentToolContinuations = 5;
  int _contentToolContinuationCount = 0;

  Future<void> sendMessage(
    String content, {
    String? imageBase64,
    String? imageMimeType,
    String languageCode = 'en',
    bool isVoiceMode = false,
    bool bypassPlanMode = false,
  }) async {
    // Do not send empty input with no attached image.
    if (content.trim().isEmpty && imageBase64 == null) return;
    if (!ref.mounted) return;

    _hiddenPrompt = null;
    _languageCode = languageCode;
    _isVoiceMode = isVoiceMode;
    _toolApprovalCache.clear();
    _pendingContentToolResults.clear();
    _contentToolContinuationCount = 0;

    _temporalReferenceContext = TemporalContextBuilder.build(
      now: DateTime.now(),
      userInput: content,
    );
    final shouldUseTemporalTool = _temporalReferenceContext != null;
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    final shouldInterceptForPlanMode =
        !bypassPlanMode &&
        _settings.assistantMode == AssistantMode.plan &&
        currentConversation?.workspaceMode == WorkspaceMode.coding;

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
      isLoading: shouldInterceptForPlanMode,
      error: null,
    );

    if (shouldInterceptForPlanMode) {
      _onMessagesChanged(
        state.messages.where((message) => !message.isStreaming).toList(),
      );
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
    state = state.copyWith(messages: [...state.messages, assistantMessage]);

    // Request extended background execution time on iOS.
    _onSendStarted();

    _assistantModeOverride = bypassPlanMode ? AssistantMode.coding : null;

    try {
      // Use tool-aware flow when the MCP tool service is available.
      if (_mcpToolService != null &&
          (_settings.mcpEnabled || shouldUseTemporalTool)) {
        final mode = _settings.mcpEnabled ? 'MCP' : 'TemporalOnly';
        appLog('[Tool] Sending in tool-aware mode ($mode)');
        await _sendWithTools();
      } else {
        appLog(
          '[Tool] Sending in normal mode (mcpToolService: ${_mcpToolService != null}, enabled: ${_settings.mcpEnabled})',
        );
        await _sendWithoutTools();
      }
    } finally {
      _assistantModeOverride = null;
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
      await _sendWithTools();
    } else {
      appLog('[Tool] Sending hidden prompt in normal mode');
      await _sendWithoutTools();
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
      final proposal = await _requestWorkflowProposal(
        currentConversation: currentConversation,
        languageCode: languageCode,
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

  Future<void> generatePlanProposal({String languageCode = 'en'}) async {
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
      final proposal = await _requestTaskProposal(
        currentConversation: currentConversation,
        languageCode: languageCode,
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

  Future<void> _runPlanProposalFlow({
    required Conversation currentConversation,
    required String languageCode,
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

    WorkflowProposalDraft? workflowDraft;
    try {
      workflowDraft = await _requestWorkflowProposal(
        currentConversation: currentConversation,
        languageCode: languageCode,
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        isGeneratingWorkflowProposal: false,
        workflowProposalDraft: workflowDraft,
        workflowProposalError: null,
      );
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
        workflowStageOverride: workflowDraft.workflowStage,
        workflowSpecOverride: workflowDraft.workflowSpec,
      );
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

  /// Sends a streaming request without tools.
  Future<void> _sendWithoutTools() async {
    if (!ref.mounted) return;
    try {
      final stream = _dataSource.streamChatCompletion(
        messages: _prepareMessagesForLLM(),
        model: _settings.model,
        temperature: _settings.temperature,
        maxTokens: _settings.maxTokens,
      );

      _streamSubscription = stream.listen(
        (chunk) {
          _appendToLastMessage(chunk);
        },
        onError: (error, stackTrace) {
          appLog(
            '[ChatNotifier] _sendWithoutTools stream onError: ${error.runtimeType}: $error',
          );
          appLog('[ChatNotifier] stackTrace: $stackTrace');
          _handleError(error.toString());
        },
        onDone: () {
          _finishStreaming();
        },
      );
    } catch (e, stackTrace) {
      appLog('[ChatNotifier] _sendWithoutTools catch: ${e.runtimeType}: $e');
      appLog('[ChatNotifier] stackTrace: $stackTrace');
      _handleError(e.toString());
    }
  }

  /// Sends a request with tool support (function calling).
  Future<void> _sendWithTools() async {
    if (!ref.mounted) return;
    try {
      // Fetch tool definitions from the MCP tool service.
      final allTools = _mcpToolService?.getOpenAiToolDefinitions() ?? [];
      if (allTools.isEmpty) {
        // Fall back to normal streaming when no tools are available.
        await _sendWithoutTools();
        return;
      }
      appLog(
        '[Tool] Tool definitions: ${allTools.map((t) => (t['function'] as Map?)?['name']).toList()}',
      );

      // Start with search tools only to avoid premature `web_url_read` calls.
      final searchOnlyTools = allTools.where((t) {
        final name = (t['function'] as Map?)?['name'] as String?;
        return name == 'searxng_web_search' || name == 'web_search';
      }).toList();
      final datetimeTools = allTools.where((t) {
        final name = (t['function'] as Map?)?['name'] as String?;
        return name == 'get_current_datetime';
      }).toList();
      final memoryTools = allTools.where((t) {
        final name = (t['function'] as Map?)?['name'] as String?;
        return name == 'search_past_conversations' || name == 'recall_memory';
      }).toList();
      const networkToolNames = {
        'ping',
        'whois_lookup',
        'dns_lookup',
        'port_check',
        'ssl_certificate',
        'http_status',
        'traceroute',
      };
      final networkTools = allTools.where((t) {
        final name = (t['function'] as Map?)?['name'] as String?;
        return networkToolNames.contains(name);
      }).toList();
      const codingToolNames = {
        'list_directory',
        'read_file',
        'write_file',
        'edit_file',
        'rollback_last_file_change',
        'find_files',
        'search_files',
        'local_execute_command',
        'git_execute_command',
      };
      final codingTools = allTools.where((t) {
        final name = (t['function'] as Map?)?['name'] as String?;
        return codingToolNames.contains(name);
      }).toList();
      final initialTools = searchOnlyTools.isNotEmpty
          ? _dedupeToolsByName([
              ...searchOnlyTools,
              ...datetimeTools,
              ...memoryTools,
              ...networkTools,
              ...codingTools,
            ])
          : allTools;

      // Stream the initial request to show thinking/content in real-time
      // while also detecting tool calls.
      final streamResult = _dataSource.streamChatCompletionWithTools(
        messages: _prepareMessagesForLLM(),
        tools: initialTools,
        model: _settings.model,
        temperature: _settings.temperature,
        maxTokens: _settings.maxTokens,
      );

      // Display streamed content (thinking, preamble) in real-time.
      await for (final chunk in streamResult.stream) {
        if (!ref.mounted) return;
        _appendToLastMessage(chunk);
      }

      // Retrieve the accumulated tool calls after the stream ends.
      final result = await streamResult.completion;

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
        );
      } else {
        // No tool calls — content was already streamed in real-time.
        appLog('[Tool] No tool calls, response already streamed');
        _finishStreaming();
      }
    } catch (e) {
      // Fall back when the LLM likely does not support tools.
      final errorStr = e.toString().toLowerCase();
      appLog('[Tool] Error occurred: $e');

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
        await _sendWithoutTools();
        return;
      }
      _handleError(e.toString());
    }
  }

  List<Map<String, dynamic>> _dedupeToolsByName(
    List<Map<String, dynamic>> tools,
  ) {
    final seen = <String>{};
    final deduped = <Map<String, dynamic>>[];
    for (final tool in tools) {
      final name = (tool['function'] as Map?)?['name'];
      if (name is! String || name.isEmpty) continue;
      if (seen.add(name)) {
        deduped.add(tool);
      }
    }
    return deduped;
  }

  /// Executes tool calls, supporting a repeated tool-call loop.
  ///
  /// Continues looping while the LLM keeps requesting tools, until it returns
  /// a text response. Because qwen35-35b does not reliably use tool-role
  /// messages as real-time data, tool results are resent as a user message.
  Future<void> _executeToolCalls(
    List<ToolCallInfo> toolCalls, {
    String? assistantContent,
  }) async {
    var currentToolCalls = toolCalls;
    var currentAssistantContent = assistantContent;
    const maxIterations = 5; // Prevent infinite loops.
    var iteration = 0;
    var consecutiveErrors = 0;
    String? lastErrorToolName;
    var hasTextResponse = false;
    final executedToolCallKeys = <String>{};
    // Collect tool results for the final user-role resend.
    final toolResults = <String>[];

    while (currentToolCalls.isNotEmpty && iteration < maxIterations) {
      iteration++;
      final toolCall = currentToolCalls.first;
      final toolCallKey = _toolExecutionKey(toolCall);
      if (!ref.mounted) return;

      if (executedToolCallKeys.contains(toolCallKey)) {
        appLog(
          '[Tool] Duplicate tool call detected, ending loop: ${toolCall.name} ${toolCall.arguments}',
        );
        currentToolCalls = [];
        break;
      }

      appLog('[Tool] Tool loop [$iteration/$maxIterations]');
      appLog('[Tool] Executing tool: ${toolCall.name}');
      appLog('[Tool] Arguments: ${toolCall.arguments}');

      _appendToolUseToLastMessage(toolCall);

      try {
        // Execute the tool. SSH tools that require a UI dialog are
        // intercepted here so ChatNotifier can surface a Completer-based
        // confirmation via ChatState; everything else dispatches straight
        // to McpToolService.
        final McpToolResult result = await _dispatchToolCall(toolCall);

        String toolResult;
        if (result.isSuccess) {
          toolResult = result.result;
          toolResults.add('[Result of ${toolCall.name}]\n$toolResult');
          executedToolCallKeys.add(toolCallKey);
          consecutiveErrors = 0;
          lastErrorToolName = null;
        } else {
          toolResult = 'Error: ${result.errorMessage}';
          // Count repeated failures for the same tool.
          if (lastErrorToolName == toolCall.name) {
            consecutiveErrors++;
          } else {
            consecutiveErrors = 1;
            lastErrorToolName = toolCall.name;
          }
          if (consecutiveErrors >= 2) {
            appLog(
              '[Tool] Same tool (${toolCall.name}) failed $consecutiveErrors times consecutively, ending loop',
            );
            _appendToLastMessage(
              '\nFailed to execute tool (${toolCall.name}). Please check your server configuration.\nError: ${result.errorMessage}\n',
            );
            hasTextResponse = true;
            break;
          }
        }

        appLog('[Tool] Result retrieved: ${toolResult.length} chars');

        // Show a thinking indicator while waiting for the follow-up request.
        _appendToLastMessage('<think>');

        // Send the tool result back to the LLM and check for follow-up calls.
        // Use a non-streaming request with tool definitions included.
        final mcpToolService = _mcpToolService;
        if (mcpToolService == null) {
          await _sendWithoutTools();
          return;
        }
        final tools = mcpToolService.getOpenAiToolDefinitions();
        final nextResult = await _dataSource.createChatCompletionWithToolResult(
          messages: _prepareMessagesForLLM(),
          toolCallId: toolCall.id,
          toolName: toolCall.name,
          toolArguments: jsonEncode(toolCall.arguments),
          toolResult: toolResult,
          assistantContent: currentAssistantContent,
          tools: tools,
          model: _settings.model,
          temperature: _settings.temperature,
          maxTokens: _settings.maxTokens,
        );

        if (!ref.mounted) return;

        // Remove the temporary thinking indicator.
        _removeTrailingThinkTag();

        // Continue looping if the LLM asks for another tool call.
        if (nextResult.hasToolCalls) {
          appLog('[Tool] LLM requested additional tool calls');
          currentToolCalls = nextResult.toolCalls!;
          currentAssistantContent = nextResult.content.isNotEmpty
              ? nextResult.content
              : null;
        } else {
          // End the loop on a text response, but delay rendering it.
          appLog('[Tool] LLM returned final text response (via tool role)');
          currentToolCalls = [];
          // Responses through the tool role often claim real-time data is
          // unavailable, so resend the results later as a user message.
        }
      } catch (e) {
        appLog('[Tool] Error: $e');
        _appendToLastMessage('[Search error: $e]\n');
        currentToolCalls = [];
        hasTextResponse = true;
      }
    }

    // If tool results exist and no text response has been shown yet,
    // resend them as a user message and stream the final answer.
    if (!hasTextResponse && toolResults.isNotEmpty) {
      appLog('[Tool] Resending tool results as user message');

      if (!ref.mounted) return;

      // Build a prompt that includes tool results as a user message.
      final messagesForLLM = _prepareMessagesForLLM();
      // Append the collected tool results as a user message.
      final resultsText = toolResults.join('\n\n');
      messagesForLLM.add(
        Message(
          id: 'tool_result_${DateTime.now().millisecondsSinceEpoch}',
          content:
              'Please answer the user\'s question based on the following search results.\n\n$resultsText',
          role: MessageRole.user,
          timestamp: DateTime.now(),
        ),
      );

      // Show a thinking indicator while waiting for the final streaming answer.
      _appendToLastMessage('<think>');

      // Stream the final answer.
      final stream = _dataSource.streamChatCompletion(
        messages: messagesForLLM,
        model: _settings.model,
        temperature: _settings.temperature,
        maxTokens: _settings.maxTokens,
      );

      var isFirstChunk = true;
      await for (final chunk in stream) {
        if (!ref.mounted) return;
        if (isFirstChunk) {
          isFirstChunk = false;
          // Remove the temporary thinking indicator now that real data arrives.
          _removeTrailingThinkTag();
          if (state.messages.isNotEmpty &&
              state.messages.last.content.isNotEmpty) {
            _appendToLastMessage('\n');
          }
        }
        _appendToLastMessage(chunk);
      }
      // If the stream was empty, still clean up the indicator.
      if (isFirstChunk) {
        _removeTrailingThinkTag();
      }
    } else if (!hasTextResponse) {
      appLog('[Tool] Tool loop reached maximum iterations (no text response)');
      if (state.messages.isNotEmpty) {
        _appendToLastMessage(
          '\nSorry, there was a problem executing the tools. Please try again later.',
        );
      }
    }

    _finishStreaming();
  }

  void _appendToLastMessage(String chunk, {bool scanForTools = true}) {
    if (!ref.mounted || state.messages.isEmpty) return;

    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];

    final newContent = lastMessage.content + chunk;
    updatedMessages[lastIndex] = lastMessage.copyWith(content: newContent);

    state = state.copyWith(messages: updatedMessages);

    // Check whether the content contains completed tool-call tags.
    if (scanForTools) {
      _checkForContentToolCalls(newContent);
    }
  }

  /// Replaces the last message's content entirely instead of appending.
  void _replaceLastMessageContent(String newContent) {
    if (!ref.mounted || state.messages.isEmpty) return;

    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];

    updatedMessages[lastIndex] = lastMessage.copyWith(content: newContent);
    state = state.copyWith(messages: updatedMessages);
  }

  /// Removes a trailing `<think>` tag appended as a temporary indicator.
  void _removeTrailingThinkTag() {
    if (!ref.mounted || state.messages.isEmpty) return;

    final lastMessage = state.messages.last;
    final content = lastMessage.content;
    if (content.endsWith('<think>')) {
      _replaceLastMessageContent(
        content.substring(0, content.length - '<think>'.length),
      );
    }
  }

  void _appendToolUseToLastMessage(ToolCallInfo toolCall) {
    final payload = <String, dynamic>{
      'name': toolCall.name,
      'arguments': toolCall.arguments,
    };
    _appendToLastMessage(
      '<tool_use>${jsonEncode(payload)}</tool_use>\n',
      scanForTools: false,
    );
  }

  /// Tool executions that are still pending.
  final List<Future<void>> _pendingToolExecutions = [];

  /// Detects and runs `tool_call` tags embedded in the content.
  void _checkForContentToolCalls(String content) {
    final toolCalls = ContentParser.extractCompletedToolCalls(content);
    final freshToolCalls = toolCalls.where((tc) {
      return _seenContentToolCallHashes.add(_contentToolCallHash(tc));
    }).toList();

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
      if (tc.name == 'memory_update') {
        appLog('[ContentTool] Ignoring display-only tool: ${tc.name}');
        continue;
      }
      final hash = '${tc.name}:${jsonEncode(tc.arguments)}';
      if (!_executedContentToolCalls.contains(hash)) {
        appLog('[ContentTool] Starting execution: $hash');
        _executedContentToolCalls.add(hash);
        final future = _executeContentToolCall(tc);
        _pendingToolExecutions.add(future);
      } else {
        appLog('[ContentTool] Already executed: $hash');
      }
    }
  }

  String _contentToolCallHash(ToolCallData toolCall) {
    return '${toolCall.name}:${jsonEncode(toolCall.arguments)}';
  }

  String _toolExecutionKey(ToolCallInfo toolCall) {
    return '${toolCall.name}:${_normalizeToolExecutionValue(toolCall.arguments)}';
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
  Future<void> _executeContentToolCall(ToolCallData tc) async {
    if (!ref.mounted) return;

    appLog('[ContentTool] Executing tool: ${tc.name}');
    appLog('[ContentTool] Arguments: ${tc.arguments}');

    try {
      final result = await _dispatchToolCall(
        ToolCallInfo(
          id: 'content_${DateTime.now().microsecondsSinceEpoch}',
          name: tc.name,
          arguments: tc.arguments,
        ),
      );

      if (!result.isSuccess) {
        appLog('[ContentTool] Execution failed: ${result.errorMessage}');
        return;
      }

      appLog('[ContentTool] Result retrieved: ${result.result.length} chars');

      // Append results without triggering recursive tool-call checks.
      if (ref.mounted && state.messages.isNotEmpty) {
        final updatedMessages = [...state.messages];
        final lastIndex = updatedMessages.length - 1;
        final lastMessage = updatedMessages[lastIndex];

        updatedMessages[lastIndex] = lastMessage.copyWith(
          content:
              '${lastMessage.content}\n\n${_buildContentToolResultTag(tc.name, result.result)}',
        );

        state = state.copyWith(messages: updatedMessages);
        appLog('[ContentTool] Appended result to message');
      }

      _pendingContentToolResults.add(
        '[Result of ${tc.name}]\n${result.result}',
      );
    } catch (e) {
      appLog('[ContentTool] Error: $e');
      if (ref.mounted && state.messages.isNotEmpty) {
        final updatedMessages = [...state.messages];
        final lastIndex = updatedMessages.length - 1;
        final lastMessage = updatedMessages[lastIndex];

        updatedMessages[lastIndex] = lastMessage.copyWith(
          content: '${lastMessage.content}\n\n[Tool execution error: $e]',
        );

        state = state.copyWith(messages: updatedMessages);
      }
    }
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
  Future<McpToolResult> _dispatchToolCall(ToolCallInfo toolCall) async {
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
      case 'ssh_connect':
        return _handleSshConnect(toolCall);
      case 'ssh_execute_command':
        return _handleSshExecuteCommand(toolCall);
      case 'git_execute_command':
        return _handleGitExecuteCommand(toolCall);
      case 'ble_connect':
        return _handleBleConnect(toolCall);
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

  Future<McpToolResult> _handleWriteFile(ToolCallInfo toolCall) async {
    final accessFailure = await _ensureActiveProjectAccess(toolCall.name);
    if (accessFailure != null) return accessFailure;

    final resolvedArguments = _resolveProjectScopedArguments(
      toolCall.name,
      toolCall.arguments,
    );
    final path = (resolvedArguments['path'] as String?)?.trim() ?? '';
    final content = resolvedArguments['content'] as String? ?? '';
    if (path.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'path is required',
      );
    }

    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      resolvedArguments,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    if (!_settings.confirmFileMutations) {
      return _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: resolvedArguments,
      );
    }

    final preview = await FilesystemTools.buildWriteDiffPreview(
      path: path,
      newContent: content,
    );
    final approved = await requestFileOperation(
      operation: 'Write File',
      path: path,
      preview: preview,
      reason: toolCall.arguments['reason'] as String?,
    );
    if (!approved) {
      return _rememberToolApprovalResult(
        toolCall.name,
        resolvedArguments,
        McpToolResult(
          toolName: toolCall.name,
          result: '',
          isSuccess: false,
          errorMessage: 'User denied file write',
        ),
      );
    }

    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: resolvedArguments,
    );
    return _rememberToolApprovalResult(
      toolCall.name,
      resolvedArguments,
      result,
    );
  }

  Future<McpToolResult> _handleEditFile(ToolCallInfo toolCall) async {
    final accessFailure = await _ensureActiveProjectAccess(toolCall.name);
    if (accessFailure != null) return accessFailure;

    final resolvedArguments = _resolveProjectScopedArguments(
      toolCall.name,
      toolCall.arguments,
    );
    final path = (resolvedArguments['path'] as String?)?.trim() ?? '';
    final oldText = resolvedArguments['old_text'] as String? ?? '';
    final newText = resolvedArguments['new_text'] as String? ?? '';
    if (path.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'path is required',
      );
    }

    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      resolvedArguments,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    if (!_settings.confirmFileMutations) {
      return _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: resolvedArguments,
      );
    }

    final preview = await FilesystemTools.buildEditDiffPreview(
      path: path,
      oldText: oldText,
      newText: newText,
      replaceAll: resolvedArguments['replace_all'] as bool? ?? false,
    );

    final approved = await requestFileOperation(
      operation: 'Edit File',
      path: path,
      preview: preview,
      reason: toolCall.arguments['reason'] as String?,
    );
    if (!approved) {
      return _rememberToolApprovalResult(
        toolCall.name,
        resolvedArguments,
        McpToolResult(
          toolName: toolCall.name,
          result: '',
          isSuccess: false,
          errorMessage: 'User denied file edit',
        ),
      );
    }

    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: resolvedArguments,
    );
    return _rememberToolApprovalResult(
      toolCall.name,
      resolvedArguments,
      result,
    );
  }

  Future<McpToolResult> _handleRollbackLastFileChange(
    ToolCallInfo toolCall,
  ) async {
    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      toolCall.arguments,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    final preview = await _mcpToolService!.previewLastFileRollbackChange();
    if (preview == null) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'No recent file change is available to roll back',
      );
    }

    if (!_settings.confirmFileMutations) {
      return _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: toolCall.arguments,
      );
    }

    final reason =
        (toolCall.arguments['reason'] as String?)?.trim().isNotEmpty == true
        ? toolCall.arguments['reason'] as String?
        : preview.summary;

    final approved = await requestFileOperation(
      operation: 'Rollback File Change',
      path: preview.path,
      preview: preview.preview,
      reason: reason,
    );
    if (!approved) {
      return _rememberToolApprovalResult(
        toolCall.name,
        toolCall.arguments,
        McpToolResult(
          toolName: toolCall.name,
          result: '',
          isSuccess: false,
          errorMessage: 'User denied file rollback',
        ),
      );
    }

    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: toolCall.arguments,
    );
    return _rememberToolApprovalResult(
      toolCall.name,
      toolCall.arguments,
      result,
    );
  }

  Future<McpToolResult> _handleLocalExecuteCommand(
    ToolCallInfo toolCall,
  ) async {
    final accessFailure = await _ensureActiveProjectAccess(toolCall.name);
    if (accessFailure != null) return accessFailure;

    final resolvedArguments = _resolveProjectScopedArguments(
      toolCall.name,
      toolCall.arguments,
    );
    final command = (resolvedArguments['command'] as String?)?.trim() ?? '';
    final workingDirectory =
        (resolvedArguments['working_directory'] as String?)?.trim() ?? '';
    if (command.isEmpty || workingDirectory.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage:
            'command is required and working_directory must be provided or inferred from the selected coding project',
      );
    }

    if (LocalShellTools.isReadOnly(command)) {
      return _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: resolvedArguments,
      );
    }

    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      resolvedArguments,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    if (!_settings.confirmLocalCommands) {
      return _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: resolvedArguments,
      );
    }

    final approved = await requestLocalCommand(
      command: command,
      workingDirectory: workingDirectory,
      reason: toolCall.arguments['reason'] as String?,
    );
    if (!approved) {
      return _rememberToolApprovalResult(
        toolCall.name,
        resolvedArguments,
        McpToolResult(
          toolName: toolCall.name,
          result: '',
          isSuccess: false,
          errorMessage: 'User denied local command execution',
        ),
      );
    }

    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: resolvedArguments,
    );
    return _rememberToolApprovalResult(
      toolCall.name,
      resolvedArguments,
      result,
    );
  }

  Future<McpToolResult> _handleSshConnect(ToolCallInfo toolCall) async {
    final host = (toolCall.arguments['host'] as String?)?.trim() ?? '';
    final port = (toolCall.arguments['port'] as num?)?.toInt() ?? 22;
    final username = (toolCall.arguments['username'] as String?)?.trim() ?? '';
    final cacheArguments = <String, dynamic>{
      'host': host,
      'port': port,
      'username': username,
    };

    if (host.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'host is required',
      );
    }

    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      cacheArguments,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    final approval = await requestSshConnect(
      host: host,
      port: port,
      username: username,
    );
    if (approval == null) {
      return _rememberToolApprovalResult(
        toolCall.name,
        cacheArguments,
        McpToolResult(
          toolName: toolCall.name,
          result: '',
          isSuccess: false,
          errorMessage: 'User cancelled SSH connection',
        ),
      );
    }

    try {
      await ref
          .read(sshServiceProvider)
          .connect(
            host: approval.host,
            port: approval.port,
            username: approval.username,
            password: approval.password,
          );
      if (approval.savePassword) {
        await ref
            .read(sshCredentialsManagerProvider)
            .savePassword(
              host: approval.host,
              port: approval.port,
              username: approval.username,
              password: approval.password,
            );
      } else {
        // User unchecked "save"; clear any previously saved password for
        // this triplet so the next connect prompt is empty.
        await ref
            .read(sshCredentialsManagerProvider)
            .deletePassword(
              host: approval.host,
              port: approval.port,
              username: approval.username,
            );
      }
      return _rememberToolApprovalResult(
        toolCall.name,
        cacheArguments,
        McpToolResult(
          toolName: toolCall.name,
          result:
              'Connected to ${approval.username}@${approval.host}:${approval.port}',
          isSuccess: true,
        ),
      );
    } catch (e) {
      appLog('[Tool] SSH connect failed: $e');
      return _rememberToolApprovalResult(
        toolCall.name,
        cacheArguments,
        McpToolResult(
          toolName: toolCall.name,
          result: '',
          isSuccess: false,
          errorMessage: 'SSH connect failed: $e',
        ),
      );
    }
  }

  Future<McpToolResult> _handleBleConnect(ToolCallInfo toolCall) async {
    final deviceId = (toolCall.arguments['device_id'] as String?)?.trim() ?? '';
    if (deviceId.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'device_id is required',
      );
    }

    final cacheArguments = <String, dynamic>{'device_id': deviceId};
    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      cacheArguments,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    final bleService = ref.read(bleServiceProvider);
    final scanResults = bleService.getScanResults();
    final device = scanResults.where(
      (d) => d.peripheral.uuid.toString() == deviceId,
    );
    final deviceName = device.isNotEmpty ? device.first.name : null;

    final approved = await requestBleConnect(
      deviceId: deviceId,
      deviceName: deviceName,
    );
    if (!approved) {
      return _rememberToolApprovalResult(
        toolCall.name,
        cacheArguments,
        McpToolResult(
          toolName: toolCall.name,
          result: '',
          isSuccess: false,
          errorMessage: 'User cancelled BLE connection',
        ),
      );
    }

    try {
      await bleService.connect(deviceId);
      return _rememberToolApprovalResult(
        toolCall.name,
        cacheArguments,
        McpToolResult(
          toolName: toolCall.name,
          result: 'Connected to ${deviceName ?? deviceId}',
          isSuccess: true,
        ),
      );
    } catch (e) {
      appLog('[Tool] BLE connect failed: $e');
      return _rememberToolApprovalResult(
        toolCall.name,
        cacheArguments,
        McpToolResult(
          toolName: toolCall.name,
          result: '',
          isSuccess: false,
          errorMessage: 'BLE connect failed: $e',
        ),
      );
    }
  }

  /// Puts a pending BLE connect request into state and returns a future
  /// that completes with `true` (approved) or `false` (denied).
  Future<bool> requestBleConnect({
    required String deviceId,
    String? deviceName,
  }) {
    final completer = Completer<bool>();
    state = state.copyWith(
      pendingBleConnect: PendingBleConnect(
        id: const Uuid().v4(),
        deviceId: deviceId,
        deviceName: deviceName,
        completer: completer,
      ),
    );
    return completer.future;
  }

  /// Resolves a pending BLE connect dialog from the UI layer.
  void resolveBleConnect({required String id, required bool approved}) {
    final pending = state.pendingBleConnect;
    if (pending == null || pending.id != id) return;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(approved);
    }
    state = state.copyWith(pendingBleConnect: null);
  }

  Future<McpToolResult> _handleSshExecuteCommand(ToolCallInfo toolCall) async {
    final sshService = ref.read(sshServiceProvider);
    if (!sshService.isConnected) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'No active SSH session — call ssh_connect first',
      );
    }
    final command = (toolCall.arguments['command'] as String?)?.trim() ?? '';
    if (command.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage: 'command is required',
      );
    }
    final cacheArguments = <String, dynamic>{'command': command};
    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      cacheArguments,
    );
    if (cachedResult != null) {
      return cachedResult;
    }
    final reason = toolCall.arguments['reason'] as String?;
    final approved = await requestSshCommand(command: command, reason: reason);
    if (!approved) {
      return _rememberToolApprovalResult(
        toolCall.name,
        cacheArguments,
        McpToolResult(
          toolName: toolCall.name,
          result: '',
          isSuccess: false,
          errorMessage: 'User denied SSH command execution',
        ),
      );
    }
    // Approved — delegate to the tool service, which runs the command on
    // the same SSH session.
    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: toolCall.arguments,
    );
    return _rememberToolApprovalResult(toolCall.name, cacheArguments, result);
  }

  /// Puts a pending SSH connect request into state and returns a future
  /// that completes when the user confirms or cancels the dialog.
  Future<SshConnectApproval?> requestSshConnect({
    required String host,
    required int port,
    required String username,
  }) async {
    String? savedPassword;
    if (username.isNotEmpty) {
      try {
        savedPassword = await ref
            .read(sshCredentialsManagerProvider)
            .loadPassword(host: host, port: port, username: username);
      } catch (e) {
        appLog('[SSH] Failed to load saved password: $e');
      }
    }

    final completer = Completer<SshConnectApproval?>();
    state = state.copyWith(
      pendingSshConnect: PendingSshConnect(
        id: const Uuid().v4(),
        host: host,
        port: port,
        username: username,
        savedPassword: savedPassword,
        completer: completer,
      ),
    );
    return completer.future;
  }

  /// Resolves a pending SSH connect dialog from the UI layer.
  void resolveSshConnect({required String id, SshConnectApproval? approval}) {
    final pending = state.pendingSshConnect;
    if (pending == null || pending.id != id) return;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(approval);
    }
    state = state.copyWith(pendingSshConnect: null);
  }

  /// Puts a pending SSH command into state and returns a future that
  /// completes with `true` (approve) or `false` (deny).
  Future<bool> requestSshCommand({required String command, String? reason}) {
    final session = ref.read(sshServiceProvider).activeSession;
    final completer = Completer<bool>();
    state = state.copyWith(
      pendingSshCommand: PendingSshCommand(
        id: const Uuid().v4(),
        command: command,
        reason: reason,
        host: session?.host ?? '(no session)',
        username: session?.username ?? '',
        completer: completer,
      ),
    );
    return completer.future;
  }

  /// Resolves a pending SSH command dialog from the UI layer.
  void resolveSshCommand({required String id, required bool approved}) {
    final pending = state.pendingSshCommand;
    if (pending == null || pending.id != id) return;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(approved);
    }
    state = state.copyWith(pendingSshCommand: null);
  }

  // -------------------------------------------------------------------------
  // Git tool handlers
  // -------------------------------------------------------------------------

  Future<McpToolResult> _handleGitExecuteCommand(ToolCallInfo toolCall) async {
    final accessFailure = await _ensureActiveProjectAccess(toolCall.name);
    if (accessFailure != null) return accessFailure;

    final resolvedArguments = _resolveProjectScopedArguments(
      toolCall.name,
      toolCall.arguments,
    );
    final command = GitTools.normalizeCommand(
      (resolvedArguments['command'] as String?)?.trim() ?? '',
    );
    final requestedWorkingDirectory =
        (resolvedArguments['working_directory'] as String?)?.trim() ?? '';
    final workingDirectory = requestedWorkingDirectory;

    if (command.isEmpty || workingDirectory.isEmpty) {
      return McpToolResult(
        toolName: toolCall.name,
        result: '',
        isSuccess: false,
        errorMessage:
            'command is required and working_directory must be provided or inferred from the selected coding project',
      );
    }

    final gitArguments = {
      ...resolvedArguments,
      'command': command,
      'working_directory': workingDirectory,
    };

    // Read-only commands execute immediately without user confirmation.
    if (GitTools.isReadOnly(command)) {
      return _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: gitArguments,
      );
    }

    final cachedResult = _lookupToolApprovalResult(toolCall.name, gitArguments);
    if (cachedResult != null) {
      return cachedResult;
    }

    if (!_settings.confirmGitWrites) {
      return _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: gitArguments,
      );
    }

    // Write commands require user approval.
    final reason = toolCall.arguments['reason'] as String?;
    final approved = await requestGitCommand(
      command: command,
      workingDirectory: workingDirectory,
      reason: reason,
    );
    if (!approved) {
      return _rememberToolApprovalResult(
        toolCall.name,
        gitArguments,
        McpToolResult(
          toolName: toolCall.name,
          result: '',
          isSuccess: false,
          errorMessage: 'User denied git command execution',
        ),
      );
    }
    final result = await _mcpToolService!.executeTool(
      name: toolCall.name,
      arguments: gitArguments,
    );
    return _rememberToolApprovalResult(toolCall.name, gitArguments, result);
  }

  /// Puts a pending git command into state and returns a future that
  /// completes with `true` (approve) or `false` (deny).
  Future<bool> requestGitCommand({
    required String command,
    required String workingDirectory,
    String? reason,
  }) {
    final completer = Completer<bool>();
    state = state.copyWith(
      pendingGitCommand: PendingGitCommand(
        id: const Uuid().v4(),
        command: command,
        workingDirectory: workingDirectory,
        reason: reason,
        completer: completer,
      ),
    );
    return completer.future;
  }

  /// Resolves a pending git command dialog from the UI layer.
  void resolveGitCommand({required String id, required bool approved}) {
    final pending = state.pendingGitCommand;
    if (pending == null || pending.id != id) return;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(approved);
    }
    state = state.copyWith(pendingGitCommand: null);
  }

  Future<bool> requestLocalCommand({
    required String command,
    required String workingDirectory,
    String? reason,
  }) {
    final completer = Completer<bool>();
    state = state.copyWith(
      pendingLocalCommand: PendingLocalCommand(
        id: const Uuid().v4(),
        command: command,
        workingDirectory: workingDirectory,
        reason: reason,
        completer: completer,
      ),
    );
    return completer.future;
  }

  void resolveLocalCommand({required String id, required bool approved}) {
    final pending = state.pendingLocalCommand;
    if (pending == null || pending.id != id) return;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(approved);
    }
    state = state.copyWith(pendingLocalCommand: null);
  }

  Future<bool> requestFileOperation({
    required String operation,
    required String path,
    required String preview,
    String? reason,
  }) {
    final completer = Completer<bool>();
    state = state.copyWith(
      pendingFileOperation: PendingFileOperation(
        id: const Uuid().v4(),
        operation: operation,
        path: path,
        preview: preview,
        reason: reason,
        completer: completer,
      ),
    );
    return completer.future;
  }

  void resolveFileOperation({required String id, required bool approved}) {
    final pending = state.pendingFileOperation;
    if (pending == null || pending.id != id) return;
    if (!pending.completer.isCompleted) {
      pending.completer.complete(approved);
    }
    state = state.copyWith(pendingFileOperation: null);
  }

  /// Read and accumulate the latest token usage from the data source.
  void _updateTokenUsage() {
    final ds = _dataSource;
    if (ds is! ChatRemoteDataSource) return;

    final usage = ds.lastUsage;
    if (usage.totalTokens <= 0) return;

    // Use the latest usage directly (represents the full conversation context)
    _accumulatedTokenUsage = usage;
    state = state.copyWith(
      promptTokens: _accumulatedTokenUsage.promptTokens,
      completionTokens: _accumulatedTokenUsage.completionTokens,
      totalTokens: _accumulatedTokenUsage.totalTokens,
    );
  }

  Future<void> _finishStreaming() async {
    // Wait for pending tool executions before finalizing the response.
    if (_pendingToolExecutions.isNotEmpty) {
      appLog(
        '[ChatNotifier] Waiting for pending tool executions: ${_pendingToolExecutions.length}',
      );
      await Future.wait(_pendingToolExecutions);
      _pendingToolExecutions.clear();
      appLog('[ChatNotifier] Tool executions completed');
    }

    if (_pendingContentToolResults.isNotEmpty) {
      final toolResults = List<String>.from(_pendingContentToolResults);
      _pendingContentToolResults.clear();

      if (_contentToolContinuationCount >= _maxContentToolContinuations) {
        if (ref.mounted && state.messages.isNotEmpty) {
          final updatedMessages = [...state.messages];
          final lastIndex = updatedMessages.length - 1;
          final lastMessage = updatedMessages[lastIndex];
          updatedMessages[lastIndex] = lastMessage.copyWith(
            content:
                '${lastMessage.content}\n\n[Tool continuation limit reached. Please ask again with a more specific request.]',
          );
          state = state.copyWith(messages: updatedMessages);
        }
      } else {
        _contentToolContinuationCount += 1;
        await _continueAfterContentToolResults(toolResults);
        return;
      }
    }

    if (!ref.mounted || state.messages.isEmpty) return;

    final updatedMessages = [...state.messages];
    final lastIndex = updatedMessages.length - 1;
    final lastMessage = updatedMessages[lastIndex];

    updatedMessages[lastIndex] = lastMessage.copyWith(isStreaming: false);

    // Capture token usage from the data source
    _updateTokenUsage();

    state = state.copyWith(messages: updatedMessages, isLoading: false);

    // Hidden prompt responses are ephemeral — remove from visible history
    // so they are spoken but not persisted in the conversation.
    if (_hiddenPrompt != null) {
      final cleaned = updatedMessages.sublist(0, lastIndex);
      state = state.copyWith(messages: cleaned);
      _hiddenPrompt = null;
      _onResponseCompleted('');
      return;
    }

    // Persist messages.
    _contentToolContinuationCount = 0;
    _saveMessages();

    // Trigger auto-read when enabled.
    if (_settings.autoReadEnabled && _settings.ttsEnabled) {
      final lastMsg = updatedMessages[lastIndex];
      if (lastMsg.role == MessageRole.assistant && lastMsg.content.isNotEmpty) {
        _onAutoRead(lastMsg.content);
      }
    }

    // Notify when the response completes while the app is in the background.
    final lastMsg = updatedMessages[lastIndex];
    if (lastMsg.role == MessageRole.assistant && lastMsg.content.isNotEmpty) {
      _onResponseCompleted(lastMsg.content);
    } else {
      _onResponseCompleted('');
    }
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
    List<String> toolResults,
  ) async {
    if (!ref.mounted || state.messages.isEmpty) return;

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

    final messagesForLLM = _prepareMessagesForLLM();
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
            'Do not repeat a tool call with the same arguments after a '
            'permission_denied or equivalent access error. '
            'Explain the issue and ask the user to re-select the project '
            'folder or grant access instead.\n\n$resultsText',
        role: MessageRole.user,
        timestamp: DateTime.now(),
      ),
    );

    final stream = _dataSource.streamChatCompletion(
      messages: messagesForLLM,
      model: _settings.model,
      temperature: _settings.temperature,
      maxTokens: _settings.maxTokens,
    );

    _streamSubscription = stream.listen(
      (chunk) {
        _appendToLastMessage(chunk);
      },
      onError: (error, stackTrace) {
        appLog(
          '[ChatNotifier] _continueAfterContentToolResults onError: ${error.runtimeType}: $error',
        );
        appLog('[ChatNotifier] stackTrace: $stackTrace');
        _handleError(error.toString());
      },
      onDone: () {
        _finishStreaming();
      },
    );
  }

  /// Persists the current conversation messages.
  void _saveMessages() {
    // Save only messages that are no longer streaming.
    final messagesToSave = state.messages.where((m) => !m.isStreaming).toList();
    String? targetAssistantMessageId;
    for (var i = messagesToSave.length - 1; i >= 0; i--) {
      if (messagesToSave[i].role == MessageRole.assistant) {
        targetAssistantMessageId = messagesToSave[i].id;
        break;
      }
    }

    _onMessagesChanged(messagesToSave);

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
    _onMessagesChanged(normalized);
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
    final extractionInput = _buildMemoryExtractionInput(messages, profile);

    final extractionMessages = [
      Message(
        id: 'memory_extractor_system',
        role: MessageRole.system,
        timestamp: now,
        content:
            'You extract reusable user memory from a conversation. '
            'Output only a single valid JSON object with no markdown. '
            'Schema: {"summary":string,"open_loops":[string],'
            '"profile":{"persona":[string],"preferences":[string],"do_not":[string]},'
            '"memories":[{"text":string,"type":"preference|persona|topic|constraint|fact",'
            '"confidence":number,"importance":number,"ttl_days":number|null}]}. '
            'Focus on stable user traits/preferences/constraints. '
            'Also extract specific facts the user mentioned: prices, quantities, '
            'purchases, dates, decisions, events, and other concrete data points. '
            'Use type "fact" with high importance for these. '
            'Facts should have detailed text (up to 300 chars) to preserve specifics. '
            'Do not include temporary assistant instructions.',
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

      final draft = _parseMemoryExtractionDraft(result.content);
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

  String _buildMemoryExtractionInput(
    List<Message> messages,
    UserMemoryProfile profile,
  ) {
    final buffer = StringBuffer()
      ..writeln('Current profile:')
      ..writeln('- persona: ${profile.persona.join(' | ')}')
      ..writeln('- preferences: ${profile.preferences.join(' | ')}')
      ..writeln('- do_not: ${profile.doNot.join(' | ')}')
      ..writeln()
      ..writeln('Conversation log:');

    final tail = messages.length > 12
        ? messages.sublist(messages.length - 12)
        : messages;
    for (final message in tail) {
      if (message.content.trim().isEmpty) continue;
      final role = message.role.name;
      final content = message.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      final clipped = content.length > 360
          ? '${content.substring(0, 360)}...'
          : content;
      buffer.writeln('- $role: $clipped');
    }

    buffer
      ..writeln()
      ..writeln('Output rules:')
      ..writeln('- summary must be 160 characters or fewer')
      ..writeln('- open_loops max 3 items')
      ..writeln('- memories max 8 items')
      ..writeln('- confidence/importance range: 0.0 to 1.0')
      ..writeln('- Set confidence low for uncertain items');

    return buffer.toString();
  }

  MemoryExtractionDraft? _parseMemoryExtractionDraft(String rawContent) {
    final jsonText = _extractJsonObject(rawContent);
    if (jsonText == null) return null;

    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);

      final summary = (map['summary'] as String?)?.trim() ?? '';
      final openLoops = _stringList(map['open_loops'], maxLength: 3);

      final profile = map['profile'];
      List<String> persona = const [];
      List<String> preferences = const [];
      List<String> doNot = const [];
      if (profile is Map) {
        final profileMap = Map<String, dynamic>.from(profile);
        persona = _stringList(profileMap['persona'], maxLength: 12);
        preferences = _stringList(profileMap['preferences'], maxLength: 16);
        doNot = _stringList(profileMap['do_not'], maxLength: 16);
      }

      final entries = <MemoryDraftEntry>[];
      final memoriesRaw = map['memories'];
      if (memoriesRaw is List) {
        for (final raw in memoriesRaw.take(8)) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          final text = (item['text'] as String?)?.trim() ?? '';
          if (text.isEmpty) continue;
          final type = (item['type'] as String?)?.trim() ?? 'topic';
          final confidence = (item['confidence'] as num?)?.toDouble() ?? 0.6;
          final importance = (item['importance'] as num?)?.toDouble() ?? 0.6;
          final ttlDays = (item['ttl_days'] as num?)?.toInt();
          entries.add(
            MemoryDraftEntry(
              text: text,
              type: type,
              confidence: confidence,
              importance: importance,
              ttlDays: ttlDays,
            ),
          );
        }
      }

      final draft = MemoryExtractionDraft(
        summary: summary,
        openLoops: openLoops,
        persona: persona,
        preferences: preferences,
        doNot: doNot,
        entries: entries,
      );
      return draft.isEmpty ? null : draft;
    } catch (e) {
      appLog('[Memory] Failed to parse memory extraction JSON: $e');
      return null;
    }
  }

  String? _extractJsonObject(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text
          .replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
    }

    final first = text.indexOf('{');
    final last = text.lastIndexOf('}');
    if (first < 0 || last <= first) return null;
    return text.substring(first, last + 1);
  }

  List<String> _stringList(Object? raw, {required int maxLength}) {
    if (raw is! List) return const [];
    final values = raw
        .whereType<String>()
        .map((value) => value.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (values.length <= maxLength) return values;
    return values.sublist(0, maxLength);
  }

  String _buildMemoryUpdateToolUse(MemoryUpdateResult result) {
    final payload = <String, dynamic>{
      'name': 'memory_update',
      'arguments': <String, dynamic>{
        'summaryUpdated': result.summaryUpdated,
        'added': result.addedMemoryCount,
        'updated': result.updatedMemoryCount,
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
    _streamSubscription?.cancel();
    _streamSubscription = null;

    if (ref.mounted && state.messages.isNotEmpty) {
      final lastMessage = state.messages.last;
      if (lastMessage.isStreaming) {
        _finishStreaming();
      }
    }
  }

  void clearMessages() {
    if (!ref.mounted) return;
    cancelStreaming();
    _executedContentToolCalls.clear();
    _seenContentToolCallHashes.clear();
    _toolApprovalCache.clear();
    _pendingContentToolResults.clear();
    _contentToolContinuationCount = 0;
    _sessionMemoryContext = null;
    _temporalReferenceContext = null;
    state = ChatState.initial();
  }
}
