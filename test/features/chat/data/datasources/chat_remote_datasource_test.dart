import 'dart:async';
import 'dart:convert';

import 'package:caverno/features/chat/data/datasources/chat_remote_datasource.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late ChatRemoteDataSource dataSource;

  setUp(() {
    dataSource = ChatRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
    );
  });

  test('recovers raw assistant text from parse failures', () {
    final error = Exception(
      'StreamException: Failed to parse input at pos 13: '
      '<|channel>thought planning<channel|><tool_use>{"name":"read_file","arguments":{"path":"pubspec.yaml"}}</tool_use>',
    );

    final recovered = dataSource.tryRecoverRawAssistantTextFromError(error);

    expect(
      recovered,
      '<think> planning</think><tool_use>{"name":"read_file","arguments":{"path":"pubspec.yaml"}}</tool_use>',
    );
  });

  test('returns null when the error does not include recoverable raw text', () {
    final recovered = dataSource.tryRecoverRawAssistantTextFromError(
      Exception('Connection refused'),
    );

    expect(recovered, isNull);
  });

  test('classifies native tool stream format errors', () {
    expect(
      ChatRemoteDataSource.isNativeToolStreamFormatError(
        Exception(
          'StreamException: The model produced output that does not match the expected peg-native format',
        ),
      ),
      isTrue,
    );

    expect(
      ChatRemoteDataSource.isNativeToolStreamFormatError(
        Exception('Connection refused'),
      ),
      isFalse,
    );
  });

  test('parses embedded tool calls from recovered assistant text', () {
    const content =
        '<think>Planning</think><tool_use>{"name":"write_file","arguments":{"path":"out.txt","content":"hello"}}</tool_use>';

    final toolCalls = dataSource.parseEmbeddedToolCallsForTest(content);

    expect(toolCalls, hasLength(1));
    expect(toolCalls!.first.name, 'write_file');
    expect(toolCalls.first.arguments['path'], 'out.txt');
    expect(toolCalls.first.arguments['content'], 'hello');
    expect(toolCalls.first.id, isNotEmpty);
  });

  test('treats tool calls as actionable when finish reason is length', () {
    final result = ChatCompletionResult(
      content: 'Preparing to run Python',
      finishReason: 'length',
      toolCalls: [
        ToolCallInfo(
          id: 'tool-1',
          name: 'run_python_script',
          arguments: const {},
        ),
      ],
    );

    expect(result.hasToolCalls, isTrue);
  });

  test('annotates successful write_file updates for LLM retries', () {
    final content = dataSource.formatToolResultContentForLlm(
      ToolResultInfo(
        id: 'tool-1',
        name: 'write_file',
        arguments: const {'path': 'tests/test_ping.py'},
        result:
            '{"path":"tests/test_ping.py","bytes_written":1062,"created":false}',
      ),
    );

    expect(
      content,
      contains(
        'Interpretation: write_file succeeded and updated an existing file.',
      ),
    );
    expect(
      content,
      contains(
        'A result with "created": false means the file already existed; it is not an error.',
      ),
    );
    expect(content, contains('Raw result:'));
  });

  test('annotates Open-Meteo weather codes for LLM retries', () {
    final content = dataSource.formatToolResultContentForLlm(
      ToolResultInfo(
        id: 'tool-1',
        name: 'http_get',
        arguments: const {'url': 'https://api.open-meteo.com/v1/forecast'},
        result: jsonEncode({
          'url': 'https://api.open-meteo.com/v1/forecast',
          'status_code': 200,
          'content_type': 'application/json; charset=utf-8',
          'body': jsonEncode({
            'daily_units': {'weathercode': 'wmo code'},
            'daily': {
              'time': ['2026-06-03'],
              'weathercode': [65],
            },
          }),
        }),
      ),
    );

    expect(
      content,
      contains(
        'Open-Meteo daily 2026-06-03 weather code 65 = Rain: Heavy intensity.',
      ),
    );
    expect(
      content,
      contains(
        'drizzle codes are 51, 53, and 55, while rain codes are 61, 63, and 65',
      ),
    );
    expect(content, contains('Raw result:'));
  });

  test('redacts screenshot base64 from text tool result content', () {
    final content = dataSource.formatToolResultContentForLlm(
      ToolResultInfo(
        id: 'tool-1',
        name: 'computer_screenshot',
        arguments: const {},
        result:
            '{"imageBase64":"very-large-payload","imageMimeType":"image/png","width":800,"height":600}',
      ),
    );

    expect(content, isNot(contains('very-large-payload')));
    expect(content, contains('[attached as image content]'));
    expect(content, contains('"width":800'));
  });

  test('counts screenshot tool results as image observations', () {
    final count = dataSource.countToolImageObservationMessagesForTest([
      ToolResultInfo(
        id: 'tool-1',
        name: 'computer_screenshot',
        arguments: const {},
        result:
            '{"imageBase64":"payload","imageMimeType":"image/png","width":800,"height":600}',
      ),
      ToolResultInfo(
        id: 'tool-2',
        name: 'computer_get_permissions',
        arguments: const {},
        result: '{"accessibilityGranted":true}',
      ),
    ]);

    expect(count, 1);
  });

  test('summarizes available tools without schema details by default', () {
    final logs = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        logs.add(message);
      }
    };
    addTearDown(() {
      debugPrint = previousDebugPrint;
    });

    dataSource.streamChatCompletionWithTools(
      messages: [
        Message(
          id: 'message-1',
          content: 'What time is it?',
          role: MessageRole.user,
          timestamp: DateTime(2026),
        ),
      ],
      tools: const [
        {
          'type': 'function',
          'function': {
            'name': 'get_current_datetime',
            'description': 'Returns the current local date/time.',
            'parameters': {'type': 'object', 'properties': {}},
          },
        },
        {
          'type': 'function',
          'function': {
            'name': 'search_past_conversations',
            'description': 'Search past conversation history.',
            'parameters': {
              'type': 'object',
              'properties': {
                'query': {'type': 'string'},
              },
            },
          },
        },
      ],
    );

    expect(
      logs,
      contains(
        '[LLM] Tools available: 2 '
        '(get_current_datetime, search_past_conversations)',
      ),
    );
    expect(logs.join('\n'), isNot(contains('[LLM] === Tool Schemas ===')));
    expect(logs.join('\n'), isNot(contains('[LLM]     params:')));
  });

  test('truncates large tool summaries', () {
    final tools = List.generate(
      14,
      (index) => {
        'type': 'function',
        'function': {
          'name': 'tool_$index',
          'description': 'Tool $index',
          'parameters': {'type': 'object'},
        },
      },
    );

    expect(
      dataSource.formatToolLogSummaryForTest(tools),
      '[LLM] Tools available: 14 '
      '(tool_0, tool_1, tool_2, tool_3, tool_4, tool_5, tool_6, tool_7, '
      'tool_8, tool_9, tool_10, tool_11, +2 more)',
    );
  });

  test('builds stable prompt prefixes for tool-result follow-ups', () {
    final now = DateTime(2026, 6, 13, 10);
    final initialMessages = [
      Message(
        id: 'system-1',
        content: 'Stable coding system prompt.',
        role: MessageRole.system,
        timestamp: now,
      ),
      Message(
        id: 'user-1',
        content: 'Update the CLI.',
        role: MessageRole.user,
        timestamp: now,
      ),
    ];
    final followUpMessages = [
      ...initialMessages,
      Message(
        id: 'assistant-1',
        content: 'I will inspect the file.',
        role: MessageRole.assistant,
        timestamp: now,
      ),
    ];
    const tools = [
      {
        'type': 'function',
        'function': {
          'name': 'read_file',
          'description': 'Read a file.',
          'parameters': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
            },
            'required': ['path'],
          },
        },
      },
    ];

    final stableMessageCount = dataSource
        .commonLeadingPromptMessageCountForTest(
          initialMessages,
          followUpMessages,
        );
    final initialPrefix = dataSource.buildPromptPrefixJsonForTest(
      messages: initialMessages,
      tools: tools,
      stableMessageCount: stableMessageCount,
    );
    final followUpPrefix = dataSource.buildPromptPrefixJsonForTest(
      messages: followUpMessages,
      tools: tools,
      stableMessageCount: stableMessageCount,
    );

    expect(stableMessageCount, 2);
    expect(followUpPrefix, initialPrefix);
  });

  test('retries without reasoning effort after HTTP 400', () async {
    final requestBodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      requestBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (requestBodies.length == 1) {
        return http.Response(
          jsonEncode({
            'error': {
              'message': 'Unrecognized request argument: reasoning_effort',
              'type': 'invalid_request_error',
              'param': 'reasoning_effort',
            },
          }),
          400,
          headers: const {'content-type': 'application/json'},
        );
      }

      return http.Response(
        jsonEncode({
          'id': 'chatcmpl-test',
          'object': 'chat.completion',
          'created': 0,
          'model': 'test-model',
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': 'Recovered'},
              'finish_reason': 'stop',
            },
          ],
          'usage': {
            'prompt_tokens': 1,
            'completion_tokens': 1,
            'total_tokens': 2,
          },
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    final dataSource = ChatRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      reasoningEffort: 'high',
      httpClient: client,
    );

    final result = await dataSource.createChatCompletion(
      messages: [
        Message(
          id: 'message-1',
          content: 'Hello',
          role: MessageRole.user,
          timestamp: DateTime(2026),
        ),
      ],
      model: 'test-model',
    );

    expect(result.content, 'Recovered');
    expect(requestBodies, hasLength(2));
    expect(requestBodies.first['reasoning_effort'], 'high');
    expect(requestBodies.last.containsKey('reasoning_effort'), isFalse);
  });

  test('retries with max_completion_tokens after HTTP 400', () async {
    final requestBodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      requestBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (requestBodies.length == 1) {
        // Verbatim rejection from OpenAI's GPT-5 family.
        return http.Response(
          jsonEncode({
            'error': {
              'message':
                  "Unsupported parameter: 'max_tokens' is not supported with "
                  "this model. Use 'max_completion_tokens' instead.",
              'type': 'invalid_request_error',
              'param': 'max_tokens',
            },
          }),
          400,
          headers: const {'content-type': 'application/json'},
        );
      }

      return http.Response(
        jsonEncode({
          'id': 'chatcmpl-test',
          'object': 'chat.completion',
          'created': 0,
          'model': 'gpt-5.6-luna',
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': 'Recovered'},
              'finish_reason': 'stop',
            },
          ],
          'usage': {
            'prompt_tokens': 1,
            'completion_tokens': 1,
            'total_tokens': 2,
          },
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    final dataSource = ChatRemoteDataSource(
      baseUrl: 'https://api.openai.com/v1',
      apiKey: 'no-key',
      httpClient: client,
    );

    Future<String?> send() async {
      final result = await dataSource.createChatCompletion(
        messages: [_userMessage()],
        model: 'gpt-5.6-luna',
        maxTokens: 8192,
      );
      return result.content;
    }

    expect(await send(), 'Recovered');
    expect(requestBodies, hasLength(2));
    expect(requestBodies.first['max_tokens'], 8192);
    expect(requestBodies.first.containsKey('max_completion_tokens'), isFalse);
    expect(requestBodies.last.containsKey('max_tokens'), isFalse);
    expect(requestBodies.last['max_completion_tokens'], 8192);

    // The quirk is remembered, so later turns do not pay the round trip again.
    expect(await send(), 'Recovered');
    expect(requestBodies, hasLength(3));
    expect(requestBodies.last['max_completion_tokens'], 8192);
  });

  test(
    'streamChatCompletionWithTools retries with max_completion_tokens',
    () async {
      final requestBodies = <Map<String, dynamic>>[];
      final client = MockClient((request) async {
        requestBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        if (requestBodies.length == 1) {
          return http.Response(
            jsonEncode({
              'error': {
                'message':
                    "Unsupported parameter: 'max_tokens' is not supported with "
                    "this model. Use 'max_completion_tokens' instead.",
                'type': 'invalid_request_error',
                'param': 'max_tokens',
              },
            }),
            400,
            headers: const {'content-type': 'application/json'},
          );
        }

        return http.Response(
          'data: ${jsonEncode({
            'id': 'chatcmpl-test',
            'object': 'chat.completion.chunk',
            'created': 0,
            'model': 'gpt-5.6-luna',
            'choices': [
              {
                'index': 0,
                'delta': {'content': 'Recovered'},
                'finish_reason': 'stop',
              },
            ],
          })}\n\ndata: [DONE]\n\n',
          200,
          headers: const {'content-type': 'text/event-stream'},
        );
      });

      final dataSource = ChatRemoteDataSource(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'no-key',
        httpClient: client,
        streamClientFactory: () => client,
      );

      final result = dataSource.streamChatCompletionWithTools(
        messages: [_userMessage()],
        tools: const [],
        model: 'gpt-5.6-luna',
        maxTokens: 8192,
      );

      expect(await result.stream.join(), 'Recovered');
      expect(requestBodies, hasLength(2));
      expect(requestBodies.first['max_tokens'], 8192);
      expect(requestBodies.last.containsKey('max_tokens'), isFalse);
      expect(requestBodies.last['max_completion_tokens'], 8192);
    },
  );

  test('streaming pins reasoning_effort to none for function tools', () async {
    final requestBodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      requestBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (requestBodies.length == 1) {
        // Verbatim rejection from OpenAI for GPT-5.x + function tools.
        return http.Response(
          jsonEncode({
            'error': {
              'message':
                  'Function tools with reasoning_effort are not supported for '
                  'gpt-5.6-luna in /v1/chat/completions. To use function '
                  "tools, use /v1/responses or set reasoning_effort to 'none'.",
              'type': 'invalid_request_error',
            },
          }),
          400,
          headers: const {'content-type': 'application/json'},
        );
      }
      return _streamedChunkResponse('Recovered');
    });

    final dataSource = ChatRemoteDataSource(
      baseUrl: 'https://api.openai.com/v1',
      apiKey: 'no-key',
      reasoningEffort: 'high',
      httpClient: client,
      streamClientFactory: () => client,
    );

    final result = dataSource.streamChatCompletionWithTools(
      messages: [_userMessage()],
      tools: const [
        {
          'type': 'function',
          'function': {
            'name': 'get_current_datetime',
            'description': 'Returns the current local date/time.',
            'parameters': {'type': 'object', 'properties': {}},
          },
        },
      ],
      model: 'gpt-5.6-luna',
    );

    expect(await result.stream.join(), 'Recovered');
    expect(requestBodies, hasLength(2));
    expect(requestBodies.first['reasoning_effort'], 'high');
    // Omitting the parameter is not enough — the server defaults it back on.
    expect(requestBodies.last['reasoning_effort'], 'none');
    expect(requestBodies.last['tools'], hasLength(1));
  });

  test('streaming retries without reasoning effort after HTTP 400', () async {
    final requestBodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      requestBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (requestBodies.length == 1) {
        return http.Response(
          jsonEncode({
            'error': {
              'message': 'Unrecognized request argument: reasoning_effort',
              'type': 'invalid_request_error',
              'param': 'reasoning_effort',
            },
          }),
          400,
          headers: const {'content-type': 'application/json'},
        );
      }
      return _streamedChunkResponse('Recovered');
    });

    final dataSource = ChatRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      reasoningEffort: 'high',
      httpClient: client,
      streamClientFactory: () => client,
    );

    final result = dataSource.streamChatCompletionWithTools(
      messages: [_userMessage()],
      tools: const [],
      model: 'test-model',
    );

    expect(await result.stream.join(), 'Recovered');
    expect(requestBodies, hasLength(2));
    expect(requestBodies.first['reasoning_effort'], 'high');
    expect(requestBodies.last.containsKey('reasoning_effort'), isFalse);
  });

  test('does not replay a stream that already emitted content', () async {
    var requests = 0;
    final client = MockClient.streaming((request, bodyStream) async {
      requests++;
      // Emit one chunk, then fail: the caller has seen content already, so the
      // turn must surface the error instead of restarting the answer.
      final body = Stream<List<int>>.fromIterable([
        utf8.encode(
          'data: ${jsonEncode({
            'id': 'chatcmpl-test',
            'object': 'chat.completion.chunk',
            'created': 0,
            'model': 'test-model',
            'choices': [
              {
                'index': 0,
                'delta': {'content': 'Partial'},
              },
            ],
          })}\n\n',
        ),
        utf8.encode('data: {"error": {"message": "boom"}}\n\n'),
      ]);
      return http.StreamedResponse(
        body,
        200,
        headers: const {'content-type': 'text/event-stream'},
      );
    });

    final dataSource = ChatRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      reasoningEffort: 'high',
      httpClient: client,
      streamClientFactory: () => client,
    );

    final result = dataSource.streamChatCompletionWithTools(
      messages: [_userMessage()],
      tools: const [],
      model: 'test-model',
    );

    await expectLater(result.stream.join(), throwsA(isA<Object>()));
    expect(requests, 1);
  });

  test('drops temperature after the server rejects the value', () async {
    final requestBodies = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      requestBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (requestBodies.length == 1) {
        return http.Response(
          jsonEncode({
            'error': {
              'message':
                  "Unsupported value: 'temperature' does not support 0.2 with "
                  'this model. Only the default (1) value is supported.',
              'type': 'invalid_request_error',
              'param': 'temperature',
            },
          }),
          400,
          headers: const {'content-type': 'application/json'},
        );
      }

      return http.Response(
        jsonEncode({
          'id': 'chatcmpl-test',
          'object': 'chat.completion',
          'created': 0,
          'model': 'gpt-5.6-luna',
          'choices': [
            {
              'index': 0,
              'message': {'role': 'assistant', 'content': 'Recovered'},
              'finish_reason': 'stop',
            },
          ],
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    final dataSource = ChatRemoteDataSource(
      baseUrl: 'https://api.openai.com/v1',
      apiKey: 'no-key',
      httpClient: client,
    );

    final result = await dataSource.createChatCompletion(
      messages: [_userMessage()],
      model: 'gpt-5.6-luna',
      temperature: 0.2,
    );

    expect(result.content, 'Recovered');
    expect(requestBodies, hasLength(2));
    expect(requestBodies.first['temperature'], 0.2);
    expect(requestBodies.last.containsKey('temperature'), isFalse);
  });

  test('promotes embedded function calls in tool-result follow-ups', () async {
    const content = '''
<tool_call>
<function=delete_file>
<parameter=path>/tmp/todo/bin/todo.dart</parameter>
<parameter=reason>Remove the unexpected entrypoint.</parameter>
</function>
</tool_call>''';
    final dataSource = ChatRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      httpClient: _completionClient(content: content),
    );

    final result = await dataSource.createChatCompletionWithToolResults(
      messages: [_userMessage()],
      toolResults: [
        ToolResultInfo(
          id: 'verifier-1',
          name: 'local_execute_command',
          arguments: {'command': 'dart run tool/verify.dart'},
          result: '{"exit_code":1}',
        ),
      ],
      tools: _deleteFileTools,
      model: 'test-model',
    );

    expect(result.finishReason, 'tool_calls');
    expect(result.toolCalls, hasLength(1));
    expect(result.toolCalls!.single.name, 'delete_file');
    expect(
      result.toolCalls!.single.arguments['path'],
      '/tmp/todo/bin/todo.dart',
    );
  });

  test('promotes embedded calls in ordinary tool-aware completions', () async {
    const content =
        '<tool_call><function=delete_file><parameter=path>bin/old.dart</parameter></function></tool_call>';
    final dataSource = ChatRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      httpClient: _completionClient(content: content),
    );

    final result = await dataSource.createChatCompletion(
      messages: [_userMessage()],
      tools: _deleteFileTools,
      model: 'test-model',
    );

    expect(result.finishReason, 'tool_calls');
    expect(result.toolCalls?.single.name, 'delete_file');
  });

  test('does not promote embedded calls without advertised tools', () async {
    const content =
        '<tool_call><function=delete_file><parameter=path>bin/old.dart</parameter></function></tool_call>';
    final dataSource = ChatRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      httpClient: _completionClient(content: content),
    );

    final result = await dataSource.createChatCompletion(
      messages: [_userMessage()],
      model: 'test-model',
    );

    expect(result.finishReason, 'stop');
    expect(result.toolCalls, isNull);
    expect(result.content, content);
  });

  test('does not promote embedded calls for unadvertised tool names', () async {
    const content =
        '<tool_call><function=read_file><parameter=path>pubspec.yaml</parameter></function></tool_call>';
    final dataSource = ChatRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      httpClient: _completionClient(content: content),
    );

    final result = await dataSource.createChatCompletion(
      messages: [_userMessage()],
      tools: _deleteFileTools,
      model: 'test-model',
    );

    expect(result.finishReason, 'stop');
    expect(result.toolCalls, isNull);
  });

  test('native tool calls take precedence over embedded calls', () async {
    const content =
        '<tool_call><function=delete_file><parameter=path>bin/old.dart</parameter></function></tool_call>';
    final dataSource = ChatRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      httpClient: _completionClient(
        content: content,
        finishReason: 'tool_calls',
        toolCalls: const [
          {
            'id': 'native-1',
            'type': 'function',
            'function': {
              'name': 'read_file',
              'arguments': '{"path":"pubspec.yaml"}',
            },
          },
        ],
      ),
    );

    final result = await dataSource.createChatCompletion(
      messages: [_userMessage()],
      tools: _deleteFileTools,
      model: 'test-model',
    );

    expect(result.toolCalls, hasLength(1));
    expect(result.toolCalls!.single.name, 'read_file');
  });

  test('keeps terminal metadata atomic across interleaved streams', () async {
    final client = _ControlledStreamingClient(['first-model', 'second-model']);
    final dataSource = ChatRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      httpClient: client,
    );
    final first = dataSource.streamChatCompletion(
      messages: [_userMessage()],
      model: 'first-model',
    );
    final second = dataSource.streamChatCompletion(
      messages: [_userMessage()],
      model: 'second-model',
    );

    final firstContent = first.toList();
    final secondContent = second.toList();
    client.addContent('first-model', 'first');
    client.addContent('second-model', 'second');
    await client.finish(
      'second-model',
      finishReason: 'length',
      usage: const TokenUsage(
        promptTokens: 20,
        completionTokens: 2,
        totalTokens: 22,
      ),
    );
    await client.finish(
      'first-model',
      finishReason: 'stop',
      usage: const TokenUsage(
        promptTokens: 10,
        completionTokens: 1,
        totalTokens: 11,
      ),
    );

    expect(await firstContent, ['first']);
    expect(await secondContent, ['second']);
    final firstTerminal = await first.terminal;
    final secondTerminal = await second.terminal;
    expect(firstTerminal.finishReason, 'stop');
    expect(firstTerminal.usage.totalTokens, 11);
    expect(secondTerminal.finishReason, 'length');
    expect(secondTerminal.usage.totalTokens, 22);
    expect(dataSource.lastFinishReason, 'stop');
    expect(dataSource.lastUsage.totalTokens, 11);
  });

  test('completes terminal metadata with the exact stream error', () async {
    final client = _ControlledStreamingClient(['error-model']);
    final dataSource = ChatRemoteDataSource(
      baseUrl: 'http://localhost:1234/v1',
      apiKey: 'no-key',
      httpClient: client,
    );
    final completion = dataSource.streamChatCompletion(
      messages: [_userMessage()],
      model: 'error-model',
    );

    final content = completion.toList();
    final streamError = StateError('stream failed');
    client.addContent('error-model', 'partial');
    client.addError('error-model', streamError);

    await expectLater(content, throwsA(same(streamError)));
    await expectLater(completion.terminal, throwsA(same(streamError)));
    expect(dataSource.lastFinishReason, isNull);
    expect(dataSource.lastUsage.totalTokens, 0);
    await client.closeModel('error-model');
  });

  test(
    'completes terminal metadata with cancellation without publishing',
    () async {
      final client = _ControlledStreamingClient(['cancel-model']);
      final dataSource = ChatRemoteDataSource(
        baseUrl: 'http://localhost:1234/v1',
        apiKey: 'no-key',
        httpClient: client,
      );
      final completion = dataSource.streamChatCompletion(
        messages: [_userMessage()],
        model: 'cancel-model',
      );
      final firstChunk = Completer<void>();
      final subscription = completion.listen((_) {
        if (!firstChunk.isCompleted) {
          firstChunk.complete();
        }
      });

      client.addContent('cancel-model', 'partial');
      await firstChunk.future;
      await subscription.cancel();

      await expectLater(
        completion.terminal,
        throwsA(isA<ChatCompletionStreamCancelledException>()),
      );
      expect(dataSource.lastFinishReason, isNull);
      expect(dataSource.lastUsage.totalTokens, 0);
      await client.closeModel('cancel-model');
    },
  );
}

