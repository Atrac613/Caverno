import 'dart:async';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/chat_request_prefix_stability_service.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/domain/services/tool_definition_search_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  test('sendMessage keeps tool-loop request prefix stable', () async {
    final toolDataSource = _ToolBatchChatDataSource(
      initialToolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'read_alpha',
          arguments: const {'path': 'alpha.txt'},
        ),
      ],
    );
    final toolService = _FakeMcpToolService(
      results: const {'read_alpha': 'alpha result'},
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final container = _buildContainer(
      settings: _ToolEnabledSettingsNotifier.new,
      toolDataSource: toolDataSource,
      toolService: toolService,
      appLifecycleService: appLifecycleService,
    );

    try {
      final notifier = container.read(chatNotifierProvider.notifier);

      await notifier.sendMessage('Inspect alpha');

      final initialPrefix = _promptPrefixForRecordedToolLoop(
        toolDataSource,
      ).initialPrefix;
      final followUpPrefix = _promptPrefixForRecordedToolLoop(
        toolDataSource,
      ).followUpPrefix;

      expect(followUpPrefix, initialPrefix);
    } finally {
      container.dispose();
    }
  });

  test(
    'sendMessage uses a fixed full tool list in prefix-stable mode',
    () async {
      final toolDataSource = _ToolBatchChatDataSource(
        initialToolCalls: [
          ToolCallInfo(
            id: 'tool-1',
            name: 'tool_29',
            arguments: const {'path': 'alpha.txt'},
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        results: {for (var index = 0; index < 30; index++) 'tool_$index': 'ok'},
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final container = _buildContainer(
        settings: _PrefixStableToolLoopSettingsNotifier.new,
        toolDataSource: toolDataSource,
        toolService: toolService,
        appLifecycleService: appLifecycleService,
      );

      try {
        final notifier = container.read(chatNotifierProvider.notifier);

        await notifier.sendMessage('Inspect alpha');

        expect(toolService.executedToolNames, ['tool_29']);
        final initialToolNames =
            ToolDefinitionSearchService.toolNamesFromDefinitions(
              toolDataSource.initialToolDefinitionBatches.single,
            );
        final followUpToolNames =
            ToolDefinitionSearchService.toolNamesFromDefinitions(
              toolDataSource.followUpToolDefinitionBatches.single,
            );
        expect(initialToolNames, contains('tool_0'));
        expect(initialToolNames, contains('tool_29'));
        expect(
          initialToolNames,
          contains(ToolDefinitionSearchService.toolName),
        );
        expect(followUpToolNames, initialToolNames);

        final prefix = _promptPrefixForRecordedToolLoop(toolDataSource);
        expect(prefix.followUpPrefix, prefix.initialPrefix);
      } finally {
        container.dispose();
      }
    },
  );
}

ProviderContainer _buildContainer({
  required SettingsNotifier Function() settings,
  required _ToolBatchChatDataSource toolDataSource,
  required _FakeMcpToolService toolService,
  required AppLifecycleService appLifecycleService,
}) {
  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(settings),
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
}

_PromptPrefixPair _promptPrefixForRecordedToolLoop(
  _ToolBatchChatDataSource toolDataSource,
) {
  expect(toolDataSource.initialRequestMessages, hasLength(1));
  expect(toolDataSource.toolResultRequestMessages, hasLength(1));
  expect(toolDataSource.initialToolDefinitionBatches, hasLength(1));
  expect(toolDataSource.followUpToolDefinitionBatches, hasLength(1));

  final initialMessages = toolDataSource.initialRequestMessages.single;
  final followUpMessages = toolDataSource.toolResultRequestMessages.single;
  final stableMessageCount =
      ChatRequestPrefixStabilityService.commonLeadingPromptMessageCount(
        initialMessages,
        followUpMessages,
      );
  expect(stableMessageCount, greaterThan(0));

  return _PromptPrefixPair(
    initialPrefix: ChatRequestPrefixStabilityService.buildPromptPrefixJson(
      messages: initialMessages,
      tools: toolDataSource.initialToolDefinitionBatches.single,
      stableMessageCount: stableMessageCount,
    ),
    followUpPrefix: ChatRequestPrefixStabilityService.buildPromptPrefixJson(
      messages: followUpMessages,
      tools: toolDataSource.followUpToolDefinitionBatches.single,
      stableMessageCount: stableMessageCount,
    ),
  );
}

class _PromptPrefixPair {
  const _PromptPrefixPair({
    required this.initialPrefix,
    required this.followUpPrefix,
  });

  final String initialPrefix;
  final String followUpPrefix;
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

class _PrefixStableToolLoopSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      mcpEnabled: true,
      demoMode: false,
      enablePrefixStableToolLoop: true,
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
    final current = state.currentConversation;
    if (current != null) return current;

    final now = DateTime(2026, 6, 14, 10);
    final conversation = Conversation(
      id: 'prefix-stability-conversation',
      title: defaultConversationTitle,
      messages: const <Message>[],
      createdAt: now,
      updatedAt: now,
      workspaceMode: WorkspaceMode.chat,
    );
    state = state.copyWith(
      conversations: [conversation],
      currentConversationId: conversation.id,
      activeWorkspaceMode: WorkspaceMode.chat,
      clearActiveProject: true,
    );
    return conversation;
  }

  @override
  Future<void> updateCurrentConversation(List<Message> messages) async {
    final current = state.currentConversation;
    if (current == null) return;
    await updateConversationMessages(current.id, messages);
  }

  @override
  Future<void> updateConversationMessages(
    String conversationId,
    List<Message> messages,
  ) async {
    Conversation? updatedConversation;
    final conversations = state.conversations
        .map((conversation) {
          if (conversation.id != conversationId) return conversation;
          updatedConversation = conversation.copyWith(messages: messages);
          return updatedConversation!;
        })
        .toList(growable: false);
    if (updatedConversation == null) return;
    state = state.copyWith(
      conversations: conversations,
      currentConversationId: updatedConversation!.id,
    );
  }

  @override
  Future<void> ensureCurrentPlanArtifactBackfilled() async {}
}

class _MockMemoryBox extends Mock implements Box<String> {}

class _TestSessionMemoryService extends SessionMemoryService {
  _TestSessionMemoryService()
    : super(ChatMemoryRepository.fromBox(_MockMemoryBox()));

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

class _TestBackgroundTaskService extends BackgroundTaskService {
  @override
  Future<void> beginBackgroundTask() async {}

  @override
  Future<void> endBackgroundTask() async {}

  @override
  void dispose() {}
}

class _FakeMcpToolService extends McpToolService {
  _FakeMcpToolService({required this.results});

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
    return ToolDefinitionSearchService.appendSearchToolIfUseful(
      results.keys
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
          .toList(growable: false),
    );
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedToolNames.add(name);
    return McpToolResult(
      toolName: name,
      result: results[name] ?? '',
      isSuccess: true,
    );
  }
}

class _ToolBatchChatDataSource implements ChatDataSource {
  _ToolBatchChatDataSource({required this.initialToolCalls});

  final List<ToolCallInfo> initialToolCalls;
  final List<List<Message>> initialRequestMessages = [];
  final List<List<Message>> toolResultRequestMessages = [];
  final List<List<Map<String, dynamic>>> initialToolDefinitionBatches = [];
  final List<List<Map<String, dynamic>>> followUpToolDefinitionBatches = [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return Stream<String>.fromIterable(const ['Combined tool summary']);
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return Future<ChatCompletionResult>.value(
      ChatCompletionResult(
        content:
            '{"summary":"Tool loop completed.","open_loops":[],"profile":{"persona":[],"preferences":[],"do_not":[]},"memories":[]}',
        finishReason: 'stop',
      ),
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
    initialRequestMessages.add(List<Message>.from(messages));
    initialToolDefinitionBatches.add(List<Map<String, dynamic>>.from(tools));
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
    toolResultRequestMessages.add(List<Message>.from(messages));
    followUpToolDefinitionBatches.add(
      List<Map<String, dynamic>>.from(tools ?? const []),
    );
    return ChatCompletionResult(content: '', finishReason: 'stop');
  }
}
