import 'package:caverno/features/chat/data/datasources/chat_completion_response_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openai_dart/openai_dart.dart';

void main() {
  const normalizer = ChatCompletionResponseNormalizer();

  group('normalize', () {
    test('uses empty content and stop when provider fields are absent', () {
      final result = normalizer.normalize(
        content: null,
        reasoning: null,
        nativeToolCalls: null,
        finishReason: null,
        advertisedTools: null,
      );

      expect(result.content, isEmpty);
      expect(result.toolCalls, isNull);
      expect(result.finishReason, 'stop');
    });

    test('prepends one reasoning block to content', () {
      final result = normalizer.normalize(
        content: 'Answer',
        reasoning: 'Plan',
        nativeToolCalls: null,
        finishReason: 'length',
        advertisedTools: null,
      );

      expect(result.content, '<think>Plan</think>Answer');
      expect(result.finishReason, 'length');
    });

    test('keeps reasoning-only responses', () {
      final result = normalizer.normalize(
        content: null,
        reasoning: 'Plan',
        nativeToolCalls: null,
        finishReason: 'stop',
        advertisedTools: null,
      );

      expect(result.content, '<think>Plan</think>');
    });

    test('sanitizes native arguments and preserves provider finish reason', () {
      final result = normalizer.normalize(
        content: 'Reading',
        reasoning: null,
        nativeToolCalls: [
          _nativeCall(
            id: 'native-1',
            name: 'read_file',
            arguments: '{"path":"pubspec.yaml","extra":null}',
          ),
        ],
        finishReason: 'length',
        advertisedTools: _tools('read_file'),
      );

      expect(result.finishReason, 'length');
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls!.single.id, 'native-1');
      expect(result.toolCalls!.single.name, 'read_file');
      expect(result.toolCalls!.single.arguments, {
        'path': 'pubspec.yaml',
        'extra': null,
      });
    });

    test('keeps native calls with empty arguments when JSON is malformed', () {
      final errors = <Object>[];
      final result = normalizer.normalize(
        content: '',
        reasoning: null,
        nativeToolCalls: [
          _nativeCall(
            id: 'native-1',
            name: 'read_file',
            arguments: '{not-json',
          ),
        ],
        finishReason: 'tool_calls',
        advertisedTools: _tools('read_file'),
        onNativeArgumentError: errors.add,
      );

      expect(result.toolCalls!.single.arguments, isEmpty);
      expect(errors, hasLength(1));
    });

    test('native calls take precedence over advertised embedded calls', () {
      final result = normalizer.normalize(
        content: _embeddedCall('delete_file', 'bin/old.dart'),
        reasoning: null,
        nativeToolCalls: [
          _nativeCall(
            id: 'native-1',
            name: 'read_file',
            arguments: '{"path":"pubspec.yaml"}',
          ),
        ],
        finishReason: 'tool_calls',
        advertisedTools: _tools('delete_file'),
      );

      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls!.single.name, 'read_file');
    });

    test('promotes calls when every embedded name is advertised', () {
      final result = normalizer.normalize(
        content:
            '${_embeddedCall('read_file', 'pubspec.yaml')}${_embeddedCall('delete_file', 'bin/old.dart')}',
        reasoning: null,
        nativeToolCalls: null,
        finishReason: 'stop',
        advertisedTools: _tools('read_file', 'delete_file'),
      );

      expect(result.finishReason, 'tool_calls');
      expect(result.toolCalls!.map((call) => call.name), [
        'read_file',
        'delete_file',
      ]);
    });

    test('does not promote calls without advertised tools', () {
      final result = normalizer.normalize(
        content: _embeddedCall('delete_file', 'bin/old.dart'),
        reasoning: null,
        nativeToolCalls: null,
        finishReason: 'stop',
        advertisedTools: null,
      );

      expect(result.toolCalls, isNull);
      expect(result.finishReason, 'stop');
    });

    test('rejects the whole embedded batch when one name is not advertised', () {
      final result = normalizer.normalize(
        content:
            '${_embeddedCall('read_file', 'pubspec.yaml')}${_embeddedCall('delete_file', 'bin/old.dart')}',
        reasoning: null,
        nativeToolCalls: null,
        finishReason: 'stop',
        advertisedTools: _tools('read_file'),
      );

      expect(result.toolCalls, isNull);
      expect(result.finishReason, 'stop');
    });

    test('ignores incomplete embedded calls', () {
      final result = normalizer.normalize(
        content: '<tool_call>{"name":"read_file"',
        reasoning: null,
        nativeToolCalls: null,
        finishReason: 'length',
        advertisedTools: _tools('read_file'),
      );

      expect(result.toolCalls, isNull);
      expect(result.finishReason, 'length');
    });
  });

  group('recoverFromParseFailure', () {
    test('normalizes thought channel markers', () {
      final result = normalizer.recoverFromParseFailure(
        Exception(
          'Failed to parse input at pos 13: '
          '<|channel>thought planning<channel|>Answer',
        ),
      );

      expect(result, isNotNull);
      expect(result!.content, '<think> planning</think>Answer');
      expect(result.toolCalls, isNull);
      expect(result.finishReason, 'stop');
    });

    test('normalizes analysis markers case-insensitively', () {
      final result = normalizer.recoverFromParseFailure(
        Exception(
          'Failed to parse input at pos 2: '
          '<|CHANNEL|>ANALYSIS inspect<channel|>Done',
        ),
      );

      expect(result!.content, '<think> inspect</think>Done');
    });

    test('promotes completed raw calls without advertised-tool metadata', () {
      final result = normalizer.recoverFromParseFailure(
        Exception(
          'Failed to parse input at pos 9: '
          '${_embeddedCall('write_file', 'out.txt')}',
        ),
      );

      expect(result!.finishReason, 'tool_calls');
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls!.single.name, 'write_file');
      expect(result.toolCalls!.single.arguments['path'], 'out.txt');
      expect(result.toolCalls!.single.id, isNotEmpty);
    });

    test('returns null for unrelated errors', () {
      expect(
        normalizer.recoverFromParseFailure(Exception('Connection refused')),
        isNull,
      );
    });

    test('returns null for an empty raw payload', () {
      expect(
        normalizer.recoverFromParseFailure(
          Exception('Failed to parse input at pos 4:    '),
        ),
        isNull,
      );
    });
  });
}

ToolCall _nativeCall({
  required String id,
  required String name,
  required String arguments,
}) {
  return ToolCall(
    id: id,
    type: 'function',
    function: FunctionCall(name: name, arguments: arguments),
  );
}

List<Map<String, dynamic>> _tools(String first, [String? second]) {
  return [
    for (final name in [first, ?second])
      {
        'type': 'function',
        'function': {'name': name},
      },
  ];
}

String _embeddedCall(String name, String path) {
  return '<tool_call>{"name":"$name","arguments":{"path":"$path"}}</tool_call>';
}
