import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/unexecuted_file_mutation_before_command_guard.dart';
import 'package:test/test.dart';

void main() {
  const guard = UnexecutedFileMutationBeforeCommandGuard();

  test('bypasses non-command and internally executed read-only calls', () {
    for (final toolCall in [
      _call('read_file'),
      _call('local_execute_command', command: 'pwd'),
      _call('git_execute_command', command: 'status'),
    ]) {
      expect(guard.evaluate(_input(toolCall: toolCall)), isNull);
    }
  });

  test('bypasses for a pending mutation before or after the command', () {
    final command = _call('local_execute_command', command: 'dart analyze');
    final mutation = _call('edit_file', id: 'edit');

    for (final pendingToolCalls in [
      [mutation, command],
      [command, mutation],
    ]) {
      expect(
        guard.evaluate(
          _input(toolCall: command, pendingToolCalls: pendingToolCalls),
        ),
        isNull,
      );
    }
  });

  test('does not treat the current command identity as a pending mutation', () {
    final command = _call(
      'local_execute_command',
      id: 'shared',
      command: 'dart analyze',
    );
    final input = _input(
      toolCall: command,
      pendingToolCalls: [_call('edit_file', id: 'shared')],
    );

    expect(guard.evaluate(input), isNotNull);
  });

  test('bypasses after a successful file side effect result', () {
    final command = _call('process_start', command: 'dart analyze');
    final input = _input(
      toolCall: command,
      executedToolResults: [
        _result('edit_file', jsonEncode({'ok': true, 'path': 'lib/app.dart'})),
      ],
    );

    expect(guard.evaluate(input), isNull);
  });

  test('does not accept failed file mutation evidence', () {
    final command = _call('process_start', command: 'dart analyze');
    final input = _input(
      toolCall: command,
      executedToolResults: [
        _result('edit_file', jsonEncode({'ok': false, 'error': 'edit failed'})),
      ],
    );

    expect(guard.evaluate(input), isNotNull);
  });

  test(
    'bypasses blank content and content without a future mutation claim',
    () {
      final command = _call('process_start', command: 'dart analyze');
      for (final content in [null, ' ', 'The file was inspected.']) {
        expect(
          guard.evaluate(
            _input(toolCall: command, currentAssistantContent: content),
          ),
          isNull,
        );
      }
    },
  );

  test(
    'returns the exact payload with a normalized clipped claim and command',
    () {
      final command = _call('process_start', command: '  dart analyze  ');
      final claim =
          '${'I will edit the local file now. ' * 20}\nThen continue.';

      final result = guard.evaluate(
        _input(toolCall: command, currentAssistantContent: claim),
      )!;
      final expectedPayload = <String, Object?>{
        'ok': false,
        'code': 'unexecuted_file_save',
        'error':
            'A command was blocked because the assistant claimed a local file '
            'would be changed, but no successful write_file, edit_file, or '
            'rollback_last_file_change result is available for that claimed '
            'mutation.',
        'missing_tool': 'edit_file',
        'blocked_tool': 'process_start',
        'claimedResponse':
            '${claim.replaceAll(RegExp(r'\s+'), ' ').trim().substring(0, 240)}...',
        'required_action':
            'Use write_file or edit_file to perform the claimed file mutation '
            'before running the command, or explain that the command remains '
            'blocked because the file change was not executed.',
        'blocked_command': 'dart analyze',
      };

      expect(result.toolName, 'process_start');
      expect(result.isSuccess, isTrue);
      expect(result.errorMessage, isNull);
      expect(result.result, jsonEncode(expectedPayload));
    },
  );

  test('omits blocked command when the command argument is absent', () {
    final result = guard.evaluate(
      _input(
        toolCall: ToolCallInfo(
          id: 'command',
          name: 'process_start',
          arguments: const {},
        ),
      ),
    )!;

    expect(
      result.result,
      jsonEncode({
        'ok': false,
        'code': 'unexecuted_file_save',
        'error':
            'A command was blocked because the assistant claimed a local file '
            'would be changed, but no successful write_file, edit_file, or '
            'rollback_last_file_change result is available for that claimed '
            'mutation.',
        'missing_tool': 'edit_file',
        'blocked_tool': 'process_start',
        'claimedResponse': 'I will edit the local file now.',
        'required_action':
            'Use write_file or edit_file to perform the claimed file mutation '
            'before running the command, or explain that the command remains '
            'blocked because the file change was not executed.',
      }),
    );
  });

  test('snapshots the command, pending calls, and results recursively', () {
    final commandArguments = <String, dynamic>{
      'command': 'dart analyze',
      'nested': {
        'paths': ['lib/command.dart'],
      },
    };
    final pendingArguments = <String, dynamic>{
      'nested': {
        'paths': ['lib/app.dart'],
        'tags': <String>['owner'],
        'labels': <String, dynamic>{'primary': 'owner'},
      },
    };
    final resultArguments = <String, dynamic>{
      'nested': {
        'paths': ['lib/app.dart'],
      },
    };
    final input = _input(
      toolCall: ToolCallInfo(
        id: 'command',
        name: 'process_start',
        arguments: commandArguments,
      ),
      pendingToolCalls: [
        ToolCallInfo(
          id: 'pending',
          name: 'read_file',
          arguments: pendingArguments,
        ),
      ],
      executedToolResults: [
        ToolResultInfo(
          id: 'result',
          name: 'read_file',
          arguments: resultArguments,
          result: 'read',
        ),
      ],
    );
    (commandArguments['nested'] as Map)['paths'] = ['poisoned'];
    (pendingArguments['nested'] as Map)['paths'] = ['poisoned'];
    ((pendingArguments['nested'] as Map)['labels'] as Map)['primary'] =
        'visible';
    (resultArguments['nested'] as Map)['paths'] = ['poisoned'];

    expect(input.toolCall.arguments['nested'], {
      'paths': ['lib/command.dart'],
    });
    expect(input.pendingToolCalls.single.arguments['nested'], {
      'paths': ['lib/app.dart'],
      'tags': ['owner'],
      'labels': {'primary': 'owner'},
    });
    expect(input.executedToolResults.single.arguments['nested'], {
      'paths': ['lib/app.dart'],
    });
    expect(
      () => (input.pendingToolCalls.single.arguments['nested'] as Map)['late'] =
          true,
      throwsUnsupportedError,
    );
    expect(
      () =>
          ((input.pendingToolCalls.single.arguments['nested'] as Map)['labels']
                  as Map)['primary'] =
              'late',
      throwsUnsupportedError,
    );
    expect(
      () => (input.toolCall.arguments['nested'] as Map)['late'] = true,
      throwsUnsupportedError,
    );
  });

  test('rejects non-JSON tool-call and result arguments', () {
    for (final invalidValue in <Object?>[
      <Object?>{'owner-a'},
      <Object?, Object?>{7: 'owner-a'},
      double.nan,
    ]) {
      expect(
        () => _input(
          toolCall: ToolCallInfo(
            id: 'command',
            name: 'process_start',
            arguments: {'invalid': invalidValue},
          ),
        ),
        throwsArgumentError,
        reason: 'tool call ${invalidValue.runtimeType}',
      );
      expect(
        () => _input(
          executedToolResults: [
            ToolResultInfo(
              id: 'result',
              name: 'read_file',
              arguments: {'invalid': invalidValue},
              result: 'read',
            ),
          ],
        ),
        throwsArgumentError,
        reason: 'tool result ${invalidValue.runtimeType}',
      );
    }
  });

  test('another owner mutation result cannot affect the owner snapshot', () {
    final ownerInput = _input(owner: _owner('conversation-a'));
    final otherOwnerInput = _input(
      owner: _owner('conversation-b'),
      executedToolResults: [
        _result('write_file', jsonEncode({'ok': true})),
      ],
    );

    expect(ownerInput.owner, _owner('conversation-a'));
    expect(guard.evaluate(ownerInput), isNotNull);
    expect(guard.evaluate(otherOwnerInput), isNull);
    expect(guard.evaluate(ownerInput), isNotNull);
  });

  test('another owner claim cannot affect the owner snapshot', () {
    final ownerInput = _input(
      owner: _owner('conversation-a'),
      currentAssistantContent: 'The file was inspected.',
    );
    final otherOwnerInput = _input(
      owner: _owner('conversation-b'),
      currentAssistantContent: 'I will edit the local file now.',
    );

    expect(guard.evaluate(ownerInput), isNull);
    expect(guard.evaluate(otherOwnerInput), isNotNull);
    expect(guard.evaluate(ownerInput), isNull);
  });
}

ChatTurnOwner _owner(String conversationId) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: 5,
  );
}

UnexecutedFileMutationGuardInput _input({
  ChatTurnOwner? owner,
  ToolCallInfo? toolCall,
  String? currentAssistantContent = 'I will edit the local file now.',
  List<ToolCallInfo> pendingToolCalls = const [],
  List<ToolResultInfo> executedToolResults = const [],
}) {
  return UnexecutedFileMutationGuardInput(
    owner: owner ?? _owner('conversation-a'),
    toolCall:
        toolCall ?? _call('local_execute_command', command: 'dart analyze'),
    currentAssistantContent: currentAssistantContent,
    pendingToolCalls: pendingToolCalls,
    executedToolResults: executedToolResults,
  );
}

ToolCallInfo _call(String name, {String id = 'command', String? command}) {
  return ToolCallInfo(id: id, name: name, arguments: {'command': ?command});
}

ToolResultInfo _result(String name, String result) {
  return ToolResultInfo(
    id: 'result',
    name: name,
    arguments: const {},
    result: result,
  );
}
