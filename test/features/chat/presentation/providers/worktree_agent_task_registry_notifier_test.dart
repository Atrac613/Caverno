import 'package:caverno/features/chat/data/repositories/worktree_agent_task_repository.dart';
import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/domain/services/worktree_agent_assignment_planner.dart';
import 'package:caverno/features/chat/presentation/providers/worktree_agent_task_registry_notifier.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    container = _container(prefs);
  });

  tearDown(() {
    container.dispose();
  });

  ProviderContainer registryContainer() => _container(prefs);

  WorktreeAgentTaskRegistryNotifier notifier() =>
      container.read(worktreeAgentTaskRegistryNotifierProvider.notifier);

  WorktreeAgentTaskRegistryState state() =>
      container.read(worktreeAgentTaskRegistryNotifierProvider);

  Future<WorktreeAgentTask> registerTask({
    String title = 'Fix test',
    String branchName = 'feature/fix-test',
    String worktreePath = '/tmp/caverno-worktrees/fix-test',
    String verificationCommand = 'fvm flutter test test/widget_test.dart',
  }) {
    return notifier().registerTask(
      title: title,
      prompt: 'Fix the failing test.',
      branchName: branchName,
      worktreePath: worktreePath,
      checkpointLineageId: 'll2-checkpoint-1',
      verificationCommand: verificationCommand,
    );
  }

  group('WorktreeAgentTaskRegistryNotifier', () {
    test('registerTask stores a queued worktree task', () async {
      final task = await registerTask();

      expect(task.status, WorktreeAgentTaskStatus.queued);
      expect(task.worktreePath, '/tmp/caverno-worktrees/fix-test');
      expect(task.checkpointLineageId, 'll2-checkpoint-1');
      expect(
        task.verificationCommand,
        'fvm flutter test test/widget_test.dart',
      );
      expect(state().tasks.single.id, task.id);
    });

    test('registerAssignment stores a planner-produced assignment', () async {
      const plan = WorktreeAgentAssignmentPlan(
        title: 'Fix test',
        prompt: 'Fix the failing test.',
        codingProjectId: 'project-1',
        baseBranch: 'main',
        branchName: 'feature/ll13-fix-test',
        worktreePath: '/tmp/caverno-worktrees/fix-test',
        checkpointLineageId: 'checkpoint-1',
        endpointId: 'mesh-1',
        verificationCommand: 'fvm flutter test test/widget_test.dart',
      );

      final task = await notifier().registerAssignment(plan);

      expect(task.branchName, 'feature/ll13-fix-test');
      expect(task.worktreePath, '/tmp/caverno-worktrees/fix-test');
      expect(task.codingProjectId, 'project-1');
      expect(task.checkpointLineageId, 'checkpoint-1');
      expect(task.endpointId, 'mesh-1');
      expect(
        task.verificationCommand,
        'fvm flutter test test/widget_test.dart',
      );
    });

    test('rejects a second active task for the same worktree', () async {
      await registerTask(worktreePath: '/tmp/caverno-worktrees/fix-test/');

      expect(
        () => registerTask(
          branchName: 'feature/other',
          worktreePath: '/tmp/caverno-worktrees/fix-test',
        ),
        throwsStateError,
      );
    });

    test('allows worktree reuse after the prior task is terminal', () async {
      final first = await registerTask();
      await notifier().markCompleted(first.id);

      final second = await registerTask(branchName: 'feature/fix-test-again');

      expect(second.id, isNot(first.id));
      expect(state().tasks, hasLength(2));
    });

    test('stores completion metadata for review-ready tasks', () async {
      final task = await registerTask();

      await notifier().markCompleted(
        task.id,
        resultSummary: 'Implemented the worktree task.',
        verifiedGreen: true,
        verificationSummary: 'flutter test passed',
      );

      final completed = state().byId(task.id)!;
      expect(completed.status, WorktreeAgentTaskStatus.completed);
      expect(completed.resultSummary, 'Implemented the worktree task.');
      expect(completed.verifiedGreen, isTrue);
      expect(completed.verificationSummary, 'flutter test passed');
      expect(completed.error, isEmpty);
    });

    test(
      'tracks visible, review-ready, and finished tasks separately',
      () async {
        final completed = await registerTask();
        final failed = await registerTask(
          branchName: 'feature/fix-test-failed',
          worktreePath: '/tmp/caverno-worktrees/fix-test-failed',
        );
        final cancelled = await registerTask(
          branchName: 'feature/fix-test-cancelled',
          worktreePath: '/tmp/caverno-worktrees/fix-test-cancelled',
        );

        await notifier().markCompleted(
          completed.id,
          verifiedGreen: true,
          verificationSummary: 'flutter test passed',
        );
        await notifier().markFailed(failed.id, 'flutter test failed');
        await notifier().cancel(cancelled.id);

        expect(state().visibleTasks.map((task) => task.id), [
          failed.id,
          completed.id,
        ]);
        expect(state().reviewReadyTasks.single.id, completed.id);
        expect(state().finishedTasks.map((task) => task.id), [
          cancelled.id,
          failed.id,
          completed.id,
        ]);
      },
    );

    test('clearFinished keeps only non-terminal tasks', () async {
      final queued = await registerTask();
      final completed = await registerTask(
        branchName: 'feature/fix-test-completed',
        worktreePath: '/tmp/caverno-worktrees/fix-test-completed',
      );
      final failed = await registerTask(
        branchName: 'feature/fix-test-failed',
        worktreePath: '/tmp/caverno-worktrees/fix-test-failed',
      );

      await notifier().markCompleted(completed.id);
      await notifier().markFailed(failed.id, 'flutter test failed');

      await notifier().clearFinished();

      expect(state().tasks.single.id, queued.id);
    });

    test('loads active tasks as recoverable after restart', () async {
      final running = WorktreeAgentTask(
        id: 'task-1',
        status: WorktreeAgentTaskStatus.running,
        title: 'Recovered task',
        prompt: 'Continue this task.',
        branchName: 'feature/recovered',
        worktreePath: '/tmp/caverno-worktrees/recovered',
        createdAt: DateTime.utc(2026, 6, 19),
        updatedAt: DateTime.utc(2026, 6, 19),
      );
      await WorktreeAgentTaskRepository(prefs).saveAll([running]);
      container.dispose();
      container = registryContainer();

      final tasks = state().tasks;

      expect(tasks.single.status, WorktreeAgentTaskStatus.needsRecovery);
      expect(state().recoverableTasks.single.id, 'task-1');
      expect(tasks.single.recoveryNote, contains('app restarted'));
    });

    test('re-queues a recovered task for an explicit resume path', () async {
      final running = WorktreeAgentTask(
        id: 'task-1',
        status: WorktreeAgentTaskStatus.running,
        title: 'Recovered task',
        prompt: 'Continue this task.',
        branchName: 'feature/recovered',
        worktreePath: '/tmp/caverno-worktrees/recovered',
        createdAt: DateTime.utc(2026, 6, 19),
        updatedAt: DateTime.utc(2026, 6, 19),
      );
      await WorktreeAgentTaskRepository(prefs).saveAll([running]);
      container.dispose();
      container = registryContainer();

      await notifier().markRecoveryQueued('task-1');

      final task = state().tasks.single;
      expect(task.status, WorktreeAgentTaskStatus.queued);
      expect(task.recoveryNote, isEmpty);
    });
  });
}

ProviderContainer _container(SharedPreferences prefs) {
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}
