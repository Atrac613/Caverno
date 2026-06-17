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
import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/data/repositories/chat_memory_repository.dart';
import 'package:caverno/features/chat/data/repositories/tool_result_artifact_store.dart';
import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/session_memory.dart';
import 'package:caverno/features/chat/domain/services/session_memory_service.dart';
import 'package:caverno/features/chat/presentation/providers/chat_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/coding_projects_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/conversations_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/mcp_tool_provider.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';

const _marker = 'COMPACT_BUDGET_LIVE_OK';

void main() {
  final liveEnabled =
      Platform.environment['CAVERNO_TOOL_RESULT_BUDGET_LIVE_CANARY'] == '1';

  test(
    'live LLM answers from compacted oversized tool results after retry',
    () async {
      final baseUrl = _requiredEnv('CAVERNO_LLM_BASE_URL');
      final apiKey = _requiredEnv('CAVERNO_LLM_API_KEY');
      final model = _requiredEnv('CAVERNO_LLM_MODEL');
      final maxTokens =
          int.tryParse(
            Platform.environment['CAVERNO_TOOL_RESULT_BUDGET_MAX_TOKENS'] ?? '',
          ) ??
          2048;
      final temperature =
          double.tryParse(
            Platform.environment['CAVERNO_TOOL_RESULT_BUDGET_TEMPERATURE'] ??
                '',
          ) ??
          0.1;

      final delegate = ChatRemoteDataSource(baseUrl: baseUrl, apiKey: apiKey);
      final dataSource = _BudgetLiveDataSource(delegate);
      final toolService = _LargeReadFileToolService();
      final tempDir = await Directory.systemTemp.createTemp(
        'caverno_tool_result_budget_canary_',
      );
      final appLifecycleService = _MockAppLifecycleService();
      when(() => appLifecycleService.isInBackground).thenReturn(false);
      final container = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            () => _LiveSettingsNotifier(
              baseUrl: baseUrl,
              apiKey: apiKey,
              model: model,
              maxTokens: maxTokens,
              temperature: temperature,
            ),
          ),
          conversationsNotifierProvider.overrideWith(
            _LiveConversationsNotifier.new,
          ),
          codingProjectsNotifierProvider.overrideWith(
            _LiveCodingProjectsNotifier.new,
          ),
          chatRemoteDataSourceProvider.overrideWithValue(dataSource),
          sessionMemoryServiceProvider.overrideWithValue(
            _NoopSessionMemoryService(),
          ),
          toolResultArtifactStoreProvider.overrideWithValue(
            ToolResultArtifactStore(baseDirectory: tempDir),
          ),
          mcpToolServiceProvider.overrideWithValue(toolService),
          appLifecycleServiceProvider.overrideWithValue(appLifecycleService),
          backgroundTaskServiceProvider.overrideWithValue(
            _NoopBackgroundTaskService(),
          ),
          notificationServiceProvider.overrideWithValue(
            _NoopNotificationService(),
          ),
        ],
      );

      try {
        final notifier = container.read(chatNotifierProvider.notifier);

        await notifier.sendMessage(
          'Use read_file to inspect large_canary.txt. '
          'Answer with only the canary marker value found in the file.',
        );

        final finalContent = container
            .read(chatNotifierProvider)
            .messages
            .last
            .content;
        expect(
          dataSource.toolResultBatches,
          hasLength(greaterThanOrEqualTo(2)),
          reason: _diagnostic(dataSource, toolService, finalContent),
        );
        expect(
          dataSource.toolResultBatches.first.single.result.length,
          greaterThan(dataSource.toolResultBatches[1].single.result.length),
        );
        expect(
          dataSource.toolResultBatches[1].single.result,
          anyOf(
            contains('content_reduced_for_prompt_budget'),
            contains('reduced to fit the prompt budget'),
          ),
        );
        expect(
          finalContent.toUpperCase(),
          contains(_marker),
          reason: _diagnostic(dataSource, toolService, finalContent),
        );
      } finally {
        container.dispose();
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
    },
    skip: liveEnabled
        ? false
        : 'Set CAVERNO_TOOL_RESULT_BUDGET_LIVE_CANARY=1 and CAVERNO_LLM_* to run.',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

String _requiredEnv(String name) {
  final value = Platform.environment[name]?.trim();
  if (value == null || value.isEmpty) {
    throw StateError('$name is required for live LLM validation.');
  }
  return value;
}

