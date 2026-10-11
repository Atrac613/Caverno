import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/verification/unresolved_verification_failure.dart';
import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

ToolResultInfo _run(String id, String command, int exitCode) => ToolResultInfo(
  id: id,
  name: 'local_execute_command',
  arguments: {'command': command},
  result: jsonEncode({'command': command, 'exit_code': exitCode}),
  outcome: ToolOutcome(exitCode: exitCode),
);

void main() {
  const failure = UnresolvedVerificationFailure();
  const suite =
      'cd /w && .venv/bin/python verify_logging.py && '
      '.venv/bin/python -m pytest test_watcher.py -q';
  const dryRun =
      'cd /w && .venv/bin/python watcher.py --dry-run 2>&1 | head -20';

  test('names the failed check a later passing command did not clear', () {
    // Session d0c0462c: the suite passed after the dry-run failed, the gap
    // said "the last verification command failed", and the model re-ran the
    // passing suite three times.
    final gap = failure.describe([
      _run('a', suite, 0),
      _run('b', dryRun, 120),
      _run('c', suite, 0),
      _run('d', suite, 0),
    ]);

    expect(gap, contains('`$dryRun`'));
    expect(gap, contains('(exit 120)'));
    expect(gap, contains('report blocked_reason'));
  });

  test('says nothing once that command passes, or when none failed', () {
    expect(
      failure.describe([_run('b', dryRun, 120), _run('e', dryRun, 0)]),
      isNull,
    );
    expect(failure.describe([_run('a', suite, 0)]), isNull);
  });

  test('an unfiltered run of the same tests settles a grep-filtered one', () {
    // Session 1fd1d58b: the filtered command kept failing because grep found
    // nothing to print in a passing run, and the gap demanded that exact
    // command pass.
    ToolResultInfo pytest(String id, String command, int exit, String out) =>
        ToolResultInfo(
          id: id,
          name: 'local_execute_command',
          arguments: {'command': command, 'working_directory': '/w'},
          result: jsonEncode({
            'command': command,
            'working_directory': '/w',
            'exit_code': exit,
            'stdout': out,
          }),
          outcome: ToolOutcome(exitCode: exit),
        );
    const test = '.venv/bin/python -m pytest test_watcher.py::test_retry -v';
    const filtered = '$test 2>&1 | grep -A 30 "FAILED\\|assert"';
    final failed = pytest('a', filtered, 1, '');

    final gap = failure.describe([failed]);
    expect(gap, contains('A passing run of the same tests'));
    expect(gap, contains('`$test`'));
    expect(
      failure.describe([
        failed,
        pytest('b', test, 0, '==== 1 passed in 6.07s ===='),
      ]),
      isNull,
    );
  });

  test(
    'an inline fixture failure names a repair path instead of exact replay',
    () {
      const command = '''python3 -c "from worker import missing
records = missing()
assert '[INFO]' in records
"''';
      final result = ToolResultInfo(
        id: 'inline-failed',
        name: 'local_execute_command',
        arguments: const {'command': command, 'working_directory': '/w'},
        result: jsonEncode({
          'command': command,
          'working_directory': '/w',
          'exit_code': 1,
        }),
        outcome: ToolOutcome(exitCode: 1),
      );
      final gap = failure.describe([result]);
      expect(gap, contains('tool call inline-failed'));
      expect(gap, contains('Repair its fixture'));
      expect(
        gap,
        contains('source block from the first top-level assert onward'),
      );
      expect(gap, contains('Dropping or weakening checks'));
    },
  );
}
