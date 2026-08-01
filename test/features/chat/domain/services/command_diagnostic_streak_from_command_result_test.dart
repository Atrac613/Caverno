import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/stalled_diagnostic_repair_contract.dart';

/// The payload shape LocalShellTools now produces for a failing dart command.
///
/// Written out by hand rather than reused from the production encoder so this
/// test fails if that shape drifts — the streak reads the result, not the
/// encoder.
ToolResultInfo _failingAnalyzeResult({required String message}) {
  return ToolResultInfo(
    id: 'call-1',
    name: 'local_execute_command',
    arguments: const {
      'command': 'dart analyze',
      'working_directory': '/work/project',
    },
    result: jsonEncode({
      'command': 'dart analyze',
      'working_directory': '/work/project',
      'exit_code': 1,
      'stdout': '',
      'stderr': '',
      'diagnostics': [
        {
          'severity': 'Error',
          'path': '/work/project/lib/main.dart',
          'relative_path': 'lib/main.dart',
          'line': 12,
          'column': 7,
          'code': 'UNDEFINED_METHOD',
          'message': message,
        },
      ],
    }),
  );
}

void main() {
  group('a real failing dart command feeds the stalled-repair streak', () {
    // Before diagnostics were attached to command results, only the canary's
    // synthetic verifier payload carried them, so this seam had never been
    // reached by anything the product itself produces.
    test('the same diagnostic twice reaches streak 2', () {
      final tracker = CommandDiagnosticStreakTracker();
      const commandKey = 'local_execute_command:dart analyze';

      final first = tracker.observe(
        commandKey: commandKey,
        toolResult: _failingAnalyzeResult(message: 'The method is not defined.'),
      );
      final second = tracker.observe(
        commandKey: commandKey,
        toolResult: _failingAnalyzeResult(message: 'The method is not defined.'),
      );

      expect(first, isNotNull, reason: 'the first failure must be observed');
      expect(first!.streak, 1);
      expect(second, isNotNull);
      expect(second!.streak, 2);
      expect(second.signatureChanged, isFalse);
      expect(second.repairFocus.hasPathBackedDiagnostic, isTrue);
      expect(second.repairFocus.diagnosticSummary, isNotEmpty);
    });

    test('a changed diagnostic restarts the streak', () {
      final tracker = CommandDiagnosticStreakTracker();
      const commandKey = 'local_execute_command:dart analyze';

      tracker.observe(
        commandKey: commandKey,
        toolResult: _failingAnalyzeResult(message: 'The method is not defined.'),
      );
      final moved = tracker.observe(
        commandKey: commandKey,
        toolResult: _failingAnalyzeResult(message: 'A different problem.'),
      );

      expect(moved, isNotNull);
      expect(moved!.streak, 1, reason: 'progress must not look like a plateau');
      expect(moved.signatureChanged, isTrue);
    });

    test('a failing command without diagnostics is not observed at all', () {
      // The guard requires an authoritative snapshot. A non-dart command, or a
      // dart command whose output held nothing parseable, must not create a
      // plateau out of an empty signature.
      final tracker = CommandDiagnosticStreakTracker();

      final observation = tracker.observe(
        commandKey: 'local_execute_command:make build',
        toolResult: ToolResultInfo(
          id: 'call-1',
          name: 'local_execute_command',
          arguments: const {'command': 'make build'},
          result: jsonEncode({
            'command': 'make build',
            'exit_code': 2,
            'stdout': 'error: something went wrong',
            'stderr': '',
          }),
        ),
      );

      expect(observation, isNull);
    });
  });
}
