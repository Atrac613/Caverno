import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/blocked_mutation_notice.dart';

ToolResultInfo _blockedEdit(
  String path, {
  String code = 'saved_task_target_scope_violation',
}) => ToolResultInfo(
  id: 'call-$path-$code',
  name: 'edit_file',
  arguments: {'path': path},
  result: jsonEncode({
    'ok': false,
    'code': code,
    'error': 'A file mutation was blocked because it targeted a file outside '
        'the active saved task scope.',
  }),
);

ToolResultInfo _appliedEdit(String path) => ToolResultInfo(
  id: 'call-$path',
  name: 'edit_file',
  arguments: {'path': path},
  result: jsonEncode({'path': path, 'replacements': 1, 'changed': true}),
);

void main() {
  const notice = BlockedMutationNotice();

  group('BlockedMutationNotice', () {
    test('says nothing when the turn attempted no mutation', () {
      final assessment = notice.assess([
        ToolResultInfo(
          id: 'read',
          name: 'read_file',
          arguments: const {'path': 'js/player.js'},
          result: jsonEncode({'path': 'js/player.js', 'content': 'x'}),
        ),
      ]);

      expect(assessment.hasBlockedMutations, isFalse);
    });

    test('says nothing when any mutation landed', () {
      final assessment = notice.assess([
        _blockedEdit('js/player.js'),
        _appliedEdit('js/main.js'),
      ]);

      expect(
        assessment.hasBlockedMutations,
        isFalse,
        reason: 'a turn that changed one file did not change nothing',
      );
    });

    // Session a0ca65b7 gen-4: every edit_file was refused, the successful
    // mutation count was zero, and the answer reported that the fix had been
    // applied. The real edit landed 49 minutes later in a different turn.
    test('reports the refusals when nothing landed', () {
      final assessment = notice.assess([
        _blockedEdit('js/player.js'),
        _blockedEdit('js/player.js'),
      ]);

      expect(assessment.hasBlockedMutations, isTrue);
      expect(
        assessment.blocked.single.path,
        'js/player.js',
        reason: 'one path refused twice is one refusal',
      );
      expect(
        assessment.buildNotice(),
        'File change check: this turn changed no files, because every file '
        'mutation it attempted was refused: `js/player.js` '
        '(saved_task_target_scope_violation).',
      );
    });

    test('keeps one path refused two different ways apart', () {
      final assessment = notice.assess([
        _blockedEdit('js/cave.js'),
        _blockedEdit('js/cave.js', code: 'project_mutation_outside_root'),
      ]);

      expect(assessment.blocked, hasLength(2));
      expect(
        assessment.buildNotice(),
        contains('project_mutation_outside_root'),
      );
    });

    test('reports a refusal that carried no structured code', () {
      final assessment = notice.assess([
        ToolResultInfo(
          id: 'call',
          name: 'write_file',
          arguments: const {'path': 'js/cave.js'},
          result: jsonEncode({'error': 'disk full'}),
        ),
      ]);

      expect(assessment.buildNotice(), contains('`js/cave.js`'));
      expect(assessment.buildNotice(), isNot(contains('(')));
    });

    test('does not depend on the wording of the answer', () {
      // The same refusal evidence produces the same notice whatever the model
      // wrote, which is the whole point of not reading the answer.
      final assessment = notice.assess([_blockedEdit('js/player.js')]);

      expect(assessment.hasBlockedMutations, isTrue);
    });
  });
}
