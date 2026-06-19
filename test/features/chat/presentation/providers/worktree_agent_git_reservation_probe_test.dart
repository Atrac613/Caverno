import 'dart:io';

import 'package:caverno/features/chat/presentation/providers/worktree_agent_git_reservation_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorktreeAgentGitReservationProbe', () {
    test(
      'loads branch names and worktree paths from git porcelain output',
      () async {
        final calls = <List<String>>[];
        final probe = WorktreeAgentGitReservationProbe(
          runProcess: (executable, arguments, {workingDirectory}) async {
            calls.add(arguments);
            if (_argumentsEqual(arguments, const [
              'rev-parse',
              '--show-toplevel',
            ])) {
              expect(workingDirectory, '/repo');
              return ProcessResult(1, 0, '/repo', '');
            }
            if (_argumentsEqual(arguments, const [
              'for-each-ref',
              '--format=%(refname:short)',
              'refs/heads',
            ])) {
              expect(workingDirectory, '/repo');
              return ProcessResult(
                2,
                0,
                'main\nfeature/ll13-fix\nfeature/ll13-fix\n',
                '',
              );
            }
            if (_argumentsEqual(arguments, const [
              'worktree',
              'list',
              '--porcelain',
            ])) {
              expect(workingDirectory, '/repo');
              return ProcessResult(
                3,
                0,
                [
                  'worktree /repo',
                  'HEAD 0000000000000000000000000000000000000000',
                  'branch refs/heads/main',
                  '',
                  'worktree /tmp/caverno-worktrees/fix/',
                  'HEAD 1111111111111111111111111111111111111111',
                  'branch refs/heads/feature/ll13-fix',
                ].join('\n'),
                '',
              );
            }
            return ProcessResult(4, 1, '', 'unexpected command');
          },
        );

        final reservations = await probe.load('/repo');

        expect(reservations.hasError, isFalse);
        expect(reservations.branchNames, ['feature/ll13-fix', 'main']);
        expect(reservations.worktreePaths, [
          '/repo',
          '/tmp/caverno-worktrees/fix',
        ]);
        expect(calls, hasLength(3));
      },
    );

    test('returns a readable error when git state is unavailable', () async {
      final probe = WorktreeAgentGitReservationProbe(
        runProcess: (executable, arguments, {workingDirectory}) async {
          return ProcessResult(1, 128, '', 'fatal: not a git repository');
        },
      );

      final reservations = await probe.load('/repo');

      expect(reservations.hasError, isTrue);
      expect(reservations.errorMessage, contains('not a git repository'));
      expect(reservations.branchNames, isEmpty);
      expect(reservations.worktreePaths, isEmpty);
    });
  });
}

bool _argumentsEqual(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
