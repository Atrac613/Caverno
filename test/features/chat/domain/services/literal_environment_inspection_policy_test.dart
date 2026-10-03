import 'package:caverno/features/chat/domain/services/literal_environment_inspection_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('import metadata is not a guarantee of unchanged execution state', () {
    const command = 'python3 -c "import pytest; print(pytest.__file__)"';
    expect(LiteralEnvironmentInspectionPolicy.applies(command), isTrue);
    expect(
      LiteralEnvironmentInspectionPolicy.applies(
        command,
        allowPackageImports: false,
      ),
      isFalse,
    );
  });
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
    "cd '/project; rm data' && ls",
    'ls -d /project/.venv /project/venv 2>/dev/null; which pytest 2>/dev/null; '
        'python3 -c "import pytest; print(pytest.__file__)" 2>&1',
    'ls -d /project/.venv && /project/.venv/bin/python -c "import pytest; print(\'pytest\', pytest.__version__)"',
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
    'python3 -c "import pytest; pytest.main()"',
    'python3 -c "import pytest; assert pytest.__version__ == \'1\'"',
    'python3 -c "import pytest; print(pytest.__file__); open(\'result\', \'w\')"',
    'python3 -c "import pytest; print(pytest.__file__)" > result.txt',
    r'python3 -c "import pytest; print(pytest.__file__) $(touch result)"',
    'python3 -c "import pytest; print(pytest.__file__)" && python3 verify.py',
    'python3 -c "import pytest; print(pytest.__file__)";',
    'python3 -c "import pytest; print(pytest.__file__)',
  ]) {
    test('rejects unknown syntax: $command', () {
      expect(LiteralEnvironmentInspectionPolicy.applies(command), isFalse);
    });
  }
}
