import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/data/datasources/mcp_tool_service.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/routines/data/routine_execution_service.dart';
import 'package:caverno/features/routines/domain/entities/routine.dart';
import 'package:caverno/features/settings/domain/entities/app_settings.dart';

void main() {
  Routine buildRoutine({bool toolsEnabled = false}) {
    final now = DateTime(2026, 4, 21, 10);
    return Routine(
      id: 'routine-1',
      name: 'Morning summary',
      prompt: 'Summarize the latest updates.',
      createdAt: now,
      updatedAt: now,
      toolsEnabled: toolsEnabled,
    );
  }

  group('RoutineExecutionService', () {
    test('falls back to plain chat when tools are disabled', () async {
      final dataSource = _FakeChatDataSource(
        plainResults: [
          ChatCompletionResult(content: 'Plain answer', finishReason: 'stop'),
        ],
      );
      final toolService = _FakeMcpToolService(
        definitions: [_toolDefinition('web_search', 'Search the web')],
        resultsByToolName: const {},
      );
      final service = RoutineExecutionService(
        dataSource: dataSource,
        mcpToolService: toolService,
        settings: AppSettings.defaults(),
      );

      final record = await service.execute(buildRoutine());

      expect(record.isSuccessful, isTrue);
      expect(record.output, 'Plain answer');
      expect(record.usedTools, isFalse);
      expect(record.toolCallCount, 0);
      expect(dataSource.toolRequestNames, isEmpty);
      expect(toolService.executedCalls, isEmpty);
    });

    test('uses read-only tools when routine tools are enabled', () async {
      final dataSource = _FakeChatDataSource(
        initialToolAwareResult: ChatCompletionResult(
          content: 'Looking up the latest weather',
          toolCalls: [
            ToolCallInfo(
              id: 'tool-1',
              name: 'web_search',
              arguments: const {'query': 'tokyo weather'},
            ),
          ],
          finishReason: 'tool_calls',
        ),
        toolLoopResult: ChatCompletionResult(
          content: 'Collected tool results',
          finishReason: 'stop',
        ),
        plainResults: [
          ChatCompletionResult(
            content: 'Tokyo will be sunny today.',
            finishReason: 'stop',
          ),
        ],
      );
      final toolService = _FakeMcpToolService(
        definitions: [
          _toolDefinition('web_search', 'Search the web'),
          _toolDefinition('write_file', 'Write a file'),
        ],
        resultsByToolName: {
          'web_search': const McpToolResult(
            toolName: 'web_search',
            result: '{"results":[{"title":"Forecast"}]}',
            isSuccess: true,
          ),
        },
      );
      final service = RoutineExecutionService(
        dataSource: dataSource,
        mcpToolService: toolService,
        settings: AppSettings.defaults(),
      );

      final record = await service.execute(
        buildRoutine(toolsEnabled: true),
        trigger: RoutineRunTrigger.scheduled,
      );

      expect(record.isSuccessful, isTrue);
      expect(record.output, 'Tokyo will be sunny today.');
      expect(record.usedTools, isTrue);
      expect(record.toolCallCount, 1);
      expect(record.toolNames, ['web_search']);
      expect(dataSource.toolRequestNames, ['web_search']);
      expect(dataSource.createChatCompletionWithToolResultsCallCount, 1);
      expect(toolService.executedCalls, hasLength(1));
      expect(toolService.executedCalls.single.name, 'web_search');
      expect(toolService.executedCalls.single.arguments, {
        'query': 'tokyo weather',
      });
    });
  });
}

Map<String, dynamic> _toolDefinition(String name, String description) => {
  'type': 'function',
  'function': {
    'name': name,
    'description': description,
    'parameters': const {'type': 'object', 'properties': {}},
  },
};

class _FakeChatDataSource implements ChatDataSource {
  _FakeChatDataSource({
    this.initialToolAwareResult,
    this.toolLoopResult,
    List<ChatCompletionResult> plainResults = const [],
  }) : _plainResults = Queue<ChatCompletionResult>.from(plainResults);

  final ChatCompletionResult? initialToolAwareResult;
  final ChatCompletionResult? toolLoopResult;
  final Queue<ChatCompletionResult> _plainResults;

  List<String> toolRequestNames = const [];
  int createChatCompletionWithToolResultsCallCount = 0;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    if (tools != null && tools.isNotEmpty) {
      toolRequestNames = tools
          .map((tool) => (tool['function'] as Map<String, dynamic>)['name'])
          .whereType<String>()
          .toList(growable: false);
      return initialToolAwareResult ??
          ChatCompletionResult(content: '', finishReason: 'stop');
    }

    if (_plainResults.isEmpty) {
      return ChatCompletionResult(content: '', finishReason: 'stop');
    }
    return _plainResults.removeFirst();
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
    createChatCompletionWithToolResultsCallCount += 1;
    return toolLoopResult ??
        ChatCompletionResult(content: '', finishReason: 'stop');
  }

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
}

class _FakeMcpToolService extends McpToolService {
  _FakeMcpToolService({
    required this.definitions,
    required this.resultsByToolName,
  });

  final List<Map<String, dynamic>> definitions;
  final Map<String, McpToolResult> resultsByToolName;
  final List<_ExecutedToolCall> executedCalls = [];

  @override
  List<Map<String, dynamic>> getOpenAiToolDefinitions() => definitions;

  @override
  Future<McpToolResult> executeTool({
    required String name,
    required Map<String, dynamic> arguments,
  }) async {
    executedCalls.add(_ExecutedToolCall(name: name, arguments: arguments));
    return resultsByToolName[name] ??
        McpToolResult(
          toolName: name,
          result: '',
          isSuccess: false,
          errorMessage: 'Tool result not stubbed',
        );
  }
}

class _ExecutedToolCall {
  const _ExecutedToolCall({required this.name, required this.arguments});

  final String name;
  final Map<String, dynamic> arguments;
}
