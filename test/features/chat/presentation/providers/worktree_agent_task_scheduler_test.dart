import 'dart:io';

import 'package:caverno/features/chat/data/repositories/coding_project_repository.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_git_worktree_preparer.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_registry_notifier.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_scheduler.dart';
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
    await _saveProjects(prefs, [
      _project(id: 'project-1', name: 'caverno', rootPath: '/repo/app'),
    ]);
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

  WorktreeAgentTaskScheduler scheduler() =>
      container.read(worktreeAgentTaskSchedulerProvider);

  test('starts only one queued task per endpoint capacity', () async {
    final first = await _registerTask(
      registry(),
      branchName: 'feature/ll13-first',
      worktreePath: '/tmp/caverno-worktrees/first',
      endpointId: 'mesh-1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 1));
    final second = await _registerTask(
      registry(),
      branchName: 'feature/ll13-second',
      worktreePath: '/tmp/caverno-worktrees/second',
      endpointId: 'mesh-1',
    );

    final result = await scheduler().startReady(
      const WorktreeAgentTaskScheduleRequest(maxConcurrentPerEndpoint: 1),
    );

    expect(result.started.map((item) => item.taskId), [first.id]);
    expect(result.failed, isEmpty);
    expect(result.skipped.single.taskId, second.id);
    expect(
      result.skipped.single.reason,
      WorktreeAgentTaskScheduleSkipReason.endpointCapacityReached,
    );
    expect(
      registryState().byId(first.id)!.status,
      WorktreeAgentTaskStatus.running,
    );
    expect(
      registryState().byId(second.id)!.status,
      WorktreeAgentTaskStatus.queued,
    );
  });

  test('uses fallback root for tasks without a coding project', () async {
    final task = await _registerTask(
      registry(),
      codingProjectId: '',
      branchName: 'feature/ll13-no-project',
      worktreePath: '/tmp/caverno-worktrees/no-project',
    );

    final result = await scheduler().startReady(
      const WorktreeAgentTaskScheduleRequest(
        fallbackProjectRootPath: '/fallback/repo',
      ),
    );

    expect(result.started.single.taskId, task.id);
    expect(calls.first.workingDirectory, '/fallback/repo');
  });

  test('skips queued tasks when no project root can be resolved', () async {
    final task = await _registerTask(
      registry(),
      codingProjectId: '',
      branchName: 'feature/ll13-no-root',
      worktreePath: '/tmp/caverno-worktrees/no-root',
    );

    final result = await scheduler().startReady(
      const WorktreeAgentTaskScheduleRequest(),
    );

    expect(result.started, isEmpty);
    expect(result.failed, isEmpty);
    expect(result.skipped.single.taskId, task.id);
    expect(
      result.skipped.single.reason,
      WorktreeAgentTaskScheduleSkipReason.missingProjectRoot,
    );
    expect(calls, isEmpty);
  });

  test('records failed starts without consuming endpoint capacity', () async {
    container.dispose();
    calls = <_GitCall>[];
    container = _container(
      prefs,
      preparer: _preparer(
        calls: calls,
        worktreeAddResult: ProcessResult(2, 128, '', 'fatal: branch exists'),
      ),
    );
    final first = await _registerTask(
      registry(),
      branchName: 'feature/ll13-first',
      worktreePath: '/tmp/caverno-worktrees/first',
      endpointId: 'mesh-1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 1));
    final second = await _registerTask(
      registry(),
      branchName: 'feature/ll13-second',
      worktreePath: '/tmp/caverno-worktrees/second',
      endpointId: 'mesh-1',
    );

    final result = await scheduler().startReady(
      const WorktreeAgentTaskScheduleRequest(maxConcurrentPerEndpoint: 1),
    );

    expect(result.started, isEmpty);
    expect(result.failed.map((item) => item.taskId), [first.id, second.id]);
    expect(result.skipped, isEmpty);
    expect(
      registryState().byId(first.id)!.status,
      WorktreeAgentTaskStatus.failed,
    );
    expect(
      registryState().byId(second.id)!.status,
      WorktreeAgentTaskStatus.failed,
    );
  });

  test('respects maxStarts across available endpoints', () async {
    final first = await _registerTask(
      registry(),
      branchName: 'feature/ll13-first',
      worktreePath: '/tmp/caverno-worktrees/first',
      endpointId: 'mesh-1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 1));
    final second = await _registerTask(
      registry(),
      branchName: 'feature/ll13-second',
      worktreePath: '/tmp/caverno-worktrees/second',
      endpointId: 'mesh-2',
    );

    final result = await scheduler().startReady(
      const WorktreeAgentTaskScheduleRequest(maxStarts: 1),
    );

    expect(result.started.map((item) => item.taskId), [first.id]);
    expect(
      registryState().byId(second.id)!.status,
      WorktreeAgentTaskStatus.queued,
    );
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
        return ProcessResult(1, 0, workingDirectory ?? '', '');
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
  WorktreeAgentTaskRegistryNotifier registry, {
  String codingProjectId = 'project-1',
  required String branchName,
  required String worktreePath,
  String endpointId = '',
}) {
  return registry.registerTask(
    title: branchName,
    prompt: 'Run this task.',
    branchName: branchName,
    worktreePath: worktreePath,
    codingProjectId: codingProjectId,
    endpointId: endpointId,
  );
}

Future<void> _saveProjects(
  SharedPreferences prefs,
  List<CodingProject> projects,
) {
  return CodingProjectRepository(prefs).saveAll(projects);
}

CodingProject _project({
  required String id,
  required String name,
  required String rootPath,
}) {
  return CodingProject(
    id: id,
    name: name,
    rootPath: rootPath,
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
