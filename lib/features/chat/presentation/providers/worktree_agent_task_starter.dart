import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/worktree_agent_task.dart';
import 'worktree_agent_git_worktree_preparer.dart';
import 'worktree_agent_task_registry_notifier.dart';

class WorktreeAgentTaskStartResult {
  const WorktreeAgentTaskStartResult({
    required this.success,
    required this.taskId,
    this.repositoryRoot = '',
    this.errorMessage,
  });

  const WorktreeAgentTaskStartResult.succeeded({
    required String taskId,
    required String repositoryRoot,
  }) : this(success: true, taskId: taskId, repositoryRoot: repositoryRoot);

  const WorktreeAgentTaskStartResult.failed({
    required String taskId,
    required String errorMessage,
  }) : this(success: false, taskId: taskId, errorMessage: errorMessage);

  final bool success;
  final String taskId;
  final String repositoryRoot;
  final String? errorMessage;
}

final worktreeAgentTaskStarterProvider = Provider<WorktreeAgentTaskStarter>((
  ref,
) {
  return WorktreeAgentTaskStarter(ref);
});

class WorktreeAgentTaskStarter {
  const WorktreeAgentTaskStarter(this._ref);

  final Ref _ref;

  Future<WorktreeAgentTaskStartResult> start({
    required String taskId,
    required String projectRootPath,
  }) async {
    final normalizedTaskId = taskId.trim();
    final registry = _ref.read(worktreeAgentTaskRegistryNotifierProvider);
    final task = registry.byId(normalizedTaskId);
    if (task == null) {
      return WorktreeAgentTaskStartResult.failed(
        taskId: normalizedTaskId,
        errorMessage: 'Worktree-agent task was not found.',
      );
    }
    if (task.status != WorktreeAgentTaskStatus.queued) {
      return WorktreeAgentTaskStartResult.failed(
        taskId: task.id,
        errorMessage: 'Only queued worktree-agent tasks can be started.',
      );
    }

    final prepareResult = await _ref
        .read(worktreeAgentGitWorktreePreparerProvider)
        .prepare(projectRootPath: projectRootPath, task: task);
    final notifier = _ref.read(
      worktreeAgentTaskRegistryNotifierProvider.notifier,
    );
    if (!prepareResult.success) {
      final errorMessage =
          prepareResult.errorMessage ?? 'Could not create git worktree.';
      await notifier.markFailed(task.id, errorMessage);
      return WorktreeAgentTaskStartResult.failed(
        taskId: task.id,
        errorMessage: errorMessage,
      );
    }

    await notifier.markRunning(task.id);
    return WorktreeAgentTaskStartResult.succeeded(
      taskId: task.id,
      repositoryRoot: prepareResult.repositoryRoot,
    );
  }
}
