import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/mcp_tool_entity.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/timed_out_command_retry_guard.dart';
import 'package:test/test.dart';

const _guard = TimedOutCommandRetryGuard();

ToolCallInfo _call({
  String name = 'local_execute_command',
  Object? command = 'dart run tool.dart',
  Map<String, dynamic> extraArguments = const {},
}) {
  return ToolCallInfo(
    id: 'current-call',
    name: name,
    arguments: {'command': ?command, ...extraArguments},
  );
}

ToolResultInfo _result({
  String id = 'previous-result',
  String name = 'local_execute_command',
  Object? command = 'dart run tool.dart',
  bool timedOut = true,
  String? error = 'Command timed out after 60 seconds',
  String? resultCommand,
}) {
  return ToolResultInfo(
    id: id,
    name: name,
    arguments: {'command': ?command},
    result: jsonEncode({
      'timed_out': timedOut,
      'error': ?error,
      'command': ?resultCommand,
    }),
  );
}

TimedOutCommandRetryInput _input({
  ToolCallInfo? toolCall,
  List<ToolResultInfo>? executedToolResults,
}) {
  return TimedOutCommandRetryInput(
    toolCall: toolCall ?? _call(),
    executedToolResults: executedToolResults ?? [_result()],
  );
}

Map<String, dynamic> _payload(McpToolResult result) {
  return jsonDecode(result.result) as Map<String, dynamic>;
}

