import 'package:caverno/features/chat/domain/services/literal_environment_inspection_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final command in [
    'cd /project && ls -a && which python3 && python3 --version '
        '&& ls .venv 2>/dev/null; which pytest',
    "cd '/project with spaces/日本語' && ls -la",
    'pwd; python3.14 -V',
    'cd /project && ls -d .venv venv 2>/dev/null; which pytest 2>/dev/null; '
        'python3 -m pip show pytest 2>/dev/null | head -3',
    '.venv/bin/python -m pip show pytest wheel | tail -n 10',
    'pip3 show pytest',
    'cd /project && ls -a && which -a python3 python3.12 python3.13',
    'which -a python3 pytest 2>/dev/null',
  ]) {
    test('accepts literal inspection: $command', () {
      expect(LiteralEnvironmentInspectionPolicy.applies(command), isTrue);
    });
  }
  for (final command in [
    '',
    'ls; rm data',
    'ls && python3 fix.py',
    'python3 -m pip install pytest',
    'pip3 install pytest',
    'python3 -m pip show --files pytest',
    'python3 -m pip show pytest > packages.txt',
    'python3 -m pip show pytest | tee packages.txt',
    r'python3 -m pip show $(touch packages.txt)',
    'python3 script.py cat',
    'ls > result.txt',
    'ls 2> result.txt',
    r'ls $(touch result.txt)',
    'ls `touch result.txt`',
    'which --all python3',
    'which -a',
    'which -a -s python3',
    'which python3 -a',
    'which -a python3 > result.txt',
    'which -a python3 && python3 verify.py',
    r'which -a $(touch result.txt)',
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
