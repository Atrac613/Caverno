import 'dart:io';

import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_git_worktree_preparer.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_registry_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_starter.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late List<_GitCall> calls;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    calls = <_GitCall>[];
    container = _container(
      prefs,
      preparer: _preparer(
        calls: calls,
        worktreeAddResult: ProcessResult(2, 0, 'created', ''),
      ),
    );
  });

  tearDown(() {
    container.dispose();
  });

  WorktreeAgentTaskRegistryNotifier registry() =>
      container.read(worktreeAgentTaskRegistryNotifierProvider.notifier);

  WorktreeAgentTaskRegistryState registryState() =>
      container.read(worktreeAgentTaskRegistryNotifierProvider);

  WorktreeAgentTaskStarter starter() =>
      container.read(worktreeAgentTaskStarterProvider);

  test('creates a git worktree and marks the task running', () async {
    final task = await _registerTask(registry());

    final result = await starter().start(
      taskId: task.id,
      projectRootPath: '/repo/app',
    );

    expect(result.success, isTrue);
    expect(result.repositoryRoot, '/repo');
    final updated = registryState().byId(task.id)!;
    expect(updated.status, WorktreeAgentTaskStatus.running);
    expect(updated.startedAt, isNotNull);
    expect(calls.map((call) => call.arguments), [
      ['rev-parse', '--show-toplevel'],
      ['rev-parse', '--abbrev-ref', '--symbolic-full-name', 'main@{upstream}'],
      ['fetch', 'origin', 'main'],
      [
        'worktree',
        'add',
        '-b',
        'feature/ll13-fix-test',
        '/tmp/caverno-worktrees/fix-test',
        'main',
      ],
      [
        'worktree',
        'lock',
        '--reason',
        'caverno task=${task.id}',
        '/tmp/caverno-worktrees/fix-test',
      ],
    ]);
  });

  test('marks the task failed when git worktree creation fails', () async {
    container.dispose();
    calls = <_GitCall>[];
    container = _container(
      prefs,
      preparer: _preparer(
        calls: calls,
        worktreeAddResult: ProcessResult(2, 128, '', 'fatal: branch exists'),
      ),
    );
    final task = await _registerTask(registry());

    final result = await starter().start(
      taskId: task.id,
      projectRootPath: '/repo/app',
    );

    expect(result.success, isFalse);
    expect(result.errorMessage, contains('branch exists'));
    final updated = registryState().byId(task.id)!;
    expect(updated.status, WorktreeAgentTaskStatus.failed);
    expect(updated.error, contains('branch exists'));
    expect(updated.finishedAt, isNotNull);
  });

  test('does not start a terminal task', () async {
    final task = await _registerTask(registry());
    await registry().markCompleted(task.id);

    final result = await starter().start(
      taskId: task.id,
      projectRootPath: '/repo/app',
    );

    expect(result.success, isFalse);
    expect(result.errorMessage, contains('queued'));
    expect(calls, isEmpty);
  });
}

ProviderContainer _container(
  SharedPreferences prefs, {
  required WorktreeAgentGitWorktreePreparer preparer,
}) {
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      worktreeAgentGitWorktreePreparerProvider.overrideWithValue(preparer),
    ],
  );
}

WorktreeAgentGitWorktreePreparer _preparer({
  required List<_GitCall> calls,
  required ProcessResult worktreeAddResult,
}) {
  return WorktreeAgentGitWorktreePreparer(
    ensureParentDirectory: (_) async {},
    runProcess: (executable, arguments, {workingDirectory}) async {
      calls.add(
        _GitCall(arguments: arguments, workingDirectory: workingDirectory),
      );
      if (_argumentsEqual(arguments, const ['rev-parse', '--show-toplevel'])) {
        return ProcessResult(1, 0, '/repo', '');
      }
      if (_argumentsEqual(arguments, const [
        'rev-parse',
        '--abbrev-ref',
        '--symbolic-full-name',
        'main@{upstream}',
      ])) {
        return ProcessResult(2, 128, '', 'no upstream');
      }
      if (_argumentsEqual(arguments, const ['fetch', 'origin', 'main'])) {
        return ProcessResult(3, 128, '', 'offline');
      }
      if (arguments.length >= 2 &&
          arguments[0] == 'worktree' &&
          arguments[1] == 'lock') {
        return ProcessResult(4, 0, '', '');
      }
      return worktreeAddResult;
    },
  );
}

Future<WorktreeAgentTask> _registerTask(
  WorktreeAgentTaskRegistryNotifier registry,
) {
  return registry.registerTask(
    title: 'Fix test',
    prompt: 'Fix the failing test.',
    branchName: 'feature/ll13-fix-test',
    worktreePath: '/tmp/caverno-worktrees/fix-test',
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
