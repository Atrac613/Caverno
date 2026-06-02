import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
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
  });
}
