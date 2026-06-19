import 'package:caverno/features/chat/domain/entities/worktree_agent_task.dart';
import 'package:caverno/features/chat/domain/services/worktree_agent_assignment_planner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const planner = WorktreeAgentAssignmentPlanner();

  group('WorktreeAgentAssignmentPlanner', () {
    test('creates a branch and sibling worktree path from the task title', () {
      final plan = planner.plan(
        title: 'Fix flaky widget test',
        prompt: 'Repair the failing widget test.',
        projectRootPath: '/Users/test/Workspace/caverno',
        existingTasks: const [],
        codingProjectId: 'project-1',
        checkpointLineageId: 'checkpoint-1',
        endpointId: 'mesh-1',
        verificationCommand: 'fvm flutter test test/widget_test.dart',
      );

      expect(plan.title, 'Fix flaky widget test');
      expect(plan.codingProjectId, 'project-1');
      expect(plan.baseBranch, 'main');
      expect(plan.branchName, 'feature/ll13-fix-flaky-widget-test');
      expect(
        plan.worktreePath,
        '/Users/test/Workspace/caverno-worktrees/fix-flaky-widget-test',
      );
      expect(plan.checkpointLineageId, 'checkpoint-1');
      expect(plan.endpointId, 'mesh-1');
      expect(
        plan.verificationCommand,
        'fvm flutter test test/widget_test.dart',
      );
    });

    test('adds suffixes for reserved branches and active worktrees', () {
      final existing = _task(
        id: 'task-1',
        status: WorktreeAgentTaskStatus.running,
        branchName: 'feature/ll13-fix-flaky-widget-test',
        worktreePath:
            '/Users/test/Workspace/caverno-worktrees/fix-flaky-widget-test',
      );

      final plan = planner.plan(
        title: 'Fix flaky widget test',
        prompt: 'Repair the failing widget test.',
        projectRootPath: '/Users/test/Workspace/caverno',
        existingTasks: [existing],
      );

      expect(plan.branchName, 'feature/ll13-fix-flaky-widget-test-2');
      expect(
        plan.worktreePath,
        '/Users/test/Workspace/caverno-worktrees/fix-flaky-widget-test-2',
      );
    });

    test('keeps terminal worktree paths reusable but avoids branch reuse', () {
      final existing = _task(
        id: 'task-1',
        status: WorktreeAgentTaskStatus.completed,
        branchName: 'feature/ll13-fix-flaky-widget-test',
        worktreePath:
            '/Users/test/Workspace/caverno-worktrees/fix-flaky-widget-test',
      );

      final plan = planner.plan(
        title: 'Fix flaky widget test',
        prompt: 'Repair the failing widget test.',
        projectRootPath: '/Users/test/Workspace/caverno',
        existingTasks: [existing],
      );

      expect(plan.branchName, 'feature/ll13-fix-flaky-widget-test-2');
      expect(
        plan.worktreePath,
        '/Users/test/Workspace/caverno-worktrees/fix-flaky-widget-test',
      );
    });

    test('uses explicit reservation lists for git-discovered state', () {
      final plan = planner.plan(
        title: 'Fix flaky widget test',
        prompt: 'Repair the failing widget test.',
        projectRootPath: '/Users/test/Workspace/caverno',
        existingTasks: const [],
        existingBranchNames: const ['feature/ll13-fix-flaky-widget-test'],
        existingWorktreePaths: const [
          '/Users/test/Workspace/caverno-worktrees/fix-flaky-widget-test',
        ],
      );

      expect(plan.branchName, 'feature/ll13-fix-flaky-widget-test-2');
      expect(
        plan.worktreePath,
        '/Users/test/Workspace/caverno-worktrees/fix-flaky-widget-test-2',
      );
    });

    test(
      'falls back to a stable task slug when the title has no ascii words',
      () {
        final plan = planner.plan(
          title: '復旧',
          prompt: '',
          projectRootPath: '/Users/test/Workspace/caverno',
          existingTasks: const [],
        );

        expect(plan.branchName, 'feature/ll13-task');
        expect(
          plan.worktreePath,
          '/Users/test/Workspace/caverno-worktrees/task',
        );
      },
    );
  });
}

WorktreeAgentTask _task({
  required String id,
  required WorktreeAgentTaskStatus status,
  required String branchName,
  required String worktreePath,
}) {
  return WorktreeAgentTask(
    id: id,
    status: status,
    title: id,
    prompt: '',
    branchName: branchName,
    worktreePath: worktreePath,
    createdAt: DateTime.utc(2026, 6, 19),
    updatedAt: DateTime.utc(2026, 6, 19),
  );
}