const List<Map<String, dynamic>> _deleteFileTools = [
  {
    'type': 'function',
    'function': {
      'name': 'delete_file',
      'description': 'Delete one file.',
      'parameters': {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
        },
        'required': ['path'],
      },
    },
  },
];

http.Response _streamedChunkResponse(String content) {
  return http.Response(
    'data: ${jsonEncode({
      'id': 'chatcmpl-test',
      'object': 'chat.completion.chunk',
      'created': 0,
      'model': 'test-model',
      'choices': [
        {
          'index': 0,
          'delta': {'content': content},
          'finish_reason': 'stop',
        },
      ],
    })}\n\ndata: [DONE]\n\n',
    200,
    headers: const {'content-type': 'text/event-stream'},
  );
}

Message _userMessage() {
  return Message(
    id: 'message-1',
    content: 'Continue the task.',
    role: MessageRole.user,
    timestamp: DateTime(2026),
  );
}

MockClient _completionClient({
  required String content,
  String finishReason = 'stop',
  List<Map<String, dynamic>>? toolCalls,
}) {
  return MockClient((request) async {
    return http.Response(
      jsonEncode({
        'id': 'chatcmpl-embedded-tool-test',
        'object': 'chat.completion',
        'created': 0,
        'model': 'test-model',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': content,
              'tool_calls': ?toolCalls,
            },
            'finish_reason': finishReason,
          },
        ],
        'usage': {
          'prompt_tokens': 1,
          'completion_tokens': 1,
          'total_tokens': 2,
        },
      }),
      200,
      headers: const {'content-type': 'application/json'},
    );
  });
}

