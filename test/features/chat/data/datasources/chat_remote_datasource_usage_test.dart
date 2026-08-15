import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:caverno/features/chat/domain/entities/model_usage_role.dart';
import 'package:caverno/features/chat/domain/entities/model_usage_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Captures what the data source reports instead of writing to a database.
final class _RecordingSink implements ModelUsageSink {
  final List<
    ({
      String model,
      String endpointId,
      ModelUsageRole role,
      TokenUsage usage,
      int durationMs,
      String? finishReason,
      bool isError,
    })
  >
  records = [];

  @override
  void record({
    required String model,
    required String endpointId,
    required ModelUsageRole role,
    required TokenUsage usage,
    required int durationMs,
    String? label,
    String? finishReason,
    bool isError = false,
  }) {
    records.add((
      model: model,
      endpointId: endpointId,
      role: role,
      usage: usage,
      durationMs: durationMs,
      finishReason: finishReason,
      isError: isError,
    ));
  }
}

void main() {
  late _RecordingSink sink;

  setUp(() => sink = _RecordingSink());

  ChatRemoteDataSource dataSourceReturning(
    Map<String, dynamic> body, {
    int statusCode = 200,
  }) {
    return ChatRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      usageSink: sink,
      endpointId: 'primary',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode(body),
          statusCode,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );
  }

  Map<String, dynamic> completion({
    Map<String, dynamic>? usage,
    String finishReason = 'stop',
  }) => {
    'id': 'chatcmpl-test',
    'object': 'chat.completion',
    'created': 0,
    'model': 'test-model',
    'choices': [
      {
        'index': 0,
        'message': {'role': 'assistant', 'content': 'Hello'},
        'finish_reason': finishReason,
      },
    ],
    'usage': ?usage,
  };

  final messages = [
    Message(
      id: 'u1',
      content: 'Hi',
      role: MessageRole.user,
      timestamp: DateTime(2026, 8, 8),
    ),
  ];

  test('records one row per completion with the model and endpoint', () async {
    final dataSource = dataSourceReturning(
      completion(
        usage: {
          'prompt_tokens': 120,
          'completion_tokens': 30,
          'total_tokens': 150,
        },
      ),
    );

    await dataSource.createChatCompletion(
      messages: messages,
      model: 'qwen-test',
    );

    expect(sink.records, hasLength(1));
    final record = sink.records.single;
    expect(record.model, 'qwen-test');
    expect(record.endpointId, 'primary');
    expect(record.usage.promptTokens, 120);
    expect(record.usage.completionTokens, 30);
    expect(record.finishReason, 'stop');
    expect(record.isError, isFalse);
  });

  test('keeps the full usage breakdown when the provider reports it', () async {
    final dataSource = dataSourceReturning(
      completion(
        usage: {
          'prompt_tokens': 1000,
          'completion_tokens': 200,
          'total_tokens': 1200,
          'prompt_tokens_details': {'cached_tokens': 900, 'audio_tokens': 4},
          'completion_tokens_details': {
            'reasoning_tokens': 60,
            'accepted_prediction_tokens': 5,
            'rejected_prediction_tokens': 2,
          },
        },
      ),
    );

    await dataSource.createChatCompletion(messages: messages, model: 'gpt-x');

    final usage = sink.records.single.usage;
    expect(usage.cachedPromptTokens, 900);
    expect(usage.audioPromptTokens, 4);
    expect(usage.reasoningTokens, 60);
    expect(usage.acceptedPredictionTokens, 5);
    expect(usage.rejectedPredictionTokens, 2);
  });

  test('leaves detail fields at zero when the provider omits them', () async {
    // Local llama.cpp reports no *_tokens_details; nothing may throw and the
    // fields must stay 0 so the UI can render them as "not reported".
    final dataSource = dataSourceReturning(
      completion(
        usage: {
          'prompt_tokens': 10,
          'completion_tokens': 2,
          'total_tokens': 12,
        },
      ),
    );

    await dataSource.createChatCompletion(messages: messages, model: 'local');

    final usage = sink.records.single.usage;
    expect(usage.totalTokens, 12);
    expect(usage.cachedPromptTokens, 0);
    expect(usage.reasoningTokens, 0);
    expect(usage.hasPromptDetails, isFalse);
    expect(usage.hasCompletionDetails, isFalse);
  });

  test('reports the finish reason that marks a truncated answer', () async {
    final dataSource = dataSourceReturning(
      completion(
        usage: {'prompt_tokens': 5, 'completion_tokens': 5, 'total_tokens': 10},
        finishReason: 'length',
      ),
    );

    await dataSource.createChatCompletion(messages: messages, model: 'local');

    expect(sink.records.single.finishReason, 'length');
  });

  test('attributes the request to the role in scope', () async {
    final dataSource = dataSourceReturning(
      completion(
        usage: {'prompt_tokens': 5, 'completion_tokens': 5, 'total_tokens': 10},
      ),
    );

    await ModelUsageRole.memoryExtraction.runWith(
      () => dataSource.createChatCompletion(messages: messages, model: 'local'),
    );

    expect(sink.records.single.role, ModelUsageRole.memoryExtraction);
  });

  test('falls back to unknown when no call site claimed a role', () async {
    final dataSource = dataSourceReturning(
      completion(
        usage: {'prompt_tokens': 5, 'completion_tokens': 5, 'total_tokens': 10},
      ),
    );

    await dataSource.createChatCompletion(messages: messages, model: 'local');

    expect(sink.records.single.role, ModelUsageRole.unknown);
  });

  test('records a failed request as an error with no usage', () async {
    final dataSource = dataSourceReturning({
      'error': {'message': 'boom', 'type': 'server_error'},
    }, statusCode: 500);

    await expectLater(
      dataSource.createChatCompletion(messages: messages, model: 'local'),
      throwsA(anything),
    );

    expect(sink.records, hasLength(1));
    expect(sink.records.single.isError, isTrue);
    expect(sink.records.single.usage.totalTokens, 0);
  });

  test('a streamed request keeps the role of the caller that issued it', () async {
    // Regression: the stream body runs on first listen, outside the zone the
    // caller set up, so reading the role at the terminal booked every chat turn
    // as `unknown`. Reproduced live before the fix.
    final streamClient = MockClient(
      (_) async => http.Response(
        'data: ${jsonEncode({
          'id': 'chatcmpl-test',
          'object': 'chat.completion.chunk',
          'created': 0,
          'model': 'test-model',
          'choices': [
            {
              'index': 0,
              'delta': {'content': 'Hi'},
              'finish_reason': 'stop',
            },
          ],
          'usage': {'prompt_tokens': 7, 'completion_tokens': 3, 'total_tokens': 10},
        })}\n\ndata: [DONE]\n\n',
        200,
        headers: const {'content-type': 'text/event-stream'},
      ),
    );
    final dataSource = ChatRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      usageSink: sink,
      endpointId: 'primary',
      httpClient: streamClient,
      streamClientFactory: () => streamClient,
    );

    // Issue inside the zone, drain outside it, exactly as the chat loop does.
    final completion = ModelUsageRole.chat.runWith(
      () => dataSource.streamChatCompletion(messages: messages, model: 'local'),
    );
    await completion.stream.drain<void>();
    await completion.terminal;

    expect(sink.records, hasLength(1));
    expect(sink.records.single.role, ModelUsageRole.chat);
  });

  test('records nothing when no sink is configured', () async {
    final dataSource = ChatRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode(
            completion(
              usage: {
                'prompt_tokens': 5,
                'completion_tokens': 5,
                'total_tokens': 10,
              },
            ),
          ),
          200,
          headers: const {'content-type': 'application/json'},
        ),
      ),
    );

    final result = await dataSource.createChatCompletion(
      messages: messages,
      model: 'local',
    );

    expect(result.usage.totalTokens, 10);
    expect(sink.records, isEmpty);
  });
}
