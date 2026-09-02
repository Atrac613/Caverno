import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/chat_turn_owner.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/saved_task_target_scope_guard.dart';
import 'package:test/test.dart';

final _ownerA = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 7,
);
final _ownerB = ChatTurnOwner(
  conversationId: 'conversation-b',
  interactionGeneration: 7,
);
final _ownerANext = ChatTurnOwner(
  conversationId: 'conversation-a',
  interactionGeneration: 8,
);

ConversationWorkflowTask _task({
  String id = 'task-a',
  String title = 'Implement owner A',
  List<String> targetFiles = const ['lib/a.dart'],
  String validationCommand = '',
}) {
  return ConversationWorkflowTask(
    id: id,
    title: title,
    targetFiles: targetFiles,
    validationCommand: validationCommand,
  );
}

ToolCallInfo _call({
  String name = 'write_file',
  Object? path = 'lib/a.dart',
  Map<String, dynamic>? arguments,
}) {
  return ToolCallInfo(
    id: 'tool-1',
    name: name,
    arguments:
        arguments ?? <String, dynamic>{'path': ?path, 'content': 'updated\n'},
  );
}

SavedTaskTargetScopeInput _input({
  ChatTurnOwner? owner,
  ToolCallInfo? toolCall,
  ConversationWorkflowTask? ownerTask,
  String? ownerProjectRoot = '/workspace/owner-a',
}) {
  return SavedTaskTargetScopeInput(
    owner: owner ?? _ownerA,
    toolCall: toolCall ?? _call(),
    ownerTask: ownerTask,
    ownerProjectRoot: ownerProjectRoot,
  );
}

Map<String, dynamic> _payload(String result) {
  return jsonDecode(result) as Map<String, dynamic>;
}

