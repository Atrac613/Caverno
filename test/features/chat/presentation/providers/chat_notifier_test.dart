import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

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

class _ToolBatchChatDataSource implements ChatDataSource {
  _ToolBatchChatDataSource({required this.initialToolCalls});

  final List<ToolCallInfo> initialToolCalls;
  final List<List<ToolResultInfo>> toolResultBatches = [];
  List<Message> finalAnswerMessages = const [];

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async* {
    finalAnswerMessages = List<Message>.from(messages);
    yield 'Combined tool summary';
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
    return ChatCompletionResult(content: '', finishReason: 'stop');
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

class _FakeMcpToolService extends McpToolService {
  _FakeMcpToolService({required this.results});

  final Map<String, String> results;
  final List<String> executedToolNames = [];

  @override
  Future<void> connect({
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return results.keys
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
    return McpToolResult(
      toolName: name,
      result: results[name] ?? '',
      isSuccess: true,
    );
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
    'sendMessage ignores new user input while a reply is in flight',
    () async {
      await notifier.sendMessage('First request');
      await notifier.sendMessage('Second request');

      final userMessages = notifier.state.messages
          .where((message) => message.role == MessageRole.user)
          .map((message) => message.content)
          .toList();

      expect(notifier.state.isLoading, isTrue);
      expect(userMessages, ['First request']);
      expect(notifier.state.messages, hasLength(2));
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
        contains('[Result of read_alpha]'),
      );
      expect(
        toolDataSource.finalAnswerMessages.last.content,
        contains('[Result of read_beta]'),
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
}
