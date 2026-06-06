import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/browser_session_service.dart';
import 'package:caverno/core/services/macos_computer_use_audit_log.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/ssh_credentials_manager.dart';
import 'package:caverno/core/services/ssh_service.dart';
import 'package:caverno/core/services/tool_approval_audit_log.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/filesystem_tools.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/conversation_repository.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_plan_artifact.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/entities/skill.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_hash.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_projection_service.dart';
import 'package:caverno/features/chat/domain/services/coding_command_output_guardrail_service.dart';
import 'package:caverno/features/chat/domain/services/coding_diagnostic_feedback_service.dart';
import 'package:caverno/features/chat/domain/services/coding_verification_feedback_service.dart';
import 'package:caverno/features/chat/domain/services/conversation_goal_suggestion_service.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/domain/services/tool_definition_search_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/chat_state.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/chat/presentation/providers/skills_notifier.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:caverno/core/types/workspace_mode.dart';

class _TestSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: false,
      demoMode: false,
    );
  }
}

class _TestConversationsNotifier extends ConversationsNotifier {
  @override
  ConversationsState build() => ConversationsState.initial();

  @override
  Conversation? ensureCurrentConversation({
    WorkspaceMode? workspaceMode,
    String? projectId,
  }) {
    final resolvedWorkspaceMode = workspaceMode ?? state.activeWorkspaceMode;
    if (!resolvedWorkspaceMode.usesConversations) {
      return null;
    }
    final resolvedProjectId = resolvedWorkspaceMode.usesProjects
        ? (projectId ?? state.activeProjectId)
        : null;
    if (resolvedWorkspaceMode.usesProjects &&
        (resolvedProjectId == null || resolvedProjectId.trim().isEmpty)) {
      return null;
    }
    final currentConversation = state.currentConversation;
    if (currentConversation != null) {
      return currentConversation;
    }
    final now = DateTime(2026, 5, 25, 10);
    final conversation = Conversation(
      id: 'test-conversation-${state.conversations.length + 1}',
      title: defaultConversationTitle,
      messages: const <Message>[],
      createdAt: now,
      updatedAt: now,
      workspaceMode: resolvedWorkspaceMode,
      projectId: resolvedProjectId ?? '',
    );
    state = state.copyWith(
      conversations: [conversation, ...state.conversations],
      currentConversationId: conversation.id,
      activeWorkspaceMode: resolvedWorkspaceMode,
      activeProjectId: resolvedProjectId,
      clearActiveProject:
          !resolvedWorkspaceMode.usesProjects || resolvedProjectId == null,
    );
    return conversation;
  }

  @override
  Future<void> updateCurrentConversation(List<Message> messages) async {
    final currentConversationId = state.currentConversationId;
    if (currentConversationId == null) {
      return;
    }
    await updateConversationMessages(currentConversationId, messages);
  }

  @override
  Future<void> updateConversationMessages(
    String conversationId,
    List<Message> messages,
  ) async {
    final conversation = state.conversations
        .where((item) => item.id == conversationId)
        .firstOrNull;
    if (conversation == null) {
      return;
    }
    final updated = conversation.copyWith(messages: messages);
    state = state.copyWith(
      conversations: state.conversations
          .map((item) => item.id == conversationId ? updated : item)
          .toList(growable: false),
    );
  }

  @override
  Future<void> ensureCurrentPlanArtifactBackfilled() async {}
}

class _DivergingSaveConversationsNotifier extends ConversationsNotifier {
  @override
  ConversationsState build() {
    final conversation = Conversation(
      id: 'queue-sync-conversation',
      title: 'Queue sync',
      messages: const <Message>[],
      createdAt: DateTime(2026, 5, 25, 10),
      updatedAt: DateTime(2026, 5, 25, 10),
    );
    return ConversationsState(
      conversations: [conversation],
      currentConversationId: conversation.id,
      activeWorkspaceMode: WorkspaceMode.chat,
      activeProjectId: null,
    );
  }

  @override
  Future<void> updateCurrentConversation(List<Message> messages) async {
    final current = state.currentConversation;
    if (current == null) {
      return;
    }

    final persistedMessages = messages
        .map(
          (message) => message.role == MessageRole.assistant
              ? message.copyWith(
                  content: message.content.endsWith(' persisted')
                      ? message.content
                      : '${message.content} persisted',
                )
              : message,
        )
        .toList(growable: false);
    final updated = current.copyWith(messages: persistedMessages);
    state = state.copyWith(
      conversations: state.conversations
          .map(
            (conversation) =>
                conversation.id == updated.id ? updated : conversation,
          )
          .toList(growable: false),
    );
    await Future<void>.delayed(Duration.zero);
  }

  @override
  Future<void> ensureCurrentPlanArtifactBackfilled() async {}
}

class _WorkflowTestConversationsNotifier extends ConversationsNotifier {
  _WorkflowTestConversationsNotifier(this.conversation);

  final Conversation conversation;

  @override
  ConversationsState build() => ConversationsState(
    conversations: [conversation],
    currentConversationId: conversation.id,
    activeWorkspaceMode: WorkspaceMode.coding,
    activeProjectId: conversation.normalizedProjectId,
  );

  @override
  Future<void> updateCurrentConversation(List<Message> messages) async {
    final current = state.currentConversation;
    if (current == null) {
      return;
    }
    final updated = current.copyWith(messages: messages);
    state = state.copyWith(conversations: [updated]);
  }

  @override
  Future<void> ensureCurrentPlanArtifactBackfilled() async {}
}

class _TestCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
}

class _FixedCodingProjectsNotifier extends CodingProjectsNotifier {
  _FixedCodingProjectsNotifier(this.project);

  final CodingProject project;

  @override
  CodingProjectsState build() =>
      CodingProjectsState(projects: [project], selectedProjectId: project.id);

  @override
  Future<bool> ensureProjectAccess(String? projectId) async => true;
}

class _MockConversationBox extends Mock implements Box<String> {}

class _FakeConversationRepository extends ConversationRepository {
  _FakeConversationRepository() : super(_MockConversationBox());

  final Map<String, Conversation> _store = {};

  @override
  List<Conversation> getAll() {
    final conversations = _store.values.toList();
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  @override
  Conversation? getById(String id) => _store[id];

  @override
  Future<void> save(Conversation conversation) async {
    _store[conversation.id] = conversation;
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
  }

  @override
  Future<void> deleteAll() async {
    _store.clear();
  }
}

class _DelayedConversationRepository extends _FakeConversationRepository {
  _DelayedConversationRepository({required this.saveDelay});

  final Duration saveDelay;

  @override
  Future<void> save(Conversation conversation) async {
    await Future<void>.delayed(saveDelay);
    await super.save(conversation);
  }
}

class _MockMemoryBox extends Mock implements Box<String> {}

class _TestSessionMemoryService extends SessionMemoryService {
  _TestSessionMemoryService() : super(ChatMemoryRepository(_MockMemoryBox()));

  @override
  String? buildPromptContext({
    required String currentUserInput,
    required String currentConversationId,
    DateTime? now,
  }) {
    return null;
  }

  @override
  Future<MemoryUpdateResult> updateFromConversation({
    required String conversationId,
    required List<Message> messages,
    DateTime? now,
    MemoryExtractionDraft? draft,
  }) async {
    return const MemoryUpdateResult.none();
  }

  @override
  UserMemoryProfile loadProfile() {
    return UserMemoryProfile.empty();
  }
}

class _MockAppLifecycleService extends Mock implements AppLifecycleService {}

class _MockSshService extends Mock implements SshService {}

class _MockSshCredentialsManager extends Mock
    implements SshCredentialsManager {}

class _TestBackgroundTaskService extends BackgroundTaskService {
  @override
  Future<void> beginBackgroundTask() async {}

  @override
  Future<void> endBackgroundTask() async {}

  @override
  void dispose() {}
}

class _ReleaseCheckSkillsNotifier extends SkillsNotifier {
  @override
  SkillsState build() {
    final now = DateTime(2026, 5, 29, 20, 28);
    return SkillsState(
      skills: [
        Skill(
          id: 'release-check',
          name: 'Release Check',
          description: 'Use for release readiness checks',
          whenToUse: 'When the user asks to verify a release',
          content:
              'When this skill is loaded, include SKILL_LIVE_OK. List exactly two verification steps.',
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
  }
}

class _StreamingChatDataSource implements ChatDataSource {
  _StreamingChatDataSource(this.controller);

  final StreamController<String> controller;

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return controller.stream;
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }
}

class _ControllableQueueChatDataSource implements ChatDataSource {
  _ControllableQueueChatDataSource(this.controllers);

  final Queue<StreamController<String>> controllers;
  final List<List<Message>> requests = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    requests.add(List<Message>.from(messages));
    return controllers.removeFirst().stream;
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }
}

class _DelayedAskQuestionToolChatDataSource implements ChatDataSource {
  _DelayedAskQuestionToolChatDataSource({required this.initialCompletion});

  final Completer<ChatCompletionResult> initialCompletion;
  final List<String> finalAnswerChunks = const [
    'Proceeding with the selected option.',
  ];
  final List<List<Message>> initialRequests = [];
  final List<List<Message>> finalAnswerRequests = [];
  final List<List<ToolResultInfo>> toolResultBatches = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    finalAnswerRequests.add(List<Message>.from(messages));
    return Stream<String>.fromIterable(finalAnswerChunks);
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    initialRequests.add(List<Message>.from(messages));
    return StreamWithToolsResult(
      stream: const Stream.empty(),
      completion: initialCompletion.future,
    );
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    toolResultBatches.add(List<ToolResultInfo>.from(toolResults));
    return Future<ChatCompletionResult>.value(
      ChatCompletionResult(content: '', finishReason: 'stop'),
    );
  }
}

class _SkippedSkillLoadChatDataSource implements ChatDataSource {
  _SkippedSkillLoadChatDataSource({
    required this.initialContent,
    required this.finalAnswerChunks,
  });

  final String initialContent;
  final List<String> finalAnswerChunks;
  final List<List<Message>> initialRequests = [];
  final List<List<ToolResultInfo>> toolResultBatches = [];
  final List<List<Message>> finalAnswerRequests = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    finalAnswerRequests.add(List<Message>.from(messages));
    return Stream<String>.fromIterable(finalAnswerChunks);
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    initialRequests.add(List<Message>.from(messages));
    return StreamWithToolsResult(
      stream: const Stream.empty(),
      completion: Future<ChatCompletionResult>.value(
        ChatCompletionResult(content: initialContent, finishReason: 'stop'),
      ),
    );
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    toolResultBatches.add(List<ToolResultInfo>.from(toolResults));
    return Future<ChatCompletionResult>.value(
      ChatCompletionResult(content: '', finishReason: 'stop'),
    );
  }
}

class _QueuedAskQuestionToolChatDataSource implements ChatDataSource {
  _QueuedAskQuestionToolChatDataSource({
    required List<Completer<ChatCompletionResult>> initialCompletions,
    required List<String> finalAnswers,
  }) : _initialCompletions = Queue<Completer<ChatCompletionResult>>.from(
         initialCompletions,
       ),
       _finalAnswers = Queue<String>.from(finalAnswers);

  final Queue<Completer<ChatCompletionResult>> _initialCompletions;
  final Queue<String> _finalAnswers;
  final List<List<Message>> initialRequests = [];
  final List<List<Message>> finalAnswerRequests = [];
  final List<List<ToolResultInfo>> toolResultBatches = [];
  final List<String?> initialRequestContextConversationIds = [];
  final List<String?> toolResultContextConversationIds = [];
  final List<String?> finalAnswerContextConversationIds = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    finalAnswerContextConversationIds.add(
      LlmSessionLogContext.current?.conversationId,
    );
    finalAnswerRequests.add(List<Message>.from(messages));
    return Stream<String>.fromIterable([
      _finalAnswers.isEmpty
          ? 'Proceeding with the selected option.'
          : _finalAnswers.removeFirst(),
    ]);
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    initialRequestContextConversationIds.add(
      LlmSessionLogContext.current?.conversationId,
    );
    initialRequests.add(List<Message>.from(messages));
    return StreamWithToolsResult(
      stream: const Stream.empty(),
      completion: _initialCompletions.removeFirst().future,
    );
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    toolResultContextConversationIds.add(
      LlmSessionLogContext.current?.conversationId,
    );
    toolResultBatches.add(List<ToolResultInfo>.from(toolResults));
    return Future<ChatCompletionResult>.value(
      ChatCompletionResult(content: '', finishReason: 'stop'),
    );
  }
}

class _QueuedStreamingChatDataSource implements ChatDataSource {
  _QueuedStreamingChatDataSource(List<List<String>> responses)
    : _responses = Queue<List<String>>.from(responses);

  final Queue<List<String>> _responses;
  final List<List<Message>> requests = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    requests.add(List<Message>.from(messages));
    if (_responses.isEmpty) {
      return const Stream<String>.empty();
    }
    return Stream<String>.fromIterable(_responses.removeFirst());
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }
}

class _ContinuationFallbackChatDataSource implements ChatDataSource {
  final List<List<Message>> streamRequests = [];
  final List<List<Message>> completionRequests = [];
  var _streamCallCount = 0;

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    streamRequests.add(List<Message>.from(messages));
    _streamCallCount += 1;
    if (_streamCallCount == 1) {
      return Stream<String>.fromIterable(const [
        '<tool_call>{"name":"read_file","arguments":{"path":"src/config_loader.py"}}</tool_call>',
      ]);
    }
    return Stream<String>.error(
      Exception(
        'ClientException: Connection closed before full header was received',
      ),
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    completionRequests.add(List<Message>.from(messages));
    return ChatCompletionResult(
      content: 'Recovered continuation after stream failure.',
      finishReason: 'stop',
    );
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }
}

class _ToolBatchChatDataSource implements ChatDataSource {
  _ToolBatchChatDataSource({
    required this.initialToolCalls,
    this.initialCompletionContent = '',
    this.initialFinishReason = 'tool_calls',
    this.initialStreamChunks = const [],
    this.followUpToolCalls = const [],
    this.intermediateToolRoleResponseContent = '',
    this.toolRoleResponseContent = '',
    this.finalAnswerChunks = const ['Combined tool summary'],
    this.failFirstToolResultCompletionWithContextLength = false,
    this.failFirstFinalAnswerStreamWithContextLength = false,
    List<ChatCompletionResult> autoReviewResponses = const [],
  }) : autoReviewResponses = Queue<ChatCompletionResult>.from(
         autoReviewResponses,
       );

  final List<ToolCallInfo> initialToolCalls;
  final String initialCompletionContent;
  final String initialFinishReason;
  final List<String> initialStreamChunks;
  final List<ToolCallInfo> followUpToolCalls;
  final String intermediateToolRoleResponseContent;
  final String toolRoleResponseContent;
  final List<String> finalAnswerChunks;
  final bool failFirstToolResultCompletionWithContextLength;
  final bool failFirstFinalAnswerStreamWithContextLength;
  final List<List<ToolResultInfo>> toolResultBatches = [];
  final List<List<Message>> initialRequestMessages = [];
  final List<List<Message>> toolResultRequestMessages = [];
  final List<List<Map<String, dynamic>>> initialToolDefinitionBatches = [];
  final List<List<Map<String, dynamic>>> followUpToolDefinitionBatches = [];
  final List<List<Message>> finalAnswerRequestMessages = [];
  final List<List<Message>> autoReviewRequestMessages = [];
  final Queue<ChatCompletionResult> autoReviewResponses;
  List<Message> finalAnswerMessages = const [];
  var _toolLoopResponseCount = 0;

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    final requestMessages = List<Message>.from(messages);
    finalAnswerRequestMessages.add(requestMessages);
    finalAnswerMessages = requestMessages;
    if (failFirstFinalAnswerStreamWithContextLength &&
        finalAnswerRequestMessages.length == 1) {
      throw StateError(
        'This model has a maximum context length of 8192 tokens',
      );
    }
    yield* Stream<String>.fromIterable(finalAnswerChunks);
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    if ((tools == null || tools.isEmpty) &&
        messages.isNotEmpty &&
        messages.first.id == 'auto_review_policy') {
      autoReviewRequestMessages.add(List<Message>.from(messages));
      if (autoReviewResponses.isNotEmpty) {
        return Future<ChatCompletionResult>.value(
          autoReviewResponses.removeFirst(),
        );
      }
    }
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    initialRequestMessages.add(List<Message>.from(messages));
    initialToolDefinitionBatches.add(List<Map<String, dynamic>>.from(tools));
    return StreamWithToolsResult(
      stream: Stream<String>.fromIterable(initialStreamChunks),
      completion: Future<ChatCompletionResult>.value(
        ChatCompletionResult(
          content: initialCompletionContent,
          toolCalls: initialToolCalls,
          finishReason: initialFinishReason,
        ),
      ),
    );
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    toolResultRequestMessages.add(List<Message>.from(messages));
    toolResultBatches.add(List<ToolResultInfo>.from(toolResults));
    followUpToolDefinitionBatches.add(
      List<Map<String, dynamic>>.from(tools ?? const []),
    );
    _toolLoopResponseCount += 1;
    if (failFirstToolResultCompletionWithContextLength &&
        _toolLoopResponseCount == 1) {
      throw StateError(
        'This model has a maximum context length of 8192 tokens',
      );
    }
    if (_toolLoopResponseCount == 1 && followUpToolCalls.isNotEmpty) {
      return ChatCompletionResult(
        content: intermediateToolRoleResponseContent,
        toolCalls: followUpToolCalls,
        finishReason: 'tool_calls',
      );
    }
    return ChatCompletionResult(
      content: toolRoleResponseContent,
      finishReason: 'stop',
    );
  }
}

class _QueuedToolLoopChatDataSource implements ChatDataSource {
  _QueuedToolLoopChatDataSource({
    required this.initialToolCalls,
    required List<ChatCompletionResult> toolLoopResponses,
    this.finalAnswerChunks = const ['Recovered final answer'],
  }) : _toolLoopResponses = Queue<ChatCompletionResult>.from(toolLoopResponses);

  final List<ToolCallInfo> initialToolCalls;
  final Queue<ChatCompletionResult> _toolLoopResponses;
  final List<String> finalAnswerChunks;
  final List<List<ToolResultInfo>> toolResultBatches = [];
  final List<Message> finalAnswerMessages = <Message>[];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    finalAnswerMessages
      ..clear()
      ..addAll(List<Message>.from(messages));
    yield* Stream<String>.fromIterable(finalAnswerChunks);
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return StreamWithToolsResult(
      stream: const Stream.empty(),
      completion: Future<ChatCompletionResult>.value(
        ChatCompletionResult(
          content: '',
          toolCalls: initialToolCalls,
          finishReason: 'tool_calls',
        ),
      ),
    );
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    toolResultBatches.add(List<ToolResultInfo>.from(toolResults));
    return _toolLoopResponses.removeFirst();
  }
}

class _NoToolStreamingWithToolsDataSource implements ChatDataSource {
  _NoToolStreamingWithToolsDataSource({
    required this.streamChunks,
    required this.completionContent,
  });

  final List<String> streamChunks;
  final String completionContent;

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return StreamWithToolsResult(
      stream: Stream<String>.fromIterable(streamChunks),
      completion: Future<ChatCompletionResult>.value(
        ChatCompletionResult(content: completionContent, finishReason: 'stop'),
      ),
    );
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }
}

class _ToolEnabledSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
    );
  }
}

Future<void> _waitForCondition(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met before timeout.', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _ToolEnabledNoConfirmSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
      codingApprovalMode: ToolApprovalMode.fullAccess,
      confirmFileMutations: false,
      confirmLocalCommands: false,
      confirmGitWrites: false,
    );
  }
}

class _ToolEnabledNoVerificationSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
      codingApprovalMode: ToolApprovalMode.fullAccess,
      confirmFileMutations: false,
      confirmLocalCommands: false,
      confirmGitWrites: false,
      enableCodingVerificationFeedback: false,
    );
  }
}

class _ToolEnabledRequestOnlyVerificationSettingsNotifier
    extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
      codingApprovalMode: ToolApprovalMode.fullAccess,
      confirmFileMutations: false,
      confirmLocalCommands: false,
      confirmGitWrites: false,
      codingVerificationTriggerPolicy:
          CodingVerificationTriggerPolicy.onRequestOnly,
    );
  }
}

class _ToolEnabledRemoteDenySettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
      codingApprovalMode: ToolApprovalMode.fullAccess,
      confirmFileMutations: false,
      confirmLocalCommands: false,
      confirmGitWrites: false,
      localCommandPermissionRules: const [
        LocalCommandPermissionRule(
          id: 'deny-rm',
          action: LocalCommandPermissionAction.deny,
          match: LocalCommandPermissionMatch.prefix,
          pattern: 'rm',
          workingDirectory: '/tmp/project',
        ),
      ],
    );
  }
}

class _ToolEnabledAutoReviewSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
      codingApprovalMode: ToolApprovalMode.autoReview,
    );
  }
}

class _ToolEnabledChatFullAccessSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
      browserToolsEnabled: true,
      chatApprovalMode: ToolApprovalMode.fullAccess,
    );
  }
}

class _ToolEnabledChatAutoReviewSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
      browserToolsEnabled: true,
      chatApprovalMode: ToolApprovalMode.autoReview,
    );
  }
}

class _ContentToolSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: false,
      demoMode: false,
      confirmFileMutations: true,
      confirmLocalCommands: true,
    );
  }
}

class _PlanSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.plan,
      mcpEnabled: false,
      demoMode: false,
    );
  }
}

class _FakeMcpToolService extends McpToolService {
  _FakeMcpToolService({
    required this.results,
    this.descriptions = const {},
    Map<String, List<String>> queuedResults = const {},
  }) : queuedResults = queuedResults.map(
         (key, value) => MapEntry(key, Queue<String>.from(value)),
       );

  final Map<String, String> results;
  final Map<String, String> descriptions;
  final Map<String, Queue<String>> queuedResults;
  final List<String> executedToolNames = [];
  final List<Map<String, dynamic>> executedToolArguments = [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return ToolDefinitionSearchService.appendSearchToolIfUseful(
      results.keys
          .map(
            (toolName) => {
              'type': 'function',
              'function': {
                'name': toolName,
                'description': descriptions[toolName] ?? 'Fake tool $toolName',
                'parameters': const <String, dynamic>{'type': 'object'},
              },
            },
          )
          .toList(growable: false),
    );
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    executedToolArguments.add(Map<String, dynamic>.from(arguments));
    if (name == ToolDefinitionSearchService.toolName) {
      return McpToolResult(
        toolName: name,
        result: ToolDefinitionSearchService.searchToolDefinitions(
          definitions: getOpenAiToolDefinitions(),
          query: (arguments['query'] as String?) ?? '',
          maxResults:
              ((arguments['max_results'] as num?)?.toInt() ??
                      ToolDefinitionSearchService.defaultMaxResults)
                  .clamp(1, ToolDefinitionSearchService.maxResultsLimit)
                  .toInt(),
        ),
        isSuccess: true,
      );
    }
    final queued = queuedResults[name];
    if (queued != null && queued.isNotEmpty) {
      return McpToolResult(
        toolName: name,
        result: queued.removeFirst(),
        isSuccess: true,
      );
    }
    return McpToolResult(
      toolName: name,
      result: results[name] ?? '',
      isSuccess: true,
    );
  }
}

class _WritingFileMcpToolService extends McpToolService {
  _WritingFileMcpToolService(this.root);

  final Directory root;
  final List<String> executedToolNames = [];
  final List<Map<String, dynamic>> executedToolArguments = [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return [
      {
        'type': 'function',
        'function': {
          'name': 'write_file',
          'description': 'Write a UTF-8 text file in the fixture project.',
          'parameters': const <String, dynamic>{
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'content': {'type': 'string'},
              'create_parents': {'type': 'boolean'},
            },
            'required': ['path', 'content'],
          },
        },
      },
    ];
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    executedToolArguments.add(Map<String, dynamic>.from(arguments));
    if (name != 'write_file') {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({'error': 'Unsupported fixture tool: $name'}),
        isSuccess: false,
        errorMessage: 'Unsupported fixture tool: $name',
      );
    }
    final resolvedPath = FilesystemTools.resolvePath(
      arguments['path'] as String?,
      defaultRoot: root.absolute.path,
    );
    if (resolvedPath == null || resolvedPath.trim().isEmpty) {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({'error': 'path is required'}),
        isSuccess: false,
        errorMessage: 'path is required',
      );
    }
    final targetPath = File(resolvedPath).absolute.path;
    final rootPath = root.absolute.path;
    if (targetPath != rootPath &&
        !targetPath.startsWith('$rootPath${Platform.pathSeparator}')) {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({'error': 'Path must stay inside the fixture.'}),
        isSuccess: false,
        errorMessage: 'Path must stay inside the fixture.',
      );
    }

    final result = await FilesystemTools.writeFile(
      path: targetPath,
      content: arguments['content'] as String? ?? '',
      createParents: arguments['create_parents'] as bool? ?? true,
    );
    final decoded = _tryDecodeObject(result);
    final error = decoded['error'] as String?;
    return McpToolResult(
      toolName: name,
      result: result,
      isSuccess: error == null || error.isEmpty,
      errorMessage: error,
    );
  }
}

Map<String, dynamic> _tryDecodeObject(String value) {
  try {
    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {
    return const {};
  }
  return const {};
}

class _FakeCodingDiagnosticFeedbackService
    extends CodingDiagnosticFeedbackService {
  _FakeCodingDiagnosticFeedbackService(this.feedback, {this.baseline});

  final ToolResultInfo? feedback;
  final CodingDiagnosticFeedbackBaseline? baseline;
  final List<String> requestedProjectRoots = [];
  final List<List<String>> requestedChangedPaths = [];
  final List<String> baselineProjectRoots = [];
  final List<List<String>> baselineChangedPaths = [];
  final List<CodingDiagnosticFeedbackBaseline?> receivedBaselines = [];

  @override
  Future<CodingDiagnosticFeedbackBaseline?> captureBaseline({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    baselineProjectRoots.add(projectRoot);
    baselineChangedPaths.add(List<String>.from(changedPaths));
    return baseline;
  }

  @override
  Future<ToolResultInfo?> buildFeedbackToolResult({
    required String projectRoot,
    required Iterable<String> changedPaths,
    CodingDiagnosticFeedbackBaseline? baseline,
    DateTime? now,
  }) async {
    requestedProjectRoots.add(projectRoot);
    requestedChangedPaths.add(List<String>.from(changedPaths));
    receivedBaselines.add(baseline);
    return feedback;
  }
}

class _FakeCodingVerificationFeedbackService
    extends CodingVerificationFeedbackService {
  _FakeCodingVerificationFeedbackService(ToolResultInfo? feedback)
    : runs = Queue<CodingVerificationFeedbackRun>.from([
        _runFromFeedback(feedback),
      ]);

  _FakeCodingVerificationFeedbackService.sequence(
    List<ToolResultInfo?> feedbacks,
  ) : runs = Queue<CodingVerificationFeedbackRun>.from(
        feedbacks.map(_runFromFeedback),
      );

  _FakeCodingVerificationFeedbackService.runs(
    List<CodingVerificationFeedbackRun> runs,
  ) : runs = Queue<CodingVerificationFeedbackRun>.from(runs);

  final Queue<CodingVerificationFeedbackRun> runs;
  final List<String> requestedProjectRoots = [];
  final List<List<String>> requestedChangedPaths = [];
  final List<CodingVerificationTrigger> requestedTriggers = [];

  @override
  Future<CodingVerificationFeedbackRun> buildFeedbackRun({
    required String projectRoot,
    required Iterable<String> changedPaths,
    required CodingVerificationTrigger trigger,
    DateTime? now,
  }) async {
    requestedProjectRoots.add(projectRoot);
    requestedChangedPaths.add(List<String>.from(changedPaths));
    requestedTriggers.add(trigger);
    if (runs.isEmpty) {
      return const CodingVerificationFeedbackRun(
        snapshot: null,
        toolResult: null,
      );
    }
    return runs.removeFirst();
  }

  @override
  Future<ToolResultInfo?> buildFeedbackToolResult({
    required String projectRoot,
    required Iterable<String> changedPaths,
    required CodingVerificationTrigger trigger,
    DateTime? now,
  }) async {
    final run = await buildFeedbackRun(
      projectRoot: projectRoot,
      changedPaths: changedPaths,
      trigger: trigger,
      now: now,
    );
    return run.toolResult;
  }

  static CodingVerificationFeedbackRun _runFromFeedback(
    ToolResultInfo? feedback,
  ) {
    return CodingVerificationFeedbackRun(snapshot: null, toolResult: feedback);
  }
}

CodingVerificationSnapshot _codingVerificationSnapshot({
  required String projectRoot,
  required String changedPath,
  required ConversationExecutionValidationStatus validationStatus,
  required int passedCount,
  required int failedCount,
  required int exitCode,
  List<CodingVerificationFailure> failures = const [],
}) {
  final command = CodingVerificationCommand(
    executable: 'flutter',
    arguments: const ['test', '--machine', 'test/main_test.dart'],
    workingDirectory: projectRoot,
  );
  final attempt = CodingVerificationCommandAttempt(
    command: command,
    exitCode: exitCode,
    durationMs: 25,
    timedOut: false,
    validationStatus: validationStatus,
    passedCount: passedCount,
    failedCount: failedCount,
    skippedCount: 0,
  );
  return CodingVerificationSnapshot(
    providerName: CodingVerificationFeedbackService.providerName,
    projectRoot: projectRoot,
    changedPaths: [changedPath],
    trigger: CodingVerificationTrigger.completionClaim,
    validationStatus: validationStatus,
    targetBatches: [
      CodingVerificationTargetBatch(
        packageRoot: projectRoot,
        targets: const ['test/main_test.dart'],
      ),
    ],
    failures: failures,
    telemetry: CodingVerificationTelemetry(durationMs: 25, attempts: [attempt]),
    passedCount: passedCount,
    failedCount: failedCount,
    skippedCount: 0,
    selectedAttempt: attempt,
  );
}

class _SavedValidationToolLoopOutcome {
  const _SavedValidationToolLoopOutcome({
    required this.executedToolNames,
    required this.finalAnswerMessages,
    required this.lastMessageContent,
  });

  final List<String> executedToolNames;
  final List<Message> finalAnswerMessages;
  final String lastMessageContent;
}

Set<String> _toolNamesFromDefinitions(List<Map<String, dynamic>> definitions) {
  return ToolDefinitionSearchService.toolNamesFromDefinitions(definitions);
}

class _SavedValidationWrapperCase {
  const _SavedValidationWrapperCase({
    required this.name,
    required this.wrapperCommand,
    required this.commandResult,
  });

  final String name;
  final String wrapperCommand;
  final String commandResult;
}

Future<_SavedValidationToolLoopOutcome>
_runSavedValidationWrapperFollowUpScenario({
  required String wrapperCommand,
  required String commandResult,
  String validationCommand = 'ls README.md',
}) async {
  final conversation = Conversation(
    id: 'conversation-tool-loop-negative-wrapper',
    title: 'Plan thread',
    messages: const <Message>[],
    createdAt: DateTime(2026, 4, 24, 12),
    updatedAt: DateTime(2026, 4, 24, 12, 5),
    workspaceMode: WorkspaceMode.coding,
    projectId: 'project-1',
    workflowStage: ConversationWorkflowStage.implement,
    workflowSpec: ConversationWorkflowSpec(
      tasks: [
        ConversationWorkflowTask(
          id: 'task-readme',
          title: 'Create README.md with project description',
          targetFiles: const ['README.md'],
          validationCommand: validationCommand,
          status: ConversationWorkflowTaskStatus.inProgress,
        ),
      ],
    ),
  );
  final toolDataSource = _QueuedToolLoopChatDataSource(
    initialToolCalls: [
      ToolCallInfo(
        id: 'tool-write',
        name: 'write_file',
        arguments: const {
          'path': 'README.md',
          'content': '# Host Health Checker\n',
        },
      ),
    ],
    toolLoopResponses: [
      ChatCompletionResult(
        content: '',
        toolCalls: [
          ToolCallInfo(
            id: 'tool-validate',
            name: 'local_execute_command',
            arguments: {'command': wrapperCommand, 'working_directory': '/tmp'},
          ),
        ],
        finishReason: 'tool_calls',
      ),
      ChatCompletionResult(
        content:
            'The wrapper result did not prove saved validation success, so the follow-up write is still allowed.',
        toolCalls: [
          ToolCallInfo(
            id: 'tool-rewrite-after-untrusted-validation',
            name: 'write_file',
            arguments: const {
              'path': 'README.md',
              'content': '# Host Health Checker\n\nFollow-up rewrite\n',
            },
          ),
        ],
        finishReason: 'tool_calls',
      ),
      ChatCompletionResult(
        content:
            'The current saved task is complete after the follow-up write.',
        finishReason: 'stop',
      ),
    ],
    finalAnswerChunks: const [
      'Final answer after rejected validation wrapper.',
    ],
  );
  final toolService = _FakeMcpToolService(
    results: {
      'write_file': '{"path":"/tmp/README.md","bytes_written":22}',
      'local_execute_command': commandResult,
    },
  );
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  final toolContainer = ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(
        _ToolEnabledNoConfirmSettingsNotifier.new,
      ),
      conversationsNotifierProvider.overrideWith(
        () => _WorkflowTestConversationsNotifier(conversation),
      ),
      chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
      sessionMemoryServiceProvider.overrideWithValue(
        _TestSessionMemoryService(),
      ),
      codingProjectsNotifierProvider.overrideWith(
        _TestCodingProjectsNotifier.new,
      ),
      mcpToolServiceProvider.overrideWithValue(toolService),
      appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
      backgroundTaskServiceProvider.overrideWithValue(
        _TestBackgroundTaskService(),
      ),
    ],
  );

  try {
    final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

    await toolNotifier.sendMessage('Create the README first');

    return _SavedValidationToolLoopOutcome(
      executedToolNames: List<String>.from(toolService.executedToolNames),
      finalAnswerMessages: List<Message>.from(
        toolDataSource.finalAnswerMessages,
      ),
      lastMessageContent: toolNotifier.state.messages.last.content,
    );
  } finally {
    toolContainer.dispose();
  }
}

