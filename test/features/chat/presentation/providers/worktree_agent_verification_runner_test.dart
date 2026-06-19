import 'package:caverno/features/chat/presentation/providers/worktree_agent_verification_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorktreeAgentVerificationRunner', () {
    test('parses a quoted command and runs it in the worktree', () async {
      final commands = <WorktreeAgentVerificationCommand>[];
      final runner = WorktreeAgentVerificationRunner(
        commandRunner: (command, timeout) async {
          commands.add(command);
          return const WorktreeAgentVerificationCommandOutput(
            exitCode: 0,
            stdout: 'green',
          );
        },
      );

      final result = await runner.run(
        verificationCommand: 'dart test "test/a b_test.dart"',
        worktreePath: '/tmp/caverno-worktrees/fix-test',
      );

      expect(result.verifiedGreen, isTrue);
      expect(result.summary, contains('Verification passed'));
      expect(commands, hasLength(1));
      expect(commands.single.executable, 'dart');
      expect(commands.single.arguments, ['test', 'test/a b_test.dart']);
      expect(
        commands.single.workingDirectory,
        '/tmp/caverno-worktrees/fix-test',
      );
    });

    test('rejects shell control operators before running', () async {
      var ran = false;
      final runner = WorktreeAgentVerificationRunner(
        commandRunner: (command, timeout) async {
          ran = true;
          return const WorktreeAgentVerificationCommandOutput(exitCode: 0);
        },
      );

      final result = await runner.run(
        verificationCommand: 'flutter test && git status',
        worktreePath: '/tmp/caverno-worktrees/fix-test',
      );

      expect(result.verifiedGreen, isFalse);
      expect(result.summary, contains('not run'));
      expect(result.summary, contains('&&'));
      expect(ran, isFalse);
    });

    test('summarizes failed command output', () async {
      final runner = WorktreeAgentVerificationRunner(
        commandRunner: (command, timeout) async {
          return const WorktreeAgentVerificationCommandOutput(
            exitCode: 1,
            stdout: 'running tests',
            stderr: 'failure details',
          );
        },
      );

      final result = await runner.run(
        verificationCommand: 'fvm flutter test test/widget_test.dart',
        worktreePath: '/tmp/caverno-worktrees/fix-test',
      );

      expect(result.verifiedGreen, isFalse);
      expect(result.summary, contains('Verification failed'));
      expect(result.summary, contains('running tests'));
      expect(result.summary, contains('failure details'));
    });
  });
}
