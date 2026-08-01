import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/saved_validation_command_guard.dart';
import 'package:test/test.dart';

void main() {
  const guard = SavedValidationCommandGuard();

  group('SavedValidationCommandGuard evaluate', () {
    test(
      'ignores non-command tools, absent saved values, and absent commands',
      () {
        expect(
          guard.evaluate(
            _input(
              toolCall: _tool('read_file', 'cat test/result.txt'),
              savedCommand: 'cat test/result.txt',
            ),
          ),
          isNull,
        );
        expect(
          guard.evaluate(
            _input(
              toolCall: _tool('local_execute_command', 'cat test/result.txt'),
              savedCommand: null,
            ),
          ),
          isNull,
        );
        expect(
          guard.evaluate(
            _input(
              toolCall: ToolCallInfo(
                id: 'call',
                name: 'local_execute_command',
                arguments: const {},
              ),
              savedCommand: 'cat test/result.txt',
            ),
          ),
          isNull,
        );
      },
    );

    test('accepts exact and whitespace-normalized commands', () {
      for (final attempted in [
        'dart test test/widget_test.dart',
        '  DART   TEST   test/widget_test.dart  ',
      ]) {
        expect(
          guard.evaluate(
            _input(
              toolCall: _tool('local_execute_command', attempted),
              savedCommand: 'dart test test/widget_test.dart',
            ),
          ),
          isNull,
          reason: attempted,
        );
      }
    });

    test('blocks every shell operator appended to the saved command', () {
      for (final operator in ['&&', '||', ';', '|']) {
        final result = guard.evaluate(
          _input(
            toolCall: _tool(
              'local_execute_command',
              'dart test test/widget_test.dart $operator echo changed',
            ),
            savedCommand: 'dart test test/widget_test.dart',
          ),
        );

        expect(result, isNotNull, reason: operator);
      }
    });

    test('does not block unrelated or merely extended command arguments', () {
      expect(
        guard.evaluate(
          _input(
            toolCall: _tool('local_execute_command', 'dart analyze'),
            savedCommand: 'dart test test/widget_test.dart',
          ),
        ),
        isNull,
      );
      expect(
        guard.evaluate(
          _input(
            toolCall: _tool(
              'local_execute_command',
              'dart test test/widget_test.dart --coverage',
            ),
            savedCommand: 'dart test test/widget_test.dart',
          ),
        ),
        isNull,
      );
    });

    test('returns the exact blocked payload', () {
      final result = guard.evaluate(
        _input(
          toolCall: _tool(
            'process_start',
            'dart test test/widget_test.dart && echo changed',
          ),
          savedCommand: 'dart test test/widget_test.dart',
        ),
      )!;

      expect(result.toolName, 'process_start');
      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'Run the saved validation command exactly as saved.',
      );
      expect(jsonDecode(result.result), {
        'ok': false,
        'code': 'saved_validation_command_modified',
        'error':
            'A saved validation command was blocked because it was modified '
            'before execution.',
        'saved_validation_command': 'dart test test/widget_test.dart',
        'attempted_command': 'dart test test/widget_test.dart && echo changed',
        'required_action':
            'Run the saved validation command exactly as saved, without '
            'wrappers, shell operators, extra echo commands, or fallback '
            'branches.',
      });
    });
  });

  group('path-resolved saved validation commands', () {
    test('detects equivalent relative and absolute cat or ls paths', () {
      for (final executable in ['cat', 'ls']) {
        expect(
          guard.looksLikePathResolvedSavedValidationCommand(
            command: '$executable /workspace/project/test/result.txt',
            validationCommand: '$executable test/result.txt',
            ownerProjectRoot: '/workspace/project',
          ),
          isTrue,
          reason: executable,
        );
      }
      expect(
        guard.looksLikePathResolvedSavedValidationCommand(
          command: 'ls /workspace/project/test/results///',
          validationCommand: 'ls test/results',
          ownerProjectRoot: '/workspace/project',
        ),
        isTrue,
      );
    });

    test('detects test and grep path positions', () {
      expect(
        guard.looksLikePathResolvedSavedValidationCommand(
          command: 'test -f /workspace/project/test/result.txt',
          validationCommand: 'test -f test/result.txt',
          ownerProjectRoot: '/workspace/project',
        ),
        isTrue,
      );
      expect(
        guard.looksLikePathResolvedSavedValidationCommand(
          command: 'grep -n needle /workspace/project/test/result.txt',
          validationCommand: 'grep -n needle test/result.txt',
          ownerProjectRoot: '/workspace/project',
        ),
        isTrue,
      );
    });

    test('blocks a path-resolved variant through the public guard', () {
      final result = guard.evaluate(
        _input(
          toolCall: _tool(
            'local_execute_command',
            'cat /workspace/project/test/result.txt',
          ),
          savedCommand: 'cat test/result.txt',
          ownerProjectRoot: '/workspace/project',
        ),
      );

      expect(result, isNotNull);
    });

    test('rejects different shapes, executables, flags, and paths', () {
      final cases = [
        (
          attempted: 'cat /workspace/project/test/result.txt extra',
          saved: 'cat test/result.txt',
        ),
        (
          attempted: 'ls /workspace/project/test/result.txt',
          saved: 'cat test/result.txt',
        ),
        (
          attempted: 'test -d /workspace/project/test/result.txt',
          saved: 'test -f test/result.txt',
        ),
        (
          attempted: 'grep -i needle /workspace/project/test/result.txt',
          saved: 'grep -n needle test/result.txt',
        ),
        (
          attempted: 'cat /workspace/project/test/other.txt',
          saved: 'cat test/result.txt',
        ),
        (attempted: 'echo value', saved: 'echo value'),
        (attempted: 'cat', saved: 'cat'),
      ];

      for (final item in cases) {
        expect(
          guard.looksLikePathResolvedSavedValidationCommand(
            command: item.attempted,
            validationCommand: item.saved,
            ownerProjectRoot: '/workspace/project',
          ),
          isFalse,
          reason: item.toString(),
        );
      }
    });

    test('uses only the first simple shell segment', () {
      expect(
        guard.simpleCommandSegmentArgs('cat test/result.txt && echo ignored'),
        ['cat', 'test/result.txt'],
      );
      expect(guard.simpleCommandSegmentArgs('cat test/result.txt'), [
        'cat',
        'test/result.txt',
      ]);
      for (final value in ['&&', '||', ';', '|']) {
        expect(guard.isShellControlArgument(value), isTrue);
      }
      expect(guard.isShellControlArgument('&'), isFalse);
    });

    test('reports each supported path argument index', () {
      expect(guard.savedValidationPathArgumentIndex(['cat', 'file']), 1);
      expect(guard.savedValidationPathArgumentIndex(['ls', 'folder']), 1);
      expect(guard.savedValidationPathArgumentIndex(['test', '-f', 'file']), 2);
      expect(
        guard.savedValidationPathArgumentIndex([
          '/usr/bin/grep',
          '-n',
          'needle',
          'file',
        ]),
        3,
      );
      expect(guard.savedValidationPathArgumentIndex(['echo', 'file']), isNull);
      expect(guard.savedValidationPathArgumentIndex(['cat']), isNull);
    });
  });

  test(
    'another owner saved command cannot alter the supplied owner context',
    () {
      final attempted = _tool(
        'local_execute_command',
        'dart test test/a_test.dart && echo changed',
      );
      final ownerAInput = _input(
        owner: _owner('conversation-a'),
        toolCall: attempted,
        savedCommand: 'dart test test/a_test.dart',
      );
      final ownerBInput = _input(
        owner: _owner('conversation-b'),
        toolCall: attempted,
        savedCommand: 'dart test test/b_test.dart',
      );

      expect(ownerAInput.owner, _owner('conversation-a'));
      expect(ownerBInput.owner, _owner('conversation-b'));
      expect(guard.evaluate(ownerAInput), isNotNull);
      expect(guard.evaluate(ownerBInput), isNull);
    },
  );

  test('path resolution stays with the captured owner project root', () {
    final attempted = _tool(
      'local_execute_command',
      'cat /workspace/owner-a/test/result.txt',
    );
    final ownerAInput = _input(
      owner: _owner('conversation-a'),
      toolCall: attempted,
      savedCommand: 'cat test/result.txt',
      ownerProjectRoot: '/workspace/owner-a',
    );
    final ownerBInput = _input(
      owner: _owner('conversation-b'),
      toolCall: attempted,
      savedCommand: 'cat test/result.txt',
      ownerProjectRoot: '/workspace/owner-b',
    );

    expect(guard.evaluate(ownerAInput), isNotNull);
    expect(guard.evaluate(ownerBInput), isNull);
  });

  test('snapshots the owner tool call and every nested argument value', () {
    final nested = <String, dynamic>{
      'paths': <Object?>['test/a_test.dart'],
      'tags': <Object?>['owner-a'],
      'labels': <String, Object?>{'7': 'owner-a'},
    };
    final arguments = <String, dynamic>{
      'command': 'dart test test/a_test.dart && echo changed',
      'metadata': nested,
    };
    final input = _input(
      toolCall: ToolCallInfo(
        id: 'call-owner-a',
        name: 'local_execute_command',
        arguments: arguments,
      ),
      savedCommand: 'dart test test/a_test.dart',
    );

    arguments['command'] = 'dart test test/b_test.dart';
    (nested['paths']! as List<Object?>).add('test/b_test.dart');
    (nested['tags']! as List<Object?>).add('owner-b');
    (nested['labels']! as Map)['7'] = 'owner-b';

    expect(guard.evaluate(input), isNotNull);
    expect(
      input.toolCall.arguments['command'],
      'dart test test/a_test.dart && echo changed',
    );
    final frozenLabels =
        (input.toolCall.arguments['metadata'] as Map<String, dynamic>)['labels']
            as Map;
    expect(frozenLabels, {'7': 'owner-a'});
    expect(
      () => input.toolCall.arguments['command'] = 'poison',
      throwsUnsupportedError,
    );
    expect(
      () =>
          ((input.toolCall.arguments['metadata']
                      as Map<String, dynamic>)['paths']
                  as List<Object?>)
              .add('poison'),
      throwsUnsupportedError,
    );
    expect(
      () =>
          ((input.toolCall.arguments['metadata']
                      as Map<String, dynamic>)['tags']
                  as List<Object?>)
              .add('poison'),
      throwsUnsupportedError,
    );
    expect(() => frozenLabels['7'] = 'late', throwsUnsupportedError);
  });
}

ChatTurnOwner _owner(String conversationId) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: 3,
  );
}

SavedValidationCommandInput _input({
  ChatTurnOwner? owner,
  required ToolCallInfo toolCall,
  required String? savedCommand,
  String? ownerProjectRoot,
}) {
  return SavedValidationCommandInput(
    owner: owner ?? _owner('conversation-a'),
    toolCall: toolCall,
    savedCommand: savedCommand,
    ownerProjectRoot: ownerProjectRoot,
  );
}

ToolCallInfo _tool(String name, String command) {
  return ToolCallInfo(id: 'call', name: name, arguments: {'command': command});
}
