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
}
