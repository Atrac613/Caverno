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

    test('drops only the reads of the path a file tool wrote', () {
      final stale = _read('a.dart', id: 'stale');
      final other = _read('c.dart', id: 'other');
      final after = _read('b.dart', id: 'after');
      final batch = _gitCommand('status --short', id: 'batch');

      final augmented = _carry.augment(
        resolved: [batch],
        executedToolResults: [stale, other, _write('a.dart'), after, batch],
      );

      // `stale` describes a file that no longer exists in that form; `other`
      // was not written and still holds.
      expect(augmented.map((result) => result.id), ['other', 'after', 'batch']);
    });

    test('keeps the release facts across a version bump', () {
      final tag = _gitCommand('tag --list --sort=-version:refname', id: 'tag');
      final log = _gitCommand('log 1.3.43+57..HEAD --oneline', id: 'log');
      final notes = _read('docs/releases/caverno-1.3.43.md', id: 'notes');
      final batch = ToolResultInfo(
        id: 'batch',
        name: 'write_file',
        arguments: {'path': 'docs/releases/caverno-1.3.44.md'},
        result: '{"ok":true}',
      );

      final augmented = _carry.augment(
        resolved: [batch],
        executedToolResults: [tag, log, notes, _write('pubspec.yaml'), batch],
      );

      // Session f76b5251: losing these at the bump sent the model back to
      // step 1 of its skill until the turn hit the loop cap.
      expect(augmented.map((result) => result.id), [
        'tag',
        'log',
        'notes',
        'batch',
      ]);
    });

    test('names the writes a carried result predates', () {
      final tag = _gitCommand('tag --list', id: 'tag');
      final log = _gitCommand('log --oneline', id: 'log');
      final batch = _read('batch.dart', id: 'batch');

      final augmented = _carry.augment(
        resolved: [batch],
        executedToolResults: [
          tag,
          _write('pubspec.yaml'),
          log,
          _write('notes.md'),
          batch,
        ],
      );

      final byId = {for (final result in augmented) result.id: result};
      expect(byId['tag']!.changesSinceCapture, [
        'write_file pubspec.yaml',
        'write_file notes.md',
      ]);
      expect(byId['log']!.changesSinceCapture, ['write_file notes.md']);
      expect(byId['batch']!.changesSinceCapture, isEmpty);
    });

    test('stops at a file write that names no path', () {
      final before = _read('a.dart', id: 'before');
      final pathless = ToolResultInfo(
        id: 'w',
        name: 'write_file',
        arguments: const <String, dynamic>{},
        result: '{"ok":true}',
      );
      final batch = _read('batch.dart', id: 'batch');

      final augmented = _carry.augment(
        resolved: [batch],
        executedToolResults: [before, pathless, batch],
      );

      // With no target there is nothing to scope the invalidation to.
      expect(augmented.map((result) => result.id), ['batch']);
    });

    test('spends the budget on the newest results and then stops', () {
      final big = 'x' * (RecentReadResultCarry.defaultBudgetBytes ~/ 2);
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

    test('keeps small older results past one that no longer fits', () {
      // Session e3a9f3f0: the diff and status went with the file read that
      // overflowed, and the review fetched them again.
      final status = _gitCommand('status --short', id: 'status');
      final file = _read(
        'watcher.py',
        body: 'x' * (RecentReadResultCarry.defaultBudgetBytes * 3 ~/ 4),
        id: 'file',
      );
      final test = _read(
        'test_watcher.py',
        body: 'x' * (RecentReadResultCarry.defaultBudgetBytes * 3 ~/ 4),
        id: 'test',
      );
      final batch = _gitCommand('diff --cached', id: 'batch');

      final augmented = _carry.augment(
        resolved: [batch],
        executedToolResults: [status, file, test, batch],
      );

      expect(augmented.map((result) => result.id), ['status', 'test', 'batch']);
    });

    test('a wider budget holds a working set the default cannot', () {
      final body = 'x' * (RecentReadResultCarry.defaultBudgetBytes * 3 ~/ 4);
      final file = _read('watcher.py', body: body, id: 'file');
      final test = _read('test_watcher.py', body: body, id: 'test');
      final batch = _gitCommand('diff --cached', id: 'batch');
      const wide = RecentReadResultCarry(budgetBytes: 32 * 1024);

      final augmented = wide.augment(
        resolved: [batch],
        executedToolResults: [file, test, batch],
      );

      expect(augmented.map((result) => result.id), ['file', 'test', 'batch']);
    });

    test('skips one oversized result instead of spending the budget on it', () {
      final huge = _read(
        'huge.dart',
        body: 'x' * (RecentReadResultCarry.defaultMaxResultBytes + 1),
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

    test('keeps the version facts across git add', () {
      // Sessions d84f819b and e6b3d03c: staging used to drop the tag and the
      // bumped version, right before the commit message that names them.
      final tag = _gitCommand('tag --list --sort=-version:refname', id: 'tag');
      final spec = _read('pubspec.yaml', id: 'spec');
      final status = _gitCommand('status --short', id: 'status');
      final diff = _gitCommand('diff HEAD -- pubspec.yaml', id: 'diff');
      final add = _gitCommand(
        'add docs/releases/caverno-1.3.50.md pubspec.yaml',
        stdout: '',
        id: 'add',
      );

      final augmented = _carry.augment(
        resolved: [add],
        executedToolResults: [tag, spec, status, diff, add],
      );

      // status and diff report the index the add just changed.
      expect(augmented.map((result) => result.id), ['tag', 'spec', 'add']);
      final byId = {for (final result in augmented) result.id: result};
      expect(byId['tag']!.changesSinceCapture, [
        'git add docs/releases/caverno-1.3.50.md pubspec.yaml',
      ]);
      expect(byId['add']!.changesSinceCapture, isEmpty);
    });

    test('still stops at a commit after git add', () {
      final tag = _gitCommand('tag --list', id: 'tag');
      final add = _gitCommand('add pubspec.yaml', stdout: '', id: 'add');
      final commit = _gitCommand('commit -m "x"', id: 'commit');
      final batch = _read('batch.dart', id: 'batch');

      final augmented = _carry.augment(
        resolved: [batch],
        executedToolResults: [tag, add, commit, batch],
      );

      expect(augmented.map((result) => result.id), ['batch']);
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
