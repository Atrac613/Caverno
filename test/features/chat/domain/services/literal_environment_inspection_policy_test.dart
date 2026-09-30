import 'package:caverno/features/chat/domain/services/literal_environment_inspection_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final command in [
    'cd /project && ls -a && which python3 && python3 --version '
        '&& ls .venv 2>/dev/null; which pytest',
    "cd '/project with spaces/日本語' && ls -la",
    'pwd; python3.14 -V',
  ]) {
    test('accepts literal inspection: $command', () {
      expect(LiteralEnvironmentInspectionPolicy.applies(command), isTrue);
    });
  }
  for (final command in [
    '',
    'ls; rm data',
    'ls && python3 fix.py',
    'python3 script.py cat',
    'ls > result.txt',
    'ls 2> result.txt',
    r'ls $(touch result.txt)',
    'ls `touch result.txt`',
    'which --all python3',
    'ls || true',
    'ls | tail -20',
    'ls &',
    'ls;',
    'ls &&',
    'ls\npython3 fix.py',
    "cd '/project; rm data' && ls",
  ]) {
    test('rejects unknown syntax: $command', () {
      expect(LiteralEnvironmentInspectionPolicy.applies(command), isFalse);
    });
  }
}