final class _ControlledStreamingClient extends http.BaseClient {
  _ControlledStreamingClient(Iterable<String> models)
    : _controllers = {
        for (final model in models) model: StreamController<List<int>>(),
      };

  final Map<String, StreamController<List<int>>> _controllers;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final requestBody = await utf8.decodeStream(request.finalize());
    final decoded = jsonDecode(requestBody) as Map<String, dynamic>;
    final model = decoded['model']! as String;
    return http.StreamedResponse(
      _controllers[model]!.stream,
      200,
      headers: const {'content-type': 'text/event-stream'},
      request: request,
    );
  }

  void addContent(String model, String content) {
    _addEvent(model, _chunk(model: model, content: content));
  }

  void addError(String model, Object error) {
    _controllers[model]!.addError(error);
  }

  Future<void> finish(
    String model, {
    required String finishReason,
    required TokenUsage usage,
  }) async {
    _addEvent(
      model,
      _chunk(model: model, finishReason: finishReason, usage: usage),
    );
    _controllers[model]!.add(utf8.encode('data: [DONE]\n\n'));
    await closeModel(model);
  }

  Future<void> closeModel(String model) => _controllers[model]!.close();

  void _addEvent(String model, Map<String, dynamic> event) {
    _controllers[model]!.add(utf8.encode('data: ${jsonEncode(event)}\n\n'));
  }

  Map<String, dynamic> _chunk({
    required String model,
    String? content,
    String? finishReason,
    TokenUsage? usage,
  }) {
    return {
      'id': 'chatcmpl-$model',
      'object': 'chat.completion.chunk',
      'created': 0,
      'model': model,
      'choices': [
        {
          'index': 0,
          'delta': {'content': ?content},
          'finish_reason': finishReason,
        },
      ],
      ...?usage == null
          ? null
          : {
              'usage': {
                'prompt_tokens': usage.promptTokens,
                'completion_tokens': usage.completionTokens,
                'total_tokens': usage.totalTokens,
              },
            },
    };
  }

  @override
  void close() {}
}
