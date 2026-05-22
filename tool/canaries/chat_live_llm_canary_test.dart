import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mocktail/mocktail.dart';

import 'package:caverno/core/services/app_lifecycle_service.dart';
import 'package:caverno/core/services/background_task_service.dart';
import 'package:caverno/core/services/notification_providers.dart';
import 'package:caverno/core/services/notification_service.dart';
import 'package:caverno/core/types/assistant_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/memory_extraction_draft_service.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

const _basicMarker = 'CHAT_BASIC_LIVE_OK';
const _embeddedMarker = 'EMBEDDED_TOOL_LIVE_OK';

void main() {
  final liveEnabled = Platform.environment['CAVERNO_CHAT_LIVE_CANARY'] == '1';

  test(
    'live LLM produces a plain chat response without tools',
    () async {
      final env = _ChatLiveEnv.fromEnvironment();
      final container = _buildChatContainer(
        env,
        mcpEnabled: false,
        toolService: _NoToolsMcpToolService(),
      );

      try {
        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Reply with exactly $_basicMarker and no extra text.',
        );
        await _waitForChatIdle(container);

        final content = _lastAssistantContent(container);
        expect(
          content.toUpperCase(),
          contains(_basicMarker),
          reason: _chatDiagnostic(container),
        );
      } finally {
        container.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CHAT_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'live LLM memory extraction returns parseable bounded memory',
    () async {
      final env = _ChatLiveEnv.fromEnvironment();
      final dataSource = ChatRemoteDataSource(
        baseUrl: env.baseUrl,
        apiKey: env.apiKey,
      );
      final now = DateTime(2026, 5, 22, 10, 0);
      final messages = [
        Message(
          id: 'memory_canary_user',
          role: MessageRole.user,
          timestamp: now,
          content:
              'My standing preference is concise English summaries. '
              'I bought a model canary notebook for 1200 yen on 2026-05-22.',
        ),
        Message(
          id: 'memory_canary_assistant',
          role: MessageRole.assistant,
          timestamp: now,
          content: 'Understood.',
        ),
      ];
      final extractionInput = MemoryExtractionDraftService.buildInput(
        messages,
        UserMemoryProfile.empty(),
      );

      final result = await dataSource.createChatCompletion(
        messages: [
          Message(
            id: 'memory_canary_system',
            role: MessageRole.system,
            timestamp: now,
            content: MemoryExtractionDraftService.systemPrompt,
          ),
          Message(
            id: 'memory_canary_request',
            role: MessageRole.user,
            timestamp: now,
            content: extractionInput,
          ),
        ],
        model: env.model,
        temperature: 0.1,
        maxTokens: env.maxTokens > 1200 ? 1200 : env.maxTokens,
      );
      final draft = MemoryExtractionDraftService.parseDraft(result.content);
      expect(draft, isNotNull, reason: 'rawMemoryExtraction=${result.content}');

      final parsed = draft!;
      final combined = [
        parsed.summary,
        ...parsed.persona,
        ...parsed.preferences,
        ...parsed.doNot,
        ...parsed.entries.map((entry) => entry.text),
      ].join('\n').toLowerCase();
      expect(combined, contains('concise'));
      expect(combined, contains('1200'));
      expect(parsed.summary.length, lessThanOrEqualTo(160));
      expect(parsed.entries.length, lessThanOrEqualTo(8));
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CHAT_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'live LLM embedded tool call executes once and exposes the result',
    () async {
      final env = _ChatLiveEnv.fromEnvironment();
      final toolService = _EchoMarkerToolService();
      final container = _buildChatContainer(
        env,
        mcpEnabled: false,
        toolService: toolService,
      );

      try {
        final notifier = container.read(chatNotifierProvider.notifier);
        await notifier.sendMessage(
          'Return exactly one content-embedded tool call and no markdown. '
          'Use this exact tool call: '
          '<tool_call>{"name":"echo_marker","arguments":{"marker":"$_embeddedMarker"}}</tool_call>. '
          'After the tool result is available, answer with $_embeddedMarker.',
        );
        await _waitForChatIdle(container);

        expect(toolService.executedToolNames, [
          _EchoMarkerToolService.toolName,
        ], reason: _chatDiagnostic(container));
        expect(
          _chatTranscript(container),
          contains(_embeddedMarker),
          reason: _chatDiagnostic(container),
        );
      } finally {
        container.dispose();
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_CHAT_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

ProviderContainer _buildChatContainer(
  _ChatLiveEnv env, {
  required bool mcpEnabled,
  required McpToolService toolService,
}) {
  final appLifecycleService = _MockAppLifecycleService();
  when(() => appLifecycleService.isInBackground).thenReturn(false);
  return ProviderContainer(
    overrides: [
      settingsNotifierProvider.overrideWith(
        () => _LiveSettingsNotifier(env: env, mcpEnabled: mcpEnabled),
      ),
      conversationsNotifierProvider.overrideWith(
        _LiveConversationsNotifier.new,
      ),
      codingProjectsNotifierProvider.overrideWith(
        _LiveCodingProjectsNotifier.new,
      ),
      chatRemoteDataSourceProvider.overrideWithValue(
        _ChatLiveDataSource(
          ChatRemoteDataSource(baseUrl: env.baseUrl, apiKey: env.apiKey),
        ),
      ),
      sessionMemoryServiceProvider.overrideWithValue(
        _NoopSessionMemoryService(),
      ),
      mcpToolServiceProvider.overrideWithValue(toolService),
      appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
      backgroundTaskServiceProvider.overrideWithValue(
        _NoopBackgroundTaskService(),
      ),
      notificationServiceProvider.overrideWithValue(_NoopNotificationService()),
    ],
  );
}

Future<void> _waitForChatIdle(
  ProviderContainer container, {
  Duration timeout = const Duration(minutes: 4),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final state = container.read(chatNotifierProvider);
    final hasFinishedAssistant = state.messages.any(
      (message) =>
          message.role == MessageRole.assistant && !message.isStreaming,
    );
    if (!state.isLoading && hasFinishedAssistant) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw TimeoutException(
    'Timed out waiting for chat live canary completion.\n'
    '${_chatDiagnostic(container)}',
  );
}

String _lastAssistantContent(ProviderContainer container) {
  final messages = container.read(chatNotifierProvider).messages;
  for (final message in messages.reversed) {
    if (message.role == MessageRole.assistant) {
      return message.content;
    }
  }
  return '';
}

String _chatTranscript(ProviderContainer container) {
  return container
      .read(chatNotifierProvider)
      .messages
      .map((message) => '${message.role.name}: ${message.content}')
      .join('\n');
}

String _chatDiagnostic(ProviderContainer container) {
  final state = container.read(chatNotifierProvider);
  return [
    'isLoading=${state.isLoading}',
    'error=${state.error}',
    'messages=${state.messages.length}',
    _chatTranscript(container),
  ].join('\n');
}

class _ChatLiveEnv {
  const _ChatLiveEnv({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    required this.maxTokens,
    required this.temperature,
  });

  final String baseUrl;
  final String apiKey;
  final String model;
  final int maxTokens;
  final double temperature;

  static _ChatLiveEnv fromEnvironment() {
    return _ChatLiveEnv(
      baseUrl: _requiredEnv('CAVERNO_LLM_BASE_URL'),
      apiKey: _requiredEnv('CAVERNO_LLM_API_KEY'),
      model: _requiredEnv('CAVERNO_LLM_MODEL'),
      maxTokens:
          int.tryParse(
            Platform.environment['CAVERNO_CHAT_LIVE_CANARY_MAX_TOKENS'] ?? '',
          ) ??
          2048,
      temperature:
          double.tryParse(
            Platform.environment['CAVERNO_CHAT_LIVE_CANARY_TEMPERATURE'] ?? '',
          ) ??
          0.1,
    );
  }
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('$name is required for chat live LLM validation.');
  }
  return value;
}

class _LiveSettingsNotifier extends SettingsNotifier {
  _LiveSettingsNotifier({required this.env, required this.mcpEnabled});

  final _ChatLiveEnv env;
  final bool mcpEnabled;

  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      baseUrl: env.baseUrl,
      apiKey: env.apiKey,
      model: env.model,
      temperature: env.temperature,
      maxTokens: env.maxTokens,
      mcpEnabled: mcpEnabled,
      demoMode: false,
    );
  }
}

class _LiveConversationsNotifier extends ConversationsNotifier {
  @override
  ConversationsState build() => ConversationsState.initial();

  @override
  Future<void> ensureCurrentPlanArtifactBackfilled() async {}

  @override
  Future<void> updateCurrentConversation(List<Message> messages) async {}
}

class _LiveCodingProjectsNotifier extends CodingProjectsNotifier {
  @override
  CodingProjectsState build() => CodingProjectsState.initial();
}

class _NoopBackgroundTaskService extends BackgroundTaskService {
  @override
  Future<void> beginBackgroundTask() async {}

  @override
  Future<void> endBackgroundTask() async {}

  @override
  void dispose() {}
}

class _NoopNotificationService extends NotificationService {
  @override
  Future<void> init() async {}

  @override
  Future<void> showResponseCompleteNotification(
    String title,
    String body,
  ) async {}
}

class _MockMemoryBox extends Mock implements Box<String> {}

class _MockAppLifecycleService extends Mock implements AppLifecycleService {}

class _NoopSessionMemoryService extends SessionMemoryService {
  _NoopSessionMemoryService() : super(ChatMemoryRepository(_MockMemoryBox()));

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

class _ChatLiveDataSource implements ChatDataSource {
  _ChatLiveDataSource(this.delegate);

  final ChatRemoteDataSource delegate;

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return delegate.streamChatCompletion(
      messages: messages,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
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
    final firstContent = messages.isEmpty ? '' : messages.first.content;
    if (firstContent.startsWith(
      'You extract reusable user memory from a conversation.',
    )) {
      return Future.value(
        ChatCompletionResult(
          content: jsonEncode(<String, dynamic>{
            'summary': '',
            'open_loops': const <String>[],
            'profile': <String, dynamic>{
              'persona': const <String>[],
              'preferences': const <String>[],
              'do_not': const <String>[],
            },
            'memories': const <Map<String, dynamic>>[],
          }),
          finishReason: 'stop',
        ),
      );
    }
    return delegate.createChatCompletion(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
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
    return delegate.streamChatCompletionWithTools(
      messages: messages,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
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
    return delegate.createChatCompletionWithToolResults(
      messages: messages,
      toolResults: toolResults,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
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
    return delegate.createChatCompletionWithToolResult(
      messages: messages,
      toolCallId: toolCallId,
      toolName: toolName,
      toolArguments: toolArguments,
      toolResult: toolResult,
      assistantContent: assistantContent,
      tools: tools,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
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
    return delegate.streamWithToolResult(
      messages: messages,
      toolCallId: toolCallId,
      toolName: toolName,
      toolArguments: toolArguments,
      toolResult: toolResult,
      assistantContent: assistantContent,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}

class _NoToolsMcpToolService extends McpToolService {
  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return const <Map<String, dynamic>>[];
  }

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    return McpToolResult(
      toolName: name,
      result: jsonEncode({'error': 'Tool is not available'}),
      isSuccess: false,
      errorMessage: 'Tool is not available',
    );
  }
}

class _EchoMarkerToolService extends McpToolService {
  static const toolName = 'echo_marker';

  final List<String> executedToolNames = [];

  @override
  Future<void> connect({
    List<McpServerConfig>? overrideServers,
    List<String>? overrideUrls,
    String? overrideUrl,
  }) async {}

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() {
    return const <Map<String, dynamic>>[
      {
        'type': 'function',
        'function': {
          'name': toolName,
          'description': 'Echo a canary marker for embedded tool validation.',
          'parameters': {
            'type': 'object',
            'properties': {
              'marker': {'type': 'string'},
            },
            'required': ['marker'],
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
    if (name != toolName) {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({'error': 'Unsupported tool'}),
        isSuccess: false,
        errorMessage: 'Unsupported tool',
      );
    }
    final marker = arguments['marker']?.toString() ?? '';
    return McpToolResult(
      toolName: name,
      result: jsonEncode({'marker': marker, 'ok': marker == _embeddedMarker}),
      isSuccess: marker == _embeddedMarker,
      errorMessage: marker == _embeddedMarker ? null : 'Unexpected marker',
    );
  }
}
