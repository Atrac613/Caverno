import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/tool_loop_context_digest.dart';

void main() {
  const digest = ToolLoopContextDigest();

  group('ToolLoopContextDigest', () {
    test('returns empty when there is nothing worth repeating', () {
      expect(digest.build(const []), isEmpty);
      expect(
        digest.build([_result('read_file', {'path': 'a.dart'})]),
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

    test('flags a repeated read that returned identical content as unchanged',
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
    });

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
  });
}

ToolResultInfo _result(
  String name,
  Map<String, dynamic> arguments, {
  String result = 'ok',
}) {
  return ToolResultInfo(
    id: 'result-$name',
    name: name,
    arguments: arguments,
    result: result,
  );
}