void main() {
  const guard = SavedTaskTargetScopeGuard();

  group('SavedTaskTargetScopeGuard applicability', () {
    test('allows mutations without an owner task', () {
      for (final toolName in const ['write_file', 'edit_file']) {
        expect(
          guard.evaluate(
            _input(
              toolCall: _call(name: toolName, path: 'outside.dart'),
              ownerTask: null,
            ),
          ),
          isNull,
        );
      }
    });

    test('allows mutations once the owner task is completed', () {
      // Session a0ca65b7: all five tasks finished, `validationTask` kept
      // returning task 1 because it carries a validation command, and every
      // later edit to js/player.js and js/cave.js was refused.
      final task = _task(
        targetFiles: const ['index.html', 'js/main.js'],
        validationCommand: 'node --check js/main.js',
      ).copyWith(status: ConversationWorkflowTaskStatus.completed);
      for (final toolName in const ['write_file', 'edit_file']) {
        expect(
          guard.evaluate(
            _input(
              toolCall: _call(name: toolName, path: 'js/player.js'),
              ownerTask: task,
            ),
          ),
          isNull,
        );
      }
    });

    test('still scopes an unfinished owner task', () {
      for (final status in const [
        ConversationWorkflowTaskStatus.pending,
        ConversationWorkflowTaskStatus.inProgress,
        ConversationWorkflowTaskStatus.blocked,
      ]) {
        final result = guard.evaluate(
          _input(
            toolCall: _call(path: 'js/player.js'),
            ownerTask: _task(
              targetFiles: const ['index.html', 'js/main.js'],
            ).copyWith(status: status),
          ),
        );
        expect(result, isNotNull, reason: 'status $status must still scope');
        expect(
          _payload(result!.result)['code'],
          'saved_task_target_scope_violation',
        );
      }
    });

    test('does not activate from validation paths when targets are empty', () {
      final task = _task(
        targetFiles: const [],
        validationCommand: 'dart run bin/tool.dart',
      );

      expect(
        guard.evaluate(
          _input(
            toolCall: _call(path: 'outside.dart'),
            ownerTask: task,
          ),
        ),
        isNull,
      );
      expect(guard.allowedTargetFilesForTask(task), ['bin/tool.dart']);
    });

    test('ignores every non-write or edit tool', () {
      final task = _task();

      for (final toolName in const [
        'read_file',
        'delete_file',
        'rollback_last_file_change',
        'write_files',
      ]) {
        expect(
          guard.evaluate(
            _input(
              toolCall: _call(name: toolName, path: 'outside.dart'),
              ownerTask: task,
            ),
          ),
          isNull,
          reason: toolName,
        );
      }
    });

    test('normalizes the mutation tool name but preserves it in results', () {
      final result = guard.evaluate(
        _input(
          toolCall: _call(name: '  EDIT_FILE  ', path: 'outside.dart'),
          ownerTask: _task(),
        ),
      );

      expect(result, isNotNull);
      expect(result!.toolName, '  EDIT_FILE  ');
    });

    test('allows missing, blank, null, and non-string paths', () {
      final task = _task();
      for (final arguments in const <Map<String, dynamic>>[
        {},
        {'path': null},
        {'path': ''},
        {'path': '   '},
        {'path': 17},
      ]) {
        expect(
          guard.evaluate(
            _input(
              toolCall: _call(arguments: arguments),
              ownerTask: task,
            ),
          ),
          isNull,
          reason: '$arguments',
        );
      }
    });
  });

  group('SavedTaskTargetScopeGuard path matching', () {
    test('allows exact relative and absolute target paths', () {
      final task = _task(targetFiles: const ['lib/main.dart']);

      for (final path in const [
        'lib/main.dart',
        '/workspace/owner-a/lib/main.dart',
      ]) {
        expect(
          guard.evaluate(
            _input(
              toolCall: _call(path: path),
              ownerTask: task,
            ),
          ),
          isNull,
          reason: path,
        );
      }
    });

    test('normalizes case, slash style, whitespace, and dot segments', () {
      final task = _task(targetFiles: const ['  LIB\\MAIN.DART  ']);

      for (final path in const [
        'lib/main.dart',
        ' LIB/MAIN.DART ',
        'lib/src/../main.dart',
      ]) {
        expect(
          guard.evaluate(
            _input(
              toolCall: _call(path: path),
              ownerTask: task,
            ),
          ),
          isNull,
          reason: path,
        );
      }
    });

    test('matches relative paths without a project root', () {
      final task = _task(targetFiles: const ['LIB\\main.dart']);

      expect(
        guard.evaluate(
          _input(
            toolCall: _call(path: 'lib/main.dart'),
            ownerTask: task,
            ownerProjectRoot: null,
          ),
        ),
        isNull,
      );
    });

    test('allows nested paths only for explicit directory targets', () {
      for (final directoryTarget in const ['lib/', 'lib\\', 'lib///']) {
        expect(
          guard.evaluate(
            _input(
              toolCall: _call(path: 'lib/src/main.dart'),
              ownerTask: _task(targetFiles: [directoryTarget]),
            ),
          ),
          isNull,
          reason: directoryTarget,
        );
      }

      expect(
        guard.evaluate(
          _input(
            toolCall: _call(path: 'lib'),
            ownerTask: _task(targetFiles: const ['lib']),
          ),
        ),
        isNull,
      );
      expect(
        guard.evaluate(
          _input(
            toolCall: _call(path: 'lib/main.dart'),
            ownerTask: _task(targetFiles: const ['lib']),
          ),
        ),
        isNotNull,
      );
      expect(
        guard.evaluate(
          _input(
            toolCall: _call(path: 'library/main.dart'),
            ownerTask: _task(targetFiles: const ['lib/']),
          ),
        ),
        isNotNull,
      );
    });

    test(
      'blocks relative and absolute paths outside the owner root target',
      () {
        final task = _task(targetFiles: const ['lib/main.dart']);

        for (final path in const [
          'README.md',
          '../other/lib/main.dart',
          '/workspace/owner-b/lib/main.dart',
        ]) {
          expect(
            guard.evaluate(
              _input(
                toolCall: _call(path: path),
                ownerTask: task,
              ),
            ),
            isNotNull,
            reason: path,
          );
        }
      },
    );

    test(
      'treats an empty normalized path as allowed and skips blank targets',
      () {
        expect(
          guard.allowsPath(
            path: '   ',
            targetFiles: const ['outside.dart'],
            projectRoot: '/workspace/owner-a',
          ),
          isTrue,
        );
        expect(
          guard.allowsPath(
            path: 'outside.dart',
            targetFiles: const [' ', '\n'],
            projectRoot: '/workspace/owner-a',
          ),
          isFalse,
        );
      },
    );
  });

  group('SavedTaskTargetScopeGuard target expansion', () {
    test('adds validation executables but excludes runtime state files', () {
      final task = _task(
        targetFiles: const ['lib/main.dart'],
        validationCommand: 'rm -f tasks.json && dart run bin/todo.dart list',
      );

      expect(guard.allowedTargetFilesForTask(task), [
        'lib/main.dart',
        'bin/todo.dart',
      ]);
      expect(
        guard.evaluate(
          _input(
            toolCall: _call(path: 'bin/todo.dart'),
            ownerTask: task,
          ),
        ),
        isNull,
      );
      expect(
        guard.evaluate(
          _input(
            toolCall: _call(path: 'tasks.json'),
            ownerTask: task,
          ),
        ),
        isNotNull,
      );
    });

    test('includes executable paths for supported validation runtimes', () {
      final cases = <String, String>{
        'python3 tool/check.py': 'tool/check.py',
        'pytest test/test_app.py': 'test/test_app.py',
        'node tool/check.js': 'tool/check.js',
        'bash tool/check.sh': 'tool/check.sh',
        'go run cmd/check.go': 'cmd/check.go',
      };

      for (final entry in cases.entries) {
        final allowed = guard.allowedTargetFilesForTask(
          _task(
            targetFiles: const ['lib/main.dart'],
            validationCommand: entry.key,
          ),
        );
        expect(allowed, contains(entry.value), reason: entry.key);
      }
    });

    test(
      'deduplicates exact targets in stable order and returns a frozen list',
      () {
        final targets = <String>[
          'lib/main.dart',
          'lib/main.dart',
          'bin/todo.dart',
        ];
        final task = _task(
          targetFiles: targets,
          validationCommand: 'dart run bin/todo.dart',
        );

        final allowed = guard.allowedTargetFilesForTask(task);

        expect(allowed, ['lib/main.dart', 'bin/todo.dart']);
        expect(() => allowed.add('poison.dart'), throwsUnsupportedError);
        targets
          ..clear()
          ..add('poison.dart');
        expect(allowed, ['lib/main.dart', 'bin/todo.dart']);
      },
    );
  });

  group('SavedTaskTargetScopeGuard result', () {
    test('returns the exact blocked result payload', () {
      final result = guard.evaluate(
        _input(
          toolCall: _call(name: 'edit_file', path: '  README.md  '),
          ownerTask: _task(
            id: 'task-owner-a',
            title: 'Implement owner A target',
            targetFiles: const ['lib/a.dart'],
            validationCommand: 'dart test test/a_test.dart',
          ),
        ),
      );

      expect(result, isNotNull);
      expect(result!.toolName, 'edit_file');
      expect(result.isSuccess, isFalse);
      expect(
        result.errorMessage,
        'File mutation is outside the active saved task targets.',
      );
      expect(_payload(result.result), {
        'ok': false,
        'code': 'saved_task_target_scope_violation',
        'result_origin': 'refusal',
        'error':
            'A file mutation was blocked because it targeted a file outside '
            'the active saved task target files.',
        'task_id': 'task-owner-a',
        'task_title': 'Implement owner A target',
        'attempted_path': 'README.md',
        'allowed_target_files': ['lib/a.dart', 'test/a_test.dart'],
        'required_action':
            'Modify only the active saved task target files, or finish the '
            'current saved task before starting work on another file.',
      });
    });
  });

  group('SavedTaskTargetScopeGuard owner poison', () {
    test('snapshots owner task, tool arguments, and nested values', () {
      final targets = <String>['lib/a.dart'];
      final metadata = <String, dynamic>{
        'paths': <Object?>['lib/a.dart'],
        'tags': <Object?>['owner-a'],
        'labels': <String, Object?>{'7': 'owner-a'},
      };
      final arguments = <String, dynamic>{
        'path': 'lib/a.dart',
        'content': 'owner a\n',
        'metadata': metadata,
      };
      final input = _input(
        toolCall: _call(arguments: arguments),
        ownerTask: _task(targetFiles: targets),
      );
      targets
        ..clear()
        ..add('lib/b.dart');
      arguments['path'] = 'lib/b.dart';
      (metadata['paths']! as List<Object?>).add('lib/b.dart');
      (metadata['tags']! as List<Object?>).add('owner-b');
      (metadata['labels']! as Map)['7'] = 'owner-b';

      expect(guard.evaluate(input), isNull);
      expect(input.owner, same(_ownerA));
      expect(input.ownerTask!.targetFiles, ['lib/a.dart']);
      expect(input.toolCall.arguments['path'], 'lib/a.dart');
      final frozenLabels =
          (input.toolCall.arguments['metadata']
                  as Map<String, dynamic>)['labels']
              as Map;
      expect(frozenLabels, {'7': 'owner-a'});
      expect(
        () => input.toolCall.arguments['path'] = 'poison.dart',
        throwsUnsupportedError,
      );
      expect(
        () =>
            ((input.toolCall.arguments['metadata']
                        as Map<String, dynamic>)['paths']
                    as List<Object?>)
                .add('poison.dart'),
        throwsUnsupportedError,
      );
      expect(() => frozenLabels['7'] = 'late', throwsUnsupportedError);
    });

    test('visible task and root cannot replace either owner snapshot', () {
      final visibleTargets = <String>['lib/b.dart'];
      var visibleTask = _task(
        id: 'task-b',
        title: 'Implement owner B',
        targetFiles: visibleTargets,
      );
      var visibleRoot = '/workspace/owner-b';
      final ownerAInput = _input(
        owner: _ownerA,
        toolCall: _call(path: 'lib/b.dart'),
        ownerTask: _task(
          id: 'task-a',
          title: 'Implement owner A',
          targetFiles: const ['lib/a.dart'],
        ),
        ownerProjectRoot: '/workspace/owner-a',
      );
      final ownerBInput = _input(
        owner: _ownerB,
        toolCall: _call(path: 'lib/a.dart'),
        ownerTask: visibleTask,
        ownerProjectRoot: visibleRoot,
      );

      visibleTargets.add('lib/a.dart');
      visibleTask = _task(
        id: 'visible-task-replaced',
        title: 'Visible task replaced',
        targetFiles: const ['lib/a.dart', 'lib/b.dart'],
      );
      visibleRoot = '/workspace/owner-a';

      final ownerAResult = guard.evaluate(ownerAInput)!;
      final ownerBResult = guard.evaluate(ownerBInput)!;

      expect(visibleTask.id, 'visible-task-replaced');
      expect(visibleRoot, '/workspace/owner-a');
      expect(ownerAInput.owner, same(_ownerA));
      expect(ownerBInput.owner, same(_ownerB));
      expect(_payload(ownerAResult.result), {
        'ok': false,
        'code': 'saved_task_target_scope_violation',
        'result_origin': 'refusal',
        'error':
            'A file mutation was blocked because it targeted a file outside '
            'the active saved task target files.',
        'task_id': 'task-a',
        'task_title': 'Implement owner A',
        'attempted_path': 'lib/b.dart',
        'allowed_target_files': ['lib/a.dart'],
        'required_action':
            'Modify only the active saved task target files, or finish the '
            'current saved task before starting work on another file.',
      });
      expect(_payload(ownerBResult.result)['task_id'], 'task-b');
      expect(_payload(ownerBResult.result)['attempted_path'], 'lib/a.dart');
      expect(_payload(ownerBResult.result)['allowed_target_files'], [
        'lib/b.dart',
      ]);
    });

    test('resolves relative paths only against the captured owner root', () {
      var visibleRoot = '/workspace/owner-b';
      final ownerAInput = _input(
        owner: _ownerA,
        toolCall: _call(path: 'lib/a.dart'),
        ownerTask: _task(targetFiles: const ['/workspace/owner-a/lib/a.dart']),
        ownerProjectRoot: '/workspace/owner-a',
      );
      visibleRoot = '/workspace/successor';
      final successorInput = _input(
        owner: _ownerANext,
        toolCall: _call(path: 'lib/a.dart'),
        ownerTask: _task(
          id: 'task-successor',
          title: 'Implement successor',
          targetFiles: const ['/workspace/successor/lib/a.dart'],
        ),
        ownerProjectRoot: '/workspace/successor',
      );
      visibleRoot = '/workspace/poison';

      expect(guard.evaluate(ownerAInput), isNull);
      expect(guard.evaluate(successorInput), isNull);
      expect(visibleRoot, '/workspace/poison');
      expect(ownerAInput.owner, same(_ownerA));
      expect(successorInput.owner, same(_ownerANext));

      final wrongRootInput = _input(
        owner: _ownerB,
        toolCall: _call(path: 'lib/a.dart'),
        ownerTask: _task(targetFiles: const ['/workspace/owner-a/lib/a.dart']),
        ownerProjectRoot: '/workspace/owner-b',
      );
      expect(guard.evaluate(wrongRootInput), isNotNull);
    });
  });
}
