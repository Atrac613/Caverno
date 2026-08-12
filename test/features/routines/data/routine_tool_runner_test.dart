import 'dart:async';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/routines/data/routine_tool_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const messages = <Message>[];
  const tools = <Map<String, dynamic>>[
    {
      'type': 'function',
      'function': {'name': 'read_file'},
    },
  ];

  test(
    'explicit turn budget can exceed the legacy routine loop limit',
    () async {
      final dataSource = _SequentialToolCallDataSource(toolResponses: 11);
      final dispatched = <String>[];
      final runner = RoutineToolRunner(
        dataSource: dataSource,
        maxTurns: 12,
        maxToolCalls: 100,
      );

      await runner.execute(
        messages: messages,
        tools: tools,
        dispatchToolCall: (toolCall) async {
          dispatched.add(toolCall.id);
          return McpToolResult(
            toolName: toolCall.name,
            result: 'ok',
            isSuccess: true,
          );
        },
        model: 'model',
        temperature: 0.2,
        maxTokens: 1024,
      );

      expect(dataSource.requestCount, 12);
      expect(dispatched, hasLength(11));
      expect(dispatched, contains('tool-9'));
    },
  );

  test('explicit turn and tool-call caps remain hard upper bounds', () async {
    final turnLimitedSource = _SequentialToolCallDataSource(toolResponses: 20);
    var turnLimitedDispatches = 0;
    await RoutineToolRunner(
      dataSource: turnLimitedSource,
      maxTurns: 4,
      maxToolCalls: 100,
    ).execute(
      messages: messages,
      tools: tools,
      dispatchToolCall: (toolCall) async {
        turnLimitedDispatches += 1;
        return McpToolResult(
          toolName: toolCall.name,
          result: 'ok',
          isSuccess: true,
        );
      },
      model: 'model',
      temperature: 0.2,
      maxTokens: 1024,
    );

    final toolLimitedSource = _SequentialToolCallDataSource(toolResponses: 20);
    var toolLimitedDispatches = 0;
    await RoutineToolRunner(
      dataSource: toolLimitedSource,
      maxTurns: 12,
      maxToolCalls: 3,
    ).execute(
      messages: messages,
      tools: tools,
      dispatchToolCall: (toolCall) async {
        toolLimitedDispatches += 1;
        return McpToolResult(
          toolName: toolCall.name,
          result: 'ok',
          isSuccess: true,
        );
      },
      model: 'model',
      temperature: 0.2,
      maxTokens: 1024,
    );

    expect(turnLimitedSource.requestCount, 4);
    expect(turnLimitedDispatches, 4);
    expect(toolLimitedDispatches, 3);
  });

  test(
    'default runner retains the legacy five plus three loop bounds',
    () async {
      final dataSource = _SequentialToolCallDataSource(toolResponses: 20);
      var dispatches = 0;

      await RoutineToolRunner(dataSource: dataSource).execute(
        messages: messages,
        tools: tools,
        dispatchToolCall: (toolCall) async {
          dispatches += 1;
          return McpToolResult(
            toolName: toolCall.name,
            result: 'ok',
            isSuccess: true,
          );
        },
        model: 'model',
        temperature: 0.2,
        maxTokens: 1024,
      );

      expect(dispatches, 8);
    },
  );
}

class _SequentialToolCallDataSource extends ChatDataSource {
  _SequentialToolCallDataSource({required this.toolResponses});

  final int toolResponses;
  int requestCount = 0;

  ChatCompletionResult _next() {
    requestCount += 1;
    if (requestCount > toolResponses) {
      return ChatCompletionResult(content: 'done', finishReason: 'stop');
    }
    return ChatCompletionResult(
      content: '',
      finishReason: 'tool_calls',
      toolCalls: [
        ToolCallInfo(
          id: 'tool-$requestCount',
          name: 'read_file',
          arguments: {'path': 'file-$requestCount'},
        ),
      ],
    );
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async => _next();

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
  }) async => _next();

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => StreamedChatCompletion.fromStream(const Stream.empty());

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
  }) => const Stream.empty();
}