void main() {
  test('ignores non-command tools', () {
    expect(
      _guard.evaluate(_input(toolCall: _call(name: 'write_file'))),
      isNull,
    );
  });

  test('ignores read-only local and Git commands', () {
    for (final toolCall in [
      _call(command: 'ls'),
      _call(name: 'git_execute_command', command: 'status'),
    ]) {
      expect(_guard.evaluate(_input(toolCall: toolCall)), isNull);
    }
  });

  test('ignores command tools without a command argument', () {
    for (final toolCall in [
      _call(command: null),
      _call(command: '   '),
      _call(name: 'process_status', command: null),
    ]) {
      expect(_guard.evaluate(_input(toolCall: toolCall)), isNull);
    }
  });

  test('ignores results that did not time out', () {
    expect(
      _guard.evaluate(
        _input(executedToolResults: [_result(timedOut: false, error: null)]),
      ),
      isNull,
    );
  });

  test('detects timeout text when the timed_out flag is absent', () {
    final result = ToolResultInfo(
      id: 'text-timeout',
      name: 'local_execute_command',
      arguments: const {'command': 'dart run tool.dart'},
      result: '{"error":"Process TIMED OUT while waiting"}',
    );

    expect(_guard.evaluate(_input(executedToolResults: [result])), isNotNull);
  });

  test('requires a true timeout flag or the exact timed out phrase', () {
    final rejected = [
      _result(timedOut: false, error: 'Command timeout after 60 seconds'),
      ToolResultInfo(
        id: 'numeric-timeout',
        name: 'local_execute_command',
        arguments: const {'command': 'dart run tool.dart'},
        result: '{"timed_out":1}',
      ),
      ToolResultInfo(
        id: 'malformed-timeout',
        name: 'local_execute_command',
        arguments: const {'command': 'dart run tool.dart'},
        result: '{malformed',
      ),
      _result(name: 'write_file'),
    ];

    for (final result in rejected) {
      expect(
        _guard.evaluate(_input(executedToolResults: [result])),
        isNull,
        reason: result.id,
      );
    }
  });

  test('matches normalized commands from result arguments', () {
    final result = _guard.evaluate(
      _input(
        toolCall: _call(command: '  DART   RUN tool.dart  '),
        executedToolResults: [_result(command: 'dart run   tool.dart')],
      ),
    );

    expect(result, isNotNull);
    expect(_payload(result!)['command'], 'DART   RUN tool.dart');
  });

  test('normalizes model control tokens before command comparison', () {
    final result = _guard.evaluate(
      _input(
        toolCall: _call(command: 'DART <|tool|> RUN tool.dart'),
        executedToolResults: [_result(command: 'dart run tool.dart')],
      ),
    );

    expect(result, isNotNull);
  });

  test('matches a normalized command reported only in result JSON', () {
    final result = _guard.evaluate(
      _input(
        executedToolResults: [
          _result(command: null, resultCommand: ' DART run tool.dart '),
        ],
      ),
    );

    expect(result, isNotNull);
  });

  test('falls back to the result JSON after argument-command mismatch', () {
    final result = _guard.evaluate(
      _input(
        executedToolResults: [
          _result(
            command: 'dart run other.dart',
            resultCommand: 'dart run tool.dart',
          ),
        ],
      ),
    );

    expect(result, isNotNull);
  });

  test('ignores timeout results for a different command', () {
    expect(
      _guard.evaluate(
        _input(executedToolResults: [_result(command: 'dart run other.dart')]),
      ),
      isNull,
    );
  });

  test('preserves cross-command-tool matching compatibility', () {
    final result = _guard.evaluate(
      _input(executedToolResults: [_result(name: 'ssh_execute_command')]),
    );

    expect(result, isNotNull);
  });

  test('uses the reverse-most-recent matching timeout error', () {
    final result = _guard.evaluate(
      _input(
        executedToolResults: [
          _result(id: 'old', error: 'Old timeout'),
          _result(command: 'dart run other.dart', error: 'Other timeout'),
          _result(id: 'new', error: 'Newest matching timeout'),
        ],
      ),
    )!;

    expect(_payload(result)['previous_error'], 'Newest matching timeout');
  });

  test('retains an earlier timeout after a later non-timeout result', () {
    final result = _guard.evaluate(
      _input(
        executedToolResults: [
          _result(id: 'timeout', error: 'Original timeout'),
          _result(id: 'later-success', timedOut: false, error: null),
        ],
      ),
    )!;

    expect(_payload(result)['previous_error'], 'Original timeout');
  });

  test('preserves a null prior error in the exact blocked payload', () {
    final result = _guard.evaluate(
      _input(executedToolResults: [_result(error: null)]),
    )!;

    expect(_payload(result)['previous_error'], isNull);
  });

  test('returns the exact blocked result', () {
    final result = _guard.evaluate(_input())!;
    final expectedPayload = {
      'error':
          'The same command already timed out. Automatic retry is blocked '
          'because the previous process may still be running or may have '
          'partially completed side effects.',
      'code': TimedOutCommandRetryGuard.blockedCode,
      'command': 'dart run tool.dart',
      'previous_error': 'Command timed out after 60 seconds',
      'required_action':
          'Ask the user before retrying, or verify the previous process state '
          'with a read-only inspection command first.',
    };

    expect(result.toolName, 'local_execute_command');
    expect(result.isSuccess, isTrue);
    expect(result.errorMessage, isNull);
    expect(result.result, jsonEncode(expectedPayload));
    expect(_payload(result), expectedPayload);
  });

  test('uses only the supplied owner-turn results', () {
    final visibleTurnTimeout = _result(
      id: 'visible-timeout',
      command: 'dart run tool.dart',
      error: 'Visible turn timed out',
    );
    final ownerInput = _input(executedToolResults: const []);
    final visibleInput = _input(executedToolResults: [visibleTurnTimeout]);

    expect(_guard.evaluate(ownerInput), isNull);
    expect(_guard.evaluate(visibleInput), isNotNull);
    expect(_guard.evaluate(ownerInput), isNull);
  });

  test('recursively freezes current call and executed result arguments', () {
    final metadata = <String, dynamic>{
      'paths': <Object?>[
        'tool.dart',
        <String, dynamic>{
          'commands': <Object?>['dart run tool.dart'],
          'owners': <Object?>['owner-a'],
          'labels': <String, Object?>{'7': 'owner-a'},
        },
      ],
    };
    final callArguments = <String, dynamic>{
      'command': 'dart run tool.dart',
      'metadata': metadata,
    };
    final resultArguments = <String, dynamic>{
      'command': 'dart run tool.dart',
      'metadata': metadata,
    };
    final results = <ToolResultInfo>[
      ToolResultInfo(
        id: 'timeout',
        name: 'local_execute_command',
        arguments: resultArguments,
        result: '{"timed_out":true}',
      ),
    ];
    final input = TimedOutCommandRetryInput(
      toolCall: ToolCallInfo(
        id: 'current',
        name: 'local_execute_command',
        arguments: callArguments,
      ),
      executedToolResults: results,
    );

    callArguments['command'] = 'changed';
    resultArguments['command'] = 'changed';
    (((metadata['paths'] as List<Object?>)[1] as Map<String, dynamic>)['labels']
            as Map)['7'] =
        'visible';
    metadata['paths'] = <Object?>['changed'];
    results.clear();

    expect(input.toolCall.arguments['command'], 'dart run tool.dart');
    expect(
      input.executedToolResults.single.arguments['command'],
      'dart run tool.dart',
    );
    final frozenMetadata =
        input.toolCall.arguments['metadata'] as Map<String, dynamic>;
    final frozenPaths = frozenMetadata['paths'] as List<Object?>;
    expect(frozenPaths.first, 'tool.dart');
    final frozenNested = frozenPaths[1] as Map<String, dynamic>;
    final frozenOwners = frozenNested['owners'] as List<Object?>;
    final frozenLabels = frozenNested['labels'] as Map;
    expect(frozenLabels, {'7': 'owner-a'});
    expect(() => frozenLabels['7'] = 'late', throwsUnsupportedError);
    expect(() => frozenOwners.add('owner-b'), throwsUnsupportedError);
    expect(() => frozenPaths.add('changed'), throwsUnsupportedError);
    expect(
      () => input.toolCall.arguments['command'] = 'changed',
      throwsUnsupportedError,
    );
    expect(
      () => input.executedToolResults.single.arguments['command'] = 'changed',
      throwsUnsupportedError,
    );
    expect(
      () => input.executedToolResults.add(_result()),
      throwsUnsupportedError,
    );
  });
}
