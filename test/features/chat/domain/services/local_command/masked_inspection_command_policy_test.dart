import 'package:caverno/features/chat/domain/services/coding_command_output_issue_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const detector = CodingCommandOutputIssueDetector();
  test('optional environment inspection does not become a task failure', () {
    expect(
      detector.detectFromDecodedCommandResult(
        toolName: 'local_execute_command',
        decoded: {
          'command':
              'cd /project && ls -la && which python3 && python3 --version && ls .venv 2>/dev/null || true',
          'exit_code': 0,
          'stdout': 'Python 3.14.3',
        },
      ),
      isNull,
    );
  });
  for (final command in [
    'cd /project && pytest test.py || true',
    'cd /project && python3 fix.py || true',
    'cd /project && rm -rf data || true',
    'cd /project && ls > result.txt || true',
    r'cd /project && ls $(touch result.txt) || true',
  ]) {
    test('retains failure for $command', () {
      expect(
        detector.detectFromDecodedCommandResult(
          toolName: 'local_execute_command',
          decoded: {'command': command, 'exit_code': 0},
        ),
        isNotNull,
      );
    });
  }
  test('inspection still reports real runtime failure output', () {
    expect(
      detector.detectFromDecodedCommandResult(
        toolName: 'local_execute_command',
        decoded: {
          'command': 'cd /project && ls .venv || true',
          'exit_code': 0,
          'stdout': 'Traceback (most recent call last):',
        },
      ),
      isNotNull,
    );
  });
}