class _SelectiveFakeMcpToolService extends McpToolService {
  _SelectiveFakeMcpToolService({required this.results});

  final Map<String, String> results;
  final List<String> executedToolNames = [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return <String>{...results.keys, 'google'}
        .map(
          (toolName) => {
            'type': 'function',
            'function': {
              'name': toolName,
              'description': 'Fake tool $toolName',
              'parameters': const <String, dynamic>{'type': 'object'},
            },
          },
        )
        .toList(growable: false);
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    final result = results[name];
    if (result == null) {
      return McpToolResult(
        toolName: name,
        result: '',
        isSuccess: false,
        errorMessage: 'No matching tool available: $name',
      );
    }
    return McpToolResult(toolName: name, result: result, isSuccess: true);
  }
}

class _PlanningResearchMcpToolService extends McpToolService {
  final List<String> executedToolNames = [];
  final List<({String name, Map<String, dynamic> arguments})> executedCalls =
      [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    executedCalls.add((
      name: name,
      arguments: Map<String, dynamic>.from(arguments),
    ));

    return switch (name) {
      'list_directory' => McpToolResult(
        toolName: name,
        result:
            '{"path":"/tmp/planning-project","entry_count":2,"entries":["[dir] lib","[file] pubspec.yaml (1 KB)"]}',
        isSuccess: true,
      ),
      'find_files' => _findFilesResult(name, arguments),
      'search_files' => McpToolResult(
        toolName: name,
        result:
            '{"path":"/tmp/planning-project","query":"planning state","matches":["lib/features/chat/presentation/providers/chat_notifier.dart:42: class ChatNotifier extends Notifier<ChatState>"],"match_count":1,"scanned_files":3}',
        isSuccess: true,
      ),
      'read_file' => _readFileResult(name, arguments),
      _ => McpToolResult(toolName: name, result: '{}', isSuccess: true),
    };
  }

  McpToolResult _findFilesResult(String name, Map<String, dynamic> arguments) {
    final pattern = arguments['pattern'] as String? ?? '';
    final matches = switch (pattern) {
      'pubspec.yaml' => ['pubspec.yaml'],
      _ when pattern.contains('planning') => [
        'lib/features/chat/presentation/providers/chat_notifier.dart',
      ],
      _ => const <String>[],
    };
    return McpToolResult(
      toolName: name,
      result:
          '{"path":"/tmp/planning-project","pattern":"$pattern","matches":${_jsonEncodeStringList(matches)},"match_count":${matches.length}}',
      isSuccess: true,
    );
  }

  McpToolResult _readFileResult(String name, Map<String, dynamic> arguments) {
    final path = arguments['path'] as String? ?? '';
    if (path.endsWith('pubspec.yaml')) {
      return McpToolResult(
        toolName: name,
        result:
            '{"path":"$path","content":"name: caverno\\ndescription: Chat client\\ndependencies:\\n  flutter:\\n    sdk: flutter\\n  flutter_riverpod: ^2.0.0\\n","size_bytes":96}',
        isSuccess: true,
      );
    }

    return McpToolResult(
      toolName: name,
      result:
          '{"path":"$path","content":"class ChatNotifier extends Notifier<ChatState> {\\n  Future<void> generatePlanProposal({String languageCode = \\"en\\"}) async {}\\n}\\n","size_bytes":132}',
      isSuccess: true,
    );
  }

  String _jsonEncodeStringList(List<String> values) {
    return '[${values.map((value) => '"$value"').join(',')}]';
  }
}

class _QueuedProposalDataSource implements ChatDataSource {
  _QueuedProposalDataSource(List<ChatCompletionResult> responses)
    : _responses = Queue<ChatCompletionResult>.from(responses);

