import 'dart:async';
import 'dart:io';

import 'package:caverno/features/chat/data/repositories/coding_project_repository.dart';
import 'package:caverno/features/chat/domain/entities/coding_project.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_git_worktree_preparer.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_executor.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_orchestrator.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_registry_notifier.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late List<_GitCall> calls;
  late List<WorktreeAgentTaskExecutionContext> contexts;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    await _saveProjects(prefs, [
      _project(id: 'project-1', name: 'caverno', rootPath: '/repo/app'),
    ]);
    calls = <_GitCall>[];
    contexts = <WorktreeAgentTaskExecutionContext>[];
    container = _container(
      prefs,
      calls: calls,
      delegate: (context) async {
        contexts.add(context);
        return const WorktreeAgentTaskExecutionOutcome(
          resultSummary: 'Implemented the assigned change.',
          verifiedGreen: true,
          verificationSummary: 'flutter test passed',
        );
      },
    );
  });

  tearDown(() {
    container.dispose();
  });

  WorktreeAgentTaskRegistryNotifier registry() =>
      container.read(worktreeAgentTaskRegistryNotifierProvider.notifier);

  WorktreeAgentTaskRegistryState registryState() =>
      container.read(worktreeAgentTaskRegistryNotifierProvider);

  WorktreeAgentTaskOrchestrator orchestrator() =>
      container.read(worktreeAgentTaskOrchestratorProvider);

  WorktreeAgentTaskRunController runController() =>
      container.read(worktreeAgentTaskRunControllerProvider.notifier);

  WorktreeAgentTaskRunState runState() =>
      container.read(worktreeAgentTaskRunControllerProvider);

  test('starts and executes queued tasks', () async {
    final task = await _registerQueuedTask(registry());

    final result = await orchestrator().startAndExecuteReady(
      const WorktreeAgentTaskRunRequest(),
    );

    expect(result.schedule.started.single.taskId, task.id);
    expect(result.schedule.failed, isEmpty);
    expect(result.schedule.skipped, isEmpty);
    expect(result.executions.single.success, isTrue);
    expect(contexts.single.taskId, task.id);
    expect(calls, isNotEmpty);

    final completed = registryState().byId(task.id)!;
    expect(completed.status, WorktreeAgentTaskStatus.completed);
    expect(completed.resultSummary, 'Implemented the assigned change.');
    expect(completed.verifiedGreen, isTrue);
    expect(completed.verificationSummary, 'flutter test passed');
  });

  test('does not execute skipped tasks', () async {
    final task = await _registerQueuedTask(registry(), codingProjectId: '');

    final result = await orchestrator().startAndExecuteReady(
      const WorktreeAgentTaskRunRequest(),
    );

    expect(result.schedule.started, isEmpty);
    expect(result.schedule.failed, isEmpty);
    expect(result.schedule.skipped.single.taskId, task.id);
    expect(result.executions, isEmpty);
    expect(contexts, isEmpty);
    expect(
      registryState().byId(task.id)!.status,
      WorktreeAgentTaskStatus.queued,
    );
  });

  test('executes started tasks concurrently', () async {
    container.dispose();
    calls = <_GitCall>[];
    contexts = <WorktreeAgentTaskExecutionContext>[];
    final bothStarted = Completer<void>();
    container = _container(
      prefs,
      calls: calls,
      delegate: (context) async {
        contexts.add(context);
        if (contexts.length == 2 && !bothStarted.isCompleted) {
          bothStarted.complete();
        }
        await bothStarted.future.timeout(const Duration(seconds: 1));
        return WorktreeAgentTaskExecutionOutcome(
          resultSummary: 'Implemented ${context.taskId}.',
          verifiedGreen: true,
          verificationSummary: 'flutter test passed',
        );
      },
    );
    final first = await _registerQueuedTask(
      registry(),
      branchName: 'feature/ll13-first',
      worktreePath: '/tmp/caverno-worktrees/first',
      endpointId: 'mesh-1',
    );
    await Future<void>.delayed(const Duration(milliseconds: 1));
    final second = await _registerQueuedTask(
      registry(),
      branchName: 'feature/ll13-second',
      worktreePath: '/tmp/caverno-worktrees/second',
      endpointId: 'mesh-2',
    );

    final result = await orchestrator().startAndExecuteReady(
      const WorktreeAgentTaskRunRequest(maxConcurrentPerEndpoint: 1),
    );

    expect(result.schedule.started.map((item) => item.taskId), [
      first.id,
      second.id,
    ]);
    expect(result.executions.map((item) => item.taskId), [first.id, second.id]);
    expect(contexts.map((context) => context.taskId).toSet(), {
      first.id,
      second.id,
    });
    expect(
      registryState().byId(first.id)!.status,
      WorktreeAgentTaskStatus.completed,
    );
    expect(
      registryState().byId(second.id)!.status,
      WorktreeAgentTaskStatus.completed,
    );
  });

  test('ignores overlapping run requests while a run is in flight', () async {
    container.dispose();
    calls = <_GitCall>[];
    contexts = <WorktreeAgentTaskExecutionContext>[];
    final releaseFirstRun = Completer<void>();
    container = _container(
      prefs,
      calls: calls,
      delegate: (context) async {
        contexts.add(context);
        await releaseFirstRun.future;
        return WorktreeAgentTaskExecutionOutcome(
          resultSummary: 'Implemented ${context.taskId}.',
          verifiedGreen: true,
          verificationSummary: 'flutter test passed',
        );
      },
    );
    final first = await _registerQueuedTask(
      registry(),
      branchName: 'feature/ll13-first',
      worktreePath: '/tmp/caverno-worktrees/first',
      endpointId: 'mesh-1',
    );

    final firstRun = runController().startAndExecuteReady(
      const WorktreeAgentTaskRunRequest(maxConcurrentPerEndpoint: 1),
    );
    await _waitUntil(() => contexts.length == 1);

    final second = await _registerQueuedTask(
      registry(),
      branchName: 'feature/ll13-second',
      worktreePath: '/tmp/caverno-worktrees/second',
      endpointId: 'mesh-2',
    );
    final overlappingRun = await runController().startAndExecuteReady(
      const WorktreeAgentTaskRunRequest(maxConcurrentPerEndpoint: 1),
    );

    expect(overlappingRun, isNull);
    expect(runState().isRunning, isTrue);
    expect(contexts.map((context) => context.taskId), [first.id]);
    expect(
      registryState().byId(second.id)!.status,
      WorktreeAgentTaskStatus.queued,
    );

    releaseFirstRun.complete();
    final firstResult = await firstRun;

    expect(firstResult?.executions.single.taskId, first.id);
    expect(runState().isRunning, isFalse);
    expect(
      registryState().byId(first.id)!.status,
      WorktreeAgentTaskStatus.completed,
    );
    expect(
      registryState().byId(second.id)!.status,
      WorktreeAgentTaskStatus.queued,
    );
  });

  test('records execution failures after a successful start', () async {
    container.dispose();
    calls = <_GitCall>[];
    contexts = <WorktreeAgentTaskExecutionContext>[];
    container = _container(
      prefs,
      calls: calls,
      delegate: (context) async {
        contexts.add(context);
        throw StateError('agent failed');
      },
    );
    final task = await _registerQueuedTask(registry());

    final result = await orchestrator().startAndExecuteReady(
      const WorktreeAgentTaskRunRequest(),
    );

    expect(result.schedule.started.single.taskId, task.id);
    expect(result.executions.single.success, isFalse);
    expect(result.executions.single.errorMessage, contains('agent failed'));
    expect(contexts.single.taskId, task.id);
    final failed = registryState().byId(task.id)!;
    expect(failed.status, WorktreeAgentTaskStatus.failed);
    expect(failed.error, contains('agent failed'));
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt += 1) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for condition.');
}

ProviderContainer _container(
  SharedPreferences prefs, {
  required List<_GitCall> calls,
  required WorktreeAgentTaskExecutionDelegate delegate,
}) {
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      worktreeAgentGitWorktreePreparerProvider.overrideWithValue(
        _preparer(calls: calls, worktreeAddResult: ProcessResult(2, 0, '', '')),
      ),
      worktreeAgentTaskExecutionDelegateProvider.overrideWithValue(delegate),
    ],
  );
}

Future<WorktreeAgentTask> _registerQueuedTask(
  WorktreeAgentTaskRegistryNotifier registry, {
  String codingProjectId = 'project-1',
  String branchName = 'feature/ll13-fix-test',
  String worktreePath = '/tmp/caverno-worktrees/fix-test',
  String endpointId = '',
}) {
  return registry.registerTask(
    title: 'Fix test',
    prompt: 'Fix the failing test.',
    codingProjectId: codingProjectId,
    branchName: branchName,
    worktreePath: worktreePath,
    endpointId: endpointId,
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
      return worktreeAddResult;
    },
  );
}

bool _argumentsEqual(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
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

class _GitCall {
  const _GitCall({required this.arguments, required this.workingDirectory});

  final List<String> arguments;
  final String? workingDirectory;
}
