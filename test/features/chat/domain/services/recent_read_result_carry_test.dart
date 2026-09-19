import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/recent_read_result_carry.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:test/test.dart';

const _carry = RecentReadResultCarry();

ToolResultInfo _read(String path, {String? body, String id = 'r'}) =>
    ToolResultInfo(
      id: id,
      name: 'read_file',
      arguments: {'path': path},
      result: body ?? '{"path":"$path","content":"x"}',
    );

ToolResultInfo _gitCommand(
  String command, {
  int? exitCode = 0,
  String stdout = 'out',
  String id = 'g',
}) => ToolResultInfo(
  id: id,
  name: 'git_execute_command',
  arguments: {'command': command},
  result: '{"command":"git $command","exit_code":$exitCode,"stdout":"$stdout"}',
  outcome: ToolOutcome(exitCode: exitCode),
);

ToolResultInfo _write(String path) => ToolResultInfo(
  id: 'w',
  name: 'write_file',
  arguments: {'path': path},
  result: '{"ok":true}',
);

List<String> _names(List<ToolResultInfo> results) =>
    results.map((result) => '${result.name}:${result.arguments}').toList();

void main() {
  group('RecentReadResultCarry', () {
    test('carries an earlier read the batch no longer holds', () {
      final tag = _gitCommand('tag --list --sort=-version:refname');
      final spec = _read('pubspec.yaml');
      // The batch holds only the newest result, which is the whole problem.
      final resolved = <ToolResultInfo>[spec];

      final augmented = _carry.augment(
        resolved: resolved,
        executedToolResults: [tag, spec],
      );

      // Both facts the version bump needs are now in one request.
      expect(_names(augmented), [
        'git_execute_command:{command: tag --list --sort=-version:refname}',
        'read_file:{path: pubspec.yaml}',
      ]);
    });

    test('keeps execution order rather than recency order', () {
      final first = _read('a.dart', id: 'a');
      final second = _read('b.dart', id: 'b');
      final batch = _read('c.dart', id: 'c');

      final augmented = _carry.augment(
        resolved: [batch],
        executedToolResults: [first, second, batch],
      );

      expect(augmented.map((result) => result.id), ['a', 'b', 'c']);
    });

    test('never repeats what the request already carries', () {
      final spec = _read('pubspec.yaml');

      final augmented = _carry.augment(
        resolved: [spec],
        executedToolResults: [spec, spec],
      );

      expect(augmented, [spec]);
    });

    test('stops at a file mutation, which invalidates earlier reads', () {
      final before = _read('a.dart', id: 'before');
      final after = _read('b.dart', id: 'after');
      final batch = _gitCommand('status --short', id: 'batch');

      final augmented = _carry.augment(
        resolved: [batch],
        executedToolResults: [before, _write('a.dart'), after, batch],
      );

      // `after` was read against the current workspace; `before` describes one
      // that no longer exists.
      expect(augmented.map((result) => result.id), ['after', 'batch']);
    });

    test('spends the budget on the newest results and then stops', () {
      final big = 'x' * (RecentReadResultCarry.budgetBytes ~/ 2);
      final oldest = _read('oldest.dart', body: big, id: 'oldest');
      final middle = _read('middle.dart', body: big, id: 'middle');
      final newest = _read('newest.dart', body: big, id: 'newest');
      final batch = _read('batch.dart', id: 'batch');

      final augmented = _carry.augment(
        resolved: [batch],
        executedToolResults: [oldest, middle, newest, batch],
      );

      expect(augmented.map((result) => result.id), [
        'middle',
        'newest',
        'batch',
      ]);
    });

    test('skips one oversized result instead of spending the budget on it', () {
      final huge = _read(
        'huge.dart',
        body: 'x' * (RecentReadResultCarry.maxResultBytes + 1),
        id: 'huge',
      );
      final small = _read('small.dart', id: 'small');
      final batch = _read('batch.dart', id: 'batch');

      final augmented = _carry.augment(
        resolved: [batch],
        executedToolResults: [small, huge, batch],
      );

      // Skipped, not budget-exhausting: the smaller older read still fits.
      expect(augmented.map((result) => result.id), ['small', 'batch']);
    });

    test('carries only commands that reached a clean exit', () {
      final failed = _gitCommand('status --short', exitCode: 1, id: 'failed');
      final unknown = _gitCommand('tag --list', exitCode: null, id: 'unknown');
      final batch = _read('batch.dart', id: 'batch');

      final augmented = _carry.augment(
        resolved: [batch],
        executedToolResults: [failed, unknown, batch],
      );

      // An absent exit status means the command never reached one, which is
      // not success and must not be presented as output.
      expect(augmented.map((result) => result.id), ['batch']);
    });

    test('does not carry a mutating command', () {
      final mutating = _gitCommand('commit -m "x"', id: 'commit');
      final batch = _read('batch.dart', id: 'batch');

      final augmented = _carry.augment(
        resolved: [batch],
        executedToolResults: [mutating, batch],
      );

      expect(augmented.map((result) => result.id), ['batch']);
    });

    test('a mutating command also invalidates the reads before it', () {
      final before = _read('a.dart', id: 'before');
      final mutating = _gitCommand('checkout other-branch', id: 'checkout');
      final after = _read('b.dart', id: 'after');
      final batch = _read('batch.dart', id: 'batch');

      final augmented = _carry.augment(
        resolved: [batch],
        executedToolResults: [before, mutating, after, batch],
      );

      // isFileMutationToolCall sees only the file-writing tools, so without
      // the command check `before` would be carried as if it still held.
      expect(augmented.map((result) => result.id), ['after', 'batch']);
    });

    test('does not carry a duplicate-reuse pointer', () {
      final pointer = ToolResultInfo(
        id: 'pointer',
        name: 'read_file',
        arguments: {'path': 'pubspec.yaml'},
        result:
            '{"path":"pubspec.yaml","content":"Identical to ...",'
            '"code":"duplicate_tool_call_result_reused"}',
      );
      final batch = _read('batch.dart', id: 'batch');

      // A pointer is a reference to content, not the content.
      final augmented = _carry.augment(
        resolved: [batch],
        executedToolResults: [pointer, batch],
      );

      expect(augmented.map((result) => result.id), ['batch']);
    });

    test('leaves an empty request alone', () {
      expect(
        _carry.augment(
          resolved: const <ToolResultInfo>[],
          executedToolResults: [_read('a.dart')],
        ),
        isEmpty,
      );
    });
  });
}
