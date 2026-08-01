import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/git_write_confirmation_policy.dart';
import 'package:test/test.dart';

void main() {
  const policy = GitWriteConfirmationPolicy();

  group('Git write classification', () {
    test('accepts always-write and conditional-write Git commands', () {
      for (final command in [
        'add lib/app.dart',
        'commit -m "Update app"',
        'push origin main',
        'reset --hard HEAD~1',
        'checkout feature/work',
        'merge feature/work',
        'rebase main',
        'branch feature/work',
        'tag v1.2.3',
        'stash push',
        'config user.name "Caverno"',
      ]) {
        expect(
          policy.isWriteGitCommandToolCall(
            _call('git_execute_command', command),
          ),
          isTrue,
          reason: command,
        );
      }

      expect(
        policy.isWriteGitCommandToolCall(
          _call('  GIT_EXECUTE_COMMAND  ', '  commit -m "Update app"  '),
        ),
        isTrue,
      );
    });

    test('rejects always-read and conditional-read Git commands', () {
      for (final command in [
        'status --short',
        'git log -1 --oneline',
        'diff --stat',
        'branch --list',
        'tag --list',
        'stash list',
        'config --get user.name',
      ]) {
        expect(
          policy.isWriteGitCommandToolCall(
            _call('git_execute_command', command),
          ),
          isFalse,
          reason: command,
        );
      }
    });

    test('rejects missing or blank commands and non-Git tools', () {
      for (final arguments in const <Map<String, dynamic>>[
        {},
        {'command': null},
        {'command': ''},
        {'command': '   '},
      ]) {
        expect(
          policy.isWriteGitCommandToolCall(
            ToolCallInfo(
              id: 'call',
              name: 'git_execute_command',
              arguments: arguments,
            ),
          ),
          isFalse,
          reason: '$arguments',
        );
      }
      expect(
        policy.isWriteGitCommandToolCall(
          _call('local_execute_command', 'git commit'),
        ),
        isFalse,
      );
    });
  });

  group('confirmation question recognition', () {
    test(
      'recognizes every English Git write family with case and whitespace',
      () {
        for (final content in [
          'Should I commit these changes?',
          'May I STAGE the files?',
          'Proceed with staging?',
          'Can I push now?',
          'Run reset?',
          'Use checkout?',
          'Merge this branch?',
          'Start the rebase?',
          'Should I run git add?',
          'Should I run git commit?',
        ]) {
          expect(
            policy.looksLikeGitWriteConfirmationQuestion(content),
            isTrue,
            reason: content,
          );
        }
        expect(
          policy.looksLikeGitWriteConfirmationQuestion(
            '  Should I commit these changes?  ',
          ),
          isTrue,
        );
      },
    );

    test('rejects empty, oversized, declarative, and unrelated questions', () {
      expect(policy.looksLikeGitWriteConfirmationQuestion(''), isFalse);
      expect(
        policy.looksLikeGitWriteConfirmationQuestion('${'a' * 1201}? commit'),
        isFalse,
      );
      expect(
        policy.looksLikeGitWriteConfirmationQuestion(
          'I will commit these changes.',
        ),
        isFalse,
      );
      expect(
        policy.looksLikeGitWriteConfirmationQuestion('Run the tests?'),
        isFalse,
      );
      expect(
        policy.looksLikeGitWriteConfirmationQuestion(
          'Should I document the commitment?',
        ),
        isFalse,
      );
    });

    test('recognizes every localized action and question-marker family', () {
      final actions = [
        [0x30b3, 0x30df, 0x30c3, 0x30c8],
        [0x30b9, 0x30c6, 0x30fc, 0x30b8],
        [0x30d7, 0x30c3, 0x30b7, 0x30e5],
        [0x30ea, 0x30bb, 0x30c3, 0x30c8],
        [0x30c1, 0x30a7, 0x30c3, 0x30af, 0x30a2, 0x30a6, 0x30c8],
        [0x30de, 0x30fc, 0x30b8],
        [0x30ea, 0x30d9, 0x30fc, 0x30b9],
      ].map(String.fromCharCodes);
      final questionMarkers = [
        [0x3f],
        [0xff1f],
        [0x3057, 0x307e, 0x3059, 0x304b],
        [0x3057, 0x3066, 0x3082, 0x3044, 0x3044, 0x3067, 0x3059, 0x304b],
        [0x3057, 0x3066, 0x3088, 0x3044, 0x3067, 0x3059, 0x304b],
      ].map(String.fromCharCodes);

      for (final action in actions) {
        for (final marker in questionMarkers) {
          final content = '$action$marker';
          expect(
            policy.looksLikeGitWriteConfirmationQuestion(content),
            isTrue,
            reason: content,
          );
        }
      }
    });
  });

  group('batch blocking', () {
    test(
      'blocks only when both a confirmation question and Git write exist',
      () {
        expect(
          policy.shouldBlock(
            _input(
              content: 'Should I commit these changes?',
              calls: [_call('git_execute_command', 'commit -m "Update"')],
            ),
          ),
          isTrue,
        );
        expect(
          policy.shouldBlock(
            _input(
              content: 'Should I commit these changes?',
              calls: [_call('git_execute_command', 'status')],
            ),
          ),
          isFalse,
        );
        expect(
          policy.shouldBlock(
            _input(
              content: 'I will commit these changes.',
              calls: [_call('git_execute_command', 'commit -m "Update"')],
            ),
          ),
          isFalse,
        );
        expect(
          policy.shouldBlock(
            _input(content: 'Should I commit these changes?', calls: const []),
          ),
          isFalse,
        );
        expect(
          policy.shouldBlock(
            _input(
              content: null,
              calls: [_call('git_execute_command', 'commit -m "Update"')],
            ),
          ),
          isFalse,
        );
        expect(
          policy.shouldBlock(
            _input(
              content: '  SHOULD I COMMIT THESE CHANGES?  ',
              calls: [
                _call('  GIT_EXECUTE_COMMAND  ', '  commit -m "Update"  '),
              ],
            ),
          ),
          isTrue,
        );
        final trimDependentQuestion =
            '${' ' * 1201}Should I commit these changes?${' ' * 1201}';
        expect(
          policy.looksLikeGitWriteConfirmationQuestion(trimDependentQuestion),
          isFalse,
        );
        expect(
          policy.shouldBlock(
            _input(
              content: trimDependentQuestion,
              calls: [_call('git_execute_command', 'commit -m "Update"')],
            ),
          ),
          isTrue,
        );
      },
    );

    test('blocks a mixed batch when any call is a Git write', () {
      expect(
        policy.shouldBlock(
          _input(
            content: 'Should I push the branch?',
            calls: [
              _call('read_file', 'ignored'),
              _call('git_execute_command', 'status'),
              _call('git_execute_command', 'push origin main'),
            ],
          ),
        ),
        isTrue,
      );
    });

    test('does not treat non-Git mutations as Git writes', () {
      expect(
        policy.shouldBlock(
          _input(
            content: 'Should I commit these changes?',
            calls: [
              _call('write_file', 'ignored'),
              _call('local_execute_command', 'git commit'),
            ],
          ),
        ),
        isFalse,
      );
    });

    test('another owner question cannot poison an owner write batch', () {
      final ownerWriteInput = _input(
        owner: _owner('conversation-a'),
        content: 'Continue with inspection.',
        calls: [_call('git_execute_command', 'commit -m "Update"')],
      );
      final otherQuestionInput = _input(
        owner: _owner('conversation-b'),
        content: 'Should I commit these changes?',
        calls: const [],
      );

      expect(ownerWriteInput.owner, _owner('conversation-a'));
      expect(policy.shouldBlock(ownerWriteInput), isFalse);
      expect(policy.shouldBlock(otherQuestionInput), isFalse);
      expect(policy.shouldBlock(ownerWriteInput), isFalse);
    });

    test('another owner pending write cannot poison an owner question', () {
      final ownerQuestionInput = _input(
        owner: _owner('conversation-a'),
        content: 'Should I commit these changes?',
        calls: const [],
      );
      final otherWriteInput = _input(
        owner: _owner('conversation-b'),
        content: 'Continue with inspection.',
        calls: [_call('git_execute_command', 'commit -m "Update"')],
      );

      expect(policy.shouldBlock(ownerQuestionInput), isFalse);
      expect(policy.shouldBlock(otherWriteInput), isFalse);
      expect(policy.shouldBlock(ownerQuestionInput), isFalse);
    });

    test('snapshots nested pending arguments recursively', () {
      final nested = <String, dynamic>{
        'owner': 'owner-a',
        'values': ['commit'],
        'flags': <String>['owner'],
      };
      final arguments = <String, dynamic>{
        'command': 'commit',
        'nested': nested,
      };
      final input = _input(
        content: 'Should I commit these changes?',
        calls: [
          ToolCallInfo(
            id: 'call',
            name: 'git_execute_command',
            arguments: arguments,
          ),
        ],
      );
      arguments['command'] = 'status';
      (nested['values'] as List<String>).add('poison');
      (nested['flags'] as List<String>).add('poison');
      nested['owner'] = 'visible';

      expect(input.pendingToolCalls.single.arguments['command'], 'commit');
      expect(input.pendingToolCalls.single.arguments['nested'], {
        'owner': 'owner-a',
        'values': ['commit'],
        'flags': ['owner'],
      });
      expect(policy.shouldBlock(input), isTrue);
      expect(
        () => input.pendingToolCalls.add(_call('read_file', 'ignored')),
        throwsUnsupportedError,
      );
      expect(
        () =>
            (input.pendingToolCalls.single.arguments['nested'] as Map)['late'] =
                true,
        throwsUnsupportedError,
      );
      expect(
        () =>
            (input.pendingToolCalls.single.arguments['nested']
                    as Map)['owner'] =
                'late',
        throwsUnsupportedError,
      );
      expect(
        () =>
            (input.pendingToolCalls.single.arguments['nested'] as Map)['values']
                  as List
              ..add('late'),
        throwsUnsupportedError,
      );
      expect(
        () =>
            (input.pendingToolCalls.single.arguments['nested'] as Map)['flags']
                  as List
              ..add('late'),
        throwsUnsupportedError,
      );
    });

    test('rejects non-JSON pending arguments', () {
      for (final invalidValue in <Object?>[
        <Object?>{'owner-a'},
        <Object?, Object?>{7: 'owner-a'},
        double.infinity,
      ]) {
        expect(
          () => _input(
            content: 'Should I commit these changes?',
            calls: [
              ToolCallInfo(
                id: 'call',
                name: 'git_execute_command',
                arguments: {'command': 'commit', 'invalid': invalidValue},
              ),
            ],
          ),
          throwsArgumentError,
          reason: invalidValue.runtimeType.toString(),
        );
      }
    });
  });
}

ChatTurnOwner _owner(String conversationId) {
  return ChatTurnOwner(
    conversationId: conversationId,
    interactionGeneration: 6,
  );
}

GitWriteConfirmationInput _input({
  ChatTurnOwner? owner,
  required String? content,
  required List<ToolCallInfo> calls,
}) {
  return GitWriteConfirmationInput(
    owner: owner ?? _owner('conversation-a'),
    currentAssistantContent: content,
    pendingToolCalls: calls,
  );
}

ToolCallInfo _call(String name, String command) {
  return ToolCallInfo(id: 'call', name: name, arguments: {'command': command});
}