  final Queue<ChatCompletionResult> _responses;
  final List<List<Message>> requests = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    requests.add(List<Message>.from(messages));
    return _responses.removeFirst();
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<String> streamWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResult({
    required List<Message> messages,
    required String toolCallId,
    required String toolName,
    required String toolArguments,
    required String toolResult,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late ChatNotifier notifier;
  late StreamController<String> controller;

  setUp(() {
    controller = StreamController<String>();
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);

    container = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(
          _StreamingChatDataSource(controller),
        ),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    notifier = container.read(chatNotifierProvider.notifier);
  });

  tearDown(() async {
    container.dispose();
    if (controller.hasListener) {
      await controller.close();
    } else {
      unawaited(controller.close());
    }
  });

  test('sendMessage marks regular streaming requests as loading', () async {
    await notifier.sendMessage('Inspect the workspace');

    expect(notifier.state.isLoading, isTrue);
    expect(notifier.state.messages, hasLength(2));
    expect(notifier.state.messages.first.role, MessageRole.user);
    expect(notifier.state.messages.first.content, 'Inspect the workspace');
    expect(notifier.state.messages.last.role, MessageRole.assistant);
    expect(notifier.state.messages.last.isStreaming, isTrue);
  });

  test(
    'suggestCurrentGoal validates LLM clarification against pending request',
    () async {
      const request =
          '\u6771\u4eac\u306e\u660e\u65e5\u306e\u5929\u6c17\u3092\u8abf\u3079\u3066\u30de\u30fc\u30af\u30c0\u30a6\u30f3\u5f62\u5f0f\u3067\u4fdd\u5b58\u3092';
      const expectedObjective =
          '\u6771\u4eac\u306e\u660e\u65e5\u306e\u5929\u6c17\u3092\u8abf\u3079\u3066\u30de\u30fc\u30af\u30c0\u30a6\u30f3\u5f62\u5f0f\u3067\u4fdd\u5b58\u3059\u308b';
      const scriptClarification =
          '\u5929\u6c17\u60c5\u5831\u3092\u53d6\u5f97\u3057\u3066Markdown\u30d5\u30a1\u30a4\u30eb\u306b\u4fdd\u5b58\u3059\u308b\u30b9\u30af\u30ea\u30d7\u30c8\u3092\u4f5c\u6210\u3059\u308b\u306e\u3067\u3057\u3087\u3046\u304b\uff1f';
      final dataSource = _QueuedProposalDataSource([
        ChatCompletionResult(
          content: jsonEncode({
            'status': 'needs_clarification',
            'objective': '',
            'question': scriptClarification,
          }),
          finishReason: 'stop',
        ),
      ]);
      final now = DateTime(2026, 6, 1, 10);
      final conversation = Conversation(
        id: 'coding-goal-thread',
        title: 'Coding goal',
        messages: const [],
        createdAt: now,
        updatedAt: now,
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final goalContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            () => _WorkflowTestConversationsNotifier(conversation),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final goalNotifier = goalContainer.read(chatNotifierProvider.notifier);

        final suggestion = await goalNotifier.suggestCurrentGoal(
          languageCode: 'ja',
          pendingUserMessage: request,
        );

        expect(suggestion.kind, ConversationGoalSuggestionKind.suggested);
        expect(suggestion.objective, expectedObjective);
        expect(
          suggestion.objective,
          isNot(contains('\u30b9\u30af\u30ea\u30d7\u30c8')),
        );
        expect(dataSource.requests, hasLength(1));
        expect(dataSource.requests.single.last.content, contains(request));
      } finally {
        goalContainer.dispose();
      }
    },
  );

  test(
    'requestAskUserQuestion exposes pending question and resolves answer',
    () async {
      final future = notifier.requestAskUserQuestion(
        question: 'Which path should we take?',
        help: 'Choose the implementation direction.',
        options: const [
          AskUserQuestionOption(
            id: 'small',
            label: 'Small change',
            description: 'Keep the change narrow.',
            preview: 'One file',
          ),
        ],
        allowMultiple: false,
        allowOther: true,
        otherPlaceholder: 'Describe another direction',
      );

      final pending = notifier.state.pendingAskUserQuestion;
      expect(pending, isNotNull);
      expect(pending!.question, 'Which path should we take?');
      expect(pending.options.single.preview, 'One file');

      final answer = AskUserQuestionAnswer(
        question: pending.question,
        selectedOptions: const [
          AskUserQuestionSelection(
            id: 'small',
            label: 'Small change',
            description: 'Keep the change narrow.',
            preview: 'One file',
          ),
        ],
      );
      notifier.resolveAskUserQuestion(id: pending.id, answer: answer);

      expect(await future, answer);
      expect(notifier.state.pendingAskUserQuestion, isNull);
    },
  );

  test('requestAskUserQuestion ignores a second pending question', () async {
    final firstFuture = notifier.requestAskUserQuestion(
      question: 'Which path should we take?',
      help: 'Choose the implementation direction.',
      options: const [
        AskUserQuestionOption(id: 'small', label: 'Small change'),
      ],
      allowMultiple: false,
      allowOther: true,
      otherPlaceholder: 'Describe another direction',
    );
    final firstPending = notifier.state.pendingAskUserQuestion;
    expect(firstPending, isNotNull);

    final secondFuture = notifier.requestAskUserQuestion(
      question: 'Which refactor should we do?',
      help: 'Choose a refactor direction.',
      options: const [
        AskUserQuestionOption(id: 'large', label: 'Large refactor'),
      ],
      allowMultiple: false,
      allowOther: true,
      otherPlaceholder: 'Describe another direction',
    );

    expect(await secondFuture, isNull);
    expect(notifier.state.pendingAskUserQuestion!.id, firstPending!.id);
    expect(
      notifier.state.pendingAskUserQuestion!.question,
      'Which path should we take?',
    );

    final answer = AskUserQuestionAnswer(
      question: firstPending.question,
      selectedOptions: const [
        AskUserQuestionSelection(id: 'small', label: 'Small change'),
      ],
    );
    notifier.resolveAskUserQuestion(id: firstPending.id, answer: answer);

    expect(await firstFuture, answer);
    expect(notifier.state.pendingAskUserQuestion, isNull);
  });

  test(
    'read-only project tools default to current directory when path is omitted',
    () {
      expect(
        notifier.resolveProjectScopedArgumentsForTest('list_directory', {
          'recursive': true,
        }),
        containsPair('path', '.'),
      );
      expect(
        notifier.resolveProjectScopedArgumentsForTest('find_files', {
          'pattern': '*.dart',
        }),
        containsPair('path', '.'),
      );
      expect(
        notifier.resolveProjectScopedArgumentsForTest('search_files', {
          'query': 'SettingsScreen',
        }),
        containsPair('path', '.'),
      );
    },
  );

  test(
    'sendMessage recovers when a named skill is promised but not loaded',
    () async {
      final dataSource = _SkippedSkillLoadChatDataSource(
        initialContent:
            'I will load the Release Check skill before verifying readiness.',
        finalAnswerChunks: const [
          'SKILL_LIVE_OK\n1. Run verification.\n2. Draft release notes.',
        ],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'load_skill': 'Load the full markdown instructions for a skill.',
        },
        results: {
          'load_skill': jsonEncode({
            'id': 'release-check',
            'name': 'Release Check',
            'content':
                'When this skill is loaded, include SKILL_LIVE_OK. List exactly two verification steps.',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          skillsNotifierProvider.overrideWith(_ReleaseCheckSkillsNotifier.new),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage(
        'Use the Release Check skill if relevant. Verify release readiness.',
      );

      expect(toolService.executedToolNames, ['load_skill']);
      expect(toolService.executedToolArguments.single['id'], 'release-check');
      expect(dataSource.toolResultBatches, hasLength(1));
      expect(dataSource.toolResultBatches.single.single.name, 'load_skill');
      expect(dataSource.finalAnswerRequests, hasLength(1));
      expect(
        chatNotifier.state.messages.last.content,
        contains('SKILL_LIVE_OK'),
      );
    },
  );

  test(
    'sendMessage recovers when a Japanese skill load is promised but not loaded',
    () async {
      final dataSource = _SkippedSkillLoadChatDataSource(
        initialContent: 'ユーザーがリリースチェックを依頼したので、Release Checkスキルをロードして手順を確認します。',
        finalAnswerChunks: const [
          'SKILL_LIVE_OK\n1. Run verification.\n2. Draft release notes.',
        ],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'load_skill': 'Load the full markdown instructions for a skill.',
        },
        results: {
          'load_skill': jsonEncode({
            'id': 'release-check',
            'name': 'Release Check',
            'content':
                'When this skill is loaded, include SKILL_LIVE_OK. List exactly two verification steps.',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          skillsNotifierProvider.overrideWith(_ReleaseCheckSkillsNotifier.new),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage(
        'Use the Release Check skill if relevant. Verify release readiness.',
      );

      expect(toolService.executedToolNames, ['load_skill']);
      expect(toolService.executedToolArguments.single['id'], 'release-check');
      expect(dataSource.toolResultBatches, hasLength(1));
      expect(dataSource.toolResultBatches.single.single.name, 'load_skill');
      expect(dataSource.finalAnswerRequests, hasLength(1));
      expect(
        chatNotifier.state.messages.last.content,
        contains('SKILL_LIVE_OK'),
      );
    },
  );

  test(
    'sendMessage recovers when a browser action is promised without a tool',
    () async {
      const skippedBrowserClaim = 'Wikipedia has been opened.';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: const [],
        initialFinishReason: 'stop',
        initialCompletionContent: skippedBrowserClaim,
        initialStreamChunks: const [skippedBrowserClaim],
        followUpToolCalls: [
          ToolCallInfo(
            id: 'tool-click-wikipedia',
            name: 'browser_click',
            arguments: const {
              'ref': 7,
              'reason': 'Open the Wikipedia search result.',
            },
          ),
        ],
        toolRoleResponseContent: '',
        finalAnswerChunks: const [
          'Opened Wikipedia from browser tool results.',
        ],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'browser_snapshot': 'Capture browser elements.',
          'browser_click': 'Click a browser element.',
        },
        results: {
          'browser_snapshot': jsonEncode({
            'ok': true,
            'url': 'https://www.google.com/search?q=hydrangea',
            'elements': [
              {'ref': 7, 'role': 'link', 'label': 'Hydrangea - Wikipedia'},
            ],
          }),
          'browser_click': jsonEncode({
            'ok': true,
            'url': 'https://en.wikipedia.org/wiki/Hydrangea',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      final request =
          'Wikipedia${String.fromCharCodes(const [0x3092, 0x30af, 0x30ea, 0x30c3, 0x30af])}';
      final sendFuture = chatNotifier.sendMessage(request);
      await _waitForCondition(
        () => chatNotifier.state.pendingBrowserAction != null,
      );
      final pendingBrowserAction = chatNotifier.state.pendingBrowserAction!;
      expect(pendingBrowserAction.toolName, 'browser_click');

      chatNotifier.resolveBrowserAction(
        id: pendingBrowserAction.id,
        approved: true,
      );
      await sendFuture;

      expect(toolService.executedToolNames, [
        'browser_snapshot',
        'browser_click',
      ]);
      expect(toolService.executedToolArguments.first, {'max_elements': 80});
      expect(dataSource.toolResultBatches, hasLength(2));
      expect(
        dataSource.toolResultBatches.first.single.name,
        'browser_snapshot',
      );
      expect(dataSource.toolResultBatches.last.single.name, 'browser_click');
      expect(
        dataSource.followUpToolDefinitionBatches.first
            .map((definition) => (definition['function'] as Map)['name'])
            .toList(),
        contains('browser_click'),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains(skippedBrowserClaim)),
      );
      expect(
        chatNotifier.state.messages.last.content,
        contains('Opened Wikipedia from browser tool results.'),
      );
    },
  );

  test(
    'sendMessage reports unexecuted browser action after failed recovery',
    () async {
      const skippedBrowserClaim = 'Wikipedia のリンク（ref 11）をクリックしました。';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: const [],
        initialFinishReason: 'stop',
        initialCompletionContent: skippedBrowserClaim,
        initialStreamChunks: const [skippedBrowserClaim],
        toolRoleResponseContent: skippedBrowserClaim,
        finalAnswerChunks: const [
          'browser_click was not executed after refreshing the page snapshot.',
        ],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'browser_snapshot': 'Capture browser elements.',
          'browser_click': 'Click a browser element.',
        },
        results: {
          'browser_snapshot': jsonEncode({
            'ok': true,
            'url': 'https://www.google.com/search?q=hydrangea',
            'elements': [
              {'ref': 11, 'role': 'link', 'label': 'Hydrangea - Wikipedia'},
            ],
          }),
          'browser_click': jsonEncode({
            'ok': true,
            'url': 'https://en.wikipedia.org/wiki/Hydrangea',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);

      await chatNotifier.sendMessage('Click the Wikipedia result');

      expect(toolService.executedToolNames, ['browser_snapshot']);
      expect(dataSource.toolResultBatches, hasLength(2));
      expect(
        dataSource.toolResultBatches.first.single.name,
        'browser_snapshot',
      );
      expect(dataSource.toolResultBatches.last.single.name, 'browser_snapshot');
      final finalPrompt = dataSource.finalAnswerMessages
          .map((message) => message.content)
          .join('\n');
      expect(finalPrompt, contains('browser_click'));
      expect(finalPrompt, contains('unexecuted_browser_action'));
      expect(
        chatNotifier.state.messages.last.content,
        contains('browser_click was not executed'),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains(skippedBrowserClaim)),
      );
    },
  );

  test(
    'sendMessage shows resolved browser save target before approval',
    () async {
      final saveDirectory = Directory.systemTemp.createTempSync(
        'browser_save_approval_',
      );
      addTearDown(() => saveDirectory.deleteSync(recursive: true));
      final savedPath =
          '${saveDirectory.path}${Platform.pathSeparator}アジサイ_概要.md';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-save-data',
            name: 'browser_save_data',
            arguments: const {
              'filename': 'アジサイ_概要.md',
              'data': '# Hydrangea',
              'format': 'md',
              'reason': 'Save extracted page data.',
            },
          ),
        ],
        toolRoleResponseContent:
            'Saved to $savedPath.\n\nIf you want another format, let me know.',
        finalAnswerChunks: const ['WRONG_FINAL_アジサイ_概要.md'],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'browser_save_data': 'Save browser data to a file.',
        },
        results: {
          'browser_save_data': jsonEncode({
            'ok': true,
            'path': savedPath,
            'directory': saveDirectory.path,
            'filename': 'アジサイ_概要.md',
            'requestedFilename': 'アジサイ_概要.md',
            'filenameChanged': false,
            'bytes': 11,
            'format': 'md',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final browserSessionService = BrowserSessionService(
        saveDirectoryOverride: saveDirectory,
      );
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          browserSessionServiceProvider.overrideWithValue(
            browserSessionService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      final sendFuture = chatNotifier.sendMessage(
        'Save the overview as Markdown.',
      );
      await _waitForCondition(
        () => chatNotifier.state.pendingBrowserAction != null,
      );
      final pendingBrowserAction = chatNotifier.state.pendingBrowserAction!;
      expect(pendingBrowserAction.toolName, 'browser_save_data');
      expect(
        pendingBrowserAction.details,
        contains('Destination: Caverno application storage'),
      );
      expect(pendingBrowserAction.details, contains('Final file: アジサイ_概要.md'));
      expect(
        pendingBrowserAction.details,
        contains('Save location: ${saveDirectory.path}'),
      );
      expect(pendingBrowserAction.details, contains('Full path: $savedPath'));

      chatNotifier.resolveBrowserAction(
        id: pendingBrowserAction.id,
        approved: true,
      );
      await sendFuture;

      expect(dataSource.finalAnswerRequestMessages, isEmpty);
      expect(chatNotifier.state.messages.last.content, contains(savedPath));
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains('WRONG_FINAL_アジサイ_概要.md')),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains('let me know')),
      );
    },
  );

  test(
    'full chat approval access runs sensitive browser actions without prompting',
    () async {
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-click',
            name: 'browser_click',
            arguments: const {
              'ref': 7,
              'reason': 'Open the Wikipedia search result.',
            },
          ),
        ],
        toolRoleResponseContent: 'Clicked the link.',
        finalAnswerChunks: const ['Opened the Wikipedia article.'],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {'browser_click': 'Click a browser element.'},
        results: {
          'browser_click': jsonEncode({
            'ok': true,
            'url': 'https://en.wikipedia.org/wiki/Hydrangea',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledChatFullAccessSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      // No approval is resolved: full access must let the action run on its own.
      await chatNotifier.sendMessage('Open the Wikipedia article');

      expect(chatNotifier.state.pendingBrowserAction, isNull);
      expect(toolService.executedToolNames, ['browser_click']);
      expect(dataSource.autoReviewRequestMessages, isEmpty);
      expect(
        chatNotifier.state.messages.last.content,
        contains('Opened the Wikipedia article.'),
      );
    },
  );

  test(
    'auto-review chat approval consults the reviewer before a browser action',
    () async {
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-click',
            name: 'browser_click',
            arguments: const {
              'ref': 7,
              'reason': 'Open the Wikipedia search result.',
            },
          ),
        ],
        toolRoleResponseContent: 'Clicked the link.',
        finalAnswerChunks: const ['Opened the Wikipedia article.'],
        autoReviewResponses: [
          ChatCompletionResult(
            content:
                '{"outcome":"allow","riskLevel":"low","userAuthorization":"high","rationale":"User asked to open the link."}',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {'browser_click': 'Click a browser element.'},
        results: {
          'browser_click': jsonEncode({'ok': true}),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledChatAutoReviewSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('Open the Wikipedia article');

      // The reviewer is consulted and, on "allow", the action runs without a
      // manual approval prompt.
      expect(chatNotifier.state.pendingBrowserAction, isNull);
      expect(dataSource.autoReviewRequestMessages, hasLength(1));
      expect(
        dataSource.autoReviewRequestMessages.first.first.content,
        contains('built-in browser'),
      );
      expect(toolService.executedToolNames, ['browser_click']);
      expect(
        chatNotifier.state.messages.last.content,
        contains('Opened the Wikipedia article.'),
      );
    },
  );

  test('full chat approval auto-connects SSH when a password is saved', () async {
    final dataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-ssh',
          name: 'ssh_connect',
          arguments: const {'host': 'example.com', 'port': 22, 'username': 'me'},
        ),
      ],
      toolRoleResponseContent: 'Connected.',
      finalAnswerChunks: const ['SSH session is ready.'],
    );
    final toolService = _FakeMcpToolService(
      descriptions: const {'ssh_connect': 'Open an SSH session.'},
      results: const {'ssh_connect': '{"ok":true}'},
    );
    final sshService = _MockSshService();
    when(
      () => sshService.connect(
        host: any(named: 'host'),
        port: any(named: 'port'),
        username: any(named: 'username'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async {});
    final creds = _MockSshCredentialsManager();
    when(
      () => creds.loadPassword(
        host: any(named: 'host'),
        port: any(named: 'port'),
        username: any(named: 'username'),
      ),
    ).thenAnswer((_) async => 'secret');
    when(
      () => creds.savePassword(
        host: any(named: 'host'),
        port: any(named: 'port'),
        username: any(named: 'username'),
        password: any(named: 'password'),
      ),
    ).thenAnswer((_) async {});
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final threadContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledChatFullAccessSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        conversationRepositoryProvider.overrideWithValue(
          _FakeConversationRepository(),
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
        sshServiceProvider.overrideWithValue(sshService),
        sshCredentialsManagerProvider.overrideWithValue(creds),
      ],
    );
    addTearDown(threadContainer.dispose);

    final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
    await chatNotifier.sendMessage('Connect to my server');

    // Full access + a stored credential connects without raising the dialog.
    expect(chatNotifier.state.pendingSshConnect, isNull);
    verify(
      () => sshService.connect(
        host: 'example.com',
        port: 22,
        username: 'me',
        password: 'secret',
      ),
    ).called(1);
    expect(dataSource.autoReviewRequestMessages, isEmpty);
  });

  test(
    'full chat approval falls back to the SSH dialog without a saved password',
    () async {
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-ssh',
            name: 'ssh_connect',
            arguments: const {
              'host': 'example.com',
              'port': 22,
              'username': 'me',
            },
          ),
        ],
        toolRoleResponseContent: 'Cancelled.',
        finalAnswerChunks: const ['No session was opened.'],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {'ssh_connect': 'Open an SSH session.'},
        results: const {'ssh_connect': '{"ok":true}'},
      );
      final sshService = _MockSshService();
      final creds = _MockSshCredentialsManager();
      when(
        () => creds.loadPassword(
          host: any(named: 'host'),
          port: any(named: 'port'),
          username: any(named: 'username'),
        ),
      ).thenAnswer((_) async => null);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledChatFullAccessSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
          sshServiceProvider.overrideWithValue(sshService),
          sshCredentialsManagerProvider.overrideWithValue(creds),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      final sendFuture = chatNotifier.sendMessage('Connect to my server');

      // No stored credential: full access still needs the interactive dialog.
      await _waitForCondition(
        () => chatNotifier.state.pendingSshConnect != null,
      );
      expect(chatNotifier.state.pendingSshConnect!.host, 'example.com');

      // Cancel so sendMessage can finish.
      chatNotifier.resolveSshConnect(
        id: chatNotifier.state.pendingSshConnect!.id,
        approval: null,
      );
      await sendFuture;

      verifyNever(
        () => sshService.connect(
          host: any(named: 'host'),
          port: any(named: 'port'),
          username: any(named: 'username'),
          password: any(named: 'password'),
        ),
      );
    },
  );

  test('auto-review verdicts are written to the approval audit log', () async {
    final auditDir = Directory.systemTemp.createTempSync('chat_audit_');
    addTearDown(() => auditDir.deleteSync(recursive: true));
    final auditLog = ToolApprovalAuditLog(
      rootDirectoryProvider: () async => auditDir,
    );

    final dataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-click',
          name: 'browser_click',
          arguments: const {'ref': 7, 'reason': 'Open the link.'},
        ),
      ],
      toolRoleResponseContent: 'Reviewed.',
      finalAnswerChunks: const ['Stopped before clicking.'],
      autoReviewResponses: [
        ChatCompletionResult(
          content:
              '{"outcome":"deny","riskLevel":"high","userAuthorization":"low","rationale":"Looks like a credential submit."}',
          finishReason: 'stop',
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      descriptions: const {'browser_click': 'Click a browser element.'},
      results: const {'browser_click': '{"ok":true}'},
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final threadContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledChatAutoReviewSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        conversationRepositoryProvider.overrideWithValue(
          _FakeConversationRepository(),
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
        toolApprovalAuditLogProvider.overrideWithValue(auditLog),
      ],
    );
    addTearDown(threadContainer.dispose);

    final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
    await chatNotifier.sendMessage('Open the link');

    final auditFiles = Directory('${auditDir.path}/approval_audit')
        .listSync()
        .whereType<File>()
        .toList();
    expect(auditFiles, isNotEmpty);
    final entries = auditFiles
        .expand((file) => file.readAsLinesSync())
        .where((line) => line.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    final clickEntry = entries.firstWhere((e) => e['tool'] == 'browser_click');
    expect(clickEntry['outcome'], 'denied');
    expect(clickEntry['decisionSource'], 'auto_review');
    expect(clickEntry['mode'], 'autoReview');
    expect(clickEntry['domain'], 'browser');
    expect(clickEntry['rationale'], contains('credential'));
  });

  test(
    'sendMessage marks browser save claims unexecuted without save tool result',
    () async {
      const unsupportedSaveClaim = 'Saved as azusa_overview.md.';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-get-content',
            name: 'browser_get_content',
            arguments: const {'format': 'html', 'max_chars': 50000},
          ),
        ],
        toolRoleResponseContent: unsupportedSaveClaim,
        finalAnswerChunks: const [unsupportedSaveClaim],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'browser_get_content': 'Extract browser page content.',
          'browser_save_data': 'Save browser data to a file.',
        },
        results: {
          'browser_get_content': jsonEncode({
            'ok': true,
            'url': 'https://example.com/article',
            'content': 'Overview content',
          }),
          'browser_save_data': jsonEncode({
            'ok': true,
            'path': '/tmp/azusa_overview.md',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      final saveMarker = String.fromCharCodes(const [0x4fdd, 0x5b58]);
      await chatNotifier.sendMessage(
        'Extract the overview and $saveMarker it as Markdown.',
      );

      expect(toolService.executedToolNames, ['browser_get_content']);
      expect(dataSource.toolResultBatches, hasLength(1));
      expect(dataSource.finalAnswerMessages, isNotEmpty);
      final finalPrompt = dataSource.finalAnswerMessages
          .map((message) => message.content)
          .join('\n');
      expect(finalPrompt, contains('unexecuted_file_save'));
      expect(finalPrompt, contains('browser_save_data'));
      expect(
        chatNotifier.state.messages.last.content,
        contains('The requested file save was not executed'),
      );
    },
  );

  test('sendMessage does not mark loaded skill steps as unexecuted', () async {
    const preamble =
        'I will verify release readiness with the saved skill before answering.\n\n';
    const finalAnswer =
        'SKILL_LIVE_OK\n\n'
        '## リリース readiness チェック - 2つの検証ステップ\n\n'
        '1. **ビルド・テストの健全性確認**\n'
        '2. **リリース設定とバージョンの整合性確認**\n\n'
        '---\n\n'
        '実際にプロジェクトに対してこれらを実行して検証しますか？'
        '（例：`flutter analyze`・テスト実行・バージョン確認を自動で走らせる）';
    final dataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-load-skill',
          name: 'load_skill',
          arguments: const {'id': 'release-check'},
        ),
      ],
      initialCompletionContent: preamble,
      initialStreamChunks: const [preamble],
      toolRoleResponseContent: finalAnswer,
      finalAnswerChunks: const ['FALLBACK_FINAL_SHOULD_NOT_STREAM'],
    );
    final toolService = _FakeMcpToolService(
      descriptions: const {
        'load_skill': 'Load the full markdown instructions for a skill.',
      },
      results: {
        'load_skill': jsonEncode({
          'id': 'release-check',
          'name': 'Release Check',
          'content':
              'When this skill is loaded, include SKILL_LIVE_OK. List exactly two verification steps.',
        }),
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final threadContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        conversationRepositoryProvider.overrideWithValue(
          _FakeConversationRepository(),
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    addTearDown(threadContainer.dispose);

    final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
    await chatNotifier.sendMessage(
      'Use the Release Check skill if relevant. Verify release readiness.',
    );

    expect(toolService.executedToolNames, ['load_skill']);
    expect(dataSource.finalAnswerRequestMessages, isEmpty);
    expect(chatNotifier.state.messages.last.content, contains('SKILL_LIVE_OK'));
    expect(
      chatNotifier.state.messages.last.content,
      isNot(contains('FALLBACK_FINAL_SHOULD_NOT_STREAM')),
    );
    expect(
      chatNotifier.state.messages.last.content,
      isNot(contains('実際にプロジェクトに対してこれらを実行して検証しますか')),
    );
    expect(
      chatNotifier.state.messages.last.content,
      isNot(
        contains(
          'I could not execute the additional tool request above in this final-answer step.',
        ),
      ),
    );
  });

  test(
    'sendMessage ignores follow-up tool calls after constrained skill output',
    () async {
      const preamble =
          'I will verify release readiness with the saved skill before answering.\n\n';
      const constrainedAnswer =
          'SKILL_LIVE_OK\n\n'
          'リリース readiness チェックを開始します。以下の2つの検証ステップを実行します：\n\n'
          '1. **Git ステータス・変更確認** — 未コミットの変更、ステージング状態、ブランチ状況をチェック\n'
          '2. **ビルド・テスト実行** — プロジェクトのビルドとテストスイートを実行し、エラーがないか確認\n\n'
          'では、まずステップ1から進めます。';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-load-skill',
            name: 'load_skill',
            arguments: const {'id': 'release-check'},
          ),
        ],
        initialCompletionContent: preamble,
        initialStreamChunks: const [preamble],
        followUpToolCalls: [
          ToolCallInfo(
            id: 'tool-git-status',
            name: 'git_execute_command',
            arguments: const {'command': 'status'},
          ),
        ],
        intermediateToolRoleResponseContent: constrainedAnswer,
        finalAnswerChunks: const ['FALLBACK_FINAL_SHOULD_NOT_STREAM'],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'load_skill': 'Load the full markdown instructions for a skill.',
          'git_execute_command': 'Execute a git command in a local repository.',
        },
        results: {
          'load_skill': jsonEncode({
            'id': 'release-check',
            'name': 'Release Check',
            'content':
                'When this skill is loaded, include SKILL_LIVE_OK. List exactly two verification steps.',
          }),
          'git_execute_command': 'unexpected git status',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage(
        'Use the Release Check skill if relevant. Verify release readiness.',
      );

      expect(toolService.executedToolNames, ['load_skill']);
      expect(dataSource.toolResultBatches, hasLength(1));
      expect(dataSource.finalAnswerRequestMessages, isEmpty);
      expect(
        chatNotifier.state.messages.last.content,
        contains('SKILL_LIVE_OK'),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains('FALLBACK_FINAL_SHOULD_NOT_STREAM')),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains('では、まずステップ1から進めます')),
      );
    },
  );

  test(
    'sendMessage trims look-around text before ignored skill follow-up tools',
    () async {
      const preamble = 'リリースチェックのスキルをロードして進めます。\n\n';
      const constrainedAnswer =
          'SKILL_LIVE_OK\n\n'
          'リリース準備状況を確認するために、以下の2つの検証ステップを実行します：\n\n'
          '1. **コードベースのリリース関連チェック** – バージョン番号、変更ログ、ビルド設定ファイルが最新かつ整合性を持っているか確認します。\n'
          '2. **テストとビルドの健全性チェック** – テストスイートの結果とビルドが正常に完了しているか確認します。\n\n'
          '現在のプロジェクトの状態を確認するために、まずリポジトリの構造と Git ステータスを見てみましょう。';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-load-skill',
            name: 'load_skill',
            arguments: const {'id': 'release-check'},
          ),
        ],
        initialCompletionContent: preamble,
        initialStreamChunks: const [preamble],
        followUpToolCalls: [
          ToolCallInfo(
            id: 'tool-list-directory',
            name: 'list_directory',
            arguments: const {'recursive': false, 'max_entries': 30},
          ),
          ToolCallInfo(
            id: 'tool-git-status',
            name: 'git_execute_command',
            arguments: const {'command': 'status'},
          ),
        ],
        intermediateToolRoleResponseContent: constrainedAnswer,
        finalAnswerChunks: const ['FALLBACK_FINAL_SHOULD_NOT_STREAM'],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'load_skill': 'Load the full markdown instructions for a skill.',
          'list_directory': 'List files in a directory.',
          'git_execute_command': 'Execute a git command in a local repository.',
        },
        results: {
          'load_skill': jsonEncode({
            'id': 'release-check',
            'name': 'Release Check',
            'content':
                'When this skill is loaded, include SKILL_LIVE_OK. List exactly two verification steps.',
          }),
          'list_directory': 'unexpected directory listing',
          'git_execute_command': 'unexpected git status',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage(
        'Use the Release Check skill if relevant. Verify release readiness.',
      );

      expect(toolService.executedToolNames, ['load_skill']);
      expect(dataSource.toolResultBatches, hasLength(1));
      expect(dataSource.finalAnswerRequestMessages, isEmpty);
      expect(
        chatNotifier.state.messages.last.content,
        contains('SKILL_LIVE_OK'),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains('FALLBACK_FINAL_SHOULD_NOT_STREAM')),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains('リポジトリの構造と Git ステータスを見てみましょう')),
      );
    },
  );

  test(
    'sendMessage trims actual-check text before ignored skill follow-up tools',
    () async {
      const preamble = 'リリースチェックのスキルをロードして、リリース準備状況を確認します。\n\n';
      const constrainedAnswer =
          'SKILL_LIVE_OK\n\n'
          'リリース準備状況の確認として、以下の2つの検証ステップを行います。\n\n'
          '1. **プロジェクト構造と設定ファイルの確認** — `pubspec.yaml`、`build.yaml` などの設定がリリースビルドに適切に設定されているか確認します。\n'
          '2. **Git ステータスの確認** — 未コミットの変更、未プッシュのコミット、ブランチ状態を確認して、リリース対象が正しい状態か検証します。\n\n'
          'では実際に確認を進めます。';
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-load-skill',
            name: 'load_skill',
            arguments: const {'id': 'release-check'},
          ),
        ],
        initialCompletionContent: preamble,
        initialStreamChunks: const [preamble],
        followUpToolCalls: [
          ToolCallInfo(
            id: 'tool-list-directory',
            name: 'list_directory',
            arguments: const {'path': '.'},
          ),
          ToolCallInfo(
            id: 'tool-git-status',
            name: 'git_execute_command',
            arguments: const {'command': 'status'},
          ),
        ],
        intermediateToolRoleResponseContent: constrainedAnswer,
        finalAnswerChunks: const ['FALLBACK_FINAL_SHOULD_NOT_STREAM'],
      );
      final toolService = _FakeMcpToolService(
        descriptions: const {
          'load_skill': 'Load the full markdown instructions for a skill.',
          'list_directory': 'List files in a directory.',
          'git_execute_command': 'Execute a git command in a local repository.',
        },
        results: {
          'load_skill': jsonEncode({
            'id': 'release-check',
            'name': 'Release Check',
            'content':
                'When this skill is loaded, include SKILL_LIVE_OK. List exactly two verification steps.',
          }),
          'list_directory': 'unexpected directory listing',
          'git_execute_command': 'unexpected git status',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage(
        'Use the Release Check skill if relevant. Verify release readiness.',
      );

      expect(toolService.executedToolNames, ['load_skill']);
      expect(dataSource.toolResultBatches, hasLength(1));
      expect(dataSource.finalAnswerRequestMessages, isEmpty);
      expect(
        chatNotifier.state.messages.last.content,
        contains('SKILL_LIVE_OK'),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains('FALLBACK_FINAL_SHOULD_NOT_STREAM')),
      );
      expect(
        chatNotifier.state.messages.last.content,
        isNot(contains('では実際に確認を進めます')),
      );
    },
  );

  test(
    'sendHiddenPrompt preserves the hidden assistant response for follow-up inference',
    () async {
      final sendFuture = notifier.sendHiddenPrompt('Continue the saved task.');
      controller.add('The task is complete. Validation passed.');
      await controller.close();
      await sendFuture;

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.messages, isEmpty);
      expect(
        notifier.takeLatestHiddenAssistantResponse(),
        'The task is complete. Validation passed.',
      );
      expect(notifier.takeLatestHiddenAssistantResponse(), isNull);
    },
  );

  test(
    'syncConversation ignores stale updates for the active conversation while loading',
    () async {
      await notifier.sendMessage('Inspect the workspace');

      final activeConversationId = container
          .read(conversationsNotifierProvider)
          .currentConversationId;

      final messagesBeforeSync = List<Message>.from(notifier.state.messages);
      notifier.syncConversation(
        conversationId: activeConversationId,
        messages: const [],
      );

      expect(notifier.state.isLoading, isTrue);
      expect(notifier.state.messages, messagesBeforeSync);
      expect(notifier.state.messages.last.isStreaming, isTrue);
    },
  );

  test(
    'new thread creation while streaming preserves submitted user messages',
    () async {
      final firstController = StreamController<String>();
      final secondController = StreamController<String>();
      final dataSource = _ControllableQueueChatDataSource(
        Queue<StreamController<String>>.from([
          firstController,
          secondController,
        ]),
      );
      final repository = _FakeConversationRepository();
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationRepositoryProvider.overrideWithValue(repository),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(() async {
        threadContainer.dispose();
        if (!firstController.isClosed) {
          await firstController.close();
        }
        if (!secondController.isClosed) {
          await secondController.close();
        }
      });

      final conversationsNotifier = threadContainer.read(
        conversationsNotifierProvider.notifier,
      );
      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      final firstConversationId = threadContainer
          .read(conversationsNotifierProvider)
          .currentConversationId!;

      await chatNotifier.sendMessage('Repeated request');
      conversationsNotifier.createNewConversation(
        workspaceMode: WorkspaceMode.chat,
      );
      final secondConversationId = threadContainer
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      expect(secondConversationId, isNot(firstConversationId));

      await chatNotifier.sendMessage('Repeated request');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final conversations = threadContainer
          .read(conversationsNotifierProvider)
          .conversations;
      final firstConversation = conversations.firstWhere(
        (conversation) => conversation.id == firstConversationId,
      );
      final secondConversation = conversations.firstWhere(
        (conversation) => conversation.id == secondConversationId,
      );

      expect(firstConversation.messages.map((message) => message.content), [
        'Repeated request',
      ]);
      expect(secondConversation.messages.map((message) => message.content), [
        'Repeated request',
      ]);
      expect(dataSource.requests, hasLength(2));
      expect(chatNotifier.state.messages.map((message) => message.content), [
        'Repeated request',
        '',
      ]);
    },
  );

  test('streaming response survives switching away and back', () async {
    final firstController = StreamController<String>();
    final dataSource = _ControllableQueueChatDataSource(
      Queue<StreamController<String>>.from([firstController]),
    );
    final repository = _FakeConversationRepository();
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final threadContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(repository),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    addTearDown(() async {
      threadContainer.dispose();
      if (!firstController.isClosed) {
        await firstController.close();
      }
    });

    final conversationsNotifier = threadContainer.read(
      conversationsNotifierProvider.notifier,
    );
    final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
    final firstConversationId = threadContainer
        .read(conversationsNotifierProvider)
        .currentConversationId!;

    await chatNotifier.sendMessage('Keep answering after I switch');
    conversationsNotifier.createNewConversation(
      workspaceMode: WorkspaceMode.chat,
    );
    final secondConversationId = threadContainer
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    expect(secondConversationId, isNot(firstConversationId));

    firstController.add('Background ');
    firstController.add('answer');
    await firstController.close();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    conversationsNotifier.selectConversation(firstConversationId);
    await Future<void>.delayed(Duration.zero);

    final firstConversation = threadContainer
        .read(conversationsNotifierProvider)
        .conversations
        .firstWhere((conversation) => conversation.id == firstConversationId);
    expect(firstConversation.messages.map((message) => message.content), [
      'Keep answering after I switch',
      'Background answer',
    ]);
    expect(chatNotifier.state.isLoading, isFalse);
    expect(chatNotifier.state.messages.last.content, 'Background answer');
  });

  test('ask-user-question response survives switching away and back', () async {
    final initialCompletion = Completer<ChatCompletionResult>();
    final dataSource = _DelayedAskQuestionToolChatDataSource(
      initialCompletion: initialCompletion,
    );
    final repository = _FakeConversationRepository();
    final toolService = _FakeMcpToolService(
      results: const {'ask_user_question': ''},
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final threadContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(repository),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    addTearDown(threadContainer.dispose);

    final conversationsNotifier = threadContainer.read(
      conversationsNotifierProvider.notifier,
    );
    final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
    final firstConversationId = threadContainer
        .read(conversationsNotifierProvider)
        .currentConversationId!;

    final sendFuture = chatNotifier.sendMessage('Help choose a direction');
    await Future<void>.delayed(Duration.zero);
    conversationsNotifier.createNewConversation(
      workspaceMode: WorkspaceMode.chat,
    );
    final secondConversationId = threadContainer
        .read(conversationsNotifierProvider)
        .currentConversationId!;
    expect(secondConversationId, isNot(firstConversationId));
    expect(chatNotifier.state.pendingAskUserQuestion, isNull);

    initialCompletion.complete(
      ChatCompletionResult(
        content: '',
        finishReason: 'tool_calls',
        toolCalls: [
          ToolCallInfo(
            id: 'tool-ask',
            name: 'ask_user_question',
            arguments: const {
              'question': 'Which direction should we use?',
              'help': 'Pick the implementation direction.',
              'options': [
                {'label': 'Small patch'},
                {'label': 'Refactor with tests'},
              ],
            },
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    conversationsNotifier.selectConversation(firstConversationId);
    await Future<void>.delayed(Duration.zero);

    final pending = chatNotifier.state.pendingAskUserQuestion;
    expect(pending, isNotNull);
    expect(pending!.question, 'Which direction should we use?');
    expect(chatNotifier.state.isLoading, isTrue);
    expect(chatNotifier.state.messages.map((message) => message.role), [
      MessageRole.user,
      MessageRole.assistant,
    ]);

    chatNotifier.resolveAskUserQuestion(
      id: pending.id,
      answer: AskUserQuestionAnswer(
        question: pending.question,
        selectedOptions: const [
          AskUserQuestionSelection(id: 'Small patch', label: 'Small patch'),
        ],
      ),
    );
    await sendFuture;

    final firstConversation = threadContainer
        .read(conversationsNotifierProvider)
        .conversations
        .firstWhere((conversation) => conversation.id == firstConversationId);
    expect(
      firstConversation.messages.map((message) => message.content).toList(),
      anyElement(contains('Proceeding with the selected option.')),
    );
    expect(chatNotifier.state.isLoading, isFalse);
    expect(
      chatNotifier.state.messages.last.content,
      contains('Proceeding with the selected option.'),
    );
    expect(
      dataSource.toolResultBatches.single.single.name,
      'ask_user_question',
    );
  });

  test(
    'ask-user-question reuses the first answer when the model asks again',
    () async {
      final dataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-ask-first',
            name: 'ask_user_question',
            arguments: const {
              'question': 'Which direction should we use first?',
              'options': [
                {'label': 'Minimal patch'},
                {'label': 'Refactor with tests'},
              ],
            },
          ),
        ],
        followUpToolCalls: [
          ToolCallInfo(
            id: 'tool-ask-repeat',
            name: 'ask_user_question',
            arguments: const {
              'question': 'Which direction should we use now?',
              'options': [
                {'label': 'UI first'},
                {'label': 'Refactor with tests'},
              ],
            },
          ),
        ],
        finalAnswerChunks: const ['Continuing with the selected direction.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {'ask_user_question': ''},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      final sendFuture = chatNotifier.sendMessage('Choose once');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final pending = chatNotifier.state.pendingAskUserQuestion;
      expect(pending, isNotNull);
      expect(pending!.question, 'Which direction should we use first?');
      chatNotifier.resolveAskUserQuestion(
        id: pending.id,
        answer: AskUserQuestionAnswer(
          question: pending.question,
          selectedOptions: const [
            AskUserQuestionSelection(
              id: 'minimal-patch',
              label: 'Minimal patch',
            ),
          ],
        ),
      );

      await sendFuture;

      expect(chatNotifier.state.pendingAskUserQuestion, isNull);
      expect(dataSource.toolResultBatches, hasLength(2));
      final repeatedAskResult =
          jsonDecode(dataSource.toolResultBatches.last.single.result)
              as Map<String, dynamic>;
      expect(repeatedAskResult['reused'], isTrue);
      expect(repeatedAskResult['answer'], 'Minimal patch');
      expect(
        repeatedAskResult['note'],
        contains('Continue using the existing answer'),
      );
      expect(
        chatNotifier.state.messages.last.content,
        contains('Continuing with the selected direction.'),
      );
    },
  );

  test(
    'parallel ask-user-question responses survive same prompt in a new thread',
    () async {
      final firstInitialCompletion = Completer<ChatCompletionResult>();
      final secondInitialCompletion = Completer<ChatCompletionResult>();
      final dataSource = _QueuedAskQuestionToolChatDataSource(
        initialCompletions: [firstInitialCompletion, secondInitialCompletion],
        finalAnswers: const [
          'Thread two final answer.',
          'Thread one final answer.',
        ],
      );
      final repository = _FakeConversationRepository();
      final toolService = _FakeMcpToolService(
        results: const {'ask_user_question': ''},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(repository),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final conversationsNotifier = threadContainer.read(
        conversationsNotifierProvider.notifier,
      );
      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      final firstConversationId = threadContainer
          .read(conversationsNotifierProvider)
          .currentConversationId!;

      final firstSendFuture = chatNotifier.sendMessage('Repeat this prompt');
      await Future<void>.delayed(Duration.zero);
      conversationsNotifier.createNewConversation(
        workspaceMode: WorkspaceMode.chat,
      );
      final secondConversationId = threadContainer
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      expect(secondConversationId, isNot(firstConversationId));

      final secondSendFuture = chatNotifier.sendMessage('Repeat this prompt');
      await Future<void>.delayed(Duration.zero);
      expect(dataSource.initialRequests, hasLength(2));
      expect(dataSource.initialRequestContextConversationIds, [
        firstConversationId,
        secondConversationId,
      ]);

      firstInitialCompletion.complete(
        ChatCompletionResult(
          content: '',
          finishReason: 'tool_calls',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-ask-first',
              name: 'ask_user_question',
              arguments: const {
                'question': 'Which direction for thread one?',
                'options': [
                  {'label': 'Thread one option'},
                ],
              },
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(chatNotifier.state.pendingAskUserQuestion, isNull);

      secondInitialCompletion.complete(
        ChatCompletionResult(
          content: '',
          finishReason: 'tool_calls',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-ask-second',
              name: 'ask_user_question',
              arguments: const {
                'question': 'Which direction for thread two?',
                'options': [
                  {'label': 'Thread two option'},
                ],
              },
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final secondPending = chatNotifier.state.pendingAskUserQuestion;
      expect(secondPending, isNotNull);
      expect(secondPending!.question, 'Which direction for thread two?');
      chatNotifier.resolveAskUserQuestion(
        id: secondPending.id,
        answer: AskUserQuestionAnswer(
          question: secondPending.question,
          selectedOptions: const [
            AskUserQuestionSelection(
              id: 'thread-two-option',
              label: 'Thread two option',
            ),
          ],
        ),
      );
      await secondSendFuture;

      conversationsNotifier.selectConversation(firstConversationId);
      await Future<void>.delayed(Duration.zero);

      final firstPending = chatNotifier.state.pendingAskUserQuestion;
      expect(firstPending, isNotNull);
      expect(firstPending!.question, 'Which direction for thread one?');
      expect(chatNotifier.state.isLoading, isTrue);
      chatNotifier.resolveAskUserQuestion(
        id: firstPending.id,
        answer: AskUserQuestionAnswer(
          question: firstPending.question,
          selectedOptions: const [
            AskUserQuestionSelection(
              id: 'thread-one-option',
              label: 'Thread one option',
            ),
          ],
        ),
      );
      await firstSendFuture;

      final conversations = threadContainer
          .read(conversationsNotifierProvider)
          .conversations;
      final firstConversation = conversations.firstWhere(
        (conversation) => conversation.id == firstConversationId,
      );
      final secondConversation = conversations.firstWhere(
        (conversation) => conversation.id == secondConversationId,
      );
      expect(firstConversation.messages, hasLength(2));
      expect(secondConversation.messages, hasLength(2));
      expect(firstConversation.messages.first.content, 'Repeat this prompt');
      expect(secondConversation.messages.first.content, 'Repeat this prompt');
      expect(
        firstConversation.messages.last.content,
        contains('Thread one final answer.'),
      );
      expect(
        secondConversation.messages.last.content,
        contains('Thread two final answer.'),
      );
      expect(chatNotifier.state.isLoading, isFalse);
      expect(
        chatNotifier.state.messages.last.content,
        contains('Thread one final answer.'),
      );
      expect(dataSource.toolResultBatches, hasLength(2));
      expect(dataSource.toolResultContextConversationIds, [
        secondConversationId,
        firstConversationId,
      ]);
      expect(dataSource.finalAnswerContextConversationIds, [
        secondConversationId,
        firstConversationId,
      ]);
      expect(
        dataSource.toolResultBatches
            .expand((batch) => batch)
            .map((result) => result.name),
        everyElement('ask_user_question'),
      );
    },
  );

  test(
    'coding ask-user-question response survives switching away and back',
    () async {
      final project = CodingProject(
        id: 'project-question-switch',
        name: 'Question switch project',
        rootPath: '/tmp/question-switch-project',
        createdAt: DateTime(2026, 5, 29, 12),
        updatedAt: DateTime(2026, 5, 29, 12),
      );
      final initialCompletion = Completer<ChatCompletionResult>();
      final dataSource = _DelayedAskQuestionToolChatDataSource(
        initialCompletion: initialCompletion,
      );
      final repository = _FakeConversationRepository();
      final toolService = _FakeMcpToolService(
        results: const {'ask_user_question': ''},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(repository),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(threadContainer.dispose);

      final conversationsNotifier = threadContainer.read(
        conversationsNotifierProvider.notifier,
      );
      conversationsNotifier.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
        createIfMissing: true,
      );
      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      final firstConversationId = threadContainer
          .read(conversationsNotifierProvider)
          .currentConversationId!;

      final sendFuture = chatNotifier.sendMessage('Choose the coding path');
      await Future<void>.delayed(Duration.zero);
      conversationsNotifier.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
      );
      final secondConversationId = threadContainer
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      expect(secondConversationId, isNot(firstConversationId));
      expect(chatNotifier.state.pendingAskUserQuestion, isNull);

      initialCompletion.complete(
        ChatCompletionResult(
          content: '',
          finishReason: 'tool_calls',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-ask-coding',
              name: 'ask_user_question',
              arguments: const {
                'question': 'Which coding direction should we use?',
                'help': 'Pick the implementation direction.',
                'options': [
                  {'label': 'Small patch'},
                  {'label': 'Refactor with tests'},
                ],
              },
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      conversationsNotifier.selectConversation(firstConversationId);
      await Future<void>.delayed(Duration.zero);

      final pending = chatNotifier.state.pendingAskUserQuestion;
      expect(pending, isNotNull);
      expect(pending!.question, 'Which coding direction should we use?');
      expect(chatNotifier.state.isLoading, isTrue);
      expect(chatNotifier.state.messages.map((message) => message.role), [
        MessageRole.user,
        MessageRole.assistant,
      ]);

      chatNotifier.resolveAskUserQuestion(
        id: pending.id,
        answer: AskUserQuestionAnswer(
          question: pending.question,
          selectedOptions: const [
            AskUserQuestionSelection(id: 'Small patch', label: 'Small patch'),
          ],
        ),
      );
      await sendFuture;

      final firstConversation = threadContainer
          .read(conversationsNotifierProvider)
          .conversations
          .firstWhere((conversation) => conversation.id == firstConversationId);
      expect(firstConversation.workspaceMode, WorkspaceMode.coding);
      expect(firstConversation.normalizedProjectId, project.id);
      expect(
        firstConversation.messages.map((message) => message.content).toList(),
        anyElement(contains('Proceeding with the selected option.')),
      );
      expect(chatNotifier.state.isLoading, isFalse);
      expect(
        chatNotifier.state.messages.last.content,
        contains('Proceeding with the selected option.'),
      );
      expect(
        dataSource.toolResultBatches.single.single.name,
        'ask_user_question',
      );
    },
  );

  test(
    'coding thread creation while streaming preserves submitted user messages',
    () async {
      final project = CodingProject(
        id: 'project-thread-switch',
        name: 'Thread switch project',
        rootPath: '/tmp/thread-switch-project',
        createdAt: DateTime(2026, 5, 29, 11),
        updatedAt: DateTime(2026, 5, 29, 11),
      );
      final firstController = StreamController<String>();
      final secondController = StreamController<String>();
      final dataSource = _ControllableQueueChatDataSource(
        Queue<StreamController<String>>.from([
          firstController,
          secondController,
        ]),
      );
      final repository = _FakeConversationRepository();
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final threadContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationRepositoryProvider.overrideWithValue(repository),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(() async {
        threadContainer.dispose();
        if (!firstController.isClosed) {
          await firstController.close();
        }
        if (!secondController.isClosed) {
          await secondController.close();
        }
      });

      final conversationsNotifier = threadContainer.read(
        conversationsNotifierProvider.notifier,
      );
      conversationsNotifier.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
        createIfMissing: true,
      );
      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      final firstConversationId = threadContainer
          .read(conversationsNotifierProvider)
          .currentConversationId!;

      await chatNotifier.sendMessage('Implement the same slice');
      conversationsNotifier.createNewConversation(
        workspaceMode: WorkspaceMode.coding,
        projectId: project.id,
      );
      final secondConversationId = threadContainer
          .read(conversationsNotifierProvider)
          .currentConversationId!;
      expect(secondConversationId, isNot(firstConversationId));

      await chatNotifier.sendMessage('Implement the same slice');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final conversations = threadContainer
          .read(conversationsNotifierProvider)
          .conversations;
      final firstConversation = conversations.firstWhere(
        (conversation) => conversation.id == firstConversationId,
      );
      final secondConversation = conversations.firstWhere(
        (conversation) => conversation.id == secondConversationId,
      );

      expect(firstConversation.workspaceMode, WorkspaceMode.coding);
      expect(firstConversation.normalizedProjectId, project.id);
      expect(secondConversation.workspaceMode, WorkspaceMode.coding);
      expect(secondConversation.normalizedProjectId, project.id);
      expect(firstConversation.messages.map((message) => message.content), [
        'Implement the same slice',
      ]);
      expect(secondConversation.messages.map((message) => message.content), [
        'Implement the same slice',
      ]);
      expect(dataSource.requests, hasLength(2));
      expect(chatNotifier.state.messages.map((message) => message.content), [
        'Implement the same slice',
        '',
      ]);
    },
  );

  test(
    'sendMessage queues new user input while a reply is in flight',
    () async {
      final firstController = StreamController<String>();
      final secondController = StreamController<String>();
      final dataSource = _ControllableQueueChatDataSource(
        Queue<StreamController<String>>.from([
          firstController,
          secondController,
        ]),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final queueContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(() async {
        queueContainer.dispose();
        if (!firstController.isClosed) {
          await firstController.close();
        }
        if (!secondController.isClosed) {
          await secondController.close();
        }
      });
      final queueNotifier = queueContainer.read(chatNotifierProvider.notifier);

      await queueNotifier.sendMessage('First request');
      await queueNotifier.sendMessage('Second request');

      var userMessages = queueNotifier.state.messages
          .where((message) => message.role == MessageRole.user)
          .map((message) => message.content)
          .toList();

      expect(queueNotifier.state.isLoading, isTrue);
      expect(userMessages, ['First request']);
      expect(queueNotifier.state.messages, hasLength(2));
      expect(queueNotifier.state.queuedMessages, hasLength(1));
      expect(
        queueNotifier.state.queuedMessages.single.content,
        'Second request',
      );
      expect(dataSource.requests, hasLength(1));

      firstController.add('First response');
      await firstController.close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      userMessages = queueNotifier.state.messages
          .where((message) => message.role == MessageRole.user)
          .map((message) => message.content)
          .toList();

      expect(dataSource.requests, hasLength(2));
      expect(queueNotifier.state.isLoading, isTrue);
      expect(queueNotifier.state.queuedMessages, isEmpty);
      expect(userMessages, ['First request', 'Second request']);
      expect(queueNotifier.state.messages.map((message) => message.role), [
        MessageRole.user,
        MessageRole.assistant,
        MessageRole.user,
        MessageRole.assistant,
      ]);
      expect(queueNotifier.state.messages.last.isStreaming, isTrue);
      expect(
        dataSource.requests.last
            .where((message) => message.role != MessageRole.system)
            .map((message) => message.content)
            .toList(),
        ['First request', 'First response', 'Second request'],
      );

      secondController.add('Second response');
      await secondController.close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(queueNotifier.state.isLoading, isFalse);
      expect(queueNotifier.state.messages.map((message) => message.content), [
        'First request',
        'First response',
        'Second request',
        'Second response',
      ]);
    },
  );

  test(
    'queued user input survives same-conversation save synchronization',
    () async {
      final firstController = StreamController<String>();
      final secondController = StreamController<String>();
      final dataSource = _ControllableQueueChatDataSource(
        Queue<StreamController<String>>.from([
          firstController,
          secondController,
        ]),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final queueContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            _DivergingSaveConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(() async {
        queueContainer.dispose();
        if (!firstController.isClosed) {
          await firstController.close();
        }
        if (!secondController.isClosed) {
          await secondController.close();
        }
      });
      final queueNotifier = queueContainer.read(chatNotifierProvider.notifier);

      await queueNotifier.sendMessage('First request');
      await queueNotifier.sendMessage('Second request');

      expect(queueNotifier.state.queuedMessages, hasLength(1));

      firstController.add('First response');
      await firstController.close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(dataSource.requests, hasLength(2));
      expect(queueNotifier.state.queuedMessages, isEmpty);
      expect(queueNotifier.state.isLoading, isTrue);
      expect(
        dataSource.requests.last
            .where((message) => message.role != MessageRole.system)
            .map((message) => message.content)
            .toList(),
        ['First request', 'First response persisted', 'Second request'],
      );

      secondController.add('Second response');
      await secondController.close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(queueNotifier.state.isLoading, isFalse);
      expect(queueNotifier.state.messages.map((message) => message.content), [
        'First request',
        'First response persisted',
        'Second request',
        'Second response persisted',
      ]);
    },
  );

  test(
    'removeQueuedMessage drops a pending user input before it is sent',
    () async {
      final firstController = StreamController<String>();
      final dataSource = _ControllableQueueChatDataSource(
        Queue<StreamController<String>>.from([firstController]),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final queueContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      addTearDown(() async {
        queueContainer.dispose();
        if (!firstController.isClosed) {
          await firstController.close();
        }
      });
      final queueNotifier = queueContainer.read(chatNotifierProvider.notifier);

      await queueNotifier.sendMessage('First request');
      await queueNotifier.sendMessage('Second request');

      final queuedId = queueNotifier.state.queuedMessages.single.id;
      queueNotifier.removeQueuedMessage(queuedId);

      expect(queueNotifier.state.queuedMessages, isEmpty);

      firstController.add('First response');
      await firstController.close();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(dataSource.requests, hasLength(1));
      expect(queueNotifier.state.isLoading, isFalse);
      expect(queueNotifier.state.messages.map((message) => message.content), [
        'First request',
        'First response',
      ]);
    },
  );

  test(
    'parseWorkflowProposalForTest recovers malformed JSON-like proposal content',
    () {
      const rawContent = '''
{
  "kind": "decision",
  "workflowStage": "plan",
  "goal": "設定ファイルによるホスト管理機能の実装",
  "constraints": [
    "既存のpingロジックとの統合",
    "依存ライブラリの最小化"
  ],
  "acceptanceCriteria": [
    "設定ファイルからホスト一覧が読み込める",
    "CLI から利用できる"
  ],
  "openQuestions": [
    "設定ファイル形式は YAML でよいか"
  ],
''';

      final proposal = notifier.parseWorkflowProposalForTest(rawContent);

      expect(proposal, isNotNull);
      expect(proposal!.workflowStage, ConversationWorkflowStage.plan);
      expect(proposal.workflowSpec.goal, '設定ファイルによるホスト管理機能の実装');
      expect(
        proposal.workflowSpec.constraints,
        containsAll(<String>['既存のpingロジックとの統合', '依存ライブラリの最小化']),
      );
      expect(
        proposal.workflowSpec.acceptanceCriteria,
        containsAll(<String>['設定ファイルからホスト一覧が読み込める', 'CLI から利用できる']),
      );
      expect(
        proposal.workflowSpec.openQuestions,
        contains('設定ファイル形式は YAML でよいか'),
      );
    },
  );

  test(
    'parseTaskProposalForTest drops research notes and normalizes action titles',
    () {
      const rawContent = '''
{
  "tasks": [
    {
      "title": "The project root seems empty (based on research context).",
      "targetFiles": []
    },
    {
      "title": "I need to scaffold the project.",
      "targetFiles": ["pyproject.toml", "README.md"],
      "validationCommand": "",
      "notes": "Create the initial files."
    },
    {
      "title": "I need to implement the core logic (pinging).",
      "targetFiles": ["ping_cli.py"],
      "validationCommand": "python3 ping_cli.py google.com",
      "notes": "Keep the first version simple."
    }
  ]
}
''';

      final proposal = notifier.parseTaskProposalForTest(rawContent);

      expect(proposal, isNotNull);
      expect(proposal!.tasks, hasLength(2));
      expect(proposal.tasks.first.title, 'Scaffold the project');
      expect(proposal.tasks.last.title, 'Implement the core logic (pinging)');
      expect(
        proposal.tasks.last.validationCommand,
        'python3 ping_cli.py google.com -c 1',
      );
    },
  );

  test(
    'finalizeTaskProposalForTest moves scaffolding ahead in an empty workspace',
    () {
      final proposal = WorkflowTaskProposalDraft(
        tasks: const [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Argparse` for CLI',
            targetFiles: ['main.py'],
          ),
          ConversationWorkflowTask(
            id: 'task-2',
            title: 'Initialize project structure',
            targetFiles: ['pyproject.toml', 'README.md'],
          ),
        ],
      );

      final finalized = notifier.finalizeTaskProposalForTest(
        proposal,
        projectLooksEmpty: true,
      );

      expect(finalized.tasks.first.title, 'Initialize project structure');
      expect(finalized.tasks.last.title, 'Argparse for CLI');
    },
  );

  test(
    'taskProposalNeedsRetryForWorkflowForTest allows explicit single-file task',
    () {
      const workflowSpec = ConversationWorkflowSpec(
        goal: 'Create a single-file Python CLI ping tool',
        constraints: [
          'Only create ping_cli.py',
          'No other files',
          'Validate with python3 ping_cli.py --help',
        ],
        acceptanceCriteria: [
          'The approved implementation must contain exactly one implementation task',
        ],
      );
      const proposal = WorkflowTaskProposalDraft(
        tasks: [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Create ping_cli.py with argparse and subprocess ping',
            targetFiles: ['ping_cli.py'],
            validationCommand: 'python3 ping_cli.py --help',
            notes: 'Implement the requested single-file CLI directly.',
          ),
        ],
      );

      final needsRetry = notifier.taskProposalNeedsRetryForWorkflowForTest(
        proposal,
        proposal,
        true,
        workflowSpec,
      );

      expect(needsRetry, isFalse);
    },
  );

  test(
    'taskProposalNeedsRetryForWorkflowForTest rejects split scaffold files',
    () {
      const workflowSpec = ConversationWorkflowSpec(
        goal: 'Scaffold a Python host health checker',
        constraints: ['CLI-first tool for one host'],
        acceptanceCriteria: [
          'requirements.txt lists the initial dependencies',
          'README.md documents setup and usage',
        ],
      );
      const proposal = WorkflowTaskProposalDraft(
        tasks: [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Create requirements.txt',
            targetFiles: ['requirements.txt'],
            validationCommand: 'test -f requirements.txt',
            notes: 'Create the dependency file first.',
          ),
          ConversationWorkflowTask(
            id: 'task-2',
            title: 'Create README.md',
            targetFiles: ['README.md'],
            validationCommand: 'test -f README.md',
            notes: 'Document setup and usage separately.',
          ),
        ],
      );

      final needsRetry = notifier.taskProposalNeedsRetryForWorkflowForTest(
        proposal,
        proposal,
        true,
        workflowSpec,
      );

      expect(needsRetry, isTrue);
    },
  );

  test(
    'taskProposalNeedsRetryForWorkflowForTest accepts bundled scaffold files',
    () {
      const workflowSpec = ConversationWorkflowSpec(
        goal: 'Scaffold a Python host health checker',
        constraints: ['CLI-first tool for one host'],
        acceptanceCriteria: [
          'requirements.txt lists the initial dependencies',
          'README.md documents setup and usage',
        ],
      );
      const proposal = WorkflowTaskProposalDraft(
        tasks: [
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Create requirements.txt and README.md',
            targetFiles: ['requirements.txt', 'README.md'],
            validationCommand: 'test -f requirements.txt && test -f README.md',
            notes: 'Create the initial scaffold files together.',
          ),
          ConversationWorkflowTask(
            id: 'task-2',
            title: 'Implement ping CLI',
            targetFiles: ['main.py'],
            validationCommand: 'python3 main.py --help',
            notes: 'Add the runnable CLI entry point.',
          ),
        ],
      );

      final needsRetry = notifier.taskProposalNeedsRetryForWorkflowForTest(
        proposal,
        proposal,
        true,
        workflowSpec,
      );

      expect(needsRetry, isFalse);
    },
  );

  test(
    'buildTaskProposalRetryContextForTest preserves explicit single-task scope',
    () {
      const workflowSpec = ConversationWorkflowSpec(
        goal: 'Create a single-file Python CLI ping tool',
        constraints: ['Only create ping_cli.py', 'No other files'],
        acceptanceCriteria: [
          'The approved implementation must contain exactly one implementation task',
        ],
      );

      final retryContext = notifier.buildTaskProposalRetryContextForTest(
        null,
        minimalRetry: true,
        projectLooksEmpty: true,
        workflowSpec: workflowSpec,
      );

      expect(
        retryContext,
        contains('Return exactly one concrete implementation task'),
      );
      expect(
        retryContext,
        contains('Do not add a separate verification-only task'),
      );
      expect(
        retryContext,
        isNot(contains('Return two to four concrete tasks')),
      );
    },
  );

  test(
    'buildTaskProposalRetryContextForTest preserves first-slice scaffold scope',
    () {
      const workflowSpec = ConversationWorkflowSpec(
        goal: 'Scaffold a Python host health checker',
        constraints: ['CLI-first tool for one host'],
        acceptanceCriteria: [
          'requirements.txt lists the initial dependencies',
          'README.md documents setup and usage',
        ],
      );

      final retryContext = notifier.buildTaskProposalRetryContextForTest(
        null,
        minimalRetry: true,
        projectLooksEmpty: true,
        workflowSpec: workflowSpec,
      );

      expect(retryContext, contains('The first task targetFiles must include'));
      expect(retryContext, contains('readme.md'));
      expect(retryContext, contains('requirements.txt'));
      expect(
        retryContext,
        contains('Do not split those first-slice scaffold files'),
      );
    },
  );

  test('sendMessage executes every tool call in the same batch', () async {
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'read_alpha',
          arguments: const {'path': 'alpha.txt'},
        ),
        ToolCallInfo(
          id: 'tool-2',
          name: 'read_beta',
          arguments: const {'path': 'beta.txt'},
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {'read_alpha': 'alpha result', 'read_beta': 'beta result'},
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Inspect both files');

      expect(toolService.executedToolNames, ['read_alpha', 'read_beta']);
      expect(toolDataSource.toolResultBatches, hasLength(1));
      expect(
        toolDataSource.toolResultBatches.single
            .map((item) => item.name)
            .toList(),
        ['read_alpha', 'read_beta'],
      );
      expect(
        toolDataSource.finalAnswerMessages.last.content,
        contains('[Tool: read_alpha]'),
      );
      expect(
        toolDataSource.finalAnswerMessages.last.content,
        contains('[Tool: read_beta]'),
      );
      expect(toolNotifier.state.isLoading, isFalse);
      expect(
        toolNotifier.state.messages.last.content,
        contains('Combined tool summary'),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'final tool-result answers do not execute embedded content tool calls',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'read_file',
            arguments: const {'path': 'lib/main.dart'},
          ),
        ],
        finalAnswerChunks: const [
          'Summary before hidden call.\n'
              '<tool_call>{"name":"search_files","arguments":{"query":"widgets"}}</tool_call>\n'
              '<tool_call>read_file',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'read_file': '{"content":"void main() {}"}',
          'search_files': '{"matches":["should-not-run"]}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Inspect the file');

        expect(toolService.executedToolNames, ['read_file']);
        expect(toolDataSource.finalAnswerRequestMessages, hasLength(1));
        expect(
          toolDataSource.finalAnswerMessages.first.content,
          isNot(contains('Available tools:')),
        );
        final answerPrompt = toolDataSource.finalAnswerMessages.singleWhere(
          (message) => message.content.contains('[Tool: read_file]'),
        );
        expect(answerPrompt.content, isNot(contains('<tool_use>')));
        expect(
          answerPrompt.content,
          contains('instead of emitting tool-call tags'),
        );
        expect(toolNotifier.state.isLoading, isFalse);
        expect(
          toolNotifier.state.messages.last.content,
          contains('Summary before hidden call.'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('<tool_call>')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage executes pending read-only inspection at tool loop limit',
    () async {
      final toolLoopResponses = [
        for (var index = 1; index < 12; index += 1)
          ChatCompletionResult(
            content: 'Continue lookup $index',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-command-$index',
                name: 'local_execute_command',
                arguments: {'command': 'probe-$index'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ChatCompletionResult(
          content: 'Found the target log; read it now.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-read-target',
              name: 'read_file',
              arguments: const {'path': '/tmp/session-log.jsonl'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
      ];
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-command-0',
            name: 'local_execute_command',
            arguments: const {'command': 'probe-0'},
          ),
        ],
        toolLoopResponses: toolLoopResponses,
        finalAnswerChunks: const ['Final answer after reading the target log.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command':
              '{"command":"probe","exit_code":0,"stdout":"ok\\n","stderr":""}',
          'read_file':
              '{"path":"/tmp/session-log.jsonl","content":"target log body"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Find and read the interrupted log');

        expect(toolDataSource.toolResultBatches, hasLength(12));
        expect(
          toolDataSource.toolResultBatches
              .expand((batch) => batch)
              .map((result) => result.name),
          everyElement('local_execute_command'),
        );
        expect(toolService.executedToolNames.last, 'read_file');
        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        final finalPrompt = toolDataSource.finalAnswerMessages
            .map((message) => message.content)
            .join('\n');
        expect(finalPrompt, contains('[Tool: read_file]'));
        expect(finalPrompt, contains('target log body'));
        expect(
          toolNotifier.state.messages.last.content,
          contains('Final answer after reading the target log.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage lets run_python_script recover after missing code',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-python-empty',
            name: 'run_python_script',
            arguments: const {},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'Retry with a complete Python script.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-python-retry',
                name: 'run_python_script',
                arguments: const {
                  'code': 'print("metadata ok")',
                  'reason': 'Inspect the attached image metadata',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The Python metadata analysis completed.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'run_python_script': '{"stdout":"metadata ok\\n","stderr":""}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Analyze the attached image metadata');

        expect(toolService.executedToolNames, ['run_python_script']);
        expect(
          toolService.executedToolArguments.single['code'],
          contains('metadata ok'),
        );
        expect(toolDataSource.toolResultBatches, hasLength(2));
        expect(
          toolDataSource.toolResultBatches.first.single.result,
          allOf(contains('code is required'), contains('caverno.inputs[0]')),
        );
        expect(
          toolDataSource.toolResultBatches.last.single.result,
          contains('metadata ok'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage executes pending read-only local command at tool loop limit',
    () async {
      final toolLoopResponses = [
        for (var index = 1; index < 12; index += 1)
          ChatCompletionResult(
            content: 'Continue lookup $index',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-command-$index',
                name: 'local_execute_command',
                arguments: {
                  'command': 'probe-$index',
                  'working_directory': '/tmp/project',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ChatCompletionResult(
          content: 'Found the target log search; run it now.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-find-target',
              name: 'local_execute_command',
              arguments: const {
                'command': 'find /tmp -name session-log.jsonl',
                'working_directory': '/tmp/project',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
      ];
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-command-0',
            name: 'local_execute_command',
            arguments: const {
              'command': 'probe-0',
              'working_directory': '/tmp/project',
            },
          ),
        ],
        toolLoopResponses: toolLoopResponses,
        finalAnswerChunks: const [
          'Final answer after running the pending local search.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'local_execute_command': ''},
        queuedResults: {
          'local_execute_command': [
            for (var index = 0; index < 12; index += 1)
              '{"command":"probe-$index","exit_code":0,"stdout":"ok $index\\n","stderr":""}',
            '{"command":"find /tmp -name session-log.jsonl","exit_code":0,"stdout":"/tmp/session-log.jsonl\\n","stderr":""}',
          ],
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Find the interrupted log path');

        expect(
          toolService.executedToolNames,
          List.filled(13, 'local_execute_command'),
        );
        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        final finalPrompt = toolDataSource.finalAnswerMessages
            .map((message) => message.content)
            .join('\n');
        expect(finalPrompt, contains('/tmp/session-log.jsonl'));
        expect(finalPrompt, isNot(contains('tool_call_not_executed')));
        expect(
          toolNotifier.state.messages.last.content,
          contains('Final answer after running the pending local search.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage reports unsafe pending local command as unexecuted at tool loop limit',
    () async {
      final pendingCommand = 'find /tmp -type f -name "*.jsonl" | head -50';
      final toolLoopResponses = [
        for (var index = 1; index < 12; index += 1)
          ChatCompletionResult(
            content: 'Continue lookup $index',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-command-$index',
                name: 'local_execute_command',
                arguments: {
                  'command': 'probe-$index',
                  'working_directory': '/tmp/project',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ChatCompletionResult(
          content: 'Recover with one more project probe.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-recovery-trigger',
              name: 'local_execute_command',
              arguments: const {
                'command': 'probe-recovery',
                'working_directory': '/tmp/project',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'Recovery asks for one more bounded probe.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-after-recovery-1',
              name: 'local_execute_command',
              arguments: const {
                'command': 'probe-after-recovery-1',
                'working_directory': '/tmp/project',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'One more probe before the final search.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-after-recovery-2',
              name: 'local_execute_command',
              arguments: const {
                'command': 'probe-after-recovery-2',
                'working_directory': '/tmp/project',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'Search for matching logs with a shell pipeline.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-piped-find',
              name: 'local_execute_command',
              arguments: {
                'command': pendingCommand,
                'working_directory': '/tmp/project',
              },
            ),
          ],
          finishReason: 'tool_calls',
        ),
      ];
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-command-0',
            name: 'local_execute_command',
            arguments: const {
              'command': 'probe-0',
              'working_directory': '/tmp/project',
            },
          ),
        ],
        toolLoopResponses: toolLoopResponses,
        finalAnswerChunks: const [
          'Final answer acknowledges the unexecuted local command.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command':
              '{"command":"probe","exit_code":0,"stdout":"ok\\n","stderr":""}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Find the interrupted log path');

        expect(
          toolService.executedToolNames,
          List.filled(14, 'local_execute_command'),
        );
        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        final finalPrompt = toolDataSource.finalAnswerMessages
            .map((message) => message.content)
            .join('\n');
        expect(finalPrompt, contains('[Tool: local_execute_command]'));
        expect(finalPrompt, contains('*.jsonl'));
        expect(finalPrompt, contains('head -50'));
        expect(finalPrompt, contains('tool_call_not_executed'));
        expect(finalPrompt, contains('bounded_tool_loop_exhausted'));
        expect(
          toolNotifier.state.messages.last.content,
          contains('Final answer acknowledges the unexecuted local command.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('sendMessage preserves terminal blocker tool-role answers', () async {
    final cjkSourceCode = String.fromCharCodes([
      0x30bd,
      0x30fc,
      0x30b9,
      0x30b3,
      0x30fc,
      0x30c9,
    ]);
    final cjkRequired = String.fromCharCodes([0x5fc5, 0x8981, 0x3067, 0x3059]);
    final cjkRepository = String.fromCharCodes([
      0x30ea,
      0x30dd,
      0x30b8,
      0x30c8,
      0x30ea,
    ]);
    final cjkPath = String.fromCharCodes([0x30d1, 0x30b9]);
    final cjkTeachMe = String.fromCharCodes([
      0x6559,
      0x3048,
      0x3066,
      0x304f,
      0x3060,
      0x3055,
      0x3044,
    ]);
    final blockerResponse =
        'universal_ble $cjkSourceCode$cjkRequired. '
        '$cjkRepository$cjkPath$cjkTeachMe.';
    final toolDataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-read-dependency',
          name: 'read_file',
          arguments: const {
            'path': '/tmp/project/packages/pes1_ble/pubspec.yaml',
          },
        ),
      ],
      toolLoopResponses: [
        ChatCompletionResult(content: blockerResponse, finishReason: 'stop'),
      ],
      finalAnswerChunks: const ['This final answer should never be requested.'],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'read_file':
            '{"path":"/tmp/project/packages/pes1_ble/pubspec.yaml","content":"universal_ble:\\n  git:\\n    url: git@example.com:org/universal_ble.git\\n    ref: v1.2.0"}',
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Investigate Android BLE corruption');

      expect(toolService.executedToolNames, ['read_file']);
      expect(toolDataSource.finalAnswerMessages, isEmpty);
      expect(
        toolNotifier.state.messages.last.content,
        contains('universal_ble'),
      );
      expect(
        toolNotifier.state.messages.last.content,
        isNot(contains('This final answer should never be requested.')),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'sendMessage marks command JSON in final tool answers as unexecuted',
    () async {
      final toolLoopResponses = [
        for (var index = 1; index < 12; index += 1)
          ChatCompletionResult(
            content: 'Continue lookup $index',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-command-$index',
                name: 'local_execute_command',
                arguments: {'command': 'probe-$index'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ChatCompletionResult(
          content: 'Found the target file; read it now.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-read-target',
              name: 'read_file',
              arguments: const {'path': '/tmp/session-log.jsonl'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
      ];
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-command-0',
            name: 'local_execute_command',
            arguments: const {'command': 'probe-0'},
          ),
        ],
        toolLoopResponses: toolLoopResponses,
        finalAnswerChunks: const [
          'The investigation needs the Android implementation next.\n\n'
              '```json\n'
              '[\n'
              '  {"command": "find . -type d -name universal_ble", "description": "Locate the package"},\n'
              '  {"command": "cat packages/pes1_ble/pubspec.yaml", "description": "Read dependencies"}\n'
              ']\n'
              '```',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command':
              '{"command":"probe","exit_code":0,"stdout":"ok\\n","stderr":""}',
          'read_file':
              '{"path":"/tmp/session-log.jsonl","content":"target log body"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Find and read the interrupted log');

        expect(toolService.executedToolNames.last, 'read_file');
        final finalPrompt = toolDataSource.finalAnswerMessages
            .map((message) => message.content)
            .join('\n');
        expect(
          finalPrompt,
          contains('This final answer request cannot call tools'),
        );
        expect(finalPrompt, contains('Do not output JSON command arrays'));
        expect(
          toolNotifier.state.messages.last.content,
          contains(
            'I could not execute the additional tool request above in this final-answer step.',
          ),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage marks bracketed tool requests in final answers as unexecuted',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-read',
            name: 'read_file',
            arguments: const {'path': '/tmp/session-log.jsonl'},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The tool result is not enough; retry with Python.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const [
          'I need to retry the analysis.\n\n'
              '[Tool: run_python_script]\n'
              'Arguments: {"code":"print(1)"}',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'read_file':
              '{"path":"/tmp/session-log.jsonl","content":"target log body"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Find and read the interrupted log');

        expect(toolService.executedToolNames, ['read_file']);
        expect(
          toolNotifier.state.messages.last.content,
          contains(
            'I could not execute the additional tool request above in this final-answer step.',
          ),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('sendMessage marks plan-only final tool answers as unexecuted', () async {
    final toolLoopResponses = [
      for (var index = 1; index < 12; index += 1)
        ChatCompletionResult(
          content: 'Continue lookup $index',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-command-$index',
              name: 'local_execute_command',
              arguments: {'command': 'probe-$index'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
      ChatCompletionResult(
        content: 'Found the target file; read it now.',
        toolCalls: [
          ToolCallInfo(
            id: 'tool-read-target',
            name: 'read_file',
            arguments: const {'path': '/tmp/session-log.jsonl'},
          ),
        ],
        finishReason: 'tool_calls',
      ),
    ];
    final toolDataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-command-0',
          name: 'local_execute_command',
          arguments: const {'command': 'probe-0'},
        ),
      ],
      toolLoopResponses: toolLoopResponses,
      finalAnswerChunks: const [
        'Investigation plan\n\n'
            '1. Inspect the universal_ble Android implementation.\n'
            '2. Trace the notification byte flow.\n'
            '3. Check parser conversion boundaries.\n\n'
            'First, I will inspect the universal_ble Android implementation.',
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'local_execute_command':
            '{"command":"probe","exit_code":0,"stdout":"ok\\n","stderr":""}',
        'read_file':
            '{"path":"/tmp/session-log.jsonl","content":"target log body"}',
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );
    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Find and read the interrupted log');

      final finalPrompt = toolDataSource.finalAnswerMessages
          .map((message) => message.content)
          .join('\n');
      expect(finalPrompt, contains('Do not restate an investigation plan'));
      expect(
        toolNotifier.state.messages.last.content,
        contains(
          'I could not execute the additional tool request above in this final-answer step.',
        ),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'sendMessage discovers a deferred tool with tool_search before execution',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-search-1',
            name: ToolDefinitionSearchService.toolName,
            arguments: const {'query': 'special diagnostics', 'max_results': 3},
          ),
        ],
        followUpToolCalls: [
          ToolCallInfo(
            id: 'special-tool-1',
            name: 'special_remote_diagnostics',
            arguments: const {'target': 'router-1'},
          ),
        ],
        finalAnswerChunks: const ['Special diagnostics summary'],
      );
      final toolService = _FakeMcpToolService(
        results: {
          for (var i = 0; i < 30; i++) 'remote_filler_tool_$i': 'filler $i',
          'special_remote_diagnostics': 'special diagnostics result',
        },
        descriptions: const {
          'special_remote_diagnostics':
              'Run special diagnostics against a remote network target.',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Run the special diagnostics tool');

        expect(toolService.executedToolNames, [
          ToolDefinitionSearchService.toolName,
          'special_remote_diagnostics',
        ]);
        final initialNames = _toolNamesFromDefinitions(
          toolDataSource.initialToolDefinitionBatches.single,
        );
        expect(initialNames, contains(ToolDefinitionSearchService.toolName));
        expect(initialNames, isNot(contains('special_remote_diagnostics')));
        final initialSystemPrompt =
            toolDataSource.initialRequestMessages.single.first.content;
        expect(initialSystemPrompt, contains('tool_search'));
        expect(
          initialSystemPrompt,
          contains('If the task needs a tool or capability that is not listed'),
        );
        expect(
          initialSystemPrompt,
          isNot(contains('special_remote_diagnostics')),
        );

        final firstFollowUpNames = _toolNamesFromDefinitions(
          toolDataSource.followUpToolDefinitionBatches.first,
        );
        expect(
          firstFollowUpNames,
          contains(ToolDefinitionSearchService.toolName),
        );
        expect(firstFollowUpNames, contains('special_remote_diagnostics'));
        expect(
          toolDataSource.toolResultBatches.first.single.name,
          ToolDefinitionSearchService.toolName,
        );
        expect(
          toolDataSource.toolResultBatches.last.single.name,
          'special_remote_diagnostics',
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Special diagnostics summary'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage repairs skipped run_python_script after tool search',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-search-python',
            name: ToolDefinitionSearchService.toolName,
            arguments: const {'query': 'run_python_script'},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content:
                '`run_python_script` is available. I will analyze the attached file metadata.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Retrying with the required Python call.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-python-metadata',
                name: 'run_python_script',
                arguments: const {
                  'code': '''
import json
print(json.dumps({"input_count": len(caverno.inputs)}))
''',
                  'reason': 'Inspect attached image metadata',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The attached image metadata analysis completed.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'run_python_script': '{"stdout":"{\\"input_count\\":1}\\n"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage(
          'Use run_python_script to analyze the metadata',
          imageBase64: base64Encode([1, 2, 3, 4]),
          imageMimeType: 'image/png',
        );

        expect(toolService.executedToolNames, [
          ToolDefinitionSearchService.toolName,
          'run_python_script',
        ]);
        expect(
          toolService.executedToolArguments.last['code'],
          contains('caverno.inputs'),
        );
        expect(toolDataSource.toolResultBatches, hasLength(3));
        expect(
          toolDataSource.toolResultBatches.last.single.result,
          contains('input_count'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage repairs run_python_script file path failures for attachments',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-python-guessed-path',
            name: 'run_python_script',
            arguments: const {
              'code': '''
with open("test.jpg", "rb") as file:
    print(len(file.read()))
''',
              'reason': 'Inspect attached image metadata',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content:
                'The file test.jpg was not found. Please attach the image or provide a path.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'Retrying with the staged attachment path.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-python-staged-path',
                name: 'run_python_script',
                arguments: const {
                  'code': '''
path = caverno.inputs[0].path
with open(path, "rb") as file:
    print(len(file.read()))
''',
                  'reason': 'Inspect attached image metadata',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The attached image metadata analysis completed.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'run_python_script': '{"stdout":"4\\n"}'},
        queuedResults: const {
          'run_python_script': [
            '{"error":"FileNotFoundError: [Errno 2] No such file or directory: \'test.jpg\'"}',
            '{"stdout":"4\\n"}',
          ],
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage(
          'Use run_python_script to analyze the metadata',
          imageBase64: base64Encode([1, 2, 3, 4]),
          imageMimeType: 'image/jpeg',
        );

        expect(toolService.executedToolNames, [
          'run_python_script',
          'run_python_script',
        ]);
        expect(
          toolService.executedToolArguments.first['code'],
          contains('test.jpg'),
        );
        expect(
          toolService.executedToolArguments.last['code'],
          contains('caverno.inputs[0].path'),
        );
        expect(toolDataSource.toolResultBatches, hasLength(3));
        expect(
          toolDataSource.toolResultBatches.last.single.result,
          contains('"stdout":"4'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage retries tool-result follow-up with forced prompt compaction',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-read',
            name: 'read_file',
            arguments: const {'path': 'README.md'},
          ),
        ],
        failFirstToolResultCompletionWithContextLength: true,
      );
      final toolService = _FakeMcpToolService(
        results: const {'read_file': 'README contents'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);
        final previousMessages = List<Message>.generate(10, (index) {
          return Message(
            id: 'history-$index',
            content:
                'Previous conversation turn $index with enough detail to summarize.',
            role: index.isEven ? MessageRole.user : MessageRole.assistant,
            timestamp: DateTime(2026, 1, 1).add(Duration(minutes: index)),
          );
        });
        toolNotifier.syncConversation(
          conversationId: null,
          messages: previousMessages,
        );

        await toolNotifier.sendMessage('Inspect the README');

        expect(toolService.executedToolNames, ['read_file']);
        expect(toolDataSource.toolResultBatches, hasLength(2));
        expect(toolDataSource.toolResultRequestMessages, hasLength(2));
        expect(
          toolDataSource.toolResultRequestMessages.first.any(
            (message) => message.id == 'system_compaction',
          ),
          isFalse,
        );
        expect(
          toolDataSource.toolResultRequestMessages.last.any(
            (message) => message.id == 'system_compaction',
          ),
          isTrue,
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Combined tool summary'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage retries final tool-result answer with forced prompt compaction',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-read',
            name: 'read_file',
            arguments: const {'path': 'README.md'},
          ),
        ],
        failFirstFinalAnswerStreamWithContextLength: true,
      );
      final toolService = _FakeMcpToolService(
        results: const {'read_file': 'README contents'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);
        final previousMessages = List<Message>.generate(10, (index) {
          return Message(
            id: 'history-$index',
            content:
                'Previous conversation turn $index with enough detail to summarize.',
            role: index.isEven ? MessageRole.user : MessageRole.assistant,
            timestamp: DateTime(2026, 1, 1).add(Duration(minutes: index)),
          );
        });
        toolNotifier.syncConversation(
          conversationId: null,
          messages: previousMessages,
        );

        await toolNotifier.sendMessage('Inspect the README');

        expect(toolService.executedToolNames, ['read_file']);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        expect(toolDataSource.finalAnswerRequestMessages, hasLength(2));
        expect(
          toolDataSource.finalAnswerRequestMessages.first.any(
            (message) => message.id == 'system_compaction',
          ),
          isFalse,
        );
        expect(
          toolDataSource.finalAnswerRequestMessages.last.any(
            (message) => message.id == 'system_compaction',
          ),
          isTrue,
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Combined tool summary'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('<think>')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage retries tool-result follow-up with compact tool results only',
    () async {
      final largeContent = '${'A' * 24000}\nneedle\n${'B' * 24000}';
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-read',
            name: 'read_file',
            arguments: const {'path': 'large.log'},
          ),
        ],
        failFirstToolResultCompletionWithContextLength: true,
      );
      final toolService = _FakeMcpToolService(
        results: {
          'read_file': jsonEncode({
            'path': '/workspace/large.log',
            'content': largeContent,
            'size_bytes': largeContent.length,
            'start_line': 1,
            'line_count': 2000,
            'total_lines': 4000,
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Inspect the large log');

        expect(toolService.executedToolNames, ['read_file']);
        expect(toolDataSource.toolResultBatches, hasLength(2));
        expect(
          toolDataSource.toolResultBatches.first.single.result.length,
          greaterThan(
            toolDataSource.toolResultBatches.last.single.result.length,
          ),
        );
        expect(
          toolDataSource.toolResultBatches.last.single.result,
          contains('content_reduced_for_prompt_budget'),
        );
        expect(
          toolDataSource.toolResultRequestMessages.last.any(
            (message) => message.id == 'system_compaction',
          ),
          isFalse,
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Combined tool summary'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('approved input actions record post-action observations', () async {
    for (final caseData in const [
      (
        toolName: 'computer_drag',
        arguments: {'from_x': 10, 'from_y': 20, 'to_x': 30, 'to_y': 40},
        result: '{"selectedIpcTransport":"xpc_service","code":"ok"}',
      ),
      (
        toolName: 'computer_scroll',
        arguments: {'x': 20, 'y': 30, 'delta_y': -5},
        result: '{"selectedIpcTransport":"xpc_service","code":"ok"}',
      ),
      (
        toolName: 'computer_type_text',
        arguments: {'text': 'secret typed body'},
        result:
            '{"selectedIpcTransport":"xpc_service","code":"ok","characters":17,"text":"secret typed body"}',
      ),
      (
        toolName: 'computer_press_key',
        arguments: {'key': 'escape'},
        result: '{"selectedIpcTransport":"xpc_service","code":"ok"}',
      ),
      (
        toolName: 'computer_switch_space',
        arguments: {'direction': 'next'},
        result:
            '{"selectedIpcTransport":"xpc_service","code":"ok","schemaName":"macos_computer_use_space_switch","direction":"next"}',
      ),
    ]) {
      MacosComputerUseAuditLog.instance.clear();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-${caseData.toolName}',
            name: caseData.toolName,
            arguments: Map<String, dynamic>.from(caseData.arguments),
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          caseData.toolName: caseData.result,
          'computer_vision_observe':
              '{"ok":true,"schemaName":"macos_computer_use_vision_observation","selectedIpcTransport":"xpc_service","code":"ok","target":{"resolved":"front_window"},"coordinateSpace":"window_pixels","imageBase64":"secret","imageMimeType":"image/png"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);
        final sendFuture = toolNotifier.sendMessage('Use ${caseData.toolName}');

        PendingComputerUseAction? pending;
        for (var attempt = 0; attempt < 10 && pending == null; attempt += 1) {
          await Future<void>.delayed(Duration.zero);
          pending = toolNotifier.state.pendingComputerUseAction;
        }
        expect(pending, isNotNull, reason: caseData.toolName);
        expect(pending!.requiresSmokeArming, isTrue);
        toolNotifier.resolveComputerUseAction(
          id: pending.id,
          approved: true,
          armed: true,
        );

        await sendFuture;

        expect(toolService.executedToolNames, [
          caseData.toolName,
          'computer_vision_observe',
        ]);
        final entry = MacosComputerUseAuditLog.instance.redactedEntries.single;
        expect(entry['toolName'], caseData.toolName);
        expect(entry['postActionObservationRequired'], isTrue);
        expect(
          entry['postActionObservationToolName'],
          'computer_vision_observe',
        );
        expect(entry['postActionObservationSuccess'], isTrue);
        expect(entry['postActionObservationTransport'], 'xpc_service');
        expect(
          entry['postActionObservationSchemaName'],
          'macos_computer_use_vision_observation',
        );
        expect(entry['postActionObservationCoordinateSpace'], 'window_pixels');
        expect(entry['postActionObservationImageAttached'], isTrue);
        expect(entry.containsKey('text'), isFalse);
        expect(entry.containsKey('imageBase64'), isFalse);
      } finally {
        toolContainer.dispose();
        MacosComputerUseAuditLog.instance.clear();
      }
    }
  });

  test('computer-use actions return a post-action vision observation', () async {
    MacosComputerUseAuditLog.instance.clear();
    final initialObservation =
        '{"ok":true,"schemaName":"macos_computer_use_vision_observation","observationId":"vision-1","target":{"resolved":"window","windowId":123},"coordinateSpace":"window_pixels","coordinateGuidance":{"sourceWidth":640,"sourceHeight":480,"windowId":123},"allowedNextTools":["computer_move_mouse"],"approvalRequiredTools":["computer_move_mouse"],"imageBase64":"initial-image","imageMimeType":"image/png"}';
    final postActionObservation =
        '{"ok":true,"schemaName":"macos_computer_use_vision_observation","observationId":"vision-2","target":{"resolved":"window","windowId":123},"coordinateSpace":"window_pixels","coordinateGuidance":{"sourceWidth":640,"sourceHeight":480,"windowId":123},"imageBase64":"post-image","imageMimeType":"image/png"}';
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'observe-1',
          name: 'computer_vision_observe',
          arguments: const {'target': 'front_window', 'max_width': 640},
        ),
      ],
      followUpToolCalls: [
        ToolCallInfo(
          id: 'move-1',
          name: 'computer_move_mouse',
          arguments: const {
            'x': 20,
            'y': 30,
            'window_id': 123,
            'source_width': 640,
            'source_height': 480,
            'coordinate_space': 'window_pixels',
            'vision_observation_id': 'vision-1',
            'reason': 'Move to the highlighted control.',
          },
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: {
        'computer_move_mouse':
            '{"ok":true,"selectedIpcTransport":"xpc_service","code":"ok"}',
      },
      queuedResults: {
        'computer_vision_observe': [initialObservation, postActionObservation],
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);
      final sendFuture = toolNotifier.sendMessage('Move after observing');

      PendingComputerUseAction? pending;
      for (var attempt = 0; attempt < 20 && pending == null; attempt += 1) {
        await Future<void>.delayed(Duration.zero);
        pending = toolNotifier.state.pendingComputerUseAction;
      }
      expect(pending, isNotNull);
      expect(
        pending!.visionObservationSummary,
        contains('latest vision observation'),
      );
      expect(
        pending.visionObservationDetails,
        contains('Observation ID: vision-1'),
      );
      expect(
        pending.visionObservationDetails,
        contains('Coordinate space: window_pixels'),
      );
      expect(
        pending.visionObservationDetails,
        contains('Source screenshot: 640 x 480 px'),
      );
      toolNotifier.resolveComputerUseAction(
        id: pending.id,
        approved: true,
        armed: true,
      );

      await sendFuture;

      expect(toolService.executedToolNames, [
        'computer_vision_observe',
        'computer_move_mouse',
        'computer_vision_observe',
      ]);
      final actionBatch = toolDataSource.toolResultBatches.last;
      final actionResult = jsonDecode(actionBatch.single.result) as Map;
      expect(actionResult['schemaName'], 'macos_computer_use_action_result');
      expect(actionResult['imageBase64'], 'post-image');
      expect(actionResult['nextAction'], contains('post-action observation'));
      final postObservation =
          actionResult['postActionObservation'] as Map<String, dynamic>;
      expect(postObservation['toolName'], 'computer_vision_observe');
      expect(postObservation['imageAttached'], isTrue);
      final entry = MacosComputerUseAuditLog.instance.redactedEntries.last;
      expect(entry['toolName'], 'computer_move_mouse');
      expect(entry['postActionObservationToolName'], 'computer_vision_observe');
      expect(entry['postActionObservationImageAttached'], isTrue);
    } finally {
      toolContainer.dispose();
      MacosComputerUseAuditLog.instance.clear();
    }
  });

  test('Space switch actions return a post-action vision observation', () async {
    MacosComputerUseAuditLog.instance.clear();
    final postActionObservation =
        '{"ok":true,"schemaName":"macos_computer_use_vision_observation","observationId":"vision-space-2","target":{"resolved":"front_window"},"coordinateSpace":"display_pixels","imageBase64":"space-image","imageMimeType":"image/png"}';
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'space-1',
          name: 'computer_switch_space',
          arguments: const {
            'direction': 'next',
            'reason': 'Find the target window on the next Space.',
          },
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: {
        'computer_switch_space':
            '{"ok":true,"schemaName":"macos_computer_use_space_switch","direction":"next","key":"right","modifiers":["control"],"selectedIpcTransport":"xpc_service","requiresPostActionObservation":true}',
        'computer_vision_observe': postActionObservation,
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);
      final sendFuture = toolNotifier.sendMessage('Switch Spaces');

      PendingComputerUseAction? pending;
      for (var attempt = 0; attempt < 20 && pending == null; attempt += 1) {
        await Future<void>.delayed(Duration.zero);
        pending = toolNotifier.state.pendingComputerUseAction;
      }
      expect(pending, isNotNull);
      expect(pending!.summary, contains('next macOS Space'));
      expect(pending.details, contains('Direction: next'));
      expect(pending.details, contains('Shortcut: control+right'));
      expect(pending.warningMessage, contains('observe again'));
      toolNotifier.resolveComputerUseAction(
        id: pending.id,
        approved: true,
        armed: true,
      );

      await sendFuture;

      expect(toolService.executedToolNames, [
        'computer_switch_space',
        'computer_vision_observe',
      ]);
      expect(toolDataSource.toolResultBatches, hasLength(1));
      final actionResult =
          jsonDecode(toolDataSource.toolResultBatches.single.single.result)
              as Map<String, dynamic>;
      expect(actionResult['schemaName'], 'macos_computer_use_action_result');
      expect(actionResult['toolName'], 'computer_switch_space');
      expect(actionResult['postActionObservationRequired'], isTrue);
      expect(actionResult['imageBase64'], 'space-image');
      expect(actionResult['nextAction'], contains('post-action observation'));
      final postObservation =
          actionResult['postActionObservation'] as Map<String, dynamic>;
      expect(postObservation['toolName'], 'computer_vision_observe');
      expect(postObservation['success'], isTrue);
      expect(postObservation['observationId'], 'vision-space-2');
      expect(postObservation['coordinateSpace'], 'display_pixels');
      expect(postObservation['imageAttached'], isTrue);
    } finally {
      toolContainer.dispose();
      MacosComputerUseAuditLog.instance.clear();
    }
  });

  test(
    'computer-use approvals surface target context and exact text',
    () async {
      MacosComputerUseAuditLog.instance.clear();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-type-targeted',
            name: 'computer_type_text',
            arguments: const {
              'text': 'Good morning from Caverno',
              'window_id': 321,
              'element_id': 'ax-0007',
              'vision_observation_id': 'vision-99',
              'coordinate_space': 'window_pixels',
              'source_width': 800,
              'source_height': 600,
              'target': {
                'label': 'Post composer',
                'role': 'AXTextArea',
                'elementId': 'ax-0007',
                'appName': 'Safari',
                'appBundleId': 'com.apple.Safari',
                'windowTitle': 'X / Home',
                'windowId': 321,
                'action': 'type_text',
                'risk': 'input',
              },
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'computer_type_text':
              '{"selectedIpcTransport":"xpc_service","code":"ok"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);
        final sendFuture = toolNotifier.sendMessage('Type into the composer');

        PendingComputerUseAction? pending;
        for (var attempt = 0; attempt < 10 && pending == null; attempt += 1) {
          await Future<void>.delayed(Duration.zero);
          pending = toolNotifier.state.pendingComputerUseAction;
        }

        expect(pending, isNotNull);
        expect(
          pending!.targetSummary,
          'Review the AXTextArea target "Post composer" before approving.',
        );
        expect(pending.targetDetails, contains('App: Safari'));
        expect(pending.targetDetails, contains('Bundle ID: com.apple.Safari'));
        expect(pending.targetDetails, contains('Window: X / Home (id 321)'));
        expect(pending.targetDetails, contains('Element ID: ax-0007'));
        expect(pending.targetDetails, contains('Role: AXTextArea'));
        expect(pending.targetDetails, contains('Label: Post composer'));
        expect(pending.targetDetails, contains('Intended action: type_text'));
        expect(pending.targetDetails, contains('Target risk: input'));
        expect(pending.exactTextPreview, 'Good morning from Caverno');
        expect(pending.exactTextLength, 25);
        expect(
          pending.visionObservationDetails,
          contains('Observation ID: vision-99'),
        );
        expect(
          pending.visionObservationDetails,
          contains('Source screenshot: 800 x 600 px'),
        );

        toolNotifier.resolveComputerUseAction(id: pending.id, approved: false);
        await sendFuture;

        expect(toolService.executedToolNames, isEmpty);
      } finally {
        toolContainer.dispose();
        MacosComputerUseAuditLog.instance.clear();
      }
    },
  );

  test('unsafe computer-use actions require explicit arming', () async {
    MacosComputerUseAuditLog.instance.clear();
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-click',
          name: 'computer_click',
          arguments: const {'x': 10, 'y': 20},
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'computer_click': '{"selectedIpcTransport":"xpc_service","code":"ok"}',
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);
      final sendFuture = toolNotifier.sendMessage('Click without arming');

      PendingComputerUseAction? pending;
      for (var attempt = 0; attempt < 10 && pending == null; attempt += 1) {
        await Future<void>.delayed(Duration.zero);
        pending = toolNotifier.state.pendingComputerUseAction;
      }
      expect(pending, isNotNull);
      expect(pending!.requiresUserApproval, isTrue);
      expect(pending.requiresSmokeArming, isTrue);
      expect(pending.approvalBoundaries, contains('target'));
      expect(pending.approvalBlockerCodes, isEmpty);
      expect(
        pending.actionProposalNextAction,
        contains('approve the exact target'),
      );
      toolNotifier.resolveComputerUseAction(id: pending.id, approved: true);

      await sendFuture;

      expect(toolService.executedToolNames, isEmpty);
      final result = toolDataSource.toolResultBatches.single.single;
      expect(result.name, 'computer_click');
      expect(result.result, contains('"code":"arming_missing"'));

      final entry = MacosComputerUseAuditLog.instance.redactedEntries.single;
      expect(entry['toolName'], 'computer_click');
      expect(entry['approvalResult'], 'arming_missing');
      expect(entry['requiresSmokeArming'], isTrue);
      expect(entry['success'], isFalse);
      expect(entry['responseCode'], 'arming_missing');
    } finally {
      toolContainer.dispose();
      MacosComputerUseAuditLog.instance.clear();
    }
  });

  test('computer-use approvals surface public action boundaries', () async {
    MacosComputerUseAuditLog.instance.clear();
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-post-click',
          name: 'computer_click',
          arguments: const {
            'x': 80,
            'y': 120,
            'target': {
              'label': 'Post',
              'role': 'button',
              'action': 'publish',
              'risk': 'public_action',
            },
          },
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'computer_click': '{"selectedIpcTransport":"xpc_service","code":"ok"}',
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);
      final sendFuture = toolNotifier.sendMessage('Click the post button');

      PendingComputerUseAction? pending;
      for (var attempt = 0; attempt < 10 && pending == null; attempt += 1) {
        await Future<void>.delayed(Duration.zero);
        pending = toolNotifier.state.pendingComputerUseAction;
      }
      expect(pending, isNotNull);
      expect(
        pending!.approvalBoundaries,
        containsAll(['target', 'publicAction']),
      );
      expect(
        pending.approvalBlockerCodes,
        contains('separate_public_action_approval_required'),
      );
      expect(
        pending.actionProposalNextAction,
        contains('separate explicit approval'),
      );
      toolNotifier.resolveComputerUseAction(id: pending.id, approved: false);

      await sendFuture;

      expect(toolService.executedToolNames, isEmpty);
      final result = toolDataSource.toolResultBatches.single.single;
      expect(result.result, contains('"code":"approval_denied"'));
    } finally {
      toolContainer.dispose();
      MacosComputerUseAuditLog.instance.clear();
    }
  });

  test(
    'computer-use approvals block destructive targets after approval',
    () async {
      MacosComputerUseAuditLog.instance.clear();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-delete-click',
            name: 'computer_click',
            arguments: const {
              'x': 80,
              'y': 120,
              'target': {
                'label': 'Delete workspace',
                'role': 'button',
                'action': 'delete',
                'risk': 'destructive',
              },
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'computer_click':
              '{"selectedIpcTransport":"xpc_service","code":"ok"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);
        final sendFuture = toolNotifier.sendMessage('Click the delete button');

        PendingComputerUseAction? pending;
        for (var attempt = 0; attempt < 10 && pending == null; attempt += 1) {
          await Future<void>.delayed(Duration.zero);
          pending = toolNotifier.state.pendingComputerUseAction;
        }
        expect(pending, isNotNull);
        expect(
          pending!.approvalBoundaries,
          containsAll(['target', 'destructive']),
        );
        expect(
          pending.approvalBlockerCodes,
          contains('destructive_target_blocked'),
        );
        expect(pending.actionProposalNextAction, contains('Do not execute'));
        toolNotifier.resolveComputerUseAction(
          id: pending.id,
          approved: true,
          armed: true,
        );

        await sendFuture;

        expect(toolService.executedToolNames, isEmpty);
        final result = toolDataSource.toolResultBatches.single.single;
        expect(result.result, contains('"code":"action_policy_blocked"'));
        expect(result.result, contains('"destructive_target_blocked"'));

        final entry = MacosComputerUseAuditLog.instance.redactedEntries.single;
        expect(entry['toolName'], 'computer_click');
        expect(entry['approvalResult'], 'blocked');
        expect(entry['responseCode'], 'action_policy_blocked');
        expect(entry['success'], isFalse);
      } finally {
        toolContainer.dispose();
        MacosComputerUseAuditLog.instance.clear();
      }
    },
  );

  test(
    'sendMessage carries computer-use screenshots into final vision prompt',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-display',
            name: 'computer_screenshot',
            arguments: const {'max_width': 800},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The display is visible; I need the window list.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-windows',
                name: 'computer_list_windows',
                arguments: const {'include_current_app': true},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'I found the target window and need a focused screenshot.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-window-image',
                name: 'computer_screenshot_window',
                arguments: const {'window_id': 42, 'max_width': 800},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Visual inspection is ready.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['Observed the target window.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'computer_screenshot':
              '{"imageBase64":"display-image-payload","imageMimeType":"image/png","width":800,"height":500}',
          'computer_list_windows':
              '{"windows":[{"windowId":42,"appName":"Caverno","title":"Debug","bounds":{"x":0,"y":0,"width":800,"height":500}}],"count":1}',
          'computer_screenshot_window':
              '{"imageBase64":"window-image-payload","imageMimeType":"image/png","width":640,"height":400,"windowId":42}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Inspect the desktop visually');

        expect(toolService.executedToolNames, [
          'computer_screenshot',
          'computer_list_windows',
          'computer_screenshot_window',
        ]);
        expect(
          toolDataSource.toolResultBatches
              .map((batch) => batch.map((item) => item.name).toList())
              .toList(),
          [
            ['computer_screenshot'],
            ['computer_list_windows'],
            ['computer_screenshot_window'],
          ],
        );

        final answerPrompt = toolDataSource.finalAnswerMessages.singleWhere(
          (message) => message.content.contains('[Tool: computer_screenshot]'),
        );
        expect(answerPrompt.content, isNot(contains('display-image-payload')));
        expect(answerPrompt.content, isNot(contains('window-image-payload')));
        expect(answerPrompt.content, contains('[attached as image content]'));

        final imageMessages = toolDataSource.finalAnswerMessages
            .where((message) => message.imageBase64 != null)
            .toList();
        expect(imageMessages.map((message) => message.imageBase64).toList(), [
          'display-image-payload',
          'window-image-payload',
        ]);
        expect(
          imageMessages.last.content,
          contains('Visual observation from computer_screenshot_window'),
        );
        expect(
          imageMessages.last.content,
          contains('actionProposalPolicy metadata'),
        );
        expect(
          imageMessages.last.content,
          contains('public action boundaries'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Observed the target window.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage allows repeated read_file retries across tool loops',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'read_file',
            arguments: const {'path': 'ping_cli.py'},
          ),
        ],
        followUpToolCalls: [
          ToolCallInfo(
            id: 'tool-2',
            name: 'read_file',
            arguments: const {'path': 'ping_cli.py'},
          ),
        ],
        intermediateToolRoleResponseContent:
            'I need to inspect the exact file contents again before retrying the edit.',
        toolRoleResponseContent: 'Retry finished.',
        finalAnswerChunks: const ['Recovered after repeated read_file.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {'read_file': 'file contents'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Retry the mismatched ping_cli edit');

        expect(toolService.executedToolNames, ['read_file', 'read_file']);
        expect(toolDataSource.toolResultBatches, hasLength(2));
        expect(
          toolDataSource.toolResultBatches
              .expand((batch) => batch.map((item) => item.name))
              .toList(),
          ['read_file', 'read_file'],
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Recovered after repeated read_file.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('sendMessage recovers from duplicate follow-up scaffold writes', () async {
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'create_requirements',
          arguments: const {'path': 'requirements.txt', 'content': '# deps\n'},
        ),
        ToolCallInfo(
          id: 'tool-2',
          name: 'create_readme',
          arguments: const {'path': 'README.md', 'content': '# demo\n'},
        ),
      ],
      followUpToolCalls: [
        ToolCallInfo(
          id: 'tool-3',
          name: 'create_requirements',
          arguments: const {'path': 'requirements.txt', 'content': '# deps\n'},
        ),
      ],
      intermediateToolRoleResponseContent:
          'I created README.md and will continue with the remaining scaffold files.',
      toolRoleResponseContent: 'This follow-up text should never be streamed.',
      finalAnswerChunks: const ['This final answer should never be requested.'],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'create_requirements':
            '{"path":"/tmp/requirements.txt","created":true,"bytes_written":8}',
        'create_readme':
            '{"path":"/tmp/README.md","created":true,"bytes_written":8}',
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Initialize the scaffold files');

      expect(
        toolDataSource.toolResultBatches
            .map((batch) => batch.map((item) => item.name).toList())
            .toList(),
        [
          ['create_requirements', 'create_readme'],
          ['create_requirements', 'create_readme'],
        ],
      );
      expect(toolService.executedToolNames, [
        'create_requirements',
        'create_readme',
      ]);
      expect(toolNotifier.state.isLoading, isFalse);
      expect(
        toolNotifier.takeLatestToolResults().map((item) => item.name).toList(),
        ['create_requirements', 'create_readme'],
      );
      expect(
        toolNotifier.state.messages.last.content,
        contains('This final answer should never be requested.'),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'buildDuplicateFollowUpRecoveryPromptForTest requires a file edit before rerunning validation after reading a failing file',
    () {
      final prompt = notifier.buildDuplicateFollowUpRecoveryPromptForTest(
        [
          ToolCallInfo(
            id: 'tool-validation',
            name: 'local_execute_command',
            arguments: const {'command': 'python3 -m unittest test_ping.py'},
          ),
        ],
        previousToolResults: [
          ToolResultInfo(
            id: 'tool-read',
            name: 'read_file',
            arguments: const {'path': 'test_ping.py'},
            result: 'import unittest\n',
          ),
        ],
      );

      expect(
        prompt,
        contains(
          'your next action must modify that same file before rerunning the saved validation command',
        ),
      );
      expect(
        prompt,
        contains(
          'Do not rerun the same validation command until a saved target file edit changes the current task.',
        ),
      );
    },
  );

  test(
    'buildDuplicateFollowUpRecoveryPromptForTest prevents unverified file completion claims',
    () {
      final prompt = notifier.buildDuplicateFollowUpRecoveryPromptForTest([
        ToolCallInfo(
          id: 'tool-weather',
          name: 'http_get',
          arguments: const {'url': 'https://example.com/weather'},
        ),
      ]);

      expect(
        prompt,
        contains(
          'If the user requested local file creation or modification and no successful file mutation result is already provided',
        ),
      );
      expect(
        prompt,
        contains('your next action must be write_file or edit_file'),
      );
      expect(
        prompt,
        contains(
          'Do not claim that files were created, edited, saved, moved, or deleted',
        ),
      );
    },
  );

  test(
    'buildDuplicateInspectionRecoveryPromptForTest redirects failed exit-code validation to a target edit',
    () {
      final prompt = notifier.buildDuplicateInspectionRecoveryPromptForTest(
        [
          ToolCallInfo(
            id: 'tool-list',
            name: 'list_directory',
            arguments: const {'path': '.'},
          ),
        ],
        previousToolResults: [
          ToolResultInfo(
            id: 'tool-validation',
            name: 'local_execute_command',
            arguments: const {'command': 'python3 test_ping_cli.py'},
            result:
                '{"command":"python3 test_ping_cli.py","exit_code":1,"stdout":"Testing host: invalid.hostname.that.should.fail.test (Expected exit code: 1)\\nFAIL: invalid.hostname.that.should.fail.test returned 68, expected 1","stderr":""}',
          ),
        ],
      );

      expect(
        prompt,
        contains(
          'The latest validation command failed; use that failure output now instead of inspecting the directory again.',
        ),
      );
      expect(
        prompt,
        contains(
          'edit the verification target to accept any non-zero failure code before rerunning validation',
        ),
      );
      expect(
        prompt,
        contains(
          'Do not repeat identical read-only inspection tools again in this turn: list_directory.',
        ),
      );
    },
  );

  test(
    'buildToolLoopRecoveryToolResultsForTest includes latest read context for edit mismatch recovery',
    () {
      final recoveryToolResults = notifier.buildToolLoopRecoveryToolResultsForTest(
        currentToolResults: [
          ToolResultInfo(
            id: 'tool-edit',
            name: 'edit_file',
            arguments: const {'path': 'main.py'},
            result:
                '{"error":"old_text was not found in the target file","path":"/tmp/main.py"}',
          ),
        ],
        executedToolResults: [
          ToolResultInfo(
            id: 'tool-read-other',
            name: 'read_file',
            arguments: const {'path': 'README.md'},
            result: '# Ping CLI\n',
          ),
          ToolResultInfo(
            id: 'tool-read-main',
            name: 'read_file',
            arguments: const {'path': 'main.py'},
            result: 'import argparse\n',
          ),
        ],
        pendingToolCalls: [
          ToolCallInfo(
            id: 'tool-follow-up',
            name: 'read_file',
            arguments: const {'path': 'main.py'},
          ),
        ],
      );

      expect(
        recoveryToolResults.map((toolResult) => toolResult.name).toList(),
        ['read_file', 'edit_file'],
      );
      expect(
        recoveryToolResults.first.arguments,
        containsPair('path', 'main.py'),
      );
      expect(recoveryToolResults.first.result, contains('import argparse'));
    },
  );

  test(
    'buildDuplicateRecoveryToolResultsForTest includes matching previous result before fallback context',
    () {
      final recoveryToolResults = notifier
          .buildDuplicateRecoveryToolResultsForTest(
            currentToolCalls: [
              ToolCallInfo(
                id: 'tool-backend-repeat',
                name: 'list_directory',
                arguments: const {'path': 'packages/pes1_ble/lib/src/backend'},
              ),
            ],
            executedToolResults: [
              ToolResultInfo(
                id: 'tool-src',
                name: 'list_directory',
                arguments: const {'path': 'packages/pes1_ble/lib/src'},
                result: '{"entries":["backend","core","value_state"]}',
              ),
              ToolResultInfo(
                id: 'tool-backend',
                name: 'list_directory',
                arguments: const {'path': 'packages/pes1_ble/lib/src/backend'},
                result: '{"entries":["bt_backend_type.dart"]}',
              ),
            ],
            fallbackToolResults: [
              ToolResultInfo(
                id: 'tool-src',
                name: 'list_directory',
                arguments: const {'path': 'packages/pes1_ble/lib/src'},
                result: '{"entries":["backend","core","value_state"]}',
              ),
            ],
          );

      expect(
        recoveryToolResults.map((toolResult) => toolResult.result).toList(),
        [
          '{"entries":["bt_backend_type.dart"]}',
          '{"entries":["backend","core","value_state"]}',
        ],
      );
    },
  );

  test(
    'buildToolLoopExhaustionRecoveryPromptForTest forbids rereading edit mismatch files when read context exists',
    () {
      final prompt = notifier.buildToolLoopExhaustionRecoveryPromptForTest(
        [
          ToolCallInfo(
            id: 'tool-follow-up',
            name: 'read_file',
            arguments: const {'path': 'main.py'},
          ),
        ],
        previousToolResults: [
          ToolResultInfo(
            id: 'tool-read-main',
            name: 'read_file',
            arguments: const {'path': 'main.py'},
            result: 'import argparse\n',
          ),
          ToolResultInfo(
            id: 'tool-edit',
            name: 'edit_file',
            arguments: const {'path': 'main.py'},
            result:
                '{"error":"old_text was not found in the target file","path":"/tmp/main.py"}',
          ),
        ],
      );

      expect(
        prompt,
        contains(
          'A recent read_file result for the same path is already provided below.',
        ),
      );
      expect(
        prompt,
        contains('Do not call read_file again for the same path in this turn.'),
      );
      expect(
        prompt,
        contains(
          'Use that exact file content and return only one edit_file call for the same file',
        ),
      );
    },
  );

  test('sendMessage recovers from duplicate read-only follow-up loops', () async {
    final toolDataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'list_directory',
          arguments: const {'path': '.'},
        ),
      ],
      toolLoopResponses: [
        ChatCompletionResult(
          content: 'Inspect main.py before writing the unit tests.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-2',
              name: 'read_file',
              arguments: const {'path': 'main.py'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: '',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-3',
              name: 'list_directory',
              arguments: const {'path': '.'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'Write tests/test_ping.py now.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-4',
              name: 'write_test_file',
              arguments: const {'path': 'tests/test_ping.py'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'The unit test task is complete.',
          finishReason: 'stop',
        ),
      ],
      finalAnswerChunks: const ['Recovered after duplicate inspection loop.'],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'list_directory': '{"entries":["main.py"]}',
        'read_file': 'print("ping")',
        'write_test_file':
            '{"path":"/tmp/tests/test_ping.py","created":true,"bytes_written":64}',
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Create unit tests for the ping CLI');

      expect(toolService.executedToolNames, [
        'list_directory',
        'read_file',
        'write_test_file',
      ]);
      expect(
        toolDataSource.toolResultBatches
            .map((batch) => batch.map((item) => item.name).toList())
            .toList(),
        [
          ['list_directory'],
          ['read_file'],
          ['list_directory', 'read_file'],
          ['write_test_file'],
        ],
      );
      expect(
        toolNotifier.state.messages.last.content,
        contains('Recovered after duplicate inspection loop.'),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'sendMessage treats relative and absolute read-only paths as duplicate inspections',
    () async {
      final project = CodingProject(
        id: 'project-path-dedupe',
        name: 'path-dedupe',
        rootPath: '/tmp/caverno-path-dedupe',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'list_directory',
            arguments: const {'path': 'packages/pes1_ble/lib/src/backend'},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-2',
                name: 'list_directory',
                arguments: {
                  'path':
                      '${project.rootPath}/packages/pes1_ble/lib/src/backend',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The duplicate inspection recovery is complete.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'list_directory': '{"entries":["bt_backend_type.dart"]}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            _FakeConversationRepository(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Inspect the BLE backend directory');

        expect(toolService.executedToolNames, ['list_directory']);
        expect(
          toolDataSource.toolResultBatches
              .map((batch) => batch.map((item) => item.name).toList())
              .toList(),
          [
            ['list_directory'],
            ['list_directory'],
          ],
        );
        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('The duplicate inspection recovery is complete.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage accepts terminal duplicate inspection recovery text without streaming a final answer',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'list_directory',
            arguments: const {'path': '.'},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'Inspect src/ping_cli/cli.py before finalizing.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-2',
                name: 'read_file',
                arguments: const {'path': 'src/ping_cli/cli.py'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-3',
                name: 'list_directory',
                arguments: const {'path': '.'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content:
                'The implementation of the ping CLI tool is complete and verified.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'list_directory': '{"entries":["src/ping_cli/cli.py"]}',
          'read_file': 'print("ping")',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Implement the ping CLI tool');

        expect(toolService.executedToolNames, ['list_directory', 'read_file']);
        expect(
          toolDataSource.toolResultBatches
              .map((batch) => batch.map((item) => item.name).toList())
              .toList(),
          [
            ['list_directory'],
            ['read_file'],
            ['list_directory', 'read_file'],
          ],
        );
        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(toolNotifier.state.isLoading, isFalse);
        expect(
          toolNotifier.state.messages.last.content,
          contains(
            'The implementation of the ping CLI tool is complete and verified.',
          ),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage ignores read-only follow-up after terminal saved-task text',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-write',
            name: 'write_cli',
            arguments: const {
              'path': 'ping_cli.py',
              'content': 'print("json output")',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content:
                'The task "Add JSON output support to ping_cli.py" is complete. Validation passed.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-read',
                name: 'read_file',
                arguments: const {'path': 'ping_cli.py'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ],
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_cli': '{"path":"/tmp/ping_cli.py","bytes_written":20}',
          'read_file': 'print("json output")',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Add JSON output support');

        expect(toolService.executedToolNames, ['write_cli']);
        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('Add JSON output support to ping_cli.py'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('This final answer should never be requested.')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage rejects terminal tool-role text with optional follow-up',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-write',
            name: 'write_file',
            arguments: const {
              'path': 'weather.md',
              'content': 'Saved weather report.',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content:
                'The task "Save the weather report" is complete. Validation passed. Do you want another output format?',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['Saved the weather report.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file':
              '{"path":"/tmp/weather.md","created":true,"bytes_written":21}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoVerificationSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Save the weather report');

        expect(toolService.executedToolNames, ['write_file']);
        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('Saved the weather report.'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('Do you want another output format?')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage allows longer saved-task tool loops before fallback',
    () async {
      final toolLoopResponses = <ChatCompletionResult>[
        for (var index = 0; index < 9; index += 1)
          ChatCompletionResult(
            content: 'Continue refining ping_cli.py before validation.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-${index + 2}',
                name: 'read_file',
                arguments: const {'path': 'ping_cli.py'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ChatCompletionResult(
          content: 'The ping CLI implementation is complete.',
          finishReason: 'stop',
        ),
      ];
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'read_file',
            arguments: const {'path': 'ping_cli.py'},
          ),
        ],
        toolLoopResponses: toolLoopResponses,
        finalAnswerChunks: const ['Recovered final answer after long loop.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {'read_file': 'print("ping")'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Implement the ping CLI tool');

        expect(toolService.executedToolNames, List.filled(10, 'read_file'));
        expect(toolDataSource.toolResultBatches, hasLength(10));
        expect(
          toolNotifier.state.messages.last.content,
          contains('Recovered final answer after long loop.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage requests bounded recovery before fallback when tool loops exhaust',
    () async {
      final toolLoopResponses = <ChatCompletionResult>[
        for (var index = 0; index < 11; index += 1)
          ChatCompletionResult(
            content: 'Continue repairing ping_cli.py before validation.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-${index + 2}',
                name: 'read_file',
                arguments: const {'path': 'ping_cli.py'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ChatCompletionResult(
          content: 'One final recovery step is needed for the current task.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-13',
              name: 'read_file',
              arguments: const {'path': 'ping_cli.py'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content:
              'The current saved task is complete. Validation already passed.',
          finishReason: 'stop',
        ),
      ];
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'read_file',
            arguments: const {'path': 'ping_cli.py'},
          ),
        ],
        toolLoopResponses: toolLoopResponses,
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'read_file': 'print("ping")'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Finish the current ping CLI task');

        expect(toolService.executedToolNames, List.filled(12, 'read_file'));
        expect(toolDataSource.toolResultBatches, hasLength(13));
        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('The current saved task is complete.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('sendMessage recovers from duplicate mutating follow-up loops', () async {
    final toolDataSource = _QueuedToolLoopChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'create_tests_dir',
          arguments: const {'path': 'tests'},
        ),
      ],
      toolLoopResponses: [
        ChatCompletionResult(
          content: 'Inspect ping_cli.py before writing tests/test_ping.py.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-2',
              name: 'read_file',
              arguments: const {'path': 'ping_cli.py'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content:
              'Create the tests directory before writing tests/test_ping.py.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-3',
              name: 'create_tests_dir',
              arguments: const {'path': 'tests'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'Write tests/test_ping.py now.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-4',
              name: 'write_test_file',
              arguments: const {'path': 'tests/test_ping.py'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        ChatCompletionResult(
          content: 'The unit test task is complete.',
          finishReason: 'stop',
        ),
      ],
      finalAnswerChunks: const ['Recovered after duplicate follow-up loop.'],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'create_tests_dir':
            '{"path":"/tmp/tests","created":true,"entry_type":"directory"}',
        'read_file': 'print("ping")',
        'write_test_file':
            '{"path":"/tmp/tests/test_ping.py","created":true,"bytes_written":64}',
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
        ),
        conversationsNotifierProvider.overrideWith(
          _TestConversationsNotifier.new,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Add unit tests for the ping CLI');

      expect(toolService.executedToolNames, [
        'create_tests_dir',
        'read_file',
        'write_test_file',
      ]);
      expect(
        toolDataSource.toolResultBatches
            .map((batch) => batch.map((item) => item.name).toList())
            .toList(),
        [
          ['create_tests_dir'],
          ['read_file'],
          ['create_tests_dir', 'read_file'],
          ['write_test_file'],
        ],
      );
      expect(
        toolNotifier.state.messages.last.content,
        contains('Recovered after duplicate follow-up loop.'),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'sendMessage summarizes previous command output for duplicate success intent',
    () async {
      const command = 'python3 get_weather.py';
      final duplicateCommandCall = ToolCallInfo(
        id: 'command-duplicate',
        name: 'local_execute_command',
        arguments: const {'command': command, 'working_directory': '/tmp'},
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'command-1',
            name: 'local_execute_command',
            arguments: const {'command': command, 'working_directory': '/tmp'},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'Repair the source before rerunning the command.',
            toolCalls: [
              ToolCallInfo(
                id: 'write-fix',
                name: 'write_weather_data',
                arguments: const {'path': 'get_weather.py'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Rerun the script after the repair.',
            toolCalls: [
              ToolCallInfo(
                id: 'command-2',
                name: 'local_execute_command',
                arguments: const {
                  'command': command,
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Now let me run the script to confirm the output.',
            toolCalls: [duplicateCommandCall],
            finishReason: 'tool_calls',
          ),
        ],
        finalAnswerChunks: const ['This final answer should not be requested.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command': 'unused',
          'write_weather_data':
              '{"path":"/tmp/get_weather.py","replacements":1}',
        },
        queuedResults: const {
          'local_execute_command': [
            '{"command":"python3 get_weather.py","exit_code":0,"stdout":"# Error\\nNo data found.\\n","stderr":""}',
            '{"command":"python3 get_weather.py","exit_code":0,"stdout":"OUTPUT_FEEDBACK_LIVE_OK\\n","stderr":""}',
          ],
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Run the weather script');

        expect(toolService.executedToolNames, [
          'local_execute_command',
          'write_weather_data',
          'local_execute_command',
        ]);
        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('OUTPUT_FEEDBACK_LIVE_OK'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('Now let me run')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage streams a final answer when duplicate recovery repeats a tool',
    () async {
      final duplicateDatetimeCall = ToolCallInfo(
        id: 'datetime-duplicate',
        name: 'get_current_datetime',
        arguments: const {},
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'datetime-1',
            name: 'get_current_datetime',
            arguments: const {},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'I still need the current time.',
            toolCalls: [duplicateDatetimeCall],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'I still need the current time.',
            toolCalls: [duplicateDatetimeCall],
            finishReason: 'tool_calls',
          ),
        ],
        finalAnswerChunks: const ['Recovered from the prior datetime result.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'get_current_datetime':
              '{"local_datetime":"2026-05-25 10:39:03","timezone":"JST"}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Check the current status');

        expect(toolService.executedToolNames, ['get_current_datetime']);
        expect(toolDataSource.toolResultBatches, hasLength(2));
        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('Recovered from the prior datetime result.'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('problem executing the tools')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage allows rerunning the same validation command after a file rewrite',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'local_execute_command',
            arguments: const {
              'command': 'python3 ping_cli.py --help',
              'working_directory': '/tmp',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'Fix ping_cli.py before retrying validation.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-2',
                name: 'write_cli',
                arguments: const {'path': 'ping_cli.py'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'Retry the saved validation command now.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-3',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'python3 ping_cli.py --help',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The saved task is complete.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['Recovered after validation retry.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command':
              '{"exit_code":0,"stdout":"usage: ping_cli.py"}',
          'write_cli':
              '{"path":"/tmp/ping_cli.py","created":false,"bytes_written":12}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Implement the ping CLI');

        expect(toolService.executedToolNames, [
          'local_execute_command',
          'write_cli',
          'local_execute_command',
        ]);
        expect(toolDataSource.toolResultBatches, hasLength(3));
        expect(
          toolDataSource.toolResultBatches
              .expand((batch) => batch.map((item) => item.name))
              .toList(),
          ['local_execute_command', 'write_cli', 'local_execute_command'],
        );
        expect(
          toolNotifier.state.messages.last.content,
          contains('Recovered after validation retry.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage stops duplicate command follow-up after successful validation',
    () async {
      final conversation = Conversation(
        id: 'conversation-duplicate-validation',
        title: 'Plan thread',
        messages: const <Message>[],
        createdAt: DateTime(2026, 4, 24, 12),
        updatedAt: DateTime(2026, 4, 24, 12, 5),
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-ping-cli',
              title: 'Implement ping CLI',
              targetFiles: ['ping_cli.py'],
              validationCommand: 'python3 ping_cli.py --help',
              status: ConversationWorkflowTaskStatus.inProgress,
            ),
          ],
        ),
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-write',
            name: 'write_cli',
            arguments: const {'path': 'ping_cli.py'},
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-validate',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'python3 ping_cli.py --help',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content:
                'The validation command already passed, so I will not rerun it.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-validate-duplicate',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'python3 ping_cli.py --help',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ],
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_cli': '{"path":"/tmp/ping_cli.py","bytes_written":1200}',
          'local_execute_command':
              '{"command":"python3 ping_cli.py --help","exit_code":0,"stdout":"usage: ping_cli.py [-h] host","stderr":""}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            () => _WorkflowTestConversationsNotifier(conversation),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Implement ping CLI');

        expect(toolService.executedToolNames, [
          'write_cli',
          'local_execute_command',
        ]);
        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('validation command already passed'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('This final answer should never be requested.')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage preserves duplicate read-only command investigation content',
    () async {
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-log-summary',
            name: 'local_execute_command',
            arguments: const {
              'command': 'python3 summarize_session_log.py',
              'working_directory': '/tmp',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content:
                'The session log shows the conversation reset after a duplicate inspection command.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-log-summary-duplicate',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'python3 summarize_session_log.py',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ],
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command':
              '{"command":"python3 summarize_session_log.py","exit_code":0,"stdout":"summary\\n","stderr":""}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Investigate the session log');

        expect(toolService.executedToolNames, ['local_execute_command']);
        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('conversation reset after a duplicate inspection command'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('saved validation command')),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('This final answer should never be requested.')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage stops follow-up tool calls after saved validation succeeds',
    () async {
      final conversation = Conversation(
        id: 'conversation-tool-loop',
        title: 'Plan thread',
        messages: const <Message>[],
        createdAt: DateTime(2026, 4, 24, 12),
        updatedAt: DateTime(2026, 4, 24, 12, 5),
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-readme',
              title: 'Create README.md with project description',
              targetFiles: ['README.md'],
              validationCommand: 'ls README.md',
              status: ConversationWorkflowTaskStatus.inProgress,
            ),
          ],
        ),
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-write',
            name: 'write_file',
            arguments: const {
              'path': 'README.md',
              'content': '# Host health\n',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-validate',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'ls README.md',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content:
                'The saved validation command passed, so the README task is complete.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-rewrite-after-validation',
                name: 'write_file',
                arguments: const {
                  'path': 'README.md',
                  'content': '# Host health\n\nRepeated rewrite\n',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ],
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file': '{"path":"/tmp/README.md","bytes_written":14}',
          'local_execute_command':
              '{"command":"ls README.md","exit_code":0,"stdout":"README.md\\n","stderr":""}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            () => _WorkflowTestConversationsNotifier(conversation),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Create the README first');

        expect(toolService.executedToolNames, [
          'write_file',
          'local_execute_command',
        ]);
        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('README task is complete'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('This final answer should never be requested.')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage accepts successful saved validation wrapper commands',
    () async {
      final conversation = Conversation(
        id: 'conversation-tool-loop-wrapper',
        title: 'Plan thread',
        messages: const <Message>[],
        createdAt: DateTime(2026, 4, 24, 12),
        updatedAt: DateTime(2026, 4, 24, 12, 5),
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-readme',
              title: 'Create README.md with project description',
              targetFiles: ['README.md'],
              validationCommand: 'ls README.md',
              status: ConversationWorkflowTaskStatus.inProgress,
            ),
          ],
        ),
      );
      final wrappedValidationCommand =
          'ls README.md && echo "Validation Successful" || '
          'echo "Validation Failed"';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-write',
            name: 'write_file',
            arguments: const {
              'path': 'README.md',
              'content': '# Host Health Checker\n',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-validate',
                name: 'local_execute_command',
                arguments: {
                  'command': wrappedValidationCommand,
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content:
                'The wrapped saved validation command passed, so the README task is complete.',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-rewrite-after-validation',
                name: 'write_file',
                arguments: const {
                  'path': 'README.md',
                  'content': '# Host Health Checker\n\nRepeated rewrite\n',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
        ],
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'write_file': '{"path":"/tmp/README.md","bytes_written":22}',
          'local_execute_command':
              '{"exit_code":0,"stdout":"Validation Successful\\n","stderr":""}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            () => _WorkflowTestConversationsNotifier(conversation),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Create the README first');

        expect(toolService.executedToolNames, [
          'write_file',
          'local_execute_command',
        ]);
        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('README task is complete'),
        );
        expect(
          toolNotifier.state.messages.last.content,
          isNot(contains('This final answer should never be requested.')),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  const untrustedWrapperCases = <_SavedValidationWrapperCase>[
    _SavedValidationWrapperCase(
      name: 'failure output',
      wrapperCommand: 'ls README.md && echo "Validation Failed"',
      commandResult:
          '{"exit_code":0,"stdout":"Validation Failed\\n","stderr":""}',
    ),
    _SavedValidationWrapperCase(
      name: 'empty success-or-failure output',
      wrapperCommand:
          'ls README.md && echo "Validation Successful" || echo "Validation Failed"',
      commandResult: '{"exit_code":0,"stdout":"","stderr":""}',
    ),
    _SavedValidationWrapperCase(
      name: 'different validation command',
      wrapperCommand:
          'ls CHANGELOG.md && echo "Validation Successful" || echo "Validation Failed"',
      commandResult:
          '{"exit_code":0,"stdout":"Validation Successful\\n","stderr":""}',
    ),
  ];

  for (final wrapperCase in untrustedWrapperCases) {
    test(
      'sendMessage rejects saved validation wrapper with ${wrapperCase.name}',
      () async {
        final outcome = await _runSavedValidationWrapperFollowUpScenario(
          wrapperCommand: wrapperCase.wrapperCommand,
          commandResult: wrapperCase.commandResult,
        );

        expect(outcome.executedToolNames, [
          'write_file',
          'local_execute_command',
          'write_file',
        ]);
        expect(outcome.finalAnswerMessages, isNotEmpty);
        expect(
          outcome.lastMessageContent,
          contains('rejected validation wrapper'),
        );
        expect(
          outcome.lastMessageContent,
          isNot(contains('saved validation command succeeded')),
        );
      },
    );
  }

  test(
    'sendMessage accepts natural stop after saved validation succeeds',
    () async {
      final conversation = Conversation(
        id: 'conversation-tool-loop-natural-stop',
        title: 'Plan thread',
        messages: const <Message>[],
        createdAt: DateTime(2026, 4, 24, 12),
        updatedAt: DateTime(2026, 4, 24, 12, 5),
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'task-readme',
              title: 'Create README.md with project description',
              targetFiles: ['README.md'],
              validationCommand: 'ls README.md',
              status: ConversationWorkflowTaskStatus.inProgress,
            ),
          ],
        ),
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-write',
            name: 'write_file',
            arguments: const {
              'path': 'README.md',
              'content': '# Host Health Checker\n',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'tool-validate',
                name: 'local_execute_command',
                arguments: const {
                  'command': 'ls README.md',
                  'working_directory': '/tmp',
                },
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content:
                'The saved validation command passed, so the README task is complete.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['Natural stop final answer.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file': '{"path":"/tmp/README.md","bytes_written":22}',
          'local_execute_command':
              '{"command":"ls README.md","exit_code":0,"stdout":"README.md\\n","stderr":""}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            () => _WorkflowTestConversationsNotifier(conversation),
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Create the README first');

        expect(toolService.executedToolNames, [
          'write_file',
          'local_execute_command',
        ]);
        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('Natural stop final answer.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage includes tool descriptions and identifier guardrails in the final tool prompt',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'get_router_health',
            arguments: const {'minutes': 30},
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'get_router_health':
              '{"top_affected_devices":[{"device_id":"c891fj-b","event_count":33}]}',
        },
        descriptions: const {
          'get_router_health':
              'Inspect router-side telemetry to assess whether the router or gateway path shows instability.',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Diagnose the router');

        final finalPrompt = toolDataSource.finalAnswerMessages.last.content;
        expect(
          finalPrompt,
          contains(
            'Description: Inspect router-side telemetry to assess whether the router or gateway path shows instability.',
          ),
        );
        expect(
          finalPrompt,
          contains(
            'Scope note: This is infrastructure-side telemetry. Identifiers may refer to the router, gateway, interfaces, or other monitored infrastructure rather than a client device.',
          ),
        );
        expect(
          finalPrompt,
          contains(
            'If the role of an identifier is not explicit in the payload, say it is ambiguous instead of guessing.',
          ),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage preserves tool-role final text as fallback assistant evidence',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'read_alpha',
            arguments: const {'path': 'alpha.txt'},
          ),
        ],
        toolRoleResponseContent:
            'The saved task is complete because the validation passed.',
        finalAnswerChunks: const [
          'I reviewed the tool results and outlined the next step.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'read_alpha': 'alpha result'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Inspect the file');

        expect(
          toolNotifier.takeLatestHiddenAssistantResponse(),
          'The saved task is complete because the validation passed.',
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage accepts terminal tool-role completion without final fallback',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'local_execute_command',
            arguments: const {'command': 'python3 ping_cli.py google.com'},
          ),
        ],
        toolRoleResponseContent:
            'The task "Verify the CLI tool with a single ping execution" is complete. Validation passed successfully.',
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command':
              '{"command":"python3 ping_cli.py google.com","exit_code":0,"stdout":"SUCCESS","stderr":""}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Verify the CLI tool');

        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains(
            'The task "Verify the CLI tool with a single ping execution" is complete.',
          ),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage accepts terminal tool-role completion that references a task id',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'local_execute_command',
            arguments: const {'command': 'python3 test_ping.py'},
          ),
        ],
        toolRoleResponseContent:
            'The task `21871b16-b3eb-4b54-8906-35eef1e742ac` is now complete. Validation passed successfully.',
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command':
              '{"command":"python3 test_ping.py","exit_code":0,"stdout":"TEST PASSED","stderr":""}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Verify the CLI tool');

        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains(
            'The task `21871b16-b3eb-4b54-8906-35eef1e742ac` is now complete.',
          ),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage accepts terminal file mutation completion without final fallback',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 6, 2),
        updatedAt: DateTime(2026, 6, 2),
      );
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'write_file',
            arguments: const {
              'path': 'tokyo_weather_2026-06-03.md',
              'content': '# Tokyo weather',
            },
          ),
        ],
        toolRoleResponseContent:
            'Done. Saved `/tmp/project/tokyo_weather_2026-06-03.md`.',
        finalAnswerChunks: const [
          'This final answer should never be requested.',
        ],
        autoReviewResponses: [
          ChatCompletionResult(
            content:
                '{"outcome":"allow","riskLevel":"low","userAuthorization":"high","rationale":"The user requested this file write."}',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file':
              '{"path":"/tmp/project/tokyo_weather_2026-06-03.md","created":false,"bytes_written":648}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledAutoReviewSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Save the Tokyo weather report');

        expect(toolDataSource.finalAnswerMessages, isEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('/tmp/project/tokyo_weather_2026-06-03.md'),
        );
        expect(toolService.executedToolNames, ['write_file']);
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage rejects terminal file mutation completion with optional follow-up',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 6, 2),
        updatedAt: DateTime(2026, 6, 2),
      );
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'write_file',
            arguments: const {
              'path': 'tokyo_weather_2026-06-03.md',
              'content': '# Tokyo weather',
            },
          ),
        ],
        toolRoleResponseContent:
            'Done. Saved `/tmp/project/tokyo_weather_2026-06-03.md`. '
            'Do you want me to check another city?',
        finalAnswerChunks: const ['Final fallback based on the tool result.'],
        autoReviewResponses: [
          ChatCompletionResult(
            content:
                '{"outcome":"allow","riskLevel":"low","userAuthorization":"high","rationale":"The user requested this file write."}',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file':
              '{"path":"/tmp/project/tokyo_weather_2026-06-03.md","created":false,"bytes_written":648}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledAutoReviewSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Save the Tokyo weather report');

        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        expect(
          toolNotifier.state.messages.last.content,
          contains('Final fallback based on the tool result.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage preserves tool-loop handoff text before follow-up tool calls',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'write_readme',
            arguments: const {'path': 'README.md'},
          ),
        ],
        followUpToolCalls: [
          ToolCallInfo(
            id: 'tool-2',
            name: 'write_cli',
            arguments: const {'path': 'ping_cli.py'},
          ),
        ],
        intermediateToolRoleResponseContent:
            'I have completed the first task: Create README.md with usage instructions. The next task is Implement the ping CLI tool in ping_cli.py.',
        toolRoleResponseContent: '',
        finalAnswerChunks: const ['I continued with the next saved task.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'write_readme': '{"path":"README.md","bytes_written":120}',
          'write_cli': '{"path":"ping_cli.py","bytes_written":240}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Handle the first saved task');

        expect(
          toolNotifier.takeLatestHiddenAssistantResponse(),
          'I have completed the first task: Create README.md with usage instructions. The next task is Implement the ping CLI tool in ping_cli.py.',
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage prefers streamed no-tool handoff text over stale completion content',
    () async {
      final toolDataSource = _NoToolStreamingWithToolsDataSource(
        streamChunks: const [
          'The tool result shows that `README.md` was successfully created. The next task is "Create integration test to verify ping functionality".',
        ],
        completionContent:
            'The user wants me to implement the next pending task: "Create `README.md` with usage instructions".',
      );
      final toolService = _FakeMcpToolService(
        results: const {'read_alpha': 'alpha result'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationsNotifierProvider.overrideWith(
            _TestConversationsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Continue with the next saved task');

        expect(
          toolNotifier.takeLatestHiddenAssistantResponse(),
          'The tool result shows that `README.md` was successfully created. The next task is "Create integration test to verify ping functionality".',
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'content tool calls that require approval are processed sequentially',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final streamingDataSource = _QueuedStreamingChatDataSource([
        [
          '<tool_call>{"name":"write_file","arguments":{"path":"src/ping_utils.py","content":"print(1)","create_parents":true}}</tool_call>'
              '<tool_call>{"name":"write_file","arguments":{"path":"tests/test_ping_utils.py","content":"print(2)","create_parents":true}}</tool_call>',
        ],
        ['Finished applying the requested files.'],
      ]);
      final toolService = _FakeMcpToolService(
        results: const {
          'write_file':
              '{"path":"/tmp/content-tools/file.py","bytes_written":1,"created":true}',
        },
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'tmp',
        rootPath: '/tmp/content-tools-project',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ContentToolSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(streamingDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Create the ping utility files');
        await Future<void>.delayed(Duration.zero);

        final firstPending = toolNotifier.state.pendingFileOperation;
        expect(firstPending, isNotNull);
        expect(
          firstPending!.path,
          '/tmp/content-tools-project/src/ping_utils.py',
        );

        toolNotifier.resolveFileOperation(id: firstPending.id, approved: true);
        await Future<void>.delayed(Duration.zero);

        final secondPending = toolNotifier.state.pendingFileOperation;
        expect(secondPending, isNotNull);
        expect(
          secondPending!.path,
          '/tmp/content-tools-project/tests/test_ping_utils.py',
        );

        toolNotifier.resolveFileOperation(id: secondPending.id, approved: true);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(toolNotifier.state.pendingFileOperation, isNull);
        expect(toolNotifier.state.isLoading, isFalse);
        expect(
          toolNotifier.state.messages.last.content,
          contains('Finished applying the requested files.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('content tool failures are forwarded into continuation prompts', () async {
    final conversationRepository = _FakeConversationRepository();
    final streamingDataSource = _QueuedStreamingChatDataSource([
      [
        '<tool_call>{"name":"google","arguments":{}}</tool_call>'
            '<tool_call>{"name":"write_file","arguments":{"path":"config/hosts.yaml","content":"hosts: []","create_parents":true}}</tool_call>',
      ],
      ['Continue with the available configuration tooling only.'],
    ]);
    final toolService = _SelectiveFakeMcpToolService(
      results: const {
        'write_file':
            '{"path":"/tmp/content-tools/config/hosts.yaml","bytes_written":9,"created":true}',
      },
    );
    final project = CodingProject(
      id: 'project-1',
      name: 'tmp',
      rootPath: '/tmp/content-tools-project',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ContentToolSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(streamingDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          () => _FixedCodingProjectsNotifier(project),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Create the config files');
      await Future<void>.delayed(Duration.zero);

      final pending = toolNotifier.state.pendingFileOperation;
      expect(pending, isNotNull);
      toolNotifier.resolveFileOperation(id: pending!.id, approved: true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(streamingDataSource.requests, hasLength(2));
      final continuationPrompt = streamingDataSource.requests.last.last.content;
      expect(continuationPrompt, contains('[Result of google]'));
      expect(continuationPrompt, contains('"code":"tool_not_available"'));
      expect(
        continuationPrompt,
        contains(
          'If the latest tool result already completed the current saved task or confirmed the saved validation command, do not call more tools for that task and finish with a brief text answer.',
        ),
      );
      expect(
        continuationPrompt,
        contains(
          'If a tool result reports code=tool_not_available, do not retry that tool name or alias variants',
        ),
      );
      expect(
        continuationPrompt,
        contains(
          'If a tool result reports code=edit_mismatch or says old_text was not found in the target file',
        ),
      );
      expect(continuationPrompt, contains('[Result of write_file]'));
      expect(
        toolNotifier.state.messages.last.content,
        contains('Continue with the available configuration tooling only.'),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test('content tool results are exposed for workflow progress', () async {
    final conversationRepository = _FakeConversationRepository();
    final streamingDataSource = _QueuedStreamingChatDataSource([
      [
        '<tool_call>{"name":"local_execute_command","arguments":{"command":"pwd"}}</tool_call>',
      ],
      ['Validation complete.'],
    ]);
    final toolService = _FakeMcpToolService(
      results: const {
        'local_execute_command':
            '{"command":"pwd","exit_code":0,"stdout":"/tmp/content-tools-project","stderr":""}',
      },
    );
    final project = CodingProject(
      id: 'project-1',
      name: 'tmp',
      rootPath: '/tmp/content-tools-project',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ContentToolSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(streamingDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          () => _FixedCodingProjectsNotifier(project),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Run the saved validation command');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final latestResults = toolNotifier.takeLatestToolResults();
      expect(latestResults, hasLength(1));
      expect(latestResults.single.name, 'local_execute_command');
      expect(latestResults.single.arguments['command'], 'pwd');
      expect(latestResults.single.result, contains('"exit_code":0'));
      expect(toolNotifier.takeLatestToolResults(), isEmpty);
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'incomplete content tool calls are recovered before finalizing',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final streamingDataSource = _QueuedStreamingChatDataSource([
        [
          'Checking clients.\n'
              '<tool_use>{"name":"arp","arguments":{"ip_version":"all"}}',
        ],
        ['Client analysis complete.'],
      ]);
      final toolService = _FakeMcpToolService(
        results: const {
          'arp': '{"entries":15,"table":[{"ip":"192.168.100.1"}]}',
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ContentToolSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(streamingDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Deep dive clients');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(toolService.executedToolNames, contains('arp'));
        expect(toolNotifier.state.isLoading, isFalse);
        expect(
          toolNotifier.state.messages.last.content,
          contains('Client analysis complete.'),
        );
        expect(
          toolNotifier.state.messages
              .map((message) => message.content)
              .join('\n'),
          isNot(contains('<tool_use>')),
        );

        final continuationRequest = streamingDataSource.requests.last;
        final assistantHistory = continuationRequest
            .where((message) => message.role == MessageRole.assistant)
            .map((message) => message.content)
            .join('\n');
        expect(assistantHistory, isNot(contains('<tool_use>')));
        expect(assistantHistory, isNot(contains('<tool_result>')));
        expect(continuationRequest.last.content, contains('[Result of arp]'));
        expect(
          continuationRequest.last.content,
          contains('Do not write <tool_result> tags'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('assistant-authored tool results are ignored and recovered', () async {
    final conversationRepository = _FakeConversationRepository();
    final streamingDataSource = _QueuedStreamingChatDataSource([
      [
        '<tool_result>{"name":"arp","summary":"Completed","details":["entries: 15"]}</tool_result>',
      ],
      ['Answering from verified prior results only.'],
    ]);
    final toolService = _FakeMcpToolService(
      results: const {'arp': '{"entries":15}'},
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ContentToolSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(streamingDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Deep dive clients');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(toolService.executedToolNames, isEmpty);
      expect(toolNotifier.state.isLoading, isFalse);
      expect(
        toolNotifier.state.messages.last.content,
        contains('Answering from verified prior results only.'),
      );
      expect(
        toolNotifier.state.messages
            .map((message) => message.content)
            .join('\n'),
        isNot(contains('<tool_result>')),
      );

      final continuationPrompt = streamingDataSource.requests.last.last.content;
      expect(
        continuationPrompt,
        contains('[Assistant-authored tool_result ignored]'),
      );
      expect(
        continuationPrompt,
        contains('Tool results must come from executed tools only.'),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test('content tool continuations ignore display-only print tool calls', () async {
    final conversationRepository = _FakeConversationRepository();
    final streamingDataSource = _QueuedStreamingChatDataSource([
      [
        '<tool_call>{"name":"print","arguments":{"text":"preview"}}</tool_call>'
            '<tool_call>{"name":"write_file","arguments":{"path":"config/hosts.yaml","content":"hosts: []","create_parents":true}}</tool_call>',
      ],
      ['Continue with the available configuration tooling only.'],
    ]);
    final toolService = _SelectiveFakeMcpToolService(
      results: const {
        'write_file':
            '{"path":"/tmp/content-tools/config/hosts.yaml","bytes_written":9,"created":true}',
      },
    );
    final project = CodingProject(
      id: 'project-1',
      name: 'tmp',
      rootPath: '/tmp/content-tools-project',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ContentToolSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(streamingDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          () => _FixedCodingProjectsNotifier(project),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Create the config files');
      await Future<void>.delayed(Duration.zero);

      final pending = toolNotifier.state.pendingFileOperation;
      expect(pending, isNotNull);
      toolNotifier.resolveFileOperation(id: pending!.id, approved: true);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(streamingDataSource.requests, hasLength(2));
      final continuationPrompt = streamingDataSource.requests.last.last.content;
      expect(continuationPrompt, isNot(contains('[Result of print]')));
      expect(
        continuationPrompt,
        isNot(contains('"code":"tool_not_available"')),
      );
      expect(continuationPrompt, contains('[Result of write_file]'));
      expect(
        toolNotifier.state.messages.last.content,
        contains('Continue with the available configuration tooling only.'),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'content tool continuations fall back to non-streaming completion on stream errors',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final dataSource = _ContinuationFallbackChatDataSource();
      final toolService = _FakeMcpToolService(
        results: const {
          'read_file':
              '{"path":"/tmp/content-tools-project/src/config_loader.py","content":"class ConfigLoader:\\n    pass\\n"}',
        },
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'tmp',
        rootPath: '/tmp/content-tools-project',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ContentToolSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Inspect the config loader');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(dataSource.streamRequests, hasLength(2));
        expect(dataSource.completionRequests, isNotEmpty);
        expect(
          dataSource.completionRequests.first.last.content,
          contains('Continue the task using the following tool results.'),
        );
        expect(toolNotifier.state.isLoading, isFalse);
        expect(toolNotifier.state.error, isNull);
        expect(
          toolNotifier.state.messages.last.content,
          contains('Recovered continuation after stream failure.'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('sendMessage materializes a deferred coding draft thread', () async {
    final conversationRepository = _FakeConversationRepository();
    final dataSource = _QueuedStreamingChatDataSource(const [
      ['Draft thread created.'],
    ]);
    final project = CodingProject(
      id: 'project-1',
      name: 'caverno',
      rootPath: '/tmp/caverno',
      createdAt: DateTime(2026, 6, 3, 17),
      updatedAt: DateTime(2026, 6, 3, 17),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final threadContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_TestSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(dataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          () => _FixedCodingProjectsNotifier(project),
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      threadContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
            createFreshOnFirstOpen: true,
            deferFreshConversationCreation: true,
          );
      expect(
        threadContainer.read(conversationsNotifierProvider).currentConversation,
        isNull,
      );
      expect(
        conversationRepository.getAll().where(
          (conversation) => conversation.workspaceMode == WorkspaceMode.coding,
        ),
        isEmpty,
      );

      final chatNotifier = threadContainer.read(chatNotifierProvider.notifier);
      await chatNotifier.sendMessage('Build the draft composer flow');

      final currentConversation = threadContainer
          .read(conversationsNotifierProvider)
          .currentConversation;
      expect(currentConversation, isNotNull);
      expect(currentConversation!.workspaceMode, WorkspaceMode.coding);
      expect(currentConversation.normalizedProjectId, project.id);
      expect(
        currentConversation.messages.first.content,
        'Build the draft composer flow',
      );
      expect(
        conversationRepository.getAll().where(
          (conversation) => conversation.workspaceMode == WorkspaceMode.coding,
        ),
        hasLength(1),
      );
      expect(
        dataSource.requests.single
            .where((message) => message.role == MessageRole.user)
            .single
            .content,
        'Build the draft composer flow',
      );
    } finally {
      threadContainer.dispose();
    }
  });

  test(
    'sendMessage auto-enters planning for a new coding thread when configured',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final proposalDataSource = _QueuedProposalDataSource([
        ChatCompletionResult(
          content:
              '{"kind":"proposal","workflowStage":"plan","goal":"Add explicit planning state","constraints":["Keep behavior backward compatible"],"acceptanceCriteria":["Planning is stored per thread"],"openQuestions":[]}',
          finishReason: 'stop',
        ),
        ChatCompletionResult(
          content:
              '{"tasks":[{"title":"Persist planning state on conversations","targetFiles":["lib/features/chat/domain/entities/conversation.dart"],"validationCommand":"flutter test","notes":"Update entity serialization and notifier helpers."},{"title":"Validate planning state persistence","targetFiles":["test/features/chat/presentation/providers/conversations_notifier_test.dart"],"validationCommand":"flutter test","notes":"Cover the stored planning metadata."}]}',
          finishReason: 'stop',
        ),
      ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final planContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_PlanSettingsNotifier.new),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(proposalDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        planContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: 'project-1',
              createIfMissing: true,
            );
        final planNotifier = planContainer.read(chatNotifierProvider.notifier);

        await planNotifier.sendMessage('Plan the next coding slice');

        final currentConversation = planContainer
            .read(conversationsNotifierProvider)
            .currentConversation;
        expect(currentConversation, isNotNull);
        expect(currentConversation!.isPlanningSession, isTrue);
        expect(currentConversation.messages, hasLength(1));
        expect(
          currentConversation.messages.single.content,
          'Plan the next coding slice',
        );
        expect(planNotifier.state.workflowProposalError, isNull);
        expect(planNotifier.state.taskProposalError, isNull);
        expect(planNotifier.state.isLoading, isFalse);
        expect(proposalDataSource.requests.length, greaterThanOrEqualTo(2));
      } finally {
        planContainer.dispose();
      }
    },
  );

  test(
    'planning proposals include hidden research context from read-only tools',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final proposalDataSource = _QueuedProposalDataSource([
        ChatCompletionResult(
          content:
              '{"kind":"proposal","workflowStage":"plan","goal":"Add explicit planning state","constraints":["Keep behavior backward compatible"],"acceptanceCriteria":["Planning is stored per thread"],"openQuestions":[]}',
          finishReason: 'stop',
        ),
        ChatCompletionResult(
          content:
              '{"tasks":[{"title":"Persist planning state on conversations","targetFiles":["lib/features/chat/domain/entities/conversation.dart"],"validationCommand":"flutter test","notes":"Update entity serialization and notifier helpers."},{"title":"Validate planning state persistence","targetFiles":["test/features/chat/presentation/providers/conversations_notifier_test.dart"],"validationCommand":"flutter test","notes":"Cover the stored planning metadata."}]}',
          finishReason: 'stop',
        ),
      ]);
      final toolService = _PlanningResearchMcpToolService();
      final project = CodingProject(
        id: 'project-1',
        name: 'caverno',
        rootPath: '/tmp/planning-project',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final planContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_PlanSettingsNotifier.new),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(proposalDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        planContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final planNotifier = planContainer.read(chatNotifierProvider.notifier);

        await planNotifier.sendMessage('Plan the next coding slice');

        final workflowPrompt = proposalDataSource.requests.first.last.content;
        expect(workflowPrompt, contains('Research context:'));
        expect(workflowPrompt, contains('pubspec.yaml'));
        expect(
          workflowPrompt,
          contains('class ChatNotifier extends Notifier<ChatState>'),
        );
        expect(toolService.executedToolNames, contains('list_directory'));
        expect(toolService.executedToolNames, contains('find_files'));
        expect(toolService.executedToolNames, contains('search_files'));
        expect(toolService.executedToolNames, contains('read_file'));
      } finally {
        planContainer.dispose();
      }
    },
  );

  test(
    'planning proposal keeps workflow and task drafts when message saves lag',
    () async {
      final conversationRepository = _DelayedConversationRepository(
        saveDelay: const Duration(milliseconds: 50),
      );
      final proposalDataSource = _QueuedProposalDataSource([
        ChatCompletionResult(
          content:
              '{"kind":"proposal","workflowStage":"plan","goal":"Add explicit planning state","constraints":["Keep behavior backward compatible"],"acceptanceCriteria":["Planning is stored per thread"],"openQuestions":[]}',
          finishReason: 'stop',
        ),
        ChatCompletionResult(
          content:
              '{"tasks":[{"title":"Persist planning state on conversations","targetFiles":["lib/features/chat/domain/entities/conversation.dart"],"validationCommand":"flutter test","notes":"Update entity serialization and notifier helpers."},{"title":"Validate planning state persistence","targetFiles":["test/features/chat/presentation/providers/conversations_notifier_test.dart"],"validationCommand":"flutter test","notes":"Cover the stored planning metadata."}]}',
          finishReason: 'stop',
        ),
      ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final planContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_PlanSettingsNotifier.new),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(proposalDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        planContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: 'project-1',
              createIfMissing: true,
            );
        final planNotifier = planContainer.read(chatNotifierProvider.notifier);

        await planNotifier.sendMessage('Plan the next coding slice');

        final chatState = planNotifier.state;
        final currentConversation = planContainer
            .read(conversationsNotifierProvider)
            .currentConversation;
        expect(chatState.workflowProposalDraft, isNotNull);
        expect(chatState.taskProposalDraft, isNotNull);
        expect(currentConversation?.planArtifact?.draftMarkdown, isNotNull);
        expect(
          currentConversation?.planArtifact?.draftMarkdown,
          contains('Persist planning state on conversations'),
        );
      } finally {
        planContainer.dispose();
      }
    },
  );

  test(
    'generatePlanProposal keeps the approved markdown while refreshing the draft',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final proposalDataSource = _QueuedProposalDataSource([
        ChatCompletionResult(
          content:
              '{"kind":"proposal","workflowStage":"plan","goal":"Replan from the approved baseline","constraints":["Keep the approved execution plan stable"],"acceptanceCriteria":["A new draft is generated"],"openQuestions":[]}',
          finishReason: 'stop',
        ),
        ChatCompletionResult(
          content:
              '{"tasks":[{"title":"Refresh the draft plan","targetFiles":["README.md"],"validationCommand":"flutter test","notes":"Reuse the approved plan as context."},{"title":"Validate the refreshed draft context","targetFiles":["test/features/chat/presentation/providers/chat_notifier_test.dart"],"validationCommand":"flutter test","notes":"Cover the regenerated draft metadata."}]}',
          finishReason: 'stop',
        ),
      ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final planContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_PlanSettingsNotifier.new),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(proposalDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final conversationsNotifier = planContainer.read(
          conversationsNotifierProvider.notifier,
        );
        conversationsNotifier.activateWorkspace(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-1',
          createIfMissing: true,
        );
        await conversationsNotifier.updateCurrentPlanArtifact(
          planArtifact: const ConversationPlanArtifact(
            approvedMarkdown: '# Plan\n\n## Goal\nApproved baseline',
          ),
        );
        final chatNotifier = planContainer.read(chatNotifierProvider.notifier);

        await chatNotifier.generatePlanProposal();

        final currentConversation = planContainer
            .read(conversationsNotifierProvider)
            .currentConversation;
        expect(currentConversation, isNotNull);
        expect(
          currentConversation!.planArtifact?.normalizedApprovedMarkdown,
          '# Plan\n\n## Goal\nApproved baseline',
        );
        expect(
          currentConversation.planArtifact?.normalizedDraftMarkdown,
          contains('Refresh the draft plan'),
        );
      } finally {
        planContainer.dispose();
      }
    },
  );

  test(
    'generatePlanProposal persists task draft before ending task generation',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final proposalDataSource = _QueuedProposalDataSource([
        ChatCompletionResult(
          content:
              '{"kind":"proposal","workflowStage":"plan","goal":"Create a small Python CLI","constraints":["Keep files minimal"],"acceptanceCriteria":["A runnable task plan is generated"],"openQuestions":[]}',
          finishReason: 'stop',
        ),
        ChatCompletionResult(
          content:
              '{"tasks":[{"title":"Create the CLI entrypoint","targetFiles":["main.py"],"validationCommand":"python3 main.py --help","notes":"Add argparse help output."},{"title":"Document the CLI usage","targetFiles":["README.md"],"validationCommand":"python3 main.py --help","notes":"Keep the README short."}]}',
          finishReason: 'stop',
        ),
      ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final planContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_PlanSettingsNotifier.new),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(proposalDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );
      ProviderSubscription<ChatState>? subscription;

      try {
        planContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: 'project-1',
              createIfMissing: true,
            );
        final taskCountsWhenGenerationEnds = <int>[];
        subscription = planContainer.listen<ChatState>(chatNotifierProvider, (
          previous,
          next,
        ) {
          if (!(previous?.isGeneratingTaskProposal ?? false) ||
              next.isGeneratingTaskProposal ||
              next.taskProposalDraft == null ||
              next.taskProposalError != null) {
            return;
          }
          final markdown = planContainer
              .read(conversationsNotifierProvider)
              .currentConversation
              ?.planArtifact
              ?.normalizedDraftMarkdown;
          if (markdown == null) {
            taskCountsWhenGenerationEnds.add(0);
            return;
          }
          final validation = ConversationPlanProjectionService.validateDocument(
            markdown: markdown,
            requireTasks: true,
          );
          taskCountsWhenGenerationEnds.add(validation.previewTasks.length);
        });
        final planNotifier = planContainer.read(chatNotifierProvider.notifier);

        await planNotifier.generatePlanProposal();

        expect(taskCountsWhenGenerationEnds, [2]);
      } finally {
        subscription?.close();
        planContainer.dispose();
      }
    },
  );

  test('generatePlanProposal includes execution progress when replanning', () async {
    final conversationRepository = _FakeConversationRepository();
    final proposalDataSource = _QueuedProposalDataSource([
      ChatCompletionResult(
        content:
            '{"kind":"proposal","workflowStage":"plan","goal":"Refresh the plan from current execution progress","constraints":["Keep the approved plan stable until a new draft is approved"],"acceptanceCriteria":["Execution progress shapes the next draft"],"openQuestions":[]}',
        finishReason: 'stop',
      ),
      ChatCompletionResult(
        content:
            '{"tasks":[{"title":"Update the draft from execution progress","targetFiles":["lib/features/chat/presentation/pages/chat_page.dart"],"validationCommand":"flutter test","notes":"Use completed tasks as context."},{"title":"Validate execution-aware replanning context","targetFiles":["test/features/chat/presentation/providers/chat_notifier_test.dart"],"validationCommand":"flutter test","notes":"Cover execution progress in the draft."}]}',
        finishReason: 'stop',
      ),
    ]);
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final planContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_PlanSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(proposalDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          _TestCodingProjectsNotifier.new,
        ),
        mcpToolServiceProvider.overrideWithValue(null),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final conversationsNotifier = planContainer.read(
        conversationsNotifierProvider.notifier,
      );
      conversationsNotifier.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        createIfMissing: true,
      );
      const approvedMarkdown =
          '# Plan\n'
          '\n'
          '## Stage\n'
          'implement\n'
          '\n'
          '## Goal\n'
          'Ground replans in current execution state\n'
          '\n'
          '## Tasks\n'
          '\n'
          '1. Ship the first execution improvement\n'
          '   - Status: pending\n'
          '   - Validation: flutter test\n';
      await conversationsNotifier.updateCurrentPlanArtifact(
        planArtifact: const ConversationPlanArtifact(
          approvedMarkdown: approvedMarkdown,
        ),
      );
      await conversationsNotifier.updateCurrentWorkflow(
        workflowStage: ConversationWorkflowStage.implement,
        workflowSpec: const ConversationWorkflowSpec(
          tasks: [
            ConversationWorkflowTask(
              id: 'derived-task-1-legacy',
              title: 'Ship the first execution improvement',
              validationCommand: 'flutter test',
            ),
          ],
        ),
        workflowSourceHash: computeConversationPlanHash(
          approvedMarkdown.trim(),
        ),
        workflowDerivedAt: DateTime(2026, 4, 18, 13, 0),
        preserveWorkflowProjection: true,
      );
      await conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: 'derived-task-1-legacy',
        status: ConversationWorkflowTaskStatus.completed,
        summary: 'Completed during the last implementation pass.',
        eventType: ConversationExecutionTaskEventType.completed,
      );
      final chatNotifier = planContainer.read(chatNotifierProvider.notifier);

      await chatNotifier.generatePlanProposal();

      final workflowPrompt = proposalDataSource.requests.first.last.content;
      expect(workflowPrompt, contains('Execution progress:'));
      expect(workflowPrompt, contains('projectionState: fresh'));
      expect(
        workflowPrompt,
        contains('[completed] Ship the first execution improvement'),
      );
      expect(
        workflowPrompt,
        contains('Completed during the last implementation pass.'),
      );
      expect(
        workflowPrompt,
        contains(
          'recentEvents: completed: Completed during the last implementation pass.',
        ),
      );
    } finally {
      planContainer.dispose();
    }
  });

  test(
    'generatePlanProposalWithContext includes blocker context in proposal prompts',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final proposalDataSource = _QueuedProposalDataSource([
        ChatCompletionResult(
          content:
              '{"kind":"proposal","workflowStage":"clarify","goal":"Resolve the blocker before continuing implementation","constraints":["Preserve the approved plan unless the blocker requires a change"],"acceptanceCriteria":["The blocker is either removed or reflected in the next draft"],"openQuestions":[]}',
          finishReason: 'stop',
        ),
        ChatCompletionResult(
          content:
              '{"tasks":[{"title":"Unblock the missing host setup","targetFiles":["lib/features/chat/presentation/pages/chat_page.dart"],"validationCommand":"flutter test","notes":"Refresh the plan around the blocker."},{"title":"Validate the blocker-focused replan","targetFiles":["test/features/chat/presentation/providers/chat_notifier_test.dart"],"validationCommand":"flutter test","notes":"Cover the blocker context in the draft."}]}',
          finishReason: 'stop',
        ),
      ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final planContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(_PlanSettingsNotifier.new),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(proposalDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(null),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final conversationsNotifier = planContainer.read(
          conversationsNotifierProvider.notifier,
        );
        conversationsNotifier.activateWorkspace(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-1',
          createIfMissing: true,
        );
        const approvedMarkdown =
            '# Plan\n'
            '\n'
            '## Stage\n'
            'implement\n'
            '\n'
            '## Goal\n'
            'Keep execution moving with blocker-aware replans\n'
            '\n'
            '## Tasks\n'
            '\n'
            '1. Bring the host setup online\n'
            '   - Status: blocked\n'
            '   - Validation: flutter test\n';
        await conversationsNotifier.updateCurrentPlanArtifact(
          planArtifact: const ConversationPlanArtifact(
            approvedMarkdown: approvedMarkdown,
          ),
        );
        await conversationsNotifier.updateCurrentWorkflow(
          workflowStage: ConversationWorkflowStage.implement,
          workflowSpec: const ConversationWorkflowSpec(
            tasks: [
              ConversationWorkflowTask(
                id: 'derived-task-1-legacy',
                title: 'Bring the host setup online',
                validationCommand: 'flutter test',
              ),
            ],
          ),
          workflowSourceHash: computeConversationPlanHash(
            approvedMarkdown.trim(),
          ),
          workflowDerivedAt: DateTime(2026, 4, 18, 14, 30),
          preserveWorkflowProjection: true,
        );
        await conversationsNotifier.updateCurrentExecutionTaskProgress(
          taskId: 'derived-task-1-legacy',
          status: ConversationWorkflowTaskStatus.blocked,
          summary: 'The host setup is blocked on missing credentials.',
          blockedReason:
              'Missing SSH credentials for the shared development host.',
        );
        final chatNotifier = planContainer.read(chatNotifierProvider.notifier);

        await chatNotifier.generatePlanProposalWithContext(
          additionalPlanningContext:
              'Focus on the blocked host setup task and either unblock it or add the minimum follow-up work needed.',
        );

        expect(proposalDataSource.requests.length, greaterThanOrEqualTo(2));
        final workflowPrompt = proposalDataSource.requests.first.last.content;
        final taskPrompt = proposalDataSource.requests.last.last.content;
        expect(workflowPrompt, contains('Requested replan focus:'));
        expect(
          workflowPrompt,
          contains('Focus on the blocked host setup task'),
        );
        expect(
          workflowPrompt,
          contains(
            'blockedReason: Missing SSH credentials for the shared development host.',
          ),
        );
        expect(taskPrompt, contains('Requested replan focus:'));
        expect(
          taskPrompt,
          contains(
            'either unblock it or add the minimum follow-up work needed',
          ),
        );
      } finally {
        planContainer.dispose();
      }
    },
  );

  test(
    'planning sessions block write tools with permission_denied results',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'write_file',
            arguments: const {
              'path': '/tmp/plan-notes.md',
              'content': 'draft plan',
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': 'unexpected write'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final conversationsNotifier = toolContainer.read(
          conversationsNotifierProvider.notifier,
        );
        conversationsNotifier.activateWorkspace(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-1',
          createIfMissing: true,
        );
        await conversationsNotifier.enterPlanningSession();
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage(
          'Inspect the plan before implementation',
          bypassPlanMode: true,
        );
        await Future<void>.delayed(Duration.zero);

        expect(toolService.executedToolNames, isEmpty);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        final result = toolDataSource.toolResultBatches.single.single;
        expect(result.name, 'write_file');
        expect(result.result, contains('"code":"permission_denied"'));
        expect(
          result.result,
          contains('planning_mode_requires_read_only_tools'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('planning sessions allow read-only local commands to execute', () async {
    final conversationRepository = _FakeConversationRepository();
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'local_execute_command',
          arguments: const {'command': 'pwd', 'working_directory': '/tmp'},
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'local_execute_command': '{"command":"pwd","stdout":"/tmp"}',
      },
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          _TestCodingProjectsNotifier.new,
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      final conversationsNotifier = toolContainer.read(
        conversationsNotifierProvider.notifier,
      );
      conversationsNotifier.activateWorkspace(
        workspaceMode: WorkspaceMode.coding,
        projectId: 'project-1',
        createIfMissing: true,
      );
      await conversationsNotifier.enterPlanningSession();
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage(
        'Inspect the working directory first',
        bypassPlanMode: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(toolService.executedToolNames, ['local_execute_command']);
      expect(toolDataSource.toolResultBatches, hasLength(1));
      final result = toolDataSource.toolResultBatches.single.single;
      expect(result.name, 'local_execute_command');
      expect(result.result, isNot(contains('"code":"permission_denied"')));
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'planning sessions block git write commands with permission_denied results',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'git_execute_command',
            arguments: const {
              'command': 'checkout -b temp-branch',
              'working_directory': '/tmp',
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'git_execute_command': 'unexpected git write'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            _TestCodingProjectsNotifier.new,
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final conversationsNotifier = toolContainer.read(
          conversationsNotifierProvider.notifier,
        );
        conversationsNotifier.activateWorkspace(
          workspaceMode: WorkspaceMode.coding,
          projectId: 'project-1',
          createIfMissing: true,
        );
        await conversationsNotifier.enterPlanningSession();
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage(
          'Inspect repository state only',
          bypassPlanMode: true,
        );
        await Future<void>.delayed(Duration.zero);

        expect(toolService.executedToolNames, isEmpty);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        final result = toolDataSource.toolResultBatches.single.single;
        expect(result.name, 'git_execute_command');
        expect(result.result, contains('"code":"permission_denied"'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'remote file mutations require approval in default permission mode',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'write_file',
            arguments: const {'path': 'README.md', 'content': 'remote update'},
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': 'unexpected write'},
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        final sendFuture = toolNotifier.sendMessage(
          'Write the README remotely',
          bypassPlanMode: true,
          origin: ChatInteractionOrigin.remote,
        );
        for (
          var i = 0;
          i < 10 && toolNotifier.state.pendingFileOperation == null;
          i += 1
        ) {
          await Future<void>.delayed(Duration.zero);
        }

        final pending = toolNotifier.state.pendingFileOperation;
        expect(pending, isNotNull);
        expect(pending!.origin, ChatInteractionOrigin.remote);
        expect(toolService.executedToolNames, isEmpty);

        toolNotifier.resolveFileOperation(id: pending.id, approved: false);
        await sendFuture;
        expect(toolService.executedToolNames, isEmpty);
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'remote non-read-only local commands require approval in default permission mode',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'local_execute_command',
            arguments: const {
              'command': 'rm -rf build',
              'working_directory': '/tmp/project',
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'local_execute_command': 'unexpected command'},
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        final sendFuture = toolNotifier.sendMessage(
          'Run the remote cleanup command',
          bypassPlanMode: true,
          origin: ChatInteractionOrigin.remote,
        );
        for (
          var i = 0;
          i < 10 && toolNotifier.state.pendingLocalCommand == null;
          i += 1
        ) {
          await Future<void>.delayed(Duration.zero);
        }

        final pending = toolNotifier.state.pendingLocalCommand;
        expect(pending, isNotNull);
        expect(pending!.origin, ChatInteractionOrigin.remote);
        expect(toolService.executedToolNames, isEmpty);

        toolNotifier.resolveLocalCommand(
          id: pending.id,
          approval: const LocalCommandApproval(approved: false),
        );
        await sendFuture;
        expect(toolService.executedToolNames, isEmpty);
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'run_tests reuses local command approval and preserves result name',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'run_tests',
            arguments: const {
              'test_path': 'test/widget_test.dart',
              'runner': 'flutter',
              'reason': 'Validate the widget change',
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command':
              '{"command":"flutter test test/widget_test.dart","exit_code":0,"stdout":"All tests passed.","stderr":""}',
        },
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        final sendFuture = toolNotifier.sendMessage(
          'Run the scoped widget test',
          bypassPlanMode: true,
        );
        for (
          var i = 0;
          i < 20 && toolNotifier.state.pendingLocalCommand == null;
          i += 1
        ) {
          await Future<void>.delayed(Duration.zero);
        }

        final pending = toolNotifier.state.pendingLocalCommand;
        expect(pending, isNotNull);
        expect(pending!.command, "flutter test 'test/widget_test.dart'");
        expect(pending.workingDirectory, '/tmp/project');
        expect(pending.reason, 'Validate the widget change');
        expect(toolService.executedToolNames, isEmpty);

        toolNotifier.resolveLocalCommand(
          id: pending.id,
          approval: const LocalCommandApproval(approved: true),
        );
        await sendFuture;

        expect(toolService.executedToolNames, ['local_execute_command']);
        expect(
          toolService.executedToolArguments.single['command'],
          "flutter test 'test/widget_test.dart'",
        );
        expect(toolDataSource.toolResultBatches, hasLength(1));
        final result = toolDataSource.toolResultBatches.single.single;
        expect(result.name, 'run_tests');
        expect(result.arguments['test_path'], 'test/widget_test.dart');
        expect(result.result, contains('"exit_code":0'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('run_tests rejects test paths outside the active project', () async {
    final conversationRepository = _FakeConversationRepository();
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'run_tests',
          arguments: const {
            'test_path': '../outside/widget_test.dart',
            'runner': 'dart',
          },
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {'local_execute_command': 'unexpected command'},
    );
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: '/tmp/project',
      createdAt: DateTime(2026, 5, 26),
      updatedAt: DateTime(2026, 5, 26),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(_ToolEnabledSettingsNotifier.new),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          () => _FixedCodingProjectsNotifier(project),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage(
        'Run the escaped test path',
        bypassPlanMode: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(toolNotifier.state.pendingLocalCommand, isNull);
      expect(toolService.executedToolNames, isEmpty);
      expect(toolDataSource.toolResultBatches, hasLength(1));
      final result = toolDataSource.toolResultBatches.single.single;
      expect(result.name, 'run_tests');
      expect(result.result, contains('"code":"test_path_outside_project"'));
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'remote saved deny rules block local commands before mobile approval',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'local_execute_command',
            arguments: const {
              'command': 'rm -rf build',
              'working_directory': '/tmp/project',
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'local_execute_command': 'unexpected command'},
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledRemoteDenySettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage(
          'Run the denied remote cleanup command',
          bypassPlanMode: true,
          origin: ChatInteractionOrigin.remote,
        );
        await Future<void>.delayed(Duration.zero);

        expect(toolNotifier.state.pendingLocalCommand, isNull);
        expect(toolService.executedToolNames, isEmpty);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        final result = toolDataSource.toolResultBatches.single.single;
        expect(result.name, 'local_execute_command');
        expect(
          result.result,
          contains('Local command was denied by a saved permission rule'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'remote read-only local commands can execute without approval',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'local_execute_command',
            arguments: const {
              'command': 'pwd',
              'working_directory': '/tmp/project',
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {
          'local_execute_command': '{"command":"pwd","stdout":"/tmp/project"}',
        },
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage(
          'Inspect the remote working directory',
          bypassPlanMode: true,
          origin: ChatInteractionOrigin.remote,
        );
        await Future<void>.delayed(Duration.zero);

        expect(toolNotifier.state.pendingLocalCommand, isNull);
        expect(toolService.executedToolNames, ['local_execute_command']);
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'remote git writes require approval in default permission mode',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'git_execute_command',
            arguments: const {
              'command': 'checkout -b remote-branch',
              'working_directory': '/tmp/project',
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'git_execute_command': 'unexpected git write'},
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        final sendFuture = toolNotifier.sendMessage(
          'Create a branch remotely',
          bypassPlanMode: true,
          origin: ChatInteractionOrigin.remote,
        );
        for (
          var i = 0;
          i < 10 && toolNotifier.state.pendingGitCommand == null;
          i += 1
        ) {
          await Future<void>.delayed(Duration.zero);
        }

        final pending = toolNotifier.state.pendingGitCommand;
        expect(pending, isNotNull);
        expect(pending!.origin, ChatInteractionOrigin.remote);
        expect(toolService.executedToolNames, isEmpty);

        toolNotifier.resolveGitCommand(id: pending.id, approved: false);
        await sendFuture;
        expect(toolService.executedToolNames, isEmpty);
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('auto-review allows file mutations without a pending approval', () async {
    final conversationRepository = _FakeConversationRepository();
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'write_file',
          arguments: const {'path': 'README.md', 'content': 'approved update'},
        ),
      ],
      autoReviewResponses: [
        ChatCompletionResult(
          content:
              '{"outcome":"allow","riskLevel":"low","userAuthorization":"high","rationale":"The user requested this scoped edit."}',
          finishReason: 'stop',
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {
        'write_file':
            '{"path":"/tmp/project/README.md","created":false,"bytes_written":15}',
      },
    );
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: '/tmp/project',
      createdAt: DateTime(2026, 5, 26),
      updatedAt: DateTime(2026, 5, 26),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledAutoReviewSettingsNotifier.new,
        ),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          () => _FixedCodingProjectsNotifier(project),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Update README', bypassPlanMode: true);
      await Future<void>.delayed(Duration.zero);

      expect(toolNotifier.state.pendingFileOperation, isNull);
      expect(toolDataSource.autoReviewRequestMessages, hasLength(1));
      expect(toolService.executedToolNames, ['write_file']);
      expect(toolDataSource.finalAnswerMessages, isNotEmpty);
      expect(
        toolDataSource.finalAnswerMessages.last.content,
        contains(
          'Operation note: write_file updated or overwrote an existing file',
        ),
      );
      expect(
        toolDataSource.finalAnswerMessages.last.content,
        contains('mention this existing-file update in the final answer'),
      );
      expect(
        toolDataSource.finalAnswerMessages.last.content,
        contains('end after the concise completion evidence'),
      );
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'sendMessage adds analyzer feedback after a successful Dart file mutation',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_diagnostic_feedback_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'write_file',
            arguments: const {
              'path': 'lib/main.dart',
              'content': 'void main() {}\n',
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {'write_file': '{"path":"$changedPath","bytes_written":15}'},
      );
      final diagnosticFeedback = ToolResultInfo(
        id: 'diag-1',
        name: CodingDiagnosticFeedbackService.toolName,
        arguments: const {
          'project_root': 'project',
          'changed_paths': ['lib/main.dart'],
        },
        result: jsonEncode({
          'schema': CodingDiagnosticFeedbackService.schemaName,
          'diagnostic_count': 1,
          'diagnostics': [
            {
              'relative_path': 'lib/main.dart',
              'severity': 'Error',
              'line': 1,
              'column': 6,
              'message': 'Undefined name main.',
            },
          ],
        }),
      );
      final baseline = CodingDiagnosticFeedbackBaseline(
        providerName: 'dart_analyzer',
        projectRoot: projectRoot.path,
        changedPaths: const ['lib/main.dart'],
        diagnostics: [
          CodeDiagnostic(
            absolutePath: changedPath,
            severity: 'Warning',
            line: 1,
            column: 1,
            message: 'Existing warning.',
          ),
        ],
        telemetry: const CodingDiagnosticTelemetry(durationMs: 1, attempts: []),
      );
      final diagnosticService = _FakeCodingDiagnosticFeedbackService(
        diagnosticFeedback,
        baseline: baseline,
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          codingDiagnosticFeedbackServiceProvider.overrideWithValue(
            diagnosticService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Update the Dart entrypoint');

        expect(diagnosticService.requestedProjectRoots, [projectRoot.path]);
        expect(diagnosticService.baselineProjectRoots, [projectRoot.path]);
        expect(diagnosticService.baselineChangedPaths.single, [changedPath]);
        expect(diagnosticService.requestedChangedPaths.single, [changedPath]);
        expect(diagnosticService.receivedBaselines.single, same(baseline));
        expect(toolDataSource.toolResultBatches, hasLength(1));
        expect(
          toolDataSource.toolResultBatches.single.map((result) => result.name),
          ['write_file', CodingDiagnosticFeedbackService.toolName],
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage adds command output feedback for zero-exit artifact errors',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_command_output_feedback_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final command = 'python3 get_weather.py';
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'local_execute_command',
            arguments: {
              'command': command,
              'working_directory': projectRoot.path,
            },
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {
          'local_execute_command': jsonEncode({
            'command': command,
            'working_directory': projectRoot.path,
            'exit_code': 0,
            'stdout':
                'Saved report to tokyo_weather.md\n\n# Error\n\nNo data found for 2026-06-02.\n',
            'stderr': '',
          }),
        },
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          codingDiagnosticFeedbackServiceProvider.overrideWithValue(
            _FakeCodingDiagnosticFeedbackService(null),
          ),
          codingVerificationFeedbackServiceProvider.overrideWithValue(
            _FakeCodingVerificationFeedbackService(null),
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Create the weather report');

        expect(toolService.executedToolNames, ['local_execute_command']);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        expect(
          toolDataSource.toolResultBatches.single.map((result) => result.name),
          [
            'local_execute_command',
            CodingCommandOutputGuardrailService.toolName,
          ],
        );
        final feedback = toolDataSource.toolResultBatches.single.singleWhere(
          (result) =>
              result.name == CodingCommandOutputGuardrailService.toolName,
        );
        final payload = jsonDecode(feedback.result) as Map<String, dynamic>;
        expect(
          payload['schema'],
          CodingCommandOutputGuardrailService.schemaName,
        );
        expect(payload['success'], isFalse);
        expect(payload['validation_status'], 'failed');
        expect(jsonEncode(payload['issues']), contains(command));
        expect(jsonEncode(payload['issues']), contains('Markdown error'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage runs real analyzer feedback after a broken Dart mutation',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_real_diagnostic_feedback_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      await File('${projectRoot.path}/pubspec.yaml').writeAsString('''
name: caverno_diagnostic_feedback_fixture
environment:
  sdk: '>=3.0.0 <4.0.0'
''');
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'write_file',
            arguments: const {
              'path': 'lib/main.dart',
              'content': '''
void main() {
  print(missingAnalyzerFeedbackCanarySymbol);
}
''',
            },
          ),
        ],
      );
      final toolService = _WritingFileMcpToolService(projectRoot);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Write a broken Dart entrypoint');

        expect(toolService.executedToolNames, ['write_file']);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        expect(
          toolDataSource.toolResultBatches.single.map((result) => result.name),
          ['write_file', CodingDiagnosticFeedbackService.toolName],
        );
        final diagnosticResult = toolDataSource.toolResultBatches.single
            .singleWhere(
              (result) =>
                  result.name == CodingDiagnosticFeedbackService.toolName,
            );
        final payload =
            jsonDecode(diagnosticResult.result) as Map<String, dynamic>;
        expect(payload['schema'], CodingDiagnosticFeedbackService.schemaName);
        expect(payload['changed_paths'], ['lib/main.dart']);
        expect(payload['diagnostic_count'], greaterThanOrEqualTo(1));
        expect(
          jsonEncode(payload['diagnostics']),
          contains('missingAnalyzerFeedbackCanarySymbol'),
        );
      } finally {
        toolContainer.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'sendMessage blocks completion claims with coding verification feedback',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_verification_feedback_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      final initialWrite = ToolCallInfo(
        id: 'tool-1',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 1;\n',
        },
      );
      final repairWrite = ToolCallInfo(
        id: 'tool-2',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 2;\n',
        },
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [initialWrite],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'I will fix the failing test now.',
            toolCalls: [repairWrite],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete. Validation passed.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': ''},
        queuedResults: {
          'write_file': [
            '{"path":"$changedPath","bytes_written":18}',
            '{"path":"$changedPath","bytes_written":18}',
          ],
        },
      );
      final verificationFeedback = ToolResultInfo(
        id: 'verify-1',
        name: CodingVerificationFeedbackService.toolName,
        arguments: const {
          'project_root': 'project',
          'changed_paths': ['lib/main.dart'],
          'trigger': 'completionClaim',
        },
        result: jsonEncode({
          'schema': CodingVerificationFeedbackService.schemaName,
          'provider': 'dart_test_runner',
          'trigger': 'completionClaim',
          'validation_status': 'failed',
          'changed_paths': ['lib/main.dart'],
          'counts': {'passed': 0, 'failed': 1, 'skipped': 0},
          'failing_tests': [
            {
              'relative_path': 'test/main_test.dart',
              'test_name': 'value returns two',
              'line': 4,
              'message': 'Expected: <2> Actual: <1>',
            },
          ],
        }),
      );
      final verificationService =
          _FakeCodingVerificationFeedbackService.sequence([
            verificationFeedback,
            null,
          ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          codingDiagnosticFeedbackServiceProvider.overrideWithValue(
            _FakeCodingDiagnosticFeedbackService(null),
          ),
          codingVerificationFeedbackServiceProvider.overrideWithValue(
            verificationService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Fix the failing Dart test');

        expect(verificationService.requestedProjectRoots, [
          projectRoot.path,
          projectRoot.path,
        ]);
        expect(verificationService.requestedChangedPaths, [
          [changedPath],
          [changedPath],
        ]);
        expect(verificationService.requestedTriggers, [
          CodingVerificationTrigger.completionClaim,
          CodingVerificationTrigger.completionClaim,
        ]);
        expect(toolService.executedToolNames, ['write_file', 'write_file']);
        expect(toolDataSource.toolResultBatches, hasLength(3));
        expect(
          toolDataSource.toolResultBatches[0].map((result) => result.name),
          ['write_file'],
        );
        expect(
          toolDataSource.toolResultBatches[1].map((result) => result.name),
          [CodingVerificationFeedbackService.toolName],
        );
        expect(
          toolDataSource.toolResultBatches[2].map((result) => result.name),
          ['write_file'],
        );
        final finalContent = toolContainer
            .read(chatNotifierProvider)
            .messages
            .last
            .content;
        expect(finalContent, isNot(contains('is done')));
        expect(finalContent, contains('Validation passed'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage skips coding verification feedback when disabled',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_verification_disabled_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      final writeCall = ToolCallInfo(
        id: 'tool-1',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 1;\n',
        },
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [writeCall],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': ''},
        queuedResults: {
          'write_file': ['{"path":"$changedPath","bytes_written":18}'],
        },
      );
      final verificationFeedback = ToolResultInfo(
        id: 'verify-disabled',
        name: CodingVerificationFeedbackService.toolName,
        arguments: const {
          'project_root': 'project',
          'changed_paths': ['lib/main.dart'],
          'trigger': 'completionClaim',
        },
        result: jsonEncode({
          'schema': CodingVerificationFeedbackService.schemaName,
          'provider': 'dart_test_runner',
          'trigger': 'completionClaim',
          'validation_status': 'failed',
          'changed_paths': ['lib/main.dart'],
          'counts': {'passed': 0, 'failed': 1, 'skipped': 0},
          'failing_tests': [
            {
              'relative_path': 'test/main_test.dart',
              'test_name': 'value returns two',
              'line': 4,
              'message': 'Expected: <2> Actual: <1>',
            },
          ],
        }),
      );
      final verificationService = _FakeCodingVerificationFeedbackService(
        verificationFeedback,
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoVerificationSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          codingDiagnosticFeedbackServiceProvider.overrideWithValue(
            _FakeCodingDiagnosticFeedbackService(null),
          ),
          codingVerificationFeedbackServiceProvider.overrideWithValue(
            verificationService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Fix the failing Dart test');

        expect(verificationService.requestedProjectRoots, isEmpty);
        expect(toolService.executedToolNames, ['write_file']);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        expect(
          toolDataSource.toolResultBatches.single.map((result) => result.name),
          ['write_file'],
        );
        final finalContent = toolContainer
            .read(chatNotifierProvider)
            .messages
            .last
            .content;
        expect(finalContent, contains('is complete'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage skips completion verification in request-only mode',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_verification_request_only_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'write_file',
            arguments: const {
              'path': 'lib/main.dart',
              'content': 'int value() => 1;\n',
            },
          ),
        ],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': ''},
        queuedResults: {
          'write_file': ['{"path":"$changedPath","bytes_written":18}'],
        },
      );
      final verificationService = _FakeCodingVerificationFeedbackService(
        ToolResultInfo(
          id: 'verify-request-only',
          name: CodingVerificationFeedbackService.toolName,
          arguments: const {
            'project_root': 'project',
            'changed_paths': ['lib/main.dart'],
            'trigger': 'completionClaim',
          },
          result: jsonEncode({
            'schema': CodingVerificationFeedbackService.schemaName,
            'provider': 'dart_test_runner',
            'trigger': 'completionClaim',
            'validation_status': 'failed',
            'changed_paths': ['lib/main.dart'],
            'counts': {'passed': 0, 'failed': 1, 'skipped': 0},
            'failing_tests': const [],
          }),
        ),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledRequestOnlyVerificationSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          codingDiagnosticFeedbackServiceProvider.overrideWithValue(
            _FakeCodingDiagnosticFeedbackService(null),
          ),
          codingVerificationFeedbackServiceProvider.overrideWithValue(
            verificationService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Fix the failing Dart test');

        expect(verificationService.requestedProjectRoots, isEmpty);
        expect(toolService.executedToolNames, ['write_file']);
        expect(toolDataSource.toolResultBatches, hasLength(1));
        final finalContent = toolContainer
            .read(chatNotifierProvider)
            .messages
            .last
            .content;
        expect(finalContent, contains('is complete'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage records coding verification snapshots on execution progress',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_verification_progress_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      final testPath = '${projectRoot.path}/test/main_test.dart';
      final initialWrite = ToolCallInfo(
        id: 'tool-1',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 1;\n',
        },
      );
      final repairWrite = ToolCallInfo(
        id: 'tool-2',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 2;\n',
        },
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [initialWrite],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'I will fix the failing test now.',
            toolCalls: [repairWrite],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete. Validation passed.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': ''},
        queuedResults: {
          'write_file': [
            '{"path":"$changedPath","bytes_written":18}',
            '{"path":"$changedPath","bytes_written":18}',
          ],
        },
      );
      final failedSnapshot = _codingVerificationSnapshot(
        projectRoot: projectRoot.path,
        changedPath: 'lib/main.dart',
        validationStatus: ConversationExecutionValidationStatus.failed,
        passedCount: 0,
        failedCount: 1,
        exitCode: 1,
        failures: [
          CodingVerificationFailure(
            testName: 'value returns two',
            absolutePath: testPath,
            line: 4,
            message: 'Expected: <2> Actual: <1>',
          ),
        ],
      );
      final passedSnapshot = _codingVerificationSnapshot(
        projectRoot: projectRoot.path,
        changedPath: 'lib/main.dart',
        validationStatus: ConversationExecutionValidationStatus.passed,
        passedCount: 1,
        failedCount: 0,
        exitCode: 0,
      );
      final verificationFeedback = ToolResultInfo(
        id: 'verify-progress-1',
        name: CodingVerificationFeedbackService.toolName,
        arguments: const {
          'project_root': 'project',
          'changed_paths': ['lib/main.dart'],
          'trigger': 'completionClaim',
        },
        result: jsonEncode({
          'schema': CodingVerificationFeedbackService.schemaName,
          'provider': 'dart_test_runner',
          'trigger': 'completionClaim',
          'validation_status': 'failed',
          'changed_paths': ['lib/main.dart'],
          'counts': {'passed': 0, 'failed': 1, 'skipped': 0},
          'failing_tests': [
            {
              'relative_path': 'test/main_test.dart',
              'test_name': 'value returns two',
              'line': 4,
              'message': 'Expected: <2> Actual: <1>',
            },
          ],
        }),
      );
      final verificationService = _FakeCodingVerificationFeedbackService.runs([
        CodingVerificationFeedbackRun(
          snapshot: failedSnapshot,
          toolResult: verificationFeedback,
        ),
        CodingVerificationFeedbackRun(
          snapshot: passedSnapshot,
          toolResult: null,
        ),
      ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          codingDiagnosticFeedbackServiceProvider.overrideWithValue(
            _FakeCodingDiagnosticFeedbackService(null),
          ),
          codingVerificationFeedbackServiceProvider.overrideWithValue(
            verificationService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        final conversationsNotifier = toolContainer.read(
          conversationsNotifierProvider.notifier,
        );
        conversationsNotifier.activateWorkspace(
          workspaceMode: WorkspaceMode.coding,
          projectId: project.id,
          createIfMissing: true,
        );
        await conversationsNotifier.updateCurrentPlanArtifact(
          planArtifact: const ConversationPlanArtifact(
            approvedMarkdown:
                '# Plan\n'
                '\n'
                '## Stage\n'
                'implement\n'
                '\n'
                '## Goal\n'
                'Fix a failing Dart test\n'
                '\n'
                '## Tasks\n'
                '\n'
                '1. Fix tests\n'
                '   - Status: inProgress\n'
                '   - Validation: flutter test\n',
          ),
        );
        await conversationsNotifier
            .refreshCurrentWorkflowProjectionFromApprovedPlan();
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Fix the failing Dart test');

        final progress = toolContainer
            .read(conversationsNotifierProvider)
            .currentConversation
            ?.executionProgress
            .single;
        expect(progress, isNotNull);
        expect(progress!.status, ConversationWorkflowTaskStatus.completed);
        expect(
          progress.validationStatus,
          ConversationExecutionValidationStatus.passed,
        );
        expect(
          progress.lastValidationCommand,
          'flutter test --machine test/main_test.dart',
        );
        expect(
          progress.lastValidationSummary,
          contains('Coding verification passed'),
        );
        final validationEvents = progress.events
            .where(
              (event) =>
                  event.type == ConversationExecutionTaskEventType.validated,
            )
            .toList(growable: false);
        expect(validationEvents, hasLength(2));
        expect(
          validationEvents.first.validationStatus,
          ConversationExecutionValidationStatus.failed,
        );
        expect(
          validationEvents.first.validationSummary,
          contains('Actual: <1>'),
        );
        expect(
          validationEvents.last.validationStatus,
          ConversationExecutionValidationStatus.passed,
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage blocks streamed completion claims with verification feedback',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_stream_verification_feedback_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      final initialWrite = ToolCallInfo(
        id: 'tool-1',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 1;\n',
        },
      );
      final repairWrite = ToolCallInfo(
        id: 'tool-2',
        name: 'write_file',
        arguments: const {
          'path': 'lib/main.dart',
          'content': 'int value() => 2;\n',
        },
      );
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [initialWrite],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'I wrote the requested Dart file.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'I will repair the failing test before finishing.',
            toolCalls: [repairWrite],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete. Validation passed.',
            finishReason: 'stop',
          ),
        ],
        finalAnswerChunks: const ['The task "Fix tests" is done.'],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': ''},
        queuedResults: {
          'write_file': [
            '{"path":"$changedPath","bytes_written":18}',
            '{"path":"$changedPath","bytes_written":18}',
          ],
        },
      );
      final verificationFeedback = ToolResultInfo(
        id: 'verify-stream-1',
        name: CodingVerificationFeedbackService.toolName,
        arguments: const {
          'project_root': 'project',
          'changed_paths': ['lib/main.dart'],
          'trigger': 'completionClaim',
        },
        result: jsonEncode({
          'schema': CodingVerificationFeedbackService.schemaName,
          'provider': 'dart_test_runner',
          'trigger': 'completionClaim',
          'validation_status': 'failed',
          'changed_paths': ['lib/main.dart'],
          'counts': {'passed': 0, 'failed': 1, 'skipped': 0},
          'failing_tests': [
            {
              'relative_path': 'test/main_test.dart',
              'test_name': 'value returns two',
              'line': 4,
              'message': 'Expected: <2> Actual: <1>',
            },
          ],
        }),
      );
      final verificationService =
          _FakeCodingVerificationFeedbackService.sequence([
            verificationFeedback,
            null,
          ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          codingDiagnosticFeedbackServiceProvider.overrideWithValue(
            _FakeCodingDiagnosticFeedbackService(null),
          ),
          codingVerificationFeedbackServiceProvider.overrideWithValue(
            verificationService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Fix the failing Dart test');

        expect(verificationService.requestedProjectRoots, [
          projectRoot.path,
          projectRoot.path,
        ]);
        expect(verificationService.requestedChangedPaths, [
          [changedPath],
          [changedPath],
        ]);
        expect(verificationService.requestedTriggers, [
          CodingVerificationTrigger.completionClaim,
          CodingVerificationTrigger.completionClaim,
        ]);
        expect(toolService.executedToolNames, ['write_file', 'write_file']);
        expect(toolDataSource.finalAnswerMessages, isNotEmpty);
        expect(toolDataSource.toolResultBatches, hasLength(3));
        expect(
          toolDataSource.toolResultBatches[0].map((result) => result.name),
          ['write_file'],
        );
        expect(
          toolDataSource.toolResultBatches[1].map((result) => result.name),
          [CodingVerificationFeedbackService.toolName],
        );
        expect(
          toolDataSource.toolResultBatches[2].map((result) => result.name),
          ['write_file'],
        );
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test(
    'sendMessage stops repeated verification repair for unchanged failures',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final projectRoot = await Directory.systemTemp.createTemp(
        'caverno_chat_verification_convergence_',
      );
      addTearDown(() => projectRoot.delete(recursive: true));
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: projectRoot.path,
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final changedPath = '${projectRoot.path}/lib/main.dart';
      ToolCallInfo writeCall(String id, String content) {
        return ToolCallInfo(
          id: id,
          name: 'write_file',
          arguments: {'path': 'lib/main.dart', 'content': content},
        );
      }

      ToolResultInfo verificationFeedback(String id) {
        return ToolResultInfo(
          id: id,
          name: CodingVerificationFeedbackService.toolName,
          arguments: const {
            'project_root': 'project',
            'changed_paths': ['lib/main.dart'],
            'trigger': 'completionClaim',
          },
          result: jsonEncode({
            'schema': CodingVerificationFeedbackService.schemaName,
            'provider': 'dart_test_runner',
            'trigger': 'completionClaim',
            'validation_status': 'failed',
            'changed_paths': ['lib/main.dart'],
            'counts': {'passed': 0, 'failed': 1, 'skipped': 0},
            'failing_tests': [
              {
                'relative_path': 'test/main_test.dart',
                'test_name': 'value returns two',
                'line': 4,
                'message': 'Expected: <2> Actual: <1>',
              },
            ],
          }),
        );
      }

      final initialWrite = writeCall('tool-1', 'int value() => 1;\n');
      final firstRepairWrite = writeCall('tool-2', 'int value() => 2;\n');
      final secondRepairWrite = writeCall('tool-3', 'int value() => 3;\n');
      final toolDataSource = _QueuedToolLoopChatDataSource(
        initialToolCalls: [initialWrite],
        toolLoopResponses: [
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'I will repair the failing test.',
            toolCalls: [firstRepairWrite],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
          ChatCompletionResult(
            content: 'I will try one more repair.',
            toolCalls: [secondRepairWrite],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(
            content: 'The task "Fix tests" is complete.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'write_file': ''},
        queuedResults: {
          'write_file': [
            '{"path":"$changedPath","bytes_written":18}',
            '{"path":"$changedPath","bytes_written":18}',
            '{"path":"$changedPath","bytes_written":18}',
          ],
        },
      );
      final verificationService =
          _FakeCodingVerificationFeedbackService.sequence([
            verificationFeedback('verify-1'),
            verificationFeedback('verify-2'),
            verificationFeedback('verify-3'),
          ]);
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledNoConfirmSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          codingDiagnosticFeedbackServiceProvider.overrideWithValue(
            _FakeCodingDiagnosticFeedbackService(null),
          ),
          codingVerificationFeedbackServiceProvider.overrideWithValue(
            verificationService,
          ),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        await toolNotifier.sendMessage('Fix the failing Dart test');

        expect(verificationService.requestedProjectRoots, [
          projectRoot.path,
          projectRoot.path,
          projectRoot.path,
        ]);
        expect(toolService.executedToolNames, [
          'write_file',
          'write_file',
          'write_file',
        ]);
        expect(toolDataSource.toolResultBatches, hasLength(5));
        expect(
          toolDataSource.toolResultBatches.map(
            (batch) => batch.map((result) => result.name).toList(),
          ),
          [
            ['write_file'],
            [CodingVerificationFeedbackService.toolName],
            ['write_file'],
            [CodingVerificationFeedbackService.toolName],
            ['write_file'],
          ],
        );
        final finalContent = toolContainer
            .read(chatNotifierProvider)
            .messages
            .last
            .content;
        expect(finalContent, contains('not complete'));
        expect(finalContent, contains('same failing tests persisted'));
        expect(finalContent, contains('value returns two'));
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('auto-review denies local commands without executing them', () async {
    final conversationRepository = _FakeConversationRepository();
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'local_execute_command',
          arguments: const {
            'command': 'rm -rf build',
            'working_directory': '/tmp/project',
          },
        ),
      ],
      autoReviewResponses: [
        ChatCompletionResult(
          content:
              '{"outcome":"deny","riskLevel":"high","userAuthorization":"unknown","rationale":"The deletion is not clearly authorized."}',
          finishReason: 'stop',
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {'local_execute_command': 'unexpected command'},
    );
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: '/tmp/project',
      createdAt: DateTime(2026, 5, 26),
      updatedAt: DateTime(2026, 5, 26),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledAutoReviewSettingsNotifier.new,
        ),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          () => _FixedCodingProjectsNotifier(project),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage(
        'Clean build outputs',
        bypassPlanMode: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(toolNotifier.state.pendingLocalCommand, isNull);
      expect(toolService.executedToolNames, isEmpty);
      expect(toolDataSource.toolResultBatches, hasLength(1));
      final result = toolDataSource.toolResultBatches.single.single;
      expect(result.result, contains('Auto-review denied this action'));
      expect(result.result, contains('not clearly authorized'));
    } finally {
      toolContainer.dispose();
    }
  });

  test(
    'auto-review malformed output falls back to manual git approval',
    () async {
      final conversationRepository = _FakeConversationRepository();
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'git_execute_command',
            arguments: const {
              'command': 'checkout -b reviewed-branch',
              'working_directory': '/tmp/project',
            },
          ),
        ],
        autoReviewResponses: [
          ChatCompletionResult(content: 'allow it', finishReason: 'stop'),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: const {'git_execute_command': 'unexpected git write'},
      );
      final project = CodingProject(
        id: 'project-1',
        name: 'Project',
        rootPath: '/tmp/project',
        createdAt: DateTime(2026, 5, 26),
        updatedAt: DateTime(2026, 5, 26),
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final toolContainer = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            _ToolEnabledAutoReviewSettingsNotifier.new,
          ),
          conversationRepositoryProvider.overrideWithValue(
            conversationRepository,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _TestSessionMemoryService(),
          ),
          codingProjectsNotifierProvider.overrideWith(
            () => _FixedCodingProjectsNotifier(project),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _TestBackgroundTaskService(),
          ),
        ],
      );

      try {
        toolContainer
            .read(conversationsNotifierProvider.notifier)
            .activateWorkspace(
              workspaceMode: WorkspaceMode.coding,
              projectId: project.id,
              createIfMissing: true,
            );
        final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

        final sendFuture = toolNotifier.sendMessage(
          'Create a branch',
          bypassPlanMode: true,
        );
        for (
          var i = 0;
          i < 10 && toolNotifier.state.pendingGitCommand == null;
          i += 1
        ) {
          await Future<void>.delayed(Duration.zero);
        }

        final pending = toolNotifier.state.pendingGitCommand;
        expect(pending, isNotNull);
        expect(toolDataSource.autoReviewRequestMessages, hasLength(1));
        expect(toolService.executedToolNames, isEmpty);

        toolNotifier.resolveGitCommand(id: pending!.id, approved: false);
        await sendFuture;
        expect(toolService.executedToolNames, isEmpty);
      } finally {
        toolContainer.dispose();
      }
    },
  );

  test('full access runs git writes without a pending approval', () async {
    final conversationRepository = _FakeConversationRepository();
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'git_execute_command',
          arguments: const {
            'command': 'checkout -b full-access-branch',
            'working_directory': '/tmp/project',
          },
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {'git_execute_command': '{"exit_code":0}'},
    );
    final project = CodingProject(
      id: 'project-1',
      name: 'Project',
      rootPath: '/tmp/project',
      createdAt: DateTime(2026, 5, 26),
      updatedAt: DateTime(2026, 5, 26),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final toolContainer = ProviderContainer(
      overrides: [
        settingsNotifierProvider.overrideWith(
          _ToolEnabledNoConfirmSettingsNotifier.new,
        ),
        conversationRepositoryProvider.overrideWithValue(
          conversationRepository,
        ),
        chatRemoteDataSourceProvider.overrideWithValue(toolDataSource),
        sessionMemoryServiceProvider.overrideWithValue(
          _TestSessionMemoryService(),
        ),
        codingProjectsNotifierProvider.overrideWith(
          () => _FixedCodingProjectsNotifier(project),
        ),
        mcpToolServiceProvider.overrideWithValue(toolService),
        appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
        backgroundTaskServiceProvider.overrideWithValue(
          _TestBackgroundTaskService(),
        ),
      ],
    );

    try {
      toolContainer
          .read(conversationsNotifierProvider.notifier)
          .activateWorkspace(
            workspaceMode: WorkspaceMode.coding,
            projectId: project.id,
            createIfMissing: true,
          );
      final toolNotifier = toolContainer.read(chatNotifierProvider.notifier);

      await toolNotifier.sendMessage('Create a branch', bypassPlanMode: true);
      await Future<void>.delayed(Duration.zero);

      expect(toolNotifier.state.pendingGitCommand, isNull);
      expect(toolDataSource.autoReviewRequestMessages, isEmpty);
      expect(toolService.executedToolNames, ['git_execute_command']);
    } finally {
      toolContainer.dispose();
    }
  });
}
