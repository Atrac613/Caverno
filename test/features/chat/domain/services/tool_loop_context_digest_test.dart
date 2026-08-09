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
  });
}

ToolResultInfo _result(
  String name,
  Map<String, dynamic> arguments, {
  String result = 'ok',
  String? contentHash,
}) {
  return ToolResultInfo(
    id: 'result-$name',
    name: name,
    arguments: arguments,
    result: result,
    outcome: contentHash == null
        ? null
        : ToolOutcome(
            readOutcome: ToolReadOutcome(
              path: arguments['path'] as String,
              contentHash: contentHash,
              byteSize: result.length,
              lineCount: 1,
            ),
          ),
  );
}
