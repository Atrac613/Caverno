import 'dart:async';
import 'dart:collection';

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
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/domain/services/tool_definition_search_service.dart';
import 'package:caverno/features/chat/domain/services/turn_steering_prompt_builder.dart';
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
  test('a message typed mid-turn is carried by the next request', () async {
    final toolDataSource = _ToolLoopChatDataSource(
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
      dataSource: toolDataSource,
      toolService: toolService,
      appLifecycleService: appLifecycleService,
    );
    addTearDown(container.dispose);

    final notifier = container.read(chatNotifierProvider.notifier);

    // The tool is executing, so the turn is mid-flight and has a request left
    // to build. That is the window steering exists for.
    Future<ChatTurnOwnerRecord>? steerResult;
    toolService.onExecute = () {
      steerResult ??= () async {
        final owner = await notifier.sendMessage(
          'Use beta.txt instead',
          interrupt: true,
        );
        return ChatTurnOwnerRecord(
          owner,
          notifier.state.steeringMessages.length,
        );
      }();
    };

    final turnOwner = await notifier.sendMessage('Inspect alpha');
    final steer = await steerResult;

    // Joined the running turn rather than starting one of its own.
    expect(steer, isNotNull);
    expect(steer!.owner, turnOwner);
    expect(steer.pendingAtRegistration, 1);
    expect(toolDataSource.initialRequestMessages, hasLength(1));

    final followUp = toolDataSource.toolResultRequestMessages.single;
    final followUpUserContents = followUp
        .where((message) => message.role == MessageRole.user)
        .map((message) => message.content)
        .toList(growable: false);

    expect(followUpUserContents, contains('Inspect alpha'));
    expect(followUpUserContents, contains('Use beta.txt instead'));
    // The interruption has to read as one, not as a remark filed behind the
    // work already in flight.
    expect(
      followUp
          .where((message) => message.role == MessageRole.system)
          .map((message) => message.content)
          .join('\n'),
      contains(TurnSteeringPromptBuilder.marker),
    );

    // Committed into the transcript, ahead of the reply it interrupted.
    final transcriptUserContents = notifier.state.messages
        .where((message) => message.role == MessageRole.user)
        .map((message) => message.content)
        .toList(growable: false);
    expect(transcriptUserContents, ['Inspect alpha', 'Use beta.txt instead']);

    // Nothing is left waiting, and nothing was pushed back to the queue.
    expect(notifier.state.steeringMessages, isEmpty);
    expect(notifier.state.queuedMessages, isEmpty);
  });

  test('a turn that ends first hands the message back to the queue', () async {
    final firstTurn = StreamController<String>();
    final secondTurn = StreamController<String>();
    final dataSource = _ControllableQueueChatDataSource(
      Queue<StreamController<String>>.from([firstTurn, secondTurn]),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final container = _buildContainer(
      settings: _NoToolSettingsNotifier.new,
      dataSource: dataSource,
      toolService: null,
      appLifecycleService: appLifecycleService,
    );
    addTearDown(container.dispose);

    final notifier = container.read(chatNotifierProvider.notifier);
    final firstSend = notifier.sendMessage('Explain the plan');
    for (var i = 0; i < 10 && dataSource.requests.isEmpty; i += 1) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(dataSource.requests, hasLength(1));

    // No further request is coming: this turn is one plain answer.
    final steerOwner = await notifier.sendMessage(
      'Keep it under 3 lines',
      interrupt: true,
    );
    expect(steerOwner, isNotNull);
    expect(notifier.state.steeringMessages, hasLength(1));
    expect(notifier.state.queuedMessages, isEmpty);

    firstTurn.add('Here is the long plan.');
    await firstTurn.close();
    await firstSend;
    secondTurn.add('Short version.');
    await secondTurn.close();
    for (var i = 0; i < 20 && dataSource.requests.length < 2; i += 1) {
      await Future<void>.delayed(Duration.zero);
    }

    // Never carried, so it came back as its own turn instead of being lost.
    expect(dataSource.requests, hasLength(2));
    expect(notifier.state.steeringMessages, isEmpty);
    expect(notifier.state.queuedMessages, isEmpty);
    expect(
      notifier.state.messages
          .where((message) => message.role == MessageRole.user)
          .map((message) => message.content),
      ['Explain the plan', 'Keep it under 3 lines'],
    );
  });

  test('a withdrawn interruption never reaches the model', () async {
    final firstTurn = StreamController<String>();
    final dataSource = _ControllableQueueChatDataSource(
      Queue<StreamController<String>>.from([firstTurn]),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final container = _buildContainer(
      settings: _NoToolSettingsNotifier.new,
      dataSource: dataSource,
      toolService: null,
      appLifecycleService: appLifecycleService,
    );
    addTearDown(container.dispose);

    final notifier = container.read(chatNotifierProvider.notifier);
    final firstSend = notifier.sendMessage('Explain the plan');
    for (var i = 0; i < 10 && dataSource.requests.isEmpty; i += 1) {
      await Future<void>.delayed(Duration.zero);
    }
    await notifier.sendMessage('Never mind this one', interrupt: true);
    final steerId = notifier.state.steeringMessages.single.id;

    notifier.removeQueuedMessage(steerId);
    expect(notifier.state.steeringMessages, isEmpty);

    firstTurn.add('Here is the plan.');
    await firstTurn.close();
    await firstSend;
    for (var i = 0; i < 10; i += 1) {
      await Future<void>.delayed(Duration.zero);
    }

    // Withdrawn before any request carried it, so it neither joined the turn
    // nor came back through the queue.
    expect(dataSource.requests, hasLength(1));
    expect(notifier.state.queuedMessages, isEmpty);
    expect(
      notifier.state.messages
          .where((message) => message.role == MessageRole.user)
          .map((message) => message.content),
      ['Explain the plan'],
    );
  });
}

class ChatTurnOwnerRecord {
  const ChatTurnOwnerRecord(this.owner, this.pendingAtRegistration);

  final Object? owner;
  final int pendingAtRegistration;
}

ProviderContainer _buildContainer({
  required SettingsNotifier Function() settings,
  required ChatDataSource dataSource,
  required _FakeMcpToolService? toolService,
  required AppLifecycleService appLifecycleService,
}) {
  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(settings),
      conversationsNotifierProvider.overrideWith(
        _TestConversationsNotifier.new,
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
}

class _ToolEnabledSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings.defaults().copyWith(
    assistantMode: AssistantMode.general,
    mcpEnabled: true,
    demoMode: false,
  );
}

class _NoToolSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings.defaults().copyWith(
    assistantMode: AssistantMode.general,
    mcpEnabled: false,
    demoMode: false,
  );
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

    final now = DateTime(2026, 8, 7, 10);
    final conversation = Conversation(
      id: 'steering-conversation',
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
  Future<void> ensureCurrentPlanArtifactBackfilled({
    String? conversationId,
  }) async {}
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
  }) => null;

  @override
  Future<MemoryUpdateResult> updateFromConversation({
    required String conversationId,
    required List<Message> messages,
    DateTime? now,
    MemoryExtractionDraft? draft,
  }) async => const MemoryUpdateResult.none();

  @override
  UserMemoryProfile loadProfile() => UserMemoryProfile.empty();
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
  void Function()? onExecute;

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
    onExecute?.call();
    return McpToolResult(
      toolName: name,
      result: results[name] ?? '',
      isSuccess: true,
    );
  }
}

class _ToolLoopChatDataSource implements ChatDataSource {
  _ToolLoopChatDataSource({required this.initialToolCalls});

  final List<ToolCallInfo> initialToolCalls;
  final List<List<Message>> initialRequestMessages = [];
  final List<List<Message>> toolResultRequestMessages = [];

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return StreamedChatCompletion.fromStream(
      Stream<String>.fromIterable(const ['Combined tool summary']),
      finishReason: 'stop',
    );
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
      ChatCompletionResult(content: '', finishReason: 'stop'),
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
    return ChatCompletionResult(content: '', finishReason: 'stop');
  }
}

class _ControllableQueueChatDataSource implements ChatDataSource {
  _ControllableQueueChatDataSource(this.controllers);

  final Queue<StreamController<String>> controllers;
  final List<List<Message>> requests = [];

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    requests.add(List<Message>.from(messages));
    return StreamedChatCompletion.fromStream(
      controllers.removeFirst().stream,
      finishReason: 'stop',
    );
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
      ChatCompletionResult(content: '', finishReason: 'stop'),
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
