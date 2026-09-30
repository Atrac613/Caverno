import 'package:caverno/features/chat/domain/services/pytest_verification_identity.dart';
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
  for (final command in [
    'cd /workspace && python -m pytest && rm -rf data',
    'cd /workspace; python -m pytest',
    r'cd $HOME && python -m pytest',
    r'python -m pytest $(id)',
    'python -m pytest *.py',
    'python -m pytest > tests.txt',
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