String _diagnostic(
  _BudgetLiveDataSource dataSource,
  _LargeReadFileToolService toolService,
  String finalContent,
) {
  return [
    'toolResultCalls=${dataSource.toolResultBatches.length}',
    'toolResultLengths=${dataSource.toolResultBatches.map((batch) => batch.single.result.length).join(',')}',
    'finalAnswerRequests=${dataSource.finalAnswerMessages.length}',
    'executedToolNames=${toolService.executedToolNames.join(',')}',
    'executedArguments=${toolService.executedArguments.map(jsonEncode).join(' | ')}',
    'finalContent=$finalContent',
  ].join('\n');
}

class _LiveSettingsNotifier extends SettingsNotifier {
  _LiveSettingsNotifier({
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

  @override
  AppSettings build() {
    return AppSettings.defaults().copyWith(
      assistantMode: AssistantMode.general,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
      mcpEnabled: true,
      demoMode: false,
    );
  }
}

class _LiveConversationsNotifier extends ConversationsNotifier {
  @override
  ConversationsState build() => ConversationsState.initial();

  @override
  Conversation? ensureCurrentConversation({
    WorkspaceMode? workspaceMode,
    String? projectId,
  }) {
    return null;
  }

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
  _NoopSessionMemoryService()
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

class _BudgetLiveDataSource implements ChatDataSource {
  _BudgetLiveDataSource(this.delegate);

  final ChatRemoteDataSource delegate;
  final List<List<ToolResultInfo>> toolResultBatches = [];
  final List<List<Message>> finalAnswerMessages = [];

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    return StreamWithToolsResult(
      stream: const Stream<String>.empty(),
      completion: Future<ChatCompletionResult>.value(
        ChatCompletionResult(
          content: 'I will inspect the large canary file.',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-read-large-canary',
              name: 'read_file',
              arguments: const {'path': 'large_canary.txt'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
      ),
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
    toolResultBatches.add(List<ToolResultInfo>.from(toolResults));
    if (toolResultBatches.length == 1) {
      throw StateError(
        'This model has a maximum context length of 8192 tokens',
      );
    }
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
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    finalAnswerMessages.add(List<Message>.from(messages));
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
    return delegate.createChatCompletion(
      messages: messages,
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

class _LargeReadFileToolService extends McpToolService {
  _LargeReadFileToolService() : _lines = _buildLines();

  final List<String> _lines;
  final List<String> executedToolNames = [];
  final List<Map<String, dynamic>> executedArguments = [];

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
          'name': 'read_file',
          'description':
              'Read a UTF-8 text file. Use offset and limit to inspect an exact line range when a previous result was reduced.',
          'parameters': const {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'offset': {'type': 'integer'},
              'limit': {'type': 'integer'},
            },
            'required': ['path'],
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
    executedArguments.add(Map<String, dynamic>.from(arguments));
    if (name != 'read_file') {
      return McpToolResult(
        toolName: name,
        result: jsonEncode({'error': 'Unsupported tool: $name'}),
        isSuccess: false,
        errorMessage: 'Unsupported tool: $name',
      );
    }

    final offset = (arguments['offset'] as num?)?.toInt() ?? 1;
    final limit = (arguments['limit'] as num?)?.toInt();
    final startIndex = offset <= 1 ? 0 : offset - 1;
    final endIndex = limit == null
        ? _lines.length
        : (startIndex + limit).clamp(0, _lines.length);
    final selectedLines = startIndex >= _lines.length
        ? const <String>[]
        : _lines.sublist(startIndex, endIndex);
    final content = selectedLines.join('\n');
    final fullContent = _lines.join('\n');
    return McpToolResult(
      toolName: name,
      result: jsonEncode({
        'path': '/tmp/large_canary.txt',
        'content': content,
        'size_bytes': utf8.encode(fullContent).length,
        'start_line': selectedLines.isEmpty ? offset : startIndex + 1,
        'line_count': selectedLines.length,
        'total_lines': _lines.length,
        if (offset > 1) 'offset': offset,
        ...switch (limit) {
          null => const <String, dynamic>{},
          final value => {'limit': value},
        },
        if (endIndex < _lines.length) 'truncated': true,
      }),
      isSuccess: true,
    );
  }

  static List<String> _buildLines() {
    return [
      for (var index = 1; index <= 1795; index += 1)
        'padding line $index: this line exists only to force prompt budgeting.',
      'CANARY_MARKER: $_marker',
      for (var index = 1796; index <= 1800; index += 1)
        'tail padding line $index: this line follows the canary marker.',
    ];
  }
}
