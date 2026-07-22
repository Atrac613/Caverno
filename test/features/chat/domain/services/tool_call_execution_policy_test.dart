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

    test('execution key keeps reason so re-narrated inspection can re-run', () {
      // Two read-only inspections at the same retry generation are distinguished
      // only by `reason` (e.g. `git status` after a commit, then after a
      // revert). The execution key must keep `reason` so the second is not
      // skipped as a duplicate.
      final afterCommit = policy.toolExecutionKey(
        _toolCall('git_execute_command', {
          'command': 'status',
          'reason': 'Inspect status after commit.',
        }),
      );
      final afterRevert = policy.toolExecutionKey(
        _toolCall('git_execute_command', {
          'command': 'status',
          'reason': 'Inspect final status after revert.',
        }),
      );

      expect(afterCommit, isNot(afterRevert));
    });

    test('execution key ignores reason for file mutations', () {
      final first = policy.toolExecutionKey(
        _toolCall('edit_file', {
          'path': 'pubspec.yaml',
          'old_text': 'name: todo',
          'new_text': 'name: todo_app',
          'reason': 'Align the package name.',
        }),
      );
      final repeated = policy.toolExecutionKey(
        _toolCall('edit_file', {
          'path': 'pubspec.yaml',
          'old_text': 'name: todo',
          'new_text': 'name: todo_app',
          'reason': 'Fix package imports.',
        }),
      );

      expect(first, repeated);
      expect(
        policy.isFileMutationToolCall(
          _toolCall('delete_file', {'path': 'obsolete.txt'}),
        ),
        isTrue,
      );
    });

    test('failure key ignores reason so retried denials collapse to one', () {
      // The model rewording `reason` between identical commands must not mint a
      // fresh failure key, otherwise the consecutive-failure abort never fires
      // and it re-issues the same (e.g. denied) command indefinitely.
      final first = policy.toolFailureKey(
        _toolCall('local_execute_command', {
          'command': 'python3 hello.py',
          'reason': 'output hello world',
        }),
      );
      final second = policy.toolFailureKey(
        _toolCall('local_execute_command', {
          'command': 'python3 hello.py',
          'reason': 'run hello.py to print Hello World',
        }),
      );
      final bare = policy.toolFailureKey(
        _toolCall('local_execute_command', {'command': 'python3 hello.py'}),
      );

      expect(first, second);
      expect(first, bare);
    });

    test('failure key still distinguishes different commands', () {
      final hello = policy.toolFailureKey(
        _toolCall('local_execute_command', {
          'command': 'python3 hello.py',
          'reason': 'same reason',
        }),
      );
      final inline = policy.toolFailureKey(
        _toolCall('local_execute_command', {
          'command': "python3 -c \"print('Hello, World!')\"",
          'reason': 'same reason',
        }),
      );

      expect(hello, isNot(inline));
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

    test('treats read-only git inspection as inspection but writes as not', () {
      // Read-only git probing must count as inspection so repeated
      // `git status` / `git tag --list` loops trip the duplicate-inspection
      // and loop-exhaustion recovery guards.
      expect(
        policy.isReadOnlyInspectionToolCall(
          _toolCall('git_execute_command', {'command': 'status'}),
        ),
        isTrue,
      );
      expect(
        policy.isReadOnlyInspectionToolCall(
          _toolCall('git_execute_command', {'command': 'tag --list'}),
        ),
        isTrue,
      );
      expect(
        policy.isReadOnlyInspectionToolCall(
          _toolCall('git_execute_command', {'command': 'commit -m "release"'}),
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


  group('offersCommandExecution', () {
    const policy = ToolCallExecutionPolicy();

    test('a full catalog can always execute a command', () {
      expect(policy.offersCommandExecution(null), isTrue);
    });

    test('a turn restricted to update_goal cannot', () {
      // The completion elicitation. A command claim made there is
      // unexecutable, not unexecuted — session 76864d26.
      expect(policy.offersCommandExecution(const {'update_goal'}), isFalse);
    });

    test('a validation-only continuation still can', () {
      // Restricted, but to the tools that run the verifier: a command claim
      // there really is unexecuted and must keep being faulted.
      expect(
        policy.offersCommandExecution(const {
          'local_execute_command',
          'run_tests',
        }),
        isTrue,
      );
    });

    test('a repair-only continuation cannot', () {
      expect(
        policy.offersCommandExecution(const {
          'read_file',
          'write_file',
          'edit_file',
          'delete_file',
        }),
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
