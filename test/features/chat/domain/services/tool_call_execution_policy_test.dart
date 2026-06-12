import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_call_execution_policy.dart';

void main() {
  const policy = ToolCallExecutionPolicy();

  group('ToolCallExecutionPolicy', () {
    test('normalizes tool call keys and project paths', () {
      final first = policy.toolExecutionKey(
        _toolCall('read_file', {'path': './lib/main.dart', 'z': 1}),
        resolveProjectPath: (path) => '/project/lib/main.dart',
      );
      final second = policy.toolExecutionKey(
        _toolCall('READ_FILE', {'z': 1, 'path': 'lib/main.dart'}),
        resolveProjectPath: (path) => '/project/lib/main.dart',
      );

      expect(first, second);
    });

    test('adds command retry generation only for repeatable commands', () {
      final commandKey = policy.toolExecutionKey(
        _toolCall('local_execute_command', {'command': 'fvm flutter test'}),
        commandRetryGeneration: 2,
      );
      final writeKey = policy.toolExecutionKey(
        _toolCall('write_file', {'path': 'README.md'}),
        commandRetryGeneration: 2,
      );

      expect(commandKey, contains('commandRetryGeneration=2'));
      expect(writeKey, isNot(contains('commandRetryGeneration=2')));
    });

    test('allows repeated inspection and process monitor calls', () {
      expect(
        policy.shouldAllowRepeatedToolExecution(_toolCall('read_file')),
        isTrue,
      );
      expect(
        policy.shouldAllowRepeatedToolExecution(_toolCall('process_tail')),
        isTrue,
      );
      expect(
        policy.shouldAllowRepeatedToolExecution(
          _toolCall('local_execute_command', {
            'command': 'sleep 1; ps -ef | rg dart',
          }),
        ),
        isTrue,
      );
      expect(
        policy.shouldAllowRepeatedToolExecution(
          _toolCall('local_execute_command', {'command': 'fvm flutter test'}),
        ),
        isFalse,
      );
    });

    test('classifies read-only inspection command tool calls', () {
      expect(
        policy.isReadOnlyInspectionToolCall(_toolCall('search_files')),
        isTrue,
      );
      expect(
        policy.isReadOnlyInspectionToolCall(
          _toolCall('local_execute_command', {'command': 'pwd'}),
        ),
        isTrue,
      );
      expect(
        policy.isReadOnlyInspectionToolCall(
          _toolCall('local_execute_command', {'command': 'rm -rf build'}),
        ),
        isFalse,
      );
    });

    test('detects successful command tool results', () {
      expect(
        policy.toolResultHasSuccessfulExit(
          _result(
            'local_execute_command',
            '{"exit_code":0,"stdout":"ok","stderr":""}',
          ),
        ),
        isTrue,
      );
      expect(
        policy.toolResultHasSuccessfulExit(
          _result(
            'process_wait',
            '{"ok":true,"status":"exited","exit_code":0}',
          ),
        ),
        isTrue,
      );
      expect(
        policy.toolResultHasSuccessfulExit(
          _result('local_execute_command', '{"exit_code":1,"stderr":"fail"}'),
        ),
        isFalse,
      );
    });

    test('detects timed out command results and error text', () {
      final result = _result(
        'local_execute_command',
        '{"timed_out":true,"error":"Command timed out"}',
      );

      expect(policy.toolResultTimedOut(result), isTrue);
      expect(policy.toolResultErrorText(result), 'Command timed out');
    });

    test('matches saved validation wrappers conservatively', () {
      final success = _result(
        'local_execute_command',
        '{"exit_code":0,"stdout":"all green","stderr":""}',
      );
      final failureOutput = _result(
        'local_execute_command',
        '{"exit_code":0,"stdout":"validation failed","stderr":""}',
      );

      expect(
        policy.toolCommandMatchesSavedValidation(
          result: success,
          command: 'fvm flutter test && echo ok',
          normalizedValidationCommand: policy.normalizeToolCommandForComparison(
            'fvm flutter test',
          ),
        ),
        isTrue,
      );
      expect(
        policy.toolCommandMatchesSavedValidation(
          result: failureOutput,
          command: 'fvm flutter test && echo ok',
          normalizedValidationCommand: policy.normalizeToolCommandForComparison(
            'fvm flutter test',
          ),
        ),
        isFalse,
      );
    });
  });
}

ToolCallInfo _toolCall(
  String name, [
  Map<String, dynamic> arguments = const {},
]) {
  return ToolCallInfo(id: 'tool-$name', name: name, arguments: arguments);
}

ToolResultInfo _result(String name, String result) {
  return ToolResultInfo(
    id: 'result-$name',
    name: name,
    arguments: const {},
    result: result,
  );
}
