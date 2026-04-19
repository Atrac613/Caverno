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
import '../../domain/services/conversation_plan_document_builder.dart';
import '../../domain/services/conversation_planning_prompt_service.dart';
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
import '../../domain/entities/conversation_compaction_artifact.dart';
import '../../domain/entities/conversation_plan_artifact.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/message.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../../domain/services/conversation_compaction_service.dart';
import '../../domain/services/memory_extraction_draft_service.dart';
import '../../domain/services/temporal_context_builder.dart';
import '../../domain/services/tool_execution_scheduler.dart';
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
  String? conversationId;
  String _languageCode = 'en';
  String? _sessionMemoryContext;
  String? _temporalReferenceContext;
  Message? _hiddenPrompt;
  bool _isVoiceMode = false;
  TokenUsage _accumulatedTokenUsage = TokenUsage.zero;
  AssistantMode? _assistantModeOverride;
  List<ToolResultInfo> _latestCompletedToolResults = const [];
  String? _latestHiddenAssistantResponse;
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
  Future<void> _onMessagesChanged(List<Message> messages) {
    return ref
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

    // While a response is in flight, the local chat state is authoritative for
    // the active conversation. Persisted conversation updates can lag behind
    // and would otherwise cancel streaming or discard pending content-tool
    // continuations mid-task.
    if (sameConversation && state.isLoading) {
      return;
    }

    cancelStreaming();
    _executedContentToolCalls.clear();
    _seenContentToolCallHashes.clear();
    _toolApprovalCache.clear();
    _pendingContentToolResults.clear();
    _contentToolContinuationCount = 0;
    _contentToolExecutionTail = Future<void>.value();
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
    final resolvedAssistantMode = _resolveAssistantMode(
      currentConversation: currentConversation,
    );

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
        planArtifact: currentConversation?.planArtifact,
        isVoiceMode: _isVoiceMode,
      ),
      role: MessageRole.system,
      timestamp: now,
    );
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
    final attempts = <({bool compact, int maxTokens, bool minimalRetry})>[
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

      final preview = _proposalPreview(result.content);
      final truncated = _isCompletionTruncated(result.finishReason);
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
  }) {
    final normalizedContext = additionalPlanningContext?.trim();
    if (!minimalRetry) {
      return normalizedContext;
    }

    const retryHint = '''
Retry hint:
- Return the smallest valid JSON proposal possible.
- Do not restate the user request, project summary, or research context.
- Prefer a short goal plus one or two short list items over verbose explanations.
- If you are space-constrained, return workflowStage, goal, and a minimal acceptanceCriteria list only.
''';
    if (normalizedContext == null || normalizedContext.isEmpty) {
      return retryHint.trim();
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
        if (_taskProposalNeedsRetry(
          proposal,
          finalizedProposal,
          projectLooksEmpty,
        )) {
          final preview = finalizedProposal.tasks
              .map((task) => task.title)
              .join(' | ');
          appLog(
            '[Workflow] Task proposal quality gate requested retry (attempt ${index + 1}/${attempts.length}): $preview',
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

  String? _buildTaskProposalRetryContext(
    String? additionalPlanningContext, {
    required bool minimalRetry,
    required bool projectLooksEmpty,
  }) {
    final normalizedContext = additionalPlanningContext?.trim();
    if (!minimalRetry) {
      return normalizedContext;
    }

    final retryHint = StringBuffer()
      ..writeln('Retry hint:')
      ..writeln('- Return the smallest valid JSON task list possible.')
      ..writeln('- Return at least two concrete tasks.')
      ..writeln(
        '- Every task must describe an action the agent can perform immediately.',
      )
      ..writeln(
        '- For implementation tasks, use a validationCommand that directly references, executes, or tests the target file or module.',
      )
      ..writeln(
        '- Do not use generic validation such as "module importable" or commands that only append src to sys.path.',
      )
      ..writeln('- Do not stop at a single generic setup or scaffold task.')
      ..writeln(
        '- Do not restate the user request, repo summary, or research context.',
      );
    if (projectLooksEmpty) {
      retryHint
        ..writeln(
          '- The first task may scaffold the workspace, but a later task must implement or validate the requested feature.',
        )
        ..writeln('- Include a concrete code task after any scaffold task.');
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
      r'''The user wants (?:a workflow proposal for |to )(.+?)(?:\.|$)''',
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
      "(recent context|current state|self-correction|(?:title|targetfiles|validationcommand|notes|tasks)\\s*:|[`'\\\"]\\s*(title|targetfiles|validationcommand|notes|tasks)\\s*[`'\\\"]\\s*:)",
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
      final dedupeKey = normalizedTitle.toLowerCase();
      if (!emittedTitles.add(dedupeKey)) {
        continue;
      }
      sanitizedTasks.add(
        task.copyWith(
          title: normalizedTitle,
          targetFiles: normalizedTargetFiles,
        ),
      );
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

    candidate = candidate.replaceFirst(RegExp(r'^\./'), '');
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

    if (finalized.tasks.length == 1 &&
        _looksLikeGenericScaffoldOnlyTask(finalized.tasks.first)) {
      return true;
    }

    return false;
  }

  bool _taskProposalHasImplementationFollowUp(
    List<ConversationWorkflowTask> tasks,
  ) {
    return tasks.any((task) => !_looksLikeGenericScaffoldOnlyTask(task));
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
    return _promoteChoiceLikeOpenQuestions(
      openQuestions,
      decisionAnswers: decisionAnswers,
    );
  }

  @visibleForTesting
  WorkflowTaskProposalDraft? parseTaskProposalForTest(String rawContent) {
    return _parseTaskProposalWithFallback(rawContent);
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
  String? buildTaskProposalRetryContextForTest(
    String? additionalPlanningContext, {
    required bool minimalRetry,
    required bool projectLooksEmpty,
  }) {
    return _buildTaskProposalRetryContext(
      additionalPlanningContext,
      minimalRetry: minimalRetry,
      projectLooksEmpty: projectLooksEmpty,
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
  Map<String, dynamic> normalizeWriteFileArgumentsForTest(
    Map<String, dynamic> arguments,
  ) {
    return _normalizeWriteFileArgumentAliases(arguments);
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
      return FilesystemTools.resolvePath(
        rawValue,
        defaultRoot: loadProjectRoot(),
      );
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
  List<Message> _prepareMessagesForLLM() {
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
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
    final compactionArtifact = _resolvePromptCompactionArtifact(
      currentConversation: currentConversation,
      messages: messages,
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
    return result;
  }

  ConversationCompactionArtifact? _resolvePromptCompactionArtifact({
    required Conversation? currentConversation,
    required List<Message> messages,
  }) {
    final freshArtifact = ConversationCompactionService.buildArtifact(
      messages: messages,
      planDocument: currentConversation?.displayPlanDocument(
        isPlanning: currentConversation.isPlanningSession,
      ),
      now: currentConversation?.effectiveCompactionArtifact.updatedAt,
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

  final _uuid = const Uuid();
  StreamSubscription<String>? _streamSubscription;

  /// Tracks executed `tool_call`s to avoid duplicate execution.
  final Set<String> _executedContentToolCalls = {};
  final Set<String> _seenContentToolCallHashes = {};
  final List<String> _pendingContentToolResults = [];
  final ToolApprovalCache _toolApprovalCache = ToolApprovalCache();
  static const int _maxContentToolContinuations = 5;
  int _contentToolContinuationCount = 0;
  Future<void> _contentToolExecutionTail = Future<void>.value();

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
    if (state.isLoading) return;

    _hiddenPrompt = null;
    _languageCode = languageCode;
    _isVoiceMode = isVoiceMode;
    _toolApprovalCache.clear();
    _pendingContentToolResults.clear();
    _contentToolContinuationCount = 0;
    _contentToolExecutionTail = Future<void>.value();
    _latestCompletedToolResults = const [];
    _latestHiddenAssistantResponse = null;

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
      currentConversation = ref
          .read(conversationsNotifierProvider)
          .currentConversation;
      conversationId = currentConversation?.id;
    }
    await conversationsNotifier.ensureCurrentPlanArtifactBackfilled();
    currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    conversationId = currentConversation?.id;
    final shouldInterceptForPlanMode =
        !bypassPlanMode &&
        (currentConversation?.isPlanningSession ?? false) &&
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
      isLoading: true,
      error: null,
    );

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
    _latestHiddenAssistantResponse = null;
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

  Future<void> generatePlanProposal({String languageCode = 'en'}) async {
    await generatePlanProposalWithContext(languageCode: languageCode);
  }

  List<ToolResultInfo> takeLatestToolResults() {
    final snapshot = _latestCompletedToolResults;
    _latestCompletedToolResults = const [];
    return snapshot;
  }

  String? takeLatestHiddenAssistantResponse() {
    final snapshot = _latestHiddenAssistantResponse;
    _latestHiddenAssistantResponse = null;
    return snapshot;
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
      state = state.copyWith(
        isLoading: false,
        isGeneratingTaskProposal: false,
        taskProposalDraft: taskDraft,
        taskProposalError: null,
      );
      appLog('[Workflow] Task proposal ready');
      await _persistPlanArtifactDraft(
        workflowStage: workflowDraft.workflowStage,
        workflowSpec: workflowDraft.workflowSpec,
        tasks: taskDraft.tasks,
      );
      appLog('[Workflow] Task plan artifact draft persisted');
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
    var hasTextResponse = false;
    final executedToolCallKeys = <String>{};
    final toolFailureCounts = <String, int>{};
    // Collect tool results for the final user-role resend.
    final toolResults = <String>[];
    final executedToolResults = <ToolResultInfo>[];

    while (currentToolCalls.isNotEmpty && iteration < maxIterations) {
      iteration++;
      if (!ref.mounted) return;

      appLog('[Tool] Tool loop [$iteration/$maxIterations]');
      final batchToolResults = <ToolResultInfo>[];
      final pendingBatchCalls = <ToolCallInfo>[];

      for (final toolCall in currentToolCalls) {
        final toolCallKey = _toolExecutionKey(toolCall);
        if (executedToolCallKeys.contains(toolCallKey)) {
          appLog(
            '[Tool] Duplicate tool call detected, skipping: ${toolCall.name} ${toolCall.arguments}',
          );
          continue;
        }

        appLog('[Tool] Executing tool: ${toolCall.name}');
        appLog('[Tool] Arguments: ${toolCall.arguments}');

        _appendToolUseToLastMessage(toolCall);
        pendingBatchCalls.add(toolCall);
      }

      final scheduledResults = await ToolExecutionScheduler.executeBatch(
        toolCalls: pendingBatchCalls,
        execute: _dispatchToolCall,
        onBatch: (telemetry) {
          appLog(
            '[Tool] Scheduler ${telemetry.mode.name} batch '
            '(size=${telemetry.batchSize}, tools=${telemetry.toolNames.join(', ')})'
            '${telemetry.note == null ? '' : ' • ${telemetry.note}'}',
          );
        },
      );

      for (final scheduledResult in scheduledResults) {
        final toolCall = scheduledResult.toolCall;
        final toolCallKey = _toolExecutionKey(toolCall);
        if (scheduledResult.error != null) {
          final error = scheduledResult.error!;
          appLog('[Tool] Error: $error');
          _appendToLastMessage('[Search error: $error]\n');
          hasTextResponse = true;
          break;
        }

        final result = scheduledResult.result!;
        final toolResult = result.isSuccess
            ? result.result
            : (result.result.trim().isNotEmpty
                  ? result.result
                  : 'Error: ${result.errorMessage}');

        toolResults.add('[Result of ${toolCall.name}]\n$toolResult');
        batchToolResults.add(
          ToolResultInfo(
            id: toolCall.id,
            name: toolCall.name,
            arguments: toolCall.arguments,
            result: toolResult,
          ),
        );
        executedToolResults.add(batchToolResults.last);

        if (result.isSuccess) {
          executedToolCallKeys.add(toolCallKey);
          toolFailureCounts.remove(toolCallKey);
        } else {
          final failureCount = (toolFailureCounts[toolCallKey] ?? 0) + 1;
          toolFailureCounts[toolCallKey] = failureCount;
          if (failureCount >= 2) {
            appLog(
              '[Tool] Same tool (${toolCall.name}) failed $failureCount times consecutively, ending loop',
            );
            _appendToLastMessage(
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
      if (batchToolResults.isEmpty) {
        currentToolCalls = [];
        break;
      }

      appLog(
        '[Tool] Retrieved ${batchToolResults.length} tool result(s) in this loop',
      );

      // Show a thinking indicator while waiting for the follow-up request.
      _appendToLastMessage('<think>');

      // Send the tool results back to the LLM and check for follow-up calls.
      // Use a non-streaming request with tool definitions included.
      final mcpToolService = _mcpToolService;
      if (mcpToolService == null) {
        _latestCompletedToolResults = List<ToolResultInfo>.unmodifiable(
          executedToolResults,
        );
        await _sendWithoutTools();
        return;
      }
      final tools = mcpToolService.getOpenAiToolDefinitions();
      final nextResult = await _dataSource.createChatCompletionWithToolResults(
        messages: _prepareMessagesForLLM(),
        toolResults: batchToolResults,
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
        final fallbackResponse = nextResult.content.trim();
        if (fallbackResponse.isNotEmpty) {
          _latestHiddenAssistantResponse = fallbackResponse;
        }
        // Responses through the tool role often claim real-time data is
        // unavailable, so resend the results later as a user message.
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
              'Please answer the user\'s question based on the following tool results.\n\n$resultsText',
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

    _latestCompletedToolResults = List<ToolResultInfo>.unmodifiable(
      executedToolResults,
    );
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
    _markToolCallSeenForContentDedup(toolCall.name, toolCall.arguments);
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
        final future = _enqueueContentToolCall(tc);
        _pendingToolExecutions.add(future);
      } else {
        appLog('[ContentTool] Already executed: $hash');
      }
    }
  }

  Future<void> _enqueueContentToolCall(ToolCallData tc) {
    final future = _contentToolExecutionTail.then((_) {
      if (!ref.mounted) {
        return Future<void>.value();
      }
      return _executeContentToolCall(tc);
    });
    _contentToolExecutionTail = future.catchError((_) {});
    return future;
  }

  String _contentToolCallHash(ToolCallData toolCall) {
    return _toolCallDedupKey(toolCall.name, toolCall.arguments);
  }

  String _toolExecutionKey(ToolCallInfo toolCall) {
    return _toolCallDedupKey(toolCall.name, toolCall.arguments);
  }

  String _toolCallDedupKey(String name, Object? arguments) {
    return '$name:${_normalizeToolExecutionValue(arguments)}';
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
        final failureResult = _buildContentToolFailureResult(
          tc.name,
          result.errorMessage,
        );
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
      final failureResult = _buildContentToolFailureResult(tc.name, '$e');
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
    final planningPolicyResult = _enforcePlanningToolPolicy(toolCall);
    if (planningPolicyResult != null) {
      return planningPolicyResult;
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

  McpToolResult? _enforcePlanningToolPolicy(ToolCallInfo toolCall) {
    final currentConversation = ref
        .read(conversationsNotifierProvider)
        .currentConversation;
    if (!(currentConversation?.isPlanningSession ?? false)) {
      return null;
    }

    switch (toolCall.name) {
      case 'list_directory':
      case 'read_file':
      case 'find_files':
      case 'search_files':
      case 'get_current_datetime':
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

    return switch (toolName) {
      'write_file' ||
      'edit_file' ||
      'rollback_last_file_change' ||
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
    final command = LocalShellTools.normalizeCommand(
      (resolvedArguments['command'] as String?)?.trim() ?? '',
    );
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

    final localArguments = {
      ...resolvedArguments,
      'command': command,
      'working_directory': workingDirectory,
    };

    if (LocalShellTools.isReadOnly(command)) {
      return _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: localArguments,
      );
    }

    final cachedResult = _lookupToolApprovalResult(
      toolCall.name,
      localArguments,
    );
    if (cachedResult != null) {
      return cachedResult;
    }

    if (!_settings.confirmLocalCommands) {
      return _mcpToolService!.executeTool(
        name: toolCall.name,
        arguments: localArguments,
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
        localArguments,
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
      arguments: localArguments,
    );
    return _rememberToolApprovalResult(toolCall.name, localArguments, result);
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

    state = state.copyWith(messages: updatedMessages, isLoading: false);

    // Hidden prompt responses are ephemeral — remove from visible history
    // so they are spoken but not persisted in the conversation.
    if (_hiddenPrompt != null) {
      _latestHiddenAssistantResponse =
          shouldDropLastAssistant || updatedMessages.isEmpty
          ? null
          : updatedMessages.last.content;
      final cleaned = shouldDropLastAssistant
          ? updatedMessages
          : updatedMessages.sublist(0, lastIndex);
      state = state.copyWith(messages: cleaned);
      _hiddenPrompt = null;
      _onResponseCompleted('');
      return;
    }

    // Persist messages.
    _contentToolContinuationCount = 0;
    _saveMessages();

    if (shouldDropLastAssistant || updatedMessages.isEmpty) {
      _onResponseCompleted('');
      return;
    }

    // Trigger auto-read when enabled.
    final finalizedLastMessage = updatedMessages.last;
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
        case ContentType.toolResult:
          final toolName = segment.toolCall?.name.toLowerCase();
          if (toolName != 'memory_update') {
            return true;
          }
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
        unawaited(
          _recoverAfterContentToolResultsStreamError(
            messagesForLLM,
            error,
            stackTrace,
          ),
        );
      },
      onDone: () {
        _finishStreaming();
      },
      cancelOnError: true,
    );
  }

  Future<void> _recoverAfterContentToolResultsStreamError(
    List<Message> messagesForLLM,
    Object error,
    StackTrace stackTrace,
  ) async {
    try {
      final result = await _dataSource.createChatCompletion(
        messages: messagesForLLM,
        model: _settings.model,
        temperature: _settings.temperature,
        maxTokens: _settings.maxTokens,
      );

      if (!ref.mounted || state.messages.isEmpty) {
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
      _replaceLastMessageContent(result.content);
      _checkForContentToolCalls(result.content);
      await _finishStreaming();
    } catch (fallbackError, fallbackStackTrace) {
      appLog(
        '[ChatNotifier] Content-tool continuation fallback failed: ${fallbackError.runtimeType}: $fallbackError',
      );
      appLog('[ChatNotifier] fallbackStackTrace: $fallbackStackTrace');
      appLog('[ChatNotifier] originalStackTrace: $stackTrace');
      _handleError(error.toString());
    }
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

    unawaited(_onMessagesChanged(messagesToSave));

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
    _contentToolExecutionTail = Future<void>.value();
    _sessionMemoryContext = null;
    _temporalReferenceContext = null;
    state = ChatState.initial();
  }
}
