import 'package:caverno/features/chat/domain/services/python/pytest_verification_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PytestVerificationIdentity runner(
    String arguments, {
    String root = '/project',
  }) => PytestVerificationIdentity.parse('python3 -m pytest $arguments', root)!;

  for (final verbosity in [
    '-v',
    '-vv',
    '-q',
    '-qq',
    '-vq',
    '--verbose',
    '--quiet',
  ]) {
    test('compares checks independently of reporting: $verbosity', () {
      final plain = runner('test.py');
      final reporting = runner('$verbosity test.py $verbosity');
      expect(reporting.verificationKey, plain.verificationKey);
      expect(reporting.key, isNot(plain.key));
      expect(reporting.replayCommand, contains(verbosity));
    });
  }
  for (final arguments in [
    'other.py -q',
    'test.py -q -k fast',
    'test.py -q -m slow',
    'test.py -q -x',
    'test.py -q --maxfail=1',
    'test.py -q --collect-only',
    'test.py -q --ignore=other.py',
    'test.py -q -p no:plugin',
  ]) {
    test('keeps execution and selection differences: $arguments', () {
      expect(
        runner(arguments).verificationKey,
        isNot(runner('test.py -v').verificationKey),
      );
    });
  }
  for (final prefix in [
    'test.py -k',
    'test.py -m',
    'test.py --',
    'test.py --opaque',
    'test.py -x',
  ]) {
    test('keeps positional and uncertain option values: $prefix', () {
      expect(
        runner('$prefix "-q"').verificationKey,
        isNot(runner('$prefix "-v"').verificationKey),
      );
    });
  }
  test('keeps effective working directories distinct', () {
    expect(
      runner('test.py -q').verificationKey,
      isNot(runner('test.py -v', root: '/other').verificationKey),
    );
  });
  test('compares direct pytest with Python module invocations', () {
    expect(
      PytestVerificationIdentity.parse(
        'pytest test.py -v',
        '/project',
      )!.verificationKey,
      runner('test.py -q').verificationKey,
    );
  });
  for (final selection in [
    '-k fast',
    '-m slow',
    '--maxfail 1',
    '--maxfail=1',
  ]) {
    test('preserves selection while changing reporting: $selection', () {
      expect(
        runner('test.py -v $selection -q').verificationKey,
        runner('test.py $selection').verificationKey,
      );
    });
  }
}
