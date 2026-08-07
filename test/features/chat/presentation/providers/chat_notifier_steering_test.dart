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

  test('a steer past the restart budget falls back to the queue', () async {
    final controllers = [
      for (var i = 0; i < 4; i += 1) StreamController<String>(),
    ];
    final dataSource = _ControllableQueueChatDataSource(
      Queue<StreamController<String>>.from(controllers),
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

    Future<void> settle([int ticks = 30]) async {
      for (var i = 0; i < ticks; i += 1) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    final notifier = container.read(chatNotifierProvider.notifier);
    final firstSend = notifier.sendMessage('Explain the plan');
    await settle();

    // Two restarts are the budget; the third steer has nowhere to go.
    controllers[0].add('First attempt');
    await settle();
    await notifier.sendMessage('Shorter', interrupt: true);
    await settle();
    controllers[1].add('Second attempt');
    await settle();
    await notifier.sendMessage('Shorter still', interrupt: true);
    await settle();
    controllers[2].add('Third attempt');
    await settle();
    await notifier.sendMessage('One line only', interrupt: true);
    await settle();

    expect(dataSource.requests, hasLength(3));
    // Refused, not dropped: it is still pending and owed back to the queue.
    expect(notifier.state.steeringMessages.map((message) => message.content), [
      'One line only',
    ]);

    await controllers[2].close();
    await firstSend;
    await settle();
    controllers[3].add('Final.');
    await controllers[3].close();
    await settle();

    // The refused steer came back as its own turn rather than being lost.
    expect(dataSource.requests, hasLength(4));
    expect(notifier.state.steeringMessages, isEmpty);
    expect(notifier.state.queuedMessages, isEmpty);
    expect(
      notifier.state.messages
          .where((message) => message.role == MessageRole.user)
          .map((message) => message.content),
      ['Explain the plan', 'Shorter', 'Shorter still', 'One line only'],
    );
    for (final controller in controllers) {
      if (!controller.isClosed) unawaited(controller.close());
    }
  });

  test('an interruption mid-stream restarts the same turn', () async {
    final firstTurn = StreamController<String>();
    final restarted = StreamController<String>();
    final dataSource = _ControllableQueueChatDataSource(
      Queue<StreamController<String>>.from([firstTurn, restarted]),
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

    // Mid-stream: the reply is already being written, which is the moment a
    // user reacts to it and the moment no further request is planned.
    firstTurn.add('Here is the long plan, starting with');
    await Future<void>.delayed(Duration.zero);
    await notifier.sendMessage('Keep it under 3 lines', interrupt: true);
    for (var i = 0; i < 40 && dataSource.requests.length < 2; i += 1) {
      await Future<void>.delayed(Duration.zero);
    }

    // The turn made its own second request rather than waiting for one.
    expect(dataSource.requests, hasLength(2));
    final restartedRequest = dataSource.requests.last;
    expect(
      restartedRequest
          .where((message) => message.role == MessageRole.user)
          .map((message) => message.content),
      contains('Keep it under 3 lines'),
    );
    expect(
      restartedRequest
          .where((message) => message.role == MessageRole.system)
          .map((message) => message.content)
          .join('\n'),
      contains(TurnSteeringPromptBuilder.marker),
    );

    restarted.add('Short version.');
    await restarted.close();
    unawaited(firstTurn.close());
    await firstSend;
    for (var i = 0; i < 20; i += 1) {
      await Future<void>.delayed(Duration.zero);
    }

    // What was streamed before the cut is kept, and the interruption sits
    // after it rather than before the reply it interrupted.
    final contents = notifier.state.messages
        .map((message) => '${message.role.name}:${message.content}')
        .toList(growable: false);
    expect(contents, [
      'user:Explain the plan',
      'assistant:Here is the long plan, starting with',
      'user:Keep it under 3 lines',
      'assistant:Short version.',
    ]);
    expect(notifier.state.steeringMessages, isEmpty);
    expect(notifier.state.queuedMessages, isEmpty);
  });

  test('an interruption on a tools-off turn does not switch tools on', () async {
    final firstTurn = StreamController<String>();
    final restarted = StreamController<String>();
    final dataSource = _ControllableQueueChatDataSource(
      Queue<StreamController<String>>.from([firstTurn, restarted]),
    );
    final appLifecycleService = _MockAppLifecycleService();
    when(() => appLifecycleService.isInBackground).thenReturn(false);
    final container = _buildContainer(
      settings: _NoToolSettingsNotifier.new,
      // Production always provides the service so built-in tools stay
      // available; the mcpEnabled switch is the only thing keeping its catalog
      // out of a request. A null service here would test the one arrangement
      // in which this cannot go wrong.
      toolService: _FakeMcpToolService(results: const {'read_alpha': 'alpha'}),
      dataSource: dataSource,
      appLifecycleService: appLifecycleService,
    );
    addTearDown(container.dispose);

    final notifier = container.read(chatNotifierProvider.notifier);
    final firstSend = notifier.sendMessage('Explain the plan');
    for (var i = 0; i < 10 && dataSource.requests.isEmpty; i += 1) {
      await Future<void>.delayed(Duration.zero);
    }

    firstTurn.add('Here is the long plan, starting with');
    await Future<void>.delayed(Duration.zero);
    await notifier.sendMessage('Keep it under 3 lines', interrupt: true);
    for (var i = 0; i < 40 && dataSource.requests.length < 2; i += 1) {
      await Future<void>.delayed(Duration.zero);
    }

    // Restarted, and still the turn the user asked for: an interruption is not
    // consent to a setting they switched off.
    expect(dataSource.requests, hasLength(2));
    expect(dataSource.toolAwareRequestTools, isEmpty);

    restarted.add('Short version.');
    await restarted.close();
    unawaited(firstTurn.close());
    await firstSend;
    for (var i = 0; i < 20; i += 1) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(notifier.state.steeringMessages, isEmpty);
    expect(notifier.state.queuedMessages, isEmpty);
  });

  test('a finished stream does not restart a turn that is running a tool', () async {
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
      settings: _MutableToolSettingsNotifier.new,
      dataSource: toolDataSource,
      toolService: toolService,
      appLifecycleService: appLifecycleService,
    );
    addTearDown(container.dispose);

    final notifier = container.read(chatNotifierProvider.notifier);
    final settings =
        container.read(settingsNotifierProvider.notifier)
            as _MutableToolSettingsNotifier;

    // A completed tool-free turn, which is what leaves a stream subscription
    // behind: nothing cancels one that ended on its own.
    await notifier.sendMessage('Explain the plan');
    for (var i = 0; i < 20; i += 1) {
      await Future<void>.delayed(Duration.zero);
    }
    settings.setMcpEnabled(true);

    // The next turn is tool-aware and consumes its stream through the loop, so
    // no subscription of its own is ever stored. While its tool runs it has a
    // request still to come, and the interruption belongs in that request.
    Future<void>? steerResult;
    toolService.onExecute = () {
      steerResult ??= notifier.sendMessage(
        'Use beta.txt instead',
        interrupt: true,
      );
    };
    await notifier.sendMessage('Inspect alpha');
    await steerResult;
    for (var i = 0; i < 20; i += 1) {
      await Future<void>.delayed(Duration.zero);
    }

    // One opening request, not two: the turn was never streaming, so there was
    // nothing to abandon and restart.
    expect(toolDataSource.initialRequestMessages, hasLength(1));

    // And the steer still arrives -- through the window the turn actually had.
    expect(
      toolDataSource.toolResultRequestMessages.single
          .where((message) => message.role == MessageRole.user)
          .map((message) => message.content),
      contains('Use beta.txt instead'),
    );
    expect(notifier.state.steeringMessages, isEmpty);
    expect(notifier.state.queuedMessages, isEmpty);
  });

  test('a withdrawn interruption never reaches the model', () async {
    // Registered while a tool runs, so no stream is being consumed and the
    // steer stays pending instead of restarting the turn -- which is the only
    // state a withdrawal can act on.
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
    var withdrew = false;
    toolService.onExecute = () {
      if (withdrew) return;
      withdrew = true;
      unawaited(notifier.sendMessage('Never mind this one', interrupt: true));
      final pending = notifier.state.steeringMessages.single;
      notifier.removeQueuedMessage(pending.id);
    };

    await notifier.sendMessage('Inspect alpha');

    expect(withdrew, isTrue);
    expect(notifier.state.steeringMessages, isEmpty);
    expect(notifier.state.queuedMessages, isEmpty);
    final followUp = toolDataSource.toolResultRequestMessages.single;
    expect(
      followUp.map((message) => message.content).join('\n'),
      isNot(contains('Never mind this one')),
    );
    expect(
      followUp.map((message) => message.content).join('\n'),
      isNot(contains(TurnSteeringPromptBuilder.marker)),
    );
    expect(
      notifier.state.messages
          .where((message) => message.role == MessageRole.user)
          .map((message) => message.content),
      ['Inspect alpha'],
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

class _MutableToolSettingsNotifier extends SettingsNotifier {
  @override
  AppSettings build() => AppSettings.defaults().copyWith(
    assistantMode: AssistantMode.general,
    mcpEnabled: false,
    demoMode: false,
  );

  /// Flips the switch without the repository write the real setter performs.
  void setMcpEnabled(bool enabled) {
    state = state.copyWith(mcpEnabled: enabled);
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

  /// Tool-aware requests this data source was asked for.
  ///
  /// Recorded rather than thrown: a turn that wrongly becomes tool-aware
  /// should fail an expectation, not raise an error the notifier catches and
  /// turns into an ordinary failed turn.
  final List<List<Map<String, dynamic>>> toolAwareRequestTools = [];

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
    toolAwareRequestTools.add(List<Map<String, dynamic>>.from(tools));
    requests.add(List<Message>.from(messages));
    return StreamWithToolsResult(
      stream: const Stream.empty(),
      completion: Future<ChatCompletionResult>.value(
        ChatCompletionResult(content: '', finishReason: 'stop'),
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
