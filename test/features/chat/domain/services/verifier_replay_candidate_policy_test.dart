import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/tool_call_info.dart';
import 'package:caverno/features/chat/domain/services/verifier_replay_candidate_policy.dart';

const _policy = VerifierReplayCandidatePolicy();

ToolCallInfo _command(String command, {bool? background}) => ToolCallInfo(
  id: 'call',
  name: 'local_execute_command',
  arguments: {'command': command, 'background': ?background},
);

ToolCallInfo _runTests() =>
    ToolCallInfo(id: 'call', name: 'run_tests', arguments: const {});

void main() {
  group('isEligible', () {
    test('accepts run_tests, which carries no free-form command', () {
      expect(
        _policy.isEligible(_runTests()),
        isTrue,
      );
    });

    test('accepts a single plain foreground command', () {
      expect(_policy.isEligible(_command('dart test')), isTrue);
      expect(_policy.isEligible(_command('  dart analyze  ')), isTrue);
    });

    test('rejects a backgrounded command, which never finished', () {
      expect(
        _policy.isEligible(_command('dart test', background: true)),
        isFalse,
      );
    });

    test('rejects shell control characters', () {
      // Replaying re-executes something the user approved once; a chained or
      // redirected command can do more the second time than its text suggests.
      for (final command in [
        'dart test && rm -rf build',
        'dart test; rm -rf build',
        'dart test | tee log',
        'dart test > out.txt',
        'dart test `id`',
        r'dart test $(id)',
        'dart test\nrm -rf build',
      ]) {
        expect(
          _policy.isEligible(_command(command)),
          isFalse,
          reason: command,
        );
      }
    });

    test('rejects an empty command and any other tool', () {
      expect(_policy.isEligible(_command('   ')), isFalse);
      expect(
        _policy.isEligible(
          ToolCallInfo(id: 'call', name: 'write_file', arguments: const {}),
        ),
        isFalse,
      );
    });
  });

  group('priority', () {
    test('ranks a dedicated test run above an arbitrary command', () {
      final runTests = _policy.priority(_runTests());

      expect(runTests, greaterThan(_policy.priority(_command('dart analyze'))));
    });

    test('treats a command that names itself a verifier as one', () {
      expect(_policy.priority(_command('tool/verify.sh')), 2);
      expect(_policy.priority(_command('bash run_verifier.sh')), 2);
      expect(
        _policy.priority(_command('dart run tool/diversify.dart')),
        1,
        reason: 'the word must stand on its own, not sit inside another',
      );
    });
  });
}
