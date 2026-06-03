import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/subagent_task.dart';
import 'package:caverno/features/chat/domain/services/subagent_execution_service.dart';

/// Minimal [ChatDataSource] that returns a canned completion or throws.
///
/// Only [createChatCompletion] is exercised by the no-tool subagent path, so
/// the remaining abstract members fall back to safe stubs.
class _StubChatDataSource extends ChatDataSource {
  _StubChatDataSource({this.result, this.error});

  final ChatCompletionResult? result;
  final Object? error;
  int createChatCompletionCount = 0;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    createChatCompletionCount++;
    final error = this.error;
    if (error != null) {
      throw error;
    }
    return result!;
  }

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => const Stream<String>.empty();

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
  }) => const Stream<String>.empty();

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
  }) async => throw UnimplementedError();
}

void main() {
  group('SubagentExecutionService', () {
    test('returns a completed task with the model output as summary', () async {
      final dataSource = _StubChatDataSource(
        result: ChatCompletionResult(
          content: 'Subagent finished the analysis.',
          finishReason: 'stop',
        ),
      );
      final service = SubagentExecutionService(dataSource: dataSource);

      final task = await service.run(
        id: 'task-1',
        description: 'Analyze files',
        prompt: 'Summarize lib/core',
        tools: const <Map<String, dynamic>>[],
        dispatchToolCall: (_) async =>
            throw StateError('no tools should run in this scenario'),
        model: 'test-model',
        temperature: 0.7,
        maxTokens: 1024,
        parentToolUseId: 'call-42',
      );

      expect(task.status, SubagentTaskStatus.completed);
      expect(task.isTerminal, isTrue);
      expect(task.resultSummary, 'Subagent finished the analysis.');
      expect(task.id, 'task-1');
      expect(task.parentToolUseId, 'call-42');
      expect(dataSource.createChatCompletionCount, 1);
    });

    test('returns a failed task when the data source throws', () async {
      final dataSource = _StubChatDataSource(error: StateError('network down'));
      final service = SubagentExecutionService(dataSource: dataSource);

      final task = await service.run(
        id: 'task-2',
        description: 'Analyze files',
        prompt: 'Summarize lib/core',
        tools: const <Map<String, dynamic>>[],
        dispatchToolCall: (_) async => throw StateError('unused'),
        model: 'test-model',
        temperature: 0.7,
        maxTokens: 1024,
      );

      expect(task.status, SubagentTaskStatus.failed);
      expect(task.isTerminal, isTrue);
      expect(task.error, contains('network down'));
    });

    test('caps the summary so a runaway child cannot blow up context', () async {
      final dataSource = _StubChatDataSource(
        result: ChatCompletionResult(
          content: 'x' * 20000,
          finishReason: 'stop',
        ),
      );
      final service = SubagentExecutionService(dataSource: dataSource);

      final task = await service.run(
        id: 'task-cap',
        description: 'big output',
        prompt: 'produce a lot of text',
        tools: const <Map<String, dynamic>>[],
        dispatchToolCall: (_) async => throw StateError('no tools'),
        model: 'm',
        temperature: 0.7,
        maxTokens: 1024,
      );

      expect(task.status, SubagentTaskStatus.completed);
      expect(task.resultSummary.endsWith('...[truncated]'), isTrue);
      expect(task.resultSummary.length, lessThan(20000));
    });

    test('propagates the background flag onto the task', () async {
      final dataSource = _StubChatDataSource(
        result: ChatCompletionResult(content: 'done', finishReason: 'stop'),
      );
      final service = SubagentExecutionService(dataSource: dataSource);

      final task = await service.run(
        id: 'task-bg',
        description: 'bg',
        prompt: 'p',
        tools: const <Map<String, dynamic>>[],
        dispatchToolCall: (_) async => throw StateError('no tools'),
        model: 'm',
        temperature: 0.7,
        maxTokens: 1024,
        isBackground: true,
      );

      expect(task.isBackground, isTrue);
      expect(task.status, SubagentTaskStatus.completed);
    });

    test('runs the child tool loop through the injected dispatcher', () async {
      final dataSource = _ScriptedChatDataSource(
        completions: [
          ChatCompletionResult(
            content: '',
            toolCalls: [
              ToolCallInfo(
                id: 'c1',
                name: 'calc',
                arguments: const {'expr': '6*7'},
              ),
            ],
            finishReason: 'tool_calls',
          ),
          ChatCompletionResult(content: '42', finishReason: 'stop'),
        ],
        withToolResults: ChatCompletionResult(
          content: 'The calc tool returned 42.',
          finishReason: 'stop',
        ),
      );
      final dispatched = <String>[];
      final service = SubagentExecutionService(dataSource: dataSource);

      final task = await service.run(
        id: 'task-loop',
        description: 'compute',
        prompt: 'use calc',
        tools: const [
          {
            'type': 'function',
            'function': {
              'name': 'calc',
              'description': 'Evaluate an expression.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'expr': {'type': 'string'},
                },
                'required': ['expr'],
              },
            },
          },
        ],
        dispatchToolCall: (toolCall) async {
          dispatched.add(toolCall.name);
          return McpToolResult(
            toolName: toolCall.name,
            result: '42',
            isSuccess: true,
          );
        },
        model: 'm',
        temperature: 0.7,
        maxTokens: 1024,
      );

      expect(dispatched, contains('calc'));
      expect(task.status, SubagentTaskStatus.completed);
      expect(task.resultSummary, contains('42'));
    });
  });
}

/// Scripted [ChatDataSource] that replays a queue of completions and a single
/// tool-results follow-up, so the subagent tool loop can be exercised
/// deterministically without a live model.
class _ScriptedChatDataSource extends ChatDataSource {
  _ScriptedChatDataSource({
    required List<ChatCompletionResult> completions,
    required this.withToolResults,
  }) : _completions = List<ChatCompletionResult>.of(completions);

  final List<ChatCompletionResult> _completions;
  final ChatCompletionResult withToolResults;
  int _index = 0;

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    final result = _completions[_index.clamp(0, _completions.length - 1)];
    _index++;
    return result;
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
  }) async => withToolResults;

  @override
  Stream<String> streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => const Stream<String>.empty();

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
  }) => const Stream<String>.empty();

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
  }) async => throw UnimplementedError();
}
