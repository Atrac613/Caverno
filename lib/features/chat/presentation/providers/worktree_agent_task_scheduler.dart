import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/worktree_agent_task.dart';
import 'coding_projects_notifier.dart';
import 'worktree_agent_task_registry_notifier.dart';
import 'worktree_agent_task_starter.dart';

class WorktreeAgentTaskScheduleRequest {
  const WorktreeAgentTaskScheduleRequest({
    this.fallbackProjectRootPath = '',
    this.maxConcurrentPerEndpoint = 1,
    this.maxStarts = 0,
  });

  final String fallbackProjectRootPath;
  final int maxConcurrentPerEndpoint;
  final int maxStarts;
}

class WorktreeAgentTaskScheduleResult {
  const WorktreeAgentTaskScheduleResult({
    required this.started,
    required this.failed,
    required this.skipped,
  });

  final List<WorktreeAgentTaskStartResult> started;
  final List<WorktreeAgentTaskStartResult> failed;
  final List<WorktreeAgentTaskScheduleSkip> skipped;

  bool get changed => started.isNotEmpty || failed.isNotEmpty;
}

class WorktreeAgentTaskScheduleSkip {
  const WorktreeAgentTaskScheduleSkip({
    required this.taskId,
    required this.reason,
  });

  final String taskId;
  final WorktreeAgentTaskScheduleSkipReason reason;
}

enum WorktreeAgentTaskScheduleSkipReason {
  endpointCapacityReached,
  missingProjectRoot,
}

final worktreeAgentTaskSchedulerProvider = Provider<WorktreeAgentTaskScheduler>(
  (ref) {
    return WorktreeAgentTaskScheduler(ref);
  },
);

class WorktreeAgentTaskScheduler {
  const WorktreeAgentTaskScheduler(this._ref);

  final Ref _ref;

  Future<WorktreeAgentTaskScheduleResult> startReady(
    WorktreeAgentTaskScheduleRequest request,
  ) async {
    final capacity = request.maxConcurrentPerEndpoint < 1
        ? 1
        : request.maxConcurrentPerEndpoint;
    final maxStarts = request.maxStarts < 1 ? null : request.maxStarts;
    final state = _ref.read(worktreeAgentTaskRegistryNotifierProvider);
    final projectState = _ref.read(codingProjectsNotifierProvider);
    final runningByEndpoint = _runningCountsByEndpoint(state.tasks);
    final queuedTasks =
        state.tasks
            .where((task) => task.status == WorktreeAgentTaskStatus.queued)
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final started = <WorktreeAgentTaskStartResult>[];
    final failed = <WorktreeAgentTaskStartResult>[];
    final skipped = <WorktreeAgentTaskScheduleSkip>[];

    for (final task in queuedTasks) {
      if (maxStarts != null && started.length >= maxStarts) {
        break;
      }

      final endpointKey = _endpointKey(task.endpointId);
      final runningCount = runningByEndpoint[endpointKey] ?? 0;
      if (runningCount >= capacity) {
        skipped.add(
          WorktreeAgentTaskScheduleSkip(
            taskId: task.id,
            reason: WorktreeAgentTaskScheduleSkipReason.endpointCapacityReached,
          ),
        );
        continue;
      }

      final projectRootPath = _projectRootPathFor(
        task: task,
        projectState: projectState,
        fallbackProjectRootPath: request.fallbackProjectRootPath,
      );
      if (projectRootPath.isEmpty) {
        skipped.add(
          WorktreeAgentTaskScheduleSkip(
            taskId: task.id,
            reason: WorktreeAgentTaskScheduleSkipReason.missingProjectRoot,
          ),
        );
        continue;
      }

      final result = await _ref
          .read(worktreeAgentTaskStarterProvider)
          .start(taskId: task.id, projectRootPath: projectRootPath);
      if (result.success) {
        started.add(result);
        runningByEndpoint[endpointKey] = runningCount + 1;
      } else {
        failed.add(result);
      }
    }

    return WorktreeAgentTaskScheduleResult(
      started: List.unmodifiable(started),
      failed: List.unmodifiable(failed),
      skipped: List.unmodifiable(skipped),
    );
  }

  Map<String, int> _runningCountsByEndpoint(List<WorktreeAgentTask> tasks) {
    final counts = <String, int>{};
    for (final task in tasks) {
      if (task.status != WorktreeAgentTaskStatus.running) continue;
      final endpointKey = _endpointKey(task.endpointId);
      counts[endpointKey] = (counts[endpointKey] ?? 0) + 1;
    }
    return counts;
  }

  String _projectRootPathFor({
    required WorktreeAgentTask task,
    required CodingProjectsState projectState,
    required String fallbackProjectRootPath,
  }) {
    final projectId = task.codingProjectId.trim();
    if (projectId.isNotEmpty) {
      return projectState.findById(projectId)?.normalizedRootPath ?? '';
    }
    return fallbackProjectRootPath.trim();
  }

  String _endpointKey(String endpointId) {
    final normalized = endpointId.trim();
    return normalized.isEmpty ? 'primary' : normalized;
  }
}
