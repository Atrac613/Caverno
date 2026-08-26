import 'package:flutter_test/flutter_test.dart';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_loop_context_digest.dart';

void main() {
  const digest = ToolLoopContextDigest();

  group('ToolLoopContextDigest', () {
    test('returns empty when there is nothing worth repeating', () {
      expect(digest.build(const []), isEmpty);
      expect(
        digest.build([
          _result('read_file', {'path': 'a.dart'}),
        ]),
        isEmpty,
        reason: 'a single read is below the minimum entry threshold',
      );
    });

    test('lists distinct reads, listings and searches', () {
      final block = digest.build([
        _result('list_directory', {'path': 'docs'}),
        _result('read_file', {'path': 'docs/release.md'}),
        _result('search_files', {'query': 'version'}),
      ]);

      expect(block, contains('listed docs'));
      expect(block, contains('read docs/release.md'));
      expect(block, contains('searched "version"'));
      expect(block, contains('Context already gathered this turn'));
    });

    test('deduplicates repeated reads of the same path', () {
      final block = digest.build([
        _result('list_directory', {'path': 'docs'}),
        _result('list_directory', {'path': 'docs'}),
        _result('read_file', {'path': 'a.dart'}),
      ]);

      expect('listed docs'.allMatches(block).length, 1);
    });

    test('ignores volatile and non-read tools', () {
      final block = digest.build([
        _result('process_status', {'path': 'job'}),
        _result('git_execute_command', {'command': 'log'}),
        _result('read_file', {'path': 'a.dart'}),
        _result('read_file', {'path': 'b.dart'}),
      ]);

      expect(block, isNot(contains('process_status')));
      expect(block, isNot(contains('git_execute_command')));
      expect(block, contains('read a.dart'));
      expect(block, contains('read b.dart'));
    });

    test('caps the number of listed entries', () {
      final results = [
        for (var i = 0; i < 30; i++) _result('read_file', {'path': 'f$i.dart'}),
      ];

      final block = digest.build(results, maxEntries: 5);
      expect('- read'.allMatches(block).length, 5);
    });

    test(
      'flags a repeated read that returned identical content as unchanged',
      () {
        final block = digest.build([
          _result('read_file', {'path': 'a.dart'}, result: 'contents-v1'),
          _result('read_file', {'path': 'b.dart'}, result: 'other'),
          _result('read_file', {'path': 'a.dart'}, result: 'contents-v1'),
        ]);

        expect(block, contains('read a.dart (unchanged'));
        expect(
          block,
          isNot(contains('read b.dart (unchanged')),
          reason: 'b.dart was read only once',
        );
        // Still one line per path.
        expect('read a.dart'.allMatches(block).length, 1);
      },
    );

    test('does not flag a repeated read whose content changed', () {
      final block = digest.build([
        _result('read_file', {'path': 'a.dart'}, result: 'contents-v1'),
        _result('read_file', {'path': 'b.dart'}, result: 'other'),
        _result('read_file', {'path': 'a.dart'}, result: 'contents-v2'),
      ]);

      expect(block, contains('- read a.dart'));
      expect(
        block,
        isNot(contains('unchanged')),
        reason: 'the file legitimately changed between reads',
      );
    });

    test(
      'over budget keeps repeated and most-recent reads, drops the old head',
      () {
        final block = digest.build([
          // Read early and repeated with identical content — must survive the
          // budget even though it is the oldest entry.
          _result('read_file', {'path': 'old.dart'}, result: 'x'),
          _result('read_file', {'path': 'old.dart'}, result: 'x'),
          _result('read_file', {'path': 'a.dart'}),
          _result('read_file', {'path': 'b.dart'}),
          _result('read_file', {'path': 'c.dart'}),
          _result('read_file', {'path': 'd.dart'}),
        ], maxEntries: 3);

        // Repeated old file is retained (and flagged unchanged).
        expect(block, contains('read old.dart (unchanged'));
        // The two most-recently-read files are retained.
        expect(block, contains('read c.dart'));
        expect(block, contains('read d.dart'));
        // Older distinct reads beyond the budget are dropped, not the tail.
        expect(block, isNot(contains('read a.dart')));
        expect(block, isNot(contains('read b.dart')));
      },
    );

    test('flags a paged re-read as unchanged when the file hash matches', () {
      // The label for a read is the path alone, so two paging windows of one
      // file collapse to one label with two different bodies. Byte-identity
      // cannot tell that apart from a real change; the hash can.
      final block = digest.build([
        _result(
          'read_file',
          {'path': 'lib/app.dart', 'offset': 1, 'limit': 40},
          result: 'lines 1-40',
          contentHash: 'hash-a',
        ),
        _result(
          'read_file',
          {'path': 'lib/app.dart', 'offset': 41, 'limit': 40},
          result: 'lines 41-80',
          contentHash: 'hash-a',
        ),
        _result('list_directory', {'path': 'lib'}),
      ]);

      expect(block, contains('read lib/app.dart (unchanged'));
    });

    test('does not flag unchanged when the file hash moved', () {
      final block = digest.build([
        _result(
          'read_file',
          {'path': 'lib/app.dart'},
          result: 'same rendering',
          contentHash: 'hash-a',
        ),
        _result(
          'read_file',
          {'path': 'lib/app.dart'},
          result: 'same rendering',
          contentHash: 'hash-b',
        ),
        _result('list_directory', {'path': 'lib'}),
      ]);

      expect(block, contains('read lib/app.dart'));
      expect(
        block,
        isNot(contains('unchanged')),
        reason: 'the hash is ground truth and outranks identical renderings',
      );
    });

    test('falls back to byte-identity when a repeat carries no hash', () {
      // An unhashable read (too large, an error) is unknown, and unknown must
      // not be allowed to imply unchanged via the hashed subset.
      final block = digest.build([
        _result(
          'read_file',
          {'path': 'lib/app.dart'},
          result: 'body',
          contentHash: 'hash-a',
        ),
        _result('read_file', {'path': 'lib/app.dart'}, result: 'body'),
        _result('list_directory', {'path': 'lib'}),
      ]);

      expect(
        block,
        contains('read lib/app.dart (unchanged'),
        reason: 'identical bodies still prove the read returned the same text',
      );

      final changed = digest.build([
        _result(
          'read_file',
          {'path': 'lib/app.dart'},
          result: 'first',
          contentHash: 'hash-a',
        ),
        _result('read_file', {'path': 'lib/app.dart'}, result: 'second'),
        _result('list_directory', {'path': 'lib'}),
      ]);

      expect(changed, isNot(contains('unchanged')));
    });

    test('lists commands already run this turn', () {
      // Session 655e367f: the same gh investigation was re-issued because the
      // digest never mentioned commands, only file reads.
      const runLog =
          'gh run view 31986552620 --repo Shiftall/gs1_flutter_app --log-failed';
      final block = digest.build([
        _result('local_execute_command', {
          'command': runLog,
          'reason': 'CIログから失敗ステップを抽出するため',
        }, result: 'pub get failed'),
        _result('local_execute_command', {
          'command': runLog,
          'reason': '失敗ステップだけを抽出して根本原因を確認するため',
        }, result: 'pub get failed'),
        _result('git_execute_command', {
          'command': 'status --short --branch',
        }, result: '## main'),
      ]);

      expect(block, contains('Commands already run this turn'));
      expect(block, contains('ran `$runLog`'));
      expect(block, contains('already run 2x this turn'));
      expect(block, contains('ran `git status --short --branch`'));
      // A reworded reason must not split one command into two entries.
      expect('ran `$runLog`'.allMatches(block).length, 1);
    });

    test('never claims a command was unchanged', () {
      final block = digest.build([
        _result('local_execute_command', {
          'command': 'fvm flutter test',
        }, result: 'All tests passed!'),
        _result('local_execute_command', {
          'command': 'fvm flutter test',
        }, result: 'All tests passed!'),
        // A second distinct entry: one label alone stays below minEntries.
        _result('local_execute_command', {'command': 'fvm flutter analyze'}),
      ]);

      // Identical output does not license "do not repeat": a verification
      // command must stay repeatable after an edit.
      expect(block, isNot(contains('unchanged')));
      expect(block, isNot(contains('do not repeat')));
      expect(block, contains('run it again only when you need its output'));
      // The output is not carried into the next request, so the digest must
      // not present it as still readable.
      expect(block, contains('not carried into this request'));
      expect(block, isNot(contains('Use what they returned')));
    });

    test('omits a command the fence refused before it ran', () {
      // Session a0ca65b7: two heredoc writes were blocked by the project
      // mutation fence and still reached the model as "ran `cat > …`", with
      // the advisory not to re-issue them.
      const blocked =
          '{"ok":false,"code":"project_mutation_outside_root",'
          '"error":"The mutation target is outside the authorized project '
          'root.","path":"//"}';
      final block = digest.build([
        _result('read_file', {'path': 'js/cave.js'}),
        _result('local_execute_command', {
          'command': "cat > js/cave.js << 'CAVE_EOF'\n// body\nCAVE_EOF",
        }, result: blocked),
        _result('local_execute_command', {
          'command': 'fvm flutter analyze',
        }, result: '{"command":"fvm flutter analyze","exit_code":0,'
            '"stdout":"No issues found!","stderr":""}'),
      ]);

      expect(block, isNot(contains('cat > js/cave.js')));
      expect(block, contains('ran `fvm flutter analyze`'));
    });

    test('keeps a command that ran and failed', () {
      final block = digest.build([
        _result('local_execute_command', {
          'command': 'fvm flutter test',
        }, result: '{"command":"fvm flutter test","exit_code":1,'
            '"stdout":"Some tests failed.","stderr":""}'),
        _result('local_execute_command', {'command': 'fvm flutter analyze'}),
      ]);

      expect(block, contains('ran `fvm flutter test`'));
      expect(block, contains('ran `fvm flutter analyze`'));
    });

    test('keeps command and inspection sections separate', () {
      final block = digest.build([
        _result('read_file', {'path': 'pubspec.yaml'}),
        _result('local_execute_command', {'command': 'gh pr checks 276'}),
      ]);

      expect(block, contains('Context already gathered this turn'));
      expect(block, contains('Commands already run this turn'));
      expect(
        block.indexOf('Context already gathered'),
        lessThan(block.indexOf('Commands already run')),
      );
    });

    test('reports a failed read as failed, never as gathered context', () {
      final block = digest.build([
        _result('read_file', {
          'path': '/repo/fvm/config.json',
        }, result: '{"ok":false,"code":"project_read_path_unavailable",'
            '"error":"The read target does not exist or cannot be opened.",'
            '"project_root":"/repo"}'),
        _result('list_directory', {'path': '/repo'}),
      ]);

      expect(block, contains('read /repo/fvm/config.json'));
      expect(block, contains('FAILED (project_read_path_unavailable)'));
      expect(block, contains('no content was gathered'));
      expect(block, contains('listed /repo'));
    });

    test('drops a failed read whose recovery is to repeat it', () {
      final block = digest.build([
        _result('read_file', {
          'path': '/repo/lib/main.dart',
        }, result: '{"ok":false,"code":"project_scoped_read_effect_uncertain",'
            '"error":"The read did not complete.",'
            '"next_action":"Repeat the read in the current turn."}'),
        _result('list_directory', {'path': '/repo'}),
        _result('read_file', {'path': '/repo/pubspec.yaml'}),
      ]);

      expect(
        block,
        isNot(contains('/repo/lib/main.dart')),
        reason: 'the runtime asked for this exact read to be repeated',
      );
      expect(block, contains('listed /repo'));
      expect(block, contains('read /repo/pubspec.yaml'));
    });

    test('treats a read that failed and then succeeded as gathered', () {
      final block = digest.build([
        _result('read_file', {
          'path': '/repo/new.dart',
        }, result: '{"ok":false,"code":"project_read_path_unavailable",'
            '"error":"The read target does not exist."}'),
        _result('read_file', {'path': '/repo/new.dart'}, result: 'contents'),
        _result('list_directory', {'path': '/repo'}),
      ]);

      expect(block, contains('- read /repo/new.dart'));
      expect(block, isNot(contains('FAILED')));
      expect(
        block,
        isNot(contains('unchanged')),
        reason: 'a failure body and a content body are not one unchanged file',
      );
    });

    test('reports a read that succeeded and then failed as failed', () {
      final block = digest.build([
        _result('read_file', {'path': '/repo/gone.dart'}, result: 'contents'),
        _result('read_file', {
          'path': '/repo/gone.dart',
        }, result: '{"ok":false,"code":"project_read_path_unavailable",'
            '"error":"The read target does not exist."}'),
        _result('list_directory', {'path': '/repo'}),
      ]);

      expect(block, contains('FAILED (project_read_path_unavailable)'));
    });

    test('names a failed read without a code as an unknown error', () {
      final block = digest.build([
        _result('search_files', {
          'query': 'fvm',
        }, result: '{"ok":false,"error":"Search backend unavailable."}'),
        _result('list_directory', {'path': '/repo'}),
      ]);

      expect(block, contains('searched "fvm" — FAILED (unknown_error)'));
    });

    test('keeps a read whose content merely mentions ok', () {
      final block = digest.build([
        _result('read_file', {
          'path': '/repo/notes.md',
        }, result: 'the "ok" flag is not set here'),
        _result('list_directory', {'path': '/repo'}),
      ]);

      expect(block, contains('- read /repo/notes.md'));
      expect(block, isNot(contains('FAILED')));
    });

    test('reports the exit status of a command that ran', () {
      // Session 0e94a103: `fvm use 3.47.1` succeeded, and four loops later the
      // model planned the same update again because "ran it" carried no
      // "it worked".
      final block = digest.build([
        _result('local_execute_command', {
          'command': 'fvm use 3.47.1',
        }, exitCode: 0),
        _result('read_file', {'path': '.fvmrc'}),
      ]);

      expect(block, contains('ran `fvm use 3.47.1` (exit 0)'));
    });

    test('reports a failing exit status', () {
      final block = digest.build([
        _result('local_execute_command', {
          'command': 'fvm flutter test',
        }, exitCode: 1),
        _result('read_file', {'path': '.fvmrc'}),
      ]);

      expect(block, contains('ran `fvm flutter test` (exit 1)'));
    });

    test('reports the latest exit status of a repeated command', () {
      final block = digest.build([
        _result('local_execute_command', {
          'command': 'fvm flutter test',
        }, exitCode: 1),
        _result('local_execute_command', {
          'command': 'fvm flutter test',
        }, exitCode: 0),
        _result('read_file', {'path': '.fvmrc'}),
      ]);

      expect(
        block,
        contains('ran `fvm flutter test` (last exit 0; already run 2x '
            'this turn)'),
      );
    });

    test('omits the exit status when the command never reached one', () {
      final block = digest.build([
        _result('local_execute_command', {'command': 'gh pr checks 276'}),
        _result('read_file', {'path': '.fvmrc'}),
      ]);

      expect(block, contains('- ran `gh pr checks 276`'));
      expect(
        block,
        isNot(contains('exit')),
        reason: 'an absent status must not read as a clean exit',
      );
    });

    test('flags a file that changed once and then settled', () {
      // Session 0e94a103: .fvmrc read at 3.47.0, updated, then read twice at
      // 3.47.1 — the third read went out unflagged because the first one had
      // seen a different version.
      final block = digest.build([
        _result('read_file', {'path': '.fvmrc'},
            result: 'v0', contentHash: 'hash-old'),
        _result('read_file', {'path': '.fvmrc'},
            result: 'v1', contentHash: 'hash-new'),
        _result('read_file', {'path': '.fvmrc'},
            result: 'v1', contentHash: 'hash-new'),
        _result('list_directory', {'path': '.'}),
      ]);

      expect(block, contains('.fvmrc (unchanged — the last 2 inspections'));
    });

    test('does not flag unchanged when only the older reads matched', () {
      final block = digest.build([
        _result('read_file', {'path': 'a.dart'},
            result: 'v0', contentHash: 'hash-old'),
        _result('read_file', {'path': 'a.dart'},
            result: 'v0', contentHash: 'hash-old'),
        _result('read_file', {'path': 'a.dart'},
            result: 'v1', contentHash: 'hash-new'),
        _result('list_directory', {'path': '.'}),
      ]);

      expect(
        block,
        isNot(contains('unchanged')),
        reason: 'the most recent read found a different file',
      );
    });

    test('does not extend an unchanged run through an unhashed read', () {
      final block = digest.build([
        _result('read_file', {'path': 'a.dart'},
            result: 'body', contentHash: 'hash-a'),
        _result('read_file', {'path': 'a.dart'}, result: 'body'),
        _result('read_file', {'path': 'a.dart'},
            result: 'body', contentHash: 'hash-a'),
        _result('list_directory', {'path': '.'}),
      ]);

      expect(
        block,
        isNot(contains('unchanged')),
        reason: 'the middle read reported no hash, so it cannot be compared',
      );
    });

    test('truncates an oversized command label', () {
      final long = 'gh api ${'x' * 400}';
      final block = digest.build([
        _result('local_execute_command', {'command': long}),
        _result('read_file', {'path': 'a.dart'}),
      ]);

      final label = RegExp(r'ran `([^`]*)`').firstMatch(block)!.group(1)!;
      expect(label, endsWith('…'));
      expect(label.length, lessThanOrEqualTo(121));
    });
  });
}

ToolResultInfo _result(
  String name,
  Map<String, dynamic> arguments, {
  String result = 'ok',
  String? contentHash,
  int? exitCode,
}) {
  return ToolResultInfo(
    id: 'result-$name',
    name: name,
    arguments: arguments,
    result: result,
    outcome: contentHash == null && exitCode == null
        ? null
        : ToolOutcome(
            exitCode: exitCode,
            readOutcome: contentHash == null
                ? null
                : ToolReadOutcome(
                    path: arguments['path'] as String,
                    contentHash: contentHash,
                    byteSize: result.length,
                    lineCount: 1,
                  ),
          ),
  );
}
