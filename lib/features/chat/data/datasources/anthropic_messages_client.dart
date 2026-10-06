import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/constants/api_constants.dart';

/// Adapts Caverno's chat-completions transport to Anthropic's Messages API.
/// Only the official Anthropic host is adapted; other OpenAI-compatible servers
/// keep their existing wire format.
final class AnthropicMessagesClient extends http.BaseClient {
  AnthropicMessagesClient(this._delegate);

  final http.Client _delegate;

  static http.Client wrapIfNeeded(http.Client delegate, String? baseUrl) {
    final uri = Uri.tryParse(baseUrl?.trim() ?? '');
    return uri?.scheme == 'https' &&
            uri?.host.toLowerCase() == 'api.anthropic.com'
        ? AnthropicMessagesClient(delegate)
        : delegate;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.method != 'POST' ||
        request.url.host.toLowerCase() != 'api.anthropic.com' ||
        request.url.path != '/v1/chat/completions') {
      return _delegate.send(request);
    }
    final body = jsonDecode(await request.finalize().bytesToString());
    if (body is! Map<String, dynamic>) {
      throw const FormatException('Chat request must be a JSON object.');
    }
    final streaming = body['stream'] == true;
    final native = http.Request(
      'POST',
      request.url.replace(path: '/v1/messages'),
    );
    native.headers.addAll(request.headers);
    final authorization =
        request.headers['authorization'] ??
        request.headers['Authorization'] ??
        '';
    if (authorization.startsWith('Bearer ')) {
      native.headers['x-api-key'] = authorization.substring(7);
    }
    native.headers.remove('authorization');
    native.headers.remove('Authorization');
    native.headers['anthropic-version'] = ApiConstants.anthropicApiVersion;
    native.headers['content-type'] = 'application/json';
    native.body = jsonEncode(_toMessagesRequest(body));
    final response = await _delegate.send(native);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return response;
    }
    if (streaming) {
      return http.StreamedResponse(
        _translateStream(response.stream),
        response.statusCode,
        headers: {...response.headers, 'content-type': 'text/event-stream'},
        request: request,
      );
    }
    final decoded = jsonDecode(await response.stream.bytesToString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Anthropic response must be a JSON object.');
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(_toCompletion(decoded)))),
      response.statusCode,
      headers: {...response.headers, 'content-type': 'application/json'},
      request: request,
    );
  }

  @override
  void close() => _delegate.close();

  static Map<String, dynamic> _toMessagesRequest(Map<String, dynamic> input) {
    final system = <String>[];
    final messages = <Map<String, dynamic>>[];
    for (final raw in (input['messages'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final message = Map<String, dynamic>.from(raw);
      final role = message['role'];
      if (role == 'system' || role == 'developer') {
        final content = message['content'];
        if (content is String && content.isNotEmpty) system.add(content);
        continue;
      }
      if (role == 'tool') {
        final result = {
          'type': 'tool_result',
          'tool_use_id': message['tool_call_id'],
          'content': message['content']?.toString() ?? '',
        };
        if (messages.isNotEmpty &&
            messages.last['role'] == 'user' &&
            messages.last['content'] is List) {
          (messages.last['content'] as List).add(result);
        } else {
          messages.add({
            'role': 'user',
            'content': [result],
          });
        }
        continue;
      }
      if (role != 'user' && role != 'assistant') continue;
      final blocks = _contentBlocks(message['content']);
      if (role == 'assistant') {
        for (final rawCall in (message['tool_calls'] as List? ?? const [])) {
          if (rawCall is! Map) continue;
          final function = rawCall['function'];
          if (function is! Map) continue;
          final arguments = function['arguments'];
          blocks.add({
            'type': 'tool_use',
            'id': rawCall['id'],
            'name': function['name'],
            'input': arguments is String
                ? jsonDecode(arguments)
                : arguments ?? {},
          });
        }
      }
      messages.add({
        'role': role,
        'content': blocks.isEmpty
            ? [
                const {'type': 'text', 'text': ' '},
              ]
            : blocks,
      });
    }
    final tools = <Map<String, dynamic>>[];
    for (final raw in (input['tools'] as List? ?? const [])) {
      if (raw is! Map || raw['function'] is! Map) continue;
      final function = raw['function'] as Map;
      tools.add({
        'name': function['name'],
        if (function['description'] != null)
          'description': function['description'],
        'input_schema': function['parameters'] ?? {'type': 'object'},
        if (function['strict'] == true) 'strict': true,
      });
    }
    final maxTokens = input['max_tokens'] ?? input['max_completion_tokens'];
    final responseFormat = input['response_format'];
    Map<String, dynamic>? outputConfig;
    if (responseFormat is Map && responseFormat['type'] == 'json_schema') {
      final jsonSchema = responseFormat['json_schema'];
      if (jsonSchema is Map && jsonSchema['schema'] is Map) {
        outputConfig = {
          'format': {'type': 'json_schema', 'schema': jsonSchema['schema']},
        };
      }
    }
    const supportedEfforts = {'low', 'medium', 'high', 'xhigh', 'max'};
    final effort = input['reasoning_effort'];
    if (effort is String && supportedEfforts.contains(effort)) {
      outputConfig = {...?outputConfig, 'effort': effort};
    }
    return {
      'model': input['model'],
      'max_tokens': maxTokens is int && maxTokens > 0
          ? maxTokens
          : ApiConstants.defaultMaxTokens,
      'messages': messages,
      if (system.isNotEmpty) 'system': system.join('\n'),
      if (input['temperature'] is num) 'temperature': input['temperature'],
      if (input['top_p'] is num) 'top_p': input['top_p'],
      if (tools.isNotEmpty) 'tools': tools,
      'output_config': ?outputConfig,
      if (input['tool_choice'] is Map)
        'tool_choice': _toolChoice(input['tool_choice'] as Map),
      if (input['stream'] == true) 'stream': true,
    };
  }

  static Map<String, dynamic> _toolChoice(Map choice) {
    return switch (choice['type']) {
      'required' => {'type': 'any'},
      'function' => {
        'type': 'tool',
        'name': (choice['function'] as Map?)?['name'],
      },
      _ => {'type': 'auto'},
    };
  }

  static List<Map<String, dynamic>> _contentBlocks(Object? content) {
    if (content is String) {
      return content.isEmpty
          ? []
          : [
              {'type': 'text', 'text': content},
            ];
    }
    if (content is! List) return [];
    final blocks = <Map<String, dynamic>>[];
    for (final raw in content) {
      if (raw is! Map) continue;
      if (raw['type'] == 'text') {
        blocks.add({'type': 'text', 'text': raw['text']?.toString() ?? ''});
      } else if (raw['type'] == 'image_url') {
        final image = raw['image_url'];
        final url = image is Map ? image['url'] : image;
        if (url is! String || !url.startsWith('data:image/')) {
          throw const FormatException('Anthropic requires base64 image data.');
        }
        final separator = url.indexOf(';base64,');
        if (separator < 0) {
          throw const FormatException('Image must be base64 encoded.');
        }
        blocks.add({
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': url.substring(5, separator),
            'data': url.substring(separator + 8),
          },
        });
      } else {
        throw FormatException(
          'Unsupported Anthropic content part: ${raw['type']}',
        );
      }
    }
    return blocks;
  }

  static Map<String, dynamic> _toCompletion(Map<String, dynamic> message) {
    final text = StringBuffer();
    final calls = <Map<String, dynamic>>[];
    for (final raw in (message['content'] as List? ?? const [])) {
      if (raw is! Map) continue;
      if (raw['type'] == 'text') text.write(raw['text'] ?? '');
      if (raw['type'] == 'tool_use') {
        calls.add({
          'id': raw['id'],
          'type': 'function',
          'function': {
            'name': raw['name'],
            'arguments': jsonEncode(raw['input'] ?? {}),
          },
        });
      }
    }
    final usage = message['usage'] as Map? ?? const {};
    return {
      'id': message['id'] ?? '',
      'object': 'chat.completion',
      'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'model': message['model'] ?? '',
      'choices': [
        {
          'index': 0,
          'message': {
            'role': 'assistant',
            'content': text.toString(),
            if (calls.isNotEmpty) 'tool_calls': calls,
          },
          'finish_reason': _finishReason(message['stop_reason']),
        },
      ],
      'usage': _usage(usage),
    };
  }

  static String _finishReason(Object? reason) => switch (reason) {
    'tool_use' => 'tool_calls',
    'max_tokens' => 'length',
    _ => 'stop',
  };

  static Map<String, int> _usage(Map usage) {
    final prompt = (usage['input_tokens'] as num?)?.toInt() ?? 0;
    final completion = (usage['output_tokens'] as num?)?.toInt() ?? 0;
    return {
      'prompt_tokens': prompt,
      'completion_tokens': completion,
      'total_tokens': prompt + completion,
    };
  }

  static Stream<List<int>> _translateStream(Stream<List<int>> source) async* {
    var id = '';
    var model = '';
    var promptTokens = 0;
    var outputTokens = 0;
    final toolIndexes = <int, int>{};
    var nextToolIndex = 0;
    await for (final line
        in source.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;
      final data = line.substring(6).trim();
      if (data == '[DONE]') break;
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, dynamic>) continue;
      final type = decoded['type'];
      if (type == 'error') {
        throw FormatException('Anthropic stream error: ${decoded['error']}');
      }
      Map<String, dynamic>? delta;
      String? finishReason;
      if (type == 'message_start') {
        final message = decoded['message'];
        if (message is Map) {
          id = message['id']?.toString() ?? '';
          model = message['model']?.toString() ?? '';
          final usage = message['usage'];
          if (usage is Map) {
            promptTokens = (usage['input_tokens'] as num?)?.toInt() ?? 0;
          }
        }
      } else if (type == 'content_block_start') {
        final block = decoded['content_block'];
        final index = decoded['index'];
        if (block is Map && block['type'] == 'tool_use' && index is int) {
          final toolIndex = nextToolIndex++;
          toolIndexes[index] = toolIndex;
          delta = {
            'tool_calls': [
              {
                'index': toolIndex,
                'id': block['id'],
                'type': 'function',
                'function': {'name': block['name'], 'arguments': ''},
              },
            ],
          };
        }
      } else if (type == 'content_block_delta') {
        final blockDelta = decoded['delta'];
        final index = decoded['index'];
        if (blockDelta is Map && blockDelta['type'] == 'text_delta') {
          delta = {'content': blockDelta['text']};
        } else if (blockDelta is Map &&
            blockDelta['type'] == 'input_json_delta' &&
            index is int &&
            toolIndexes.containsKey(index)) {
          delta = {
            'tool_calls': [
              {
                'index': toolIndexes[index],
                'function': {'arguments': blockDelta['partial_json'] ?? ''},
              },
            ],
          };
        }
      } else if (type == 'message_delta') {
        final usage = decoded['usage'];
        if (usage is Map) {
          outputTokens = (usage['output_tokens'] as num?)?.toInt() ?? 0;
        }
        final messageDelta = decoded['delta'];
        if (messageDelta is Map) {
          finishReason = _finishReason(messageDelta['stop_reason']);
        }
      }
      if (delta != null || finishReason != null) {
        yield _sse({
          'id': id,
          'object': 'chat.completion.chunk',
          'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'model': model,
          'choices': [
            {
              'index': 0,
              'delta': delta ?? <String, dynamic>{},
              'finish_reason': finishReason,
            },
          ],
        });
      }
    }
    yield _sse({
      'id': id,
      'object': 'chat.completion.chunk',
      'created': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'model': model,
      'choices': [],
      'usage': _usage({
        'input_tokens': promptTokens,
        'output_tokens': outputTokens,
      }),
    });
    yield utf8.encode('data: [DONE]\n\n');
  }

  static List<int> _sse(Map<String, dynamic> data) =>
      utf8.encode('data: ${jsonEncode(data)}\n\n');
}
