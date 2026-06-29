import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/worktree_agent_task.dart';
import '../../domain/services/worktree_agent_assignment_planner.dart';
import 'worktree_agent_git_reservation_probe.dart';
import 'worktree_agent_git_worktree_preparer.dart';
import 'worktree_agent_task_launcher.dart';
import 'worktree_agent_task_registry_notifier.dart';

class CodingWorktreeSessionLaunchRequest {
  const CodingWorktreeSessionLaunchRequest({
    required this.title,
    required this.prompt,
    required this.codingProjectId,
    required this.projectRootPath,
    this.baseBranch = 'main',
    this.assignmentId = '',
    this.branchPrefix = CodingWorktreeSessionLauncher.defaultBranchPrefix,
    this.worktreeRootPath = '',
  });

  final String title;
  final String prompt;
  final String codingProjectId;
  final String projectRootPath;
  final String baseBranch;
  final String assignmentId;
  final String branchPrefix;
  final String worktreeRootPath;
}

class CodingWorktreeSessionLaunchResult {
  const CodingWorktreeSessionLaunchResult({
    required this.plan,
    required this.repositoryRoot,
  });

  final WorktreeAgentAssignmentPlan plan;
  final String repositoryRoot;
}

final codingWorktreeSessionLauncherProvider =
    Provider<CodingWorktreeSessionLauncher>((ref) {
      return CodingWorktreeSessionLauncher(ref);
    });

class CodingWorktreeSessionLauncher {
  const CodingWorktreeSessionLauncher(this._ref);

  static const defaultBranchPrefix = 'feature/';

  final Ref _ref;

  Future<CodingWorktreeSessionLaunchResult> create(
    CodingWorktreeSessionLaunchRequest request,
  ) async {
    final projectRootPath = request.projectRootPath.trim();
    if (projectRootPath.isEmpty) {
      throw StateError('A coding project root path is required.');
    }

    final gitReservations = await _ref
        .read(worktreeAgentGitReservationProbeProvider)
        .load(projectRootPath);
    if (gitReservations.hasError) {
      throw StateError(
        gitReservations.errorMessage ??
            'Could not read git worktree reservations.',
      );
    }

    final registryState = _ref.read(worktreeAgentTaskRegistryNotifierProvider);
    final planner = _ref.read(worktreeAgentAssignmentPlannerProvider);
    final assignmentId = request.assignmentId.trim().isEmpty
        ? const Uuid().v4()
        : request.assignmentId.trim();
    final plan = planner.plan(
      title: request.title,
      prompt: request.prompt,
      projectRootPath: projectRootPath,
      existingTasks: registryState.tasks,
      codingProjectId: request.codingProjectId,
      baseBranch: request.baseBranch,
      assignmentId: assignmentId,
      branchPrefix: request.branchPrefix,
      worktreeRootPath: request.worktreeRootPath,
      existingBranchNames: gitReservations.branchNames,
      existingWorktreePaths: gitReservations.worktreePaths,
    );

    final now = DateTime.now();
    final task = WorktreeAgentTask(
      id: assignmentId,
      title: plan.title,
      prompt: plan.prompt,
      codingProjectId: plan.codingProjectId,
      baseBranch: plan.baseBranch,
      branchName: plan.branchName,
      worktreePath: plan.worktreePath,
      createdAt: now,
      updatedAt: now,
    );
    final prepareResult = await _ref
        .read(worktreeAgentGitWorktreePreparerProvider)
        .prepare(projectRootPath: projectRootPath, task: task);
    if (!prepareResult.success) {
      throw StateError(
        prepareResult.errorMessage ?? 'Could not create git worktree.',
      );
    }

    return CodingWorktreeSessionLaunchResult(
      plan: plan,
      repositoryRoot: prepareResult.repositoryRoot,
    );
  }
}
