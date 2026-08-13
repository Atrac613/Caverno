import 'dart:async';

import 'package:caverno/features/chat/data/datasources/chat_datasource.dart';
import 'package:caverno/features/chat/data/datasources/primary_route_chat_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/settings/domain/services/mesh_endpoint_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final messages = [
    Message(
      id: 'user',
      content: 'Question',
      role: MessageRole.user,
      timestamp: DateTime(2026),
    ),
  ];

  PrimaryRouteChatDataSource routed({
    required _ScriptedChatDataSource assigned,
    required _ScriptedChatDataSource primary,
    EndpointHealthTracker? health,
  }) => PrimaryRouteChatDataSource(
    assigned: assigned,
    primary: primary,
    assignedEndpointId: 'quality-host',
    assignedModel: 'quality-model',
    primaryModel: 'primary-model',
    health: health ?? EndpointHealthTracker(),
  );

  test('non-streaming failure retries with the primary model', () async {
    final health = EndpointHealthTracker();
    final assigned = _ScriptedChatDataSource(
      createError: StateError('connection refused'),
    );
    final primary = _ScriptedChatDataSource(content: 'fallback');
    final dataSource = routed(
      assigned: assigned,
      primary: primary,
      health: health,
    );

    final result = await dataSource.createChatCompletion(messages: messages);

    expect(result.content, 'fallback');
    expect(assigned.models, ['quality-model']);
    expect(primary.models, ['primary-model']);
    expect(health.isUnhealthy('quality-host'), isTrue);
  });

  test('successful assigned request clears endpoint failures', () async {
    final health = EndpointHealthTracker(failureThreshold: 1)
      ..recordFailure('quality-host');
    final assigned = _ScriptedChatDataSource(content: 'assigned');
    final primary = _ScriptedChatDataSource(content: 'fallback');
    final dataSource = routed(
      assigned: assigned,
      primary: primary,
      health: health,
    );

    final result = await dataSource.createChatCompletion(messages: messages);

    expect(result.content, 'assigned');
    expect(primary.models, isEmpty);
    expect(health.healthFor('quality-host').consecutiveFailures, 0);
  });

  test(
    'pre-emission stream failure falls back without duplicate content',
    () async {
      final assigned = _ScriptedChatDataSource(
        streamError: StateError('connection refused'),
      );
      final primary = _ScriptedChatDataSource(
        streamChunks: const ['fall', 'back'],
      );
      final dataSource = routed(assigned: assigned, primary: primary);

      final completion = dataSource.streamChatCompletion(messages: messages);
      final chunks = await completion.toList();
      final terminal = await completion.terminal;

      expect(chunks, ['fall', 'back']);
      expect(assigned.models, ['quality-model']);
      expect(primary.models, ['primary-model']);
      expect(terminal.finishReason, 'stop');
    },
  );

  test('post-emission stream failure never replays on the primary', () async {
    final assigned = _ScriptedChatDataSource(
      streamChunks: const ['visible'],
      streamErrorAfterChunks: StateError('connection reset'),
    );
    final primary = _ScriptedChatDataSource(streamChunks: const ['duplicate']);
    final dataSource = routed(assigned: assigned, primary: primary);

    final completion = dataSource.streamChatCompletion(messages: messages);

    await expectLater(completion.toList(), throwsA(isA<StateError>()));
    expect(primary.models, isEmpty);
    await expectLater(completion.terminal, throwsA(isA<StateError>()));
  });

  test('tool-aware pre-emission failure retries on the primary', () async {
    final assigned = _ScriptedChatDataSource(
      toolStreamError: StateError('connection refused'),
    );
    final primary = _ScriptedChatDataSource(
      streamChunks: const ['fallback answer'],
      content: 'fallback answer',
    );
    final dataSource = routed(assigned: assigned, primary: primary);

    final result = dataSource.streamChatCompletionWithTools(
      messages: messages,
      tools: const [
        {
          'type': 'function',
          'function': {'name': 'read_file'},
        },
      ],
    );

    expect(await result.stream.toList(), ['fallback answer']);
    expect((await result.completion).content, 'fallback answer');
    expect(assigned.models, ['quality-model']);
    expect(primary.models, ['primary-model']);
  });

  test('batched tool-result completion uses the same captured route', () async {
    final assigned = _ScriptedChatDataSource(content: 'continued');
    final primary = _ScriptedChatDataSource(content: 'fallback');
    final dataSource = routed(assigned: assigned, primary: primary);

    final result = await dataSource.createChatCompletionWithToolResults(
      messages: messages,
      toolResults: [
        ToolResultInfo(
          id: 'call-1',
          name: 'read_file',
          arguments: {'path': 'README.md'},
          result: 'contents',
        ),
      ],
    );

    expect(result.content, 'continued');
    expect(assigned.models, ['quality-model']);
    expect(primary.models, isEmpty);
  });
}

final class _ScriptedChatDataSource implements ChatDataSource {
  _ScriptedChatDataSource({
    this.content = 'ok',
    this.createError,
    this.streamError,
    this.streamErrorAfterChunks,
    this.toolStreamError,
    this.streamChunks = const <String>[],
  });

  final String content;
  final Object? createError;
  final Object? streamError;
  final Object? streamErrorAfterChunks;
  final Object? toolStreamError;
  final List<String> streamChunks;
  final List<String?> models = <String?>[];

  @override
  StreamedChatCompletion streamChatCompletion({
    required List<Message> messages,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    models.add(model);
    Stream<String> stream() async* {
      final earlyError = streamError;
      if (earlyError != null) throw earlyError;
      for (final chunk in streamChunks) {
        yield chunk;
      }
      final lateError = streamErrorAfterChunks;
      if (lateError != null) throw lateError;
    }

    return StreamedChatCompletion.fromStream(stream(), finishReason: 'stop');
  }

  @override
  Future<ChatCompletionResult> createChatCompletion({
    required List<Message> messages,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) async {
    models.add(model);
    final error = createError;
    if (error != null) throw error;
    return ChatCompletionResult(content: content, finishReason: 'stop');
  }

  @override
  StreamWithToolsResult streamChatCompletionWithTools({
    required List<Message> messages,
    required List<Map<String, dynamic>> tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) {
    models.add(model);
    final error = toolStreamError;
    if (error != null) {
      return StreamWithToolsResult(
        stream: Stream<String>.error(error),
        completion: Future<ChatCompletionResult>.error(error),
      );
    }
    return StreamWithToolsResult(
      stream: Stream<String>.fromIterable(streamChunks),
      completion: Future.value(
        ChatCompletionResult(content: content, finishReason: 'stop'),
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
  }) => streamChatCompletion(
    messages: messages,
    model: model,
    temperature: temperature,
    maxTokens: maxTokens,
  );

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
  }) => createChatCompletion(
    messages: messages,
    tools: tools,
    model: model,
    temperature: temperature,
    maxTokens: maxTokens,
  );

  @override
  Future<ChatCompletionResult> createChatCompletionWithToolResults({
    required List<Message> messages,
    required List<ToolResultInfo> toolResults,
    String? assistantContent,
    List<Map<String, dynamic>>? tools,
    String? model,
    double? temperature,
    int? maxTokens,
  }) => createChatCompletion(
    messages: messages,
    tools: tools,
    model: model,
    temperature: temperature,
    maxTokens: maxTokens,
  );
}
