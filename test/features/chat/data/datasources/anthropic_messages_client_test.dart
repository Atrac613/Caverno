import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/anthropic_messages_client.dart';
import 'package:http/http.dart' as http;
import 'package:openai_dart/openai_dart.dart';
import 'package:test/test.dart';

final class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.respond);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  respond;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      respond(request);
}

http.StreamedResponse _response(
  String body, {
  String contentType = 'application/json',
}) => http.StreamedResponse(
  Stream.value(utf8.encode(body)),
  200,
  headers: {'content-type': contentType},
);

void main() {
  test(
    'converts messages, image, tools, and tool results to native API',
    () async {
      final client = AnthropicMessagesClient(
        _RecordingClient((request) async {
          expect(
            request.url.toString(),
            'https://api.anthropic.com/v1/messages',
          );
          expect(request.headers['x-api-key'], 'secret');
          expect(request.headers['anthropic-version'], '2023-06-01');
          final body =
              jsonDecode(await request.finalize().bytesToString()) as Map;
          expect(body['system'], 'Be concise.');
          expect(body['max_tokens'], 128);
          expect((body['tools'] as List).single, {
            'name': 'lookup',
            'description': 'Look up a value',
            'input_schema': {'type': 'object'},
            'strict': true,
          });
          expect(body['output_config'], {
            'format': {
              'type': 'json_schema',
              'schema': {'type': 'object'},
            },
            'effort': 'high',
          });
          final messages = body['messages'] as List;
          expect((messages.first as Map)['role'], 'user');
          final image = ((messages.first as Map)['content'] as List)[1] as Map;
          expect(image['source'], {
            'type': 'base64',
            'media_type': 'image/png',
            'data': 'YWJj',
          });
          final toolUse = ((messages[1] as Map)['content'] as List)[1] as Map;
          expect(toolUse['input'], {'key': 'x'});
          final results = (messages[2] as Map)['content'] as List;
          expect(results.length, 2);
          expect((results.first as Map)['tool_use_id'], 'call_1');
          return _response(
            jsonEncode({
              'id': 'msg_1',
              'model': 'claude-test',
              'content': [
                {'type': 'text', 'text': 'Found it'},
                {
                  'type': 'tool_use',
                  'id': 'call_2',
                  'name': 'lookup',
                  'input': {'key': 'y'},
                },
              ],
              'stop_reason': 'tool_use',
              'usage': {'input_tokens': 10, 'output_tokens': 5},
            }),
          );
        }),
      );
      final request = http.Request(
        'POST',
        Uri.parse('https://api.anthropic.com/v1/chat/completions'),
      );
      request.headers['Authorization'] = 'Bearer secret';
      request.body = jsonEncode({
        'model': 'claude-test',
        'max_tokens': 128,
        'reasoning_effort': 'high',
        'response_format': {
          'type': 'json_schema',
          'json_schema': {
            'name': 'answer',
            'schema': {'type': 'object'},
          },
        },
        'messages': [
          {'role': 'system', 'content': 'Be concise.'},
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'Read this'},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/png;base64,YWJj'},
              },
            ],
          },
          {
            'role': 'assistant',
            'content': 'Checking',
            'tool_calls': [
              {
                'id': 'call_1',
                'type': 'function',
                'function': {'name': 'lookup', 'arguments': '{"key":"x"}'},
              },
            ],
          },
          {'role': 'tool', 'tool_call_id': 'call_1', 'content': 'result one'},
          {'role': 'tool', 'tool_call_id': 'call_3', 'content': 'result two'},
        ],
        'tools': [
          {
            'type': 'function',
            'function': {
              'name': 'lookup',
              'description': 'Look up a value',
              'parameters': {'type': 'object'},
              'strict': true,
            },
          },
        ],
      });
      final response = await client.send(request);
      final decoded = jsonDecode(await response.stream.bytesToString()) as Map;
      expect(
        (decoded['choices'] as List).single['finish_reason'],
        'tool_calls',
      );
      expect((decoded['usage'] as Map)['total_tokens'], 15);
      final call =
          (((decoded['choices'] as List).single['message'] as Map)['tool_calls']
                      as List)
                  .single
              as Map;
      expect((call['function'] as Map)['arguments'], '{"key":"y"}');
    },
  );

  test(
    'translates streamed text, tool arguments, finish reason, and usage',
    () async {
      final events = [
        {
          'type': 'message_start',
          'message': {
            'id': 'msg_1',
            'model': 'claude-test',
            'usage': {'input_tokens': 7, 'output_tokens': 0},
          },
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': 'Hello'},
        },
        {
          'type': 'content_block_start',
          'index': 1,
          'content_block': {
            'type': 'tool_use',
            'id': 'call_1',
            'name': 'lookup',
            'input': {},
          },
        },
        {
          'type': 'content_block_delta',
          'index': 1,
          'delta': {'type': 'input_json_delta', 'partial_json': '{"key":"x"}'},
        },
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use'},
          'usage': {'output_tokens': 3},
        },
      ];
      final client = AnthropicMessagesClient(
        _RecordingClient((request) async {
          final body =
              jsonDecode(await request.finalize().bytesToString()) as Map;
          expect(body['stream'], true);
          return _response(
            events
                .map(
                  (event) =>
                      'event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n',
                )
                .join(),
            contentType: 'text/event-stream',
          );
        }),
      );
      final request =
          http.Request(
              'POST',
              Uri.parse('https://api.anthropic.com/v1/chat/completions'),
            )
            ..body = jsonEncode({
              'model': 'claude-test',
              'stream': true,
              'messages': [
                {'role': 'user', 'content': 'Hi'},
              ],
            });
      final response = await client.send(request);
      final data = await response.stream.bytesToString();
      final chunks = data
          .split('\n')
          .where((line) => line.startsWith('data: {'))
          .map((line) => jsonDecode(line.substring(6)) as Map)
          .toList();
      expect(
        ((chunks[0]['choices'] as List).single['delta'] as Map)['content'],
        'Hello',
      );
      expect(
        (((chunks[1]['choices'] as List).single['delta'] as Map)['tool_calls']
                as List)
            .single['id'],
        'call_1',
      );
      expect(
        (((chunks[2]['choices'] as List).single['delta'] as Map)['tool_calls']
                as List)
            .single['function']['arguments'],
        '{"key":"x"}',
      );
      expect(
        (chunks[3]['choices'] as List).single['finish_reason'],
        'tool_calls',
      );
      expect((chunks.last['usage'] as Map)['total_tokens'], 10);
      expect(data, endsWith('data: [DONE]\n\n'));
    },
  );

  test('only adapts the official HTTPS Anthropic host', () {
    final delegate = _RecordingClient((_) async => _response('{}'));
    expect(
      AnthropicMessagesClient.wrapIfNeeded(
        delegate,
        'https://api.anthropic.com/v1',
      ),
      isA<AnthropicMessagesClient>(),
    );
    expect(
      AnthropicMessagesClient.wrapIfNeeded(
        delegate,
        'https://api.anthropic.com.evil.test/v1',
      ),
      same(delegate),
    );
    expect(
      AnthropicMessagesClient.wrapIfNeeded(
        delegate,
        'http://api.anthropic.com/v1',
      ),
      same(delegate),
    );
  });

  test('OpenAI client parses adapted native completion', () async {
    final transport = AnthropicMessagesClient(
      _RecordingClient((request) async {
        expect(request.url.path, '/v1/messages');
        await request.finalize().drain<void>();
        return _response(
          jsonEncode({
            'id': 'msg_sdk',
            'model': 'claude-test',
            'content': [
              {'type': 'text', 'text': 'Hello from Claude'},
            ],
            'stop_reason': 'end_turn',
            'usage': {'input_tokens': 2, 'output_tokens': 3},
          }),
        );
      }),
    );
    final client = OpenAIClient.withApiKey(
      'secret',
      baseUrl: 'https://api.anthropic.com/v1',
      httpClient: transport,
    );
    final result = await client.chat.completions.create(
      ChatCompletionCreateRequest(
        model: 'claude-test',
        messages: [ChatMessage.user('Hi')],
      ),
    );
    expect(result.choices.single.message.content, 'Hello from Claude');
    expect(result.usage?.totalTokens, 5);
    client.close();
  });

  test('OpenAI stream parser accepts adapted native events', () async {
    final events = [
      {
        'type': 'message_start',
        'message': {
          'id': 'msg_sdk_stream',
          'model': 'claude-test',
          'usage': {'input_tokens': 4, 'output_tokens': 0},
        },
      },
      {
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'text_delta', 'text': 'Hello'},
      },
      {
        'type': 'content_block_start',
        'index': 1,
        'content_block': {
          'type': 'tool_use',
          'id': 'call_sdk',
          'name': 'lookup',
          'input': {},
        },
      },
      {
        'type': 'content_block_delta',
        'index': 1,
        'delta': {'type': 'input_json_delta', 'partial_json': '{"key":"x"}'},
      },
      {
        'type': 'message_delta',
        'delta': {'stop_reason': 'tool_use'},
        'usage': {'output_tokens': 2},
      },
    ];
    http.Client makeTransport() => AnthropicMessagesClient(
      _RecordingClient((request) async {
        await request.finalize().drain<void>();
        return _response(
          events.map((event) => 'data: ${jsonEncode(event)}\n\n').join(),
          contentType: 'text/event-stream',
        );
      }),
    );
    final client = OpenAIClient.withApiKey(
      'secret',
      baseUrl: 'https://api.anthropic.com/v1',
      httpClient: makeTransport(),
      streamClientFactory: makeTransport,
    );
    final stream = client.chat.completions.createStream(
      ChatCompletionCreateRequest(
        model: 'claude-test',
        messages: [ChatMessage.user('Hi')],
        tools: [
          Tool.function(name: 'lookup', parameters: {'type': 'object'}),
        ],
        streamOptions: const StreamOptions(includeUsage: true),
      ),
    );
    final accumulator = ChatStreamAccumulator();
    var totalTokens = 0;
    await for (final event in stream) {
      accumulator.add(event);
      totalTokens = event.usage?.totalTokens ?? totalTokens;
    }
    expect(accumulator.content, 'Hello');
    expect(accumulator.finishReason?.value, 'tool_calls');
    expect(accumulator.toolCalls.single.function.arguments, '{"key":"x"}');
    expect(totalTokens, 6);
    client.close();
  });
}
