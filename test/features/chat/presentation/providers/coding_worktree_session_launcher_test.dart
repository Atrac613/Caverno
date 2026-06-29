import 'dart:io';

import 'package:caverno/features/chat/presentation/providers/coding_environment_snapshot_provider.dart';
import 'package:caverno/features/chat/presentation/providers/coding_worktree_session_launcher.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_git_worktree_preparer.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'creates composer worktrees under an assignment id path segment',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final calls = <_GitCall>[];
      final ensuredParents = <String>[];
      const assignmentId = '12345678-90ab-cdef-1234-567890abcdef';
      const projectRoot = '/Users/test/Workspace/caverno';
      const worktreePath =
          '/Users/test/Workspace/caverno-worktrees/12345678/caverno';
      final runProcess = _gitRunner(calls: calls, projectRoot: projectRoot);
      final preparer = WorktreeAgentGitWorktreePreparer(
        runProcess: runProcess,
        ensureParentDirectory: (path) async {
          ensuredParents.add(path);
        },
      );
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          codingEnvironmentProcessRunnerProvider.overrideWithValue(runProcess),
          worktreeAgentGitWorktreePreparerProvider.overrideWithValue(preparer),
        ],
      );
      addTearDown(container.dispose);

      final result = await container
          .read(codingWorktreeSessionLauncherProvider)
          .create(
            const CodingWorktreeSessionLaunchRequest(
              title: 'Fix composer flow',
              prompt: 'Repair the composer flow.',
              codingProjectId: 'project-1',
              projectRootPath: projectRoot,
              assignmentId: assignmentId,
            ),
          );

      expect(result.repositoryRoot, projectRoot);
      expect(result.plan.branchName, 'feature/fix-composer-flow-12345678');
      expect(result.plan.worktreePath, worktreePath);
      expect(ensuredParents, [
        '/Users/test/Workspace/caverno-worktrees/12345678',
      ]);
      expect(
        calls.map((call) => call.arguments),
        containsAllInOrder([
          [
            'worktree',
            'add',
            '-b',
            result.plan.branchName,
            worktreePath,
            'main',
          ],
          [
            'worktree',
            'lock',
            '--reason',
            'caverno task=$assignmentId',
            worktreePath,
          ],
        ]),
      );
    },
  );
}

CodingEnvironmentProcessRunner _gitRunner({
  required List<_GitCall> calls,
  required String projectRoot,
}) {
  return (executable, arguments, {workingDirectory}) async {
    calls.add(
      _GitCall(arguments: arguments, workingDirectory: workingDirectory),
    );
    if (executable != 'git') {
      return ProcessResult(1, 1, '', 'unexpected executable');
    }
    if (_argumentsEqual(arguments, const ['rev-parse', '--show-toplevel'])) {
      return ProcessResult(1, 0, projectRoot, '');
    }
    if (_argumentsEqual(arguments, const [
      'for-each-ref',
      '--format=%(refname:short)',
      'refs/heads',
    ])) {
      return ProcessResult(2, 0, '', '');
    }
    if (_argumentsEqual(arguments, const ['worktree', 'list', '--porcelain'])) {
      return ProcessResult(3, 0, '', '');
    }
    if (_argumentsEqual(arguments, const [
      'rev-parse',
      '--abbrev-ref',
      '--symbolic-full-name',
      'main@{upstream}',
    ])) {
      return ProcessResult(4, 128, '', 'no upstream');
    }
    if (_argumentsEqual(arguments, const ['fetch', 'origin', 'main'])) {
      return ProcessResult(5, 128, '', 'offline');
    }
    if (arguments.length == 6 &&
        _argumentsEqual(arguments.take(4).toList(), const [
          'worktree',
          'add',
          '-b',
          'feature/fix-composer-flow-12345678',
        ]) &&
        arguments[4] ==
            '/Users/test/Workspace/caverno-worktrees/12345678/caverno' &&
        arguments[5] == 'main') {
      return ProcessResult(6, 0, 'Preparing worktree', '');
    }
    if (arguments.length == 5 &&
        _argumentsEqual(arguments.take(4).toList(), const [
          'worktree',
          'lock',
          '--reason',
          'caverno task=12345678-90ab-cdef-1234-567890abcdef',
        ]) &&
        arguments[4] ==
            '/Users/test/Workspace/caverno-worktrees/12345678/caverno') {
      return ProcessResult(7, 0, '', '');
    }
    return ProcessResult(8, 1, '', 'unexpected git command: $arguments');
  };
}

bool _argumentsEqual(Iterable<String> left, List<String> right) {
  final leftList = left.toList(growable: false);
  if (leftList.length != right.length) return false;
  for (var i = 0; i < leftList.length; i++) {
    if (leftList[i] != right[i]) return false;
  }
  return true;
}

class _GitCall {
  const _GitCall({required this.arguments, this.workingDirectory});

  final List<String> arguments;
  final String? workingDirectory;
}
