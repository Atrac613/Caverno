import 'package:caverno/features/chat/domain/services/python/pytest_verification_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves literal cd and quoted Unicode arguments', () {
    final expected = PytestVerificationIdentity.parse(
      '.venv/bin/python -m pytest "test café.py" -v',
      '/workspace/日本語',
    );
    final actual = PytestVerificationIdentity.parse(
      "cd '日本語' && .venv/bin/python -m pytest 'test café.py' -v 2>&1 | tail -30",
      '/workspace',
    );
    expect(actual?.key, expected?.key);
    expect(actual?.directory, '/workspace/日本語');
    expect(
      PytestVerificationIdentity.parse(
        actual!.replayCommand,
        actual.directory,
      )?.key,
      actual.key,
    );
    expect(actual.counts('====== 6 passed in 3.05s ======')?.passedCount, 6);
  });
  test('a trailing grep filter keeps the pytest run behind it', () {
    // Session 1fd1d58b: grep exits 1 when a passing run prints no failure
    // lines, and the filtered command could never be settled.
    const nodeid = 'test_watcher.py::test_retry';
    final expected = PytestVerificationIdentity.parse(
      '.venv/bin/python -m pytest $nodeid -v --tb=long',
      '/workspace',
    )!;
    final filtered = PytestVerificationIdentity.parse(
      'cd /workspace && .venv/bin/python -m pytest $nodeid -v --tb=long '
          '2>&1 | grep -A 30 "FAILED\\|AssertionError\\|assert"',
      '/tmp',
    );
    expect(filtered?.key, expected.key);
    expect(
      filtered?.replayCommand,
      '.venv/bin/python -m pytest $nodeid -v --tb=long',
    );
    for (final command in [
      'python3 -m pytest -q | grep x && echo done',
      'python3 -m pytest -q || grep x log.txt',
      'python3 -m pytest -q | grep x > out.txt',
      'python3 -m pytest -q | sort',
    ]) {
      expect(
        PytestVerificationIdentity.parse(command, '/workspace'),
        isNull,
        reason: command,
      );
    }
  });
  test('accepts the tail -n output wrapper', () {
    // Session 26d7db3e: `| tail -n 15` was not stripped, so a passing run was
    // never counted as verification and update_goal rejected completion.
    for (final wrapper in ['tail -n 15', 'tail -n15', 'tail -15']) {
      expect(
        PytestVerificationIdentity.parse(
          'cd /workspace && .venv/bin/python -m pytest -q 2>&1 | $wrapper',
          '/tmp',
        )?.directory,
        '/workspace',
        reason: wrapper,
      );
    }
  });
  test('a terminal stderr merge keeps the same pytest invocation', () {
    final expected = PytestVerificationIdentity.parse(
      'python3 -m pytest test_state.py -v',
      '/workspace',
    )!;
    final actual = PytestVerificationIdentity.parse(
      'cd /workspace && .venv/bin/python -m pytest test_state.py -v 2>&1',
      '/parent',
    );
    expect(actual?.key, expected.key);
    expect(actual?.counts('=== 53 passed in 3.08s ===')?.passedCount, 53);
    expect(
      actual?.replayCommand,
      '.venv/bin/python -m pytest test_state.py -v',
    );
    expect(
      PytestVerificationIdentity.parse(
        "python3 -m pytest test_state.py -v '2>&1'",
        '/workspace',
      )?.key,
      isNot(expected.key),
      reason: 'a quoted argument is not a shell redirection',
    );
  });
  test('recognizes both literal tail line-count forms', () {
    final expected = PytestVerificationIdentity.parse(
      'python3 -m pytest -q',
      '/workspace',
    );
    for (final suffix in ['2>&1 | tail -5', '2>&1 | tail -n 5']) {
      expect(
        PytestVerificationIdentity.parse(
          'python3 -m pytest -q $suffix',
          '/workspace',
        )?.key,
        expected?.key,
      );
    }
    expect(
      PytestVerificationIdentity.parse(
        'git check-ignore config.json && python3 -m pytest -q 2>&1 | tail -n 5',
        '/workspace',
      ),
      isNull,
    );
  });
  for (final command in [
    'cd /workspace && python -m pytest && rm -rf data',
    'cd /workspace; python -m pytest',
    r'cd $HOME && python -m pytest',
    r'python -m pytest $(id)',
    'python -m pytest *.py',
    'python -m pytest > tests.txt',
    'python -m pytest 2>&1 > tests.txt',
    'python -m pytest 2> tests.txt',
    'python -m pytest 1>&2',
    'python -m pytest 2>&1 || true',
    'python -m pytest | tee tests.txt',
    'python -m pytest | tail 15',
    'python -m pytest # ignored.py',
    'python -m pytest\nrm -rf data',
    'cd - && python -m pytest',
    'cd && python -m pytest',
  ]) {
    test('rejects unsupported shell syntax: $command', () {
      expect(PytestVerificationIdentity.parse(command, '/workspace'), isNull);
    });
  }
}
