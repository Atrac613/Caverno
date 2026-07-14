import 'dart:convert';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/stalled_diagnostic_repair_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CommandDiagnosticStreakTracker tracker;

  setUp(() {
    tracker = CommandDiagnosticStreakTracker();
  });

  test('increments repeated equivalent command diagnostics', () {
    final first = tracker.observe(
      commandKey: 'verify',
      toolResult: _diagnosticResult(runRoot: '/tmp/run-a', line: 10),
    );
    final second = tracker.observe(
      commandKey: 'verify',
      toolResult: _diagnosticResult(runRoot: '/tmp/run-b', line: 42),
    );

    expect(first?.streak, 1);
    expect(first?.signatureChanged, isFalse);
    expect(second?.streak, 2);
    expect(second?.signatureChanged, isFalse);
    expect(second?.repairFocus.streak, 2);
    expect(second?.repairFocus.hasPathBackedDiagnostic, isTrue);
    expect(
      second?.repairFocus.diagnosticSummary,
      contains(
        'bin/todo_cli.dart: [todo_cli_missing] '
        'The required entrypoint does not exist.',
      ),
    );
    expect(second?.repairFocus.diagnosticSummary, isNot(contains('/tmp/')));
  });

  test('starts a new streak when the diagnostic changes', () {
    tracker.observe(
      commandKey: 'verify',
      toolResult: _diagnosticResult(runRoot: '/tmp/run-a', line: 10),
    );

    final changed = tracker.observe(
      commandKey: 'verify',
      toolResult: _diagnosticResult(
        runRoot: '/tmp/run-a',
        line: 10,
        code: 'unexpected_entrypoint',
        message: 'Remove the unexpected entrypoint.',
      ),
    );

    expect(changed?.streak, 1);
    expect(changed?.signatureChanged, isTrue);
  });

  test('preserves a relative path already present in the message', () {
    final observation = tracker.observe(
      commandKey: 'verify',
      toolResult: _diagnosticResult(
        runRoot: '/tmp/run-a',
        line: 10,
        message: 'bin/todo_cli.dart does not exist.',
      ),
    );

    expect(
      observation?.repairFocus.diagnosticSummary,
      contains('bin/todo_cli.dart does not exist.'),
    );
    expect(
      observation?.repairFocus.diagnosticSummary,
      isNot(contains('binbin/todo_cli.dart')),
    );
    expect(
      observation?.repairFocus.diagnosticSummary,
      isNot(contains('/tmp/')),
    );
  });

  test('tracks and resets command keys independently', () {
    tracker.observe(
      commandKey: 'verify-a',
      toolResult: _diagnosticResult(runRoot: '/tmp/run-a', line: 10),
    );
    tracker.observe(
      commandKey: 'verify-b',
      toolResult: _diagnosticResult(runRoot: '/tmp/run-b', line: 10),
    );
    tracker.reset('verify-a');

    final reset = tracker.observe(
      commandKey: 'verify-a',
      toolResult: _diagnosticResult(runRoot: '/tmp/run-a', line: 10),
    );
    final retained = tracker.observe(
      commandKey: 'verify-b',
      toolResult: _diagnosticResult(runRoot: '/tmp/run-b', line: 10),
    );

    expect(reset?.streak, 1);
    expect(retained?.streak, 2);
  });

  test('ignores results without authoritative error diagnostics', () {
    final empty = tracker.observe(
      commandKey: 'verify',
      toolResult: ToolResultInfo(
        id: 'verify-empty',
        name: 'local_execute_command',
        arguments: const {'command': 'dart run tool/verify.dart'},
        result: jsonEncode({'exit_code': 1, 'diagnostics': const []}),
      ),
    );
    final warning = tracker.observe(
      commandKey: 'verify',
      toolResult: _diagnosticResult(
        runRoot: '/tmp/run-a',
        line: 10,
        severity: 'Warning',
      ),
    );

    expect(empty, isNull);
    expect(warning, isNull);
  });

  test('marks a pathless authoritative diagnostic as generic repair', () {
    final observation = tracker.observe(
      commandKey: 'verify',
      toolResult: ToolResultInfo(
        id: 'verify-pathless',
        name: 'local_execute_command',
        arguments: const {'command': 'dart run tool/verify.dart'},
        result: jsonEncode({
          'exit_code': 1,
          'diagnostics': const [
            {
              'severity': 'Error',
              'code': 'dependency_resolution_failed',
              'message': 'Resolve the dependency constraint.',
            },
          ],
        }),
      ),
    );

    expect(observation?.repairFocus.hasPathBackedDiagnostic, isFalse);
    expect(
      observation?.repairFocus.diagnosticSummary,
      contains('[dependency_resolution_failed]'),
    );
  });
}

ToolResultInfo _diagnosticResult({
  required String runRoot,
  required int line,
  String severity = 'Error',
  String code = 'todo_cli_missing',
  String message = 'The required entrypoint does not exist.',
}) {
  final path = '$runRoot/bin/todo_cli.dart';
  return ToolResultInfo(
    id: 'verify-$line',
    name: 'local_execute_command',
    arguments: const {'command': 'dart run tool/verify.dart'},
    result: jsonEncode({
      'exit_code': 1,
      'diagnostics': [
        {
          'severity': severity,
          'path': path,
          'relative_path': 'bin/todo_cli.dart',
          'line': line,
          'column': 1,
          'code': code,
          'message': '$message at $path:$line:1',
        },
      ],
    }),
  );
}
