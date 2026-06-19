import 'dart:io';

import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_git_worktree_preparer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorktreeAgentGitWorktreePreparer', () {
    test('creates the parent directory and runs git worktree add', () async {
      final calls = <_GitCall>[];
      final ensuredParents = <String>[];
      final preparer = WorktreeAgentGitWorktreePreparer(
        ensureParentDirectory: (path) async {
          ensuredParents.add(path);
        },
        runProcess: (executable, arguments, {workingDirectory}) async {
          calls.add(
            _GitCall(arguments: arguments, workingDirectory: workingDirectory),
          );
          if (_argumentsEqual(arguments, const [
            'rev-parse',
            '--show-toplevel',
          ])) {
            return ProcessResult(1, 0, '/repo', '');
          }
          if (_argumentsEqual(arguments, const [
            'worktree',
            'add',
            '-b',
            'feature/ll13-fix-test',
            '/tmp/caverno-worktrees/fix-test',
            'main',
          ])) {
            expect(workingDirectory, '/repo');
            return ProcessResult(2, 0, 'Preparing worktree', '');
          }
          return ProcessResult(3, 1, '', 'unexpected command');
        },
      );

      final result = await preparer.prepare(
        projectRootPath: '/repo/app',
        task: _task(),
      );

      expect(result.success, isTrue);
      expect(result.repositoryRoot, '/repo');
      expect(ensuredParents, ['/tmp/caverno-worktrees']);
      expect(calls, hasLength(2));
      expect(calls.first.workingDirectory, '/repo/app');
    });

    test('rejects non-queued tasks before running git commands', () async {
      final preparer = WorktreeAgentGitWorktreePreparer(
        ensureParentDirectory: (_) async {
          throw StateError('directory should not be created');
        },
        runProcess: (executable, arguments, {workingDirectory}) async {
          throw StateError('git should not run');
        },
      );

      final result = await preparer.prepare(
        projectRootPath: '/repo',
        task: _task(status: WorktreeAgentTaskStatus.running),
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('queued'));
    });

    test('returns stderr when git worktree add fails', () async {
      final preparer = WorktreeAgentGitWorktreePreparer(
        ensureParentDirectory: (_) async {},
        runProcess: (executable, arguments, {workingDirectory}) async {
          if (_argumentsEqual(arguments, const [
            'rev-parse',
            '--show-toplevel',
          ])) {
            return ProcessResult(1, 0, '/repo', '');
          }
          return ProcessResult(2, 128, '', 'fatal: invalid reference: main');
        },
      );

      final result = await preparer.prepare(
        projectRootPath: '/repo',
        task: _task(),
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('invalid reference'));
    });
  });
}

WorktreeAgentTask _task({
  WorktreeAgentTaskStatus status = WorktreeAgentTaskStatus.queued,
}) {
  return WorktreeAgentTask(
    id: 'task-1',
    status: status,
    title: 'Fix test',
    prompt: 'Fix the failing test.',
    branchName: 'feature/ll13-fix-test',
    worktreePath: '/tmp/caverno-worktrees/fix-test',
    baseBranch: 'main',
    createdAt: DateTime.utc(2026, 6, 19),
    updatedAt: DateTime.utc(2026, 6, 19),
  );
}

bool _argumentsEqual(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

class _GitCall {
  const _GitCall({required this.arguments, required this.workingDirectory});

  final List<String> arguments;
  final String? workingDirectory;
}
