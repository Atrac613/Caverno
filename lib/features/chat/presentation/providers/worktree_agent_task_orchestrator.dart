import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'worktree_agent_task_executor.dart';
import 'worktree_agent_task_scheduler.dart';

class WorktreeAgentTaskRunRequest {
  const WorktreeAgentTaskRunRequest({
    this.fallbackProjectRootPath = '',
    this.maxConcurrentPerEndpoint = 1,
    this.maxStarts = 0,
  });

  final String fallbackProjectRootPath;
  final int maxConcurrentPerEndpoint;
  final int maxStarts;

  WorktreeAgentTaskScheduleRequest toScheduleRequest() {
    return WorktreeAgentTaskScheduleRequest(
      fallbackProjectRootPath: fallbackProjectRootPath,
      maxConcurrentPerEndpoint: maxConcurrentPerEndpoint,
      maxStarts: maxStarts,
    );
  }
}

class WorktreeAgentTaskRunResult {
  const WorktreeAgentTaskRunResult({
    required this.schedule,
    required this.executions,
  });

  final WorktreeAgentTaskScheduleResult schedule;
  final List<WorktreeAgentTaskExecutionResult> executions;

  bool get changed => schedule.changed || executions.isNotEmpty;
}

class WorktreeAgentTaskRunState {
  const WorktreeAgentTaskRunState({
    this.isRunning = false,
    this.lastResult,
    this.errorMessage = '',
  });

  final bool isRunning;
  final WorktreeAgentTaskRunResult? lastResult;
  final String errorMessage;

  WorktreeAgentTaskRunState copyWith({
    bool? isRunning,
    WorktreeAgentTaskRunResult? lastResult,
    String? errorMessage,
    bool clearLastResult = false,
    bool clearError = false,
  }) {
    return WorktreeAgentTaskRunState(
      isRunning: isRunning ?? this.isRunning,
      lastResult: clearLastResult ? null : lastResult ?? this.lastResult,
      errorMessage: clearError ? '' : errorMessage ?? this.errorMessage,
    );
  }
}

final worktreeAgentTaskOrchestratorProvider =
    Provider<WorktreeAgentTaskOrchestrator>((ref) {
      return WorktreeAgentTaskOrchestrator(ref);
    });

final worktreeAgentTaskRunControllerProvider =
    NotifierProvider<WorktreeAgentTaskRunController, WorktreeAgentTaskRunState>(
      WorktreeAgentTaskRunController.new,
    );

class WorktreeAgentTaskOrchestrator {
  const WorktreeAgentTaskOrchestrator(this._ref);

  final Ref _ref;

  Future<WorktreeAgentTaskRunResult> startAndExecuteReady(
    WorktreeAgentTaskRunRequest request,
  ) async {
    final schedule = await _ref
        .read(worktreeAgentTaskSchedulerProvider)
        .startReady(request.toScheduleRequest());
    final executor = _ref.read(worktreeAgentTaskExecutorProvider);
    final executions = await Future.wait([
      for (final started in schedule.started) executor.execute(started.taskId),
    ]);
    return WorktreeAgentTaskRunResult(
      schedule: schedule,
      executions: List.unmodifiable(executions),
    );
  }
}

class WorktreeAgentTaskRunController
    extends Notifier<WorktreeAgentTaskRunState> {
  bool _isRunning = false;

  @override
  WorktreeAgentTaskRunState build() => const WorktreeAgentTaskRunState();

  Future<WorktreeAgentTaskRunResult?> startAndExecuteReady(
    WorktreeAgentTaskRunRequest request,
  ) async {
    if (_isRunning) {
      return null;
    }

    _isRunning = true;
    state = state.copyWith(
      isRunning: true,
      clearLastResult: true,
      clearError: true,
    );
    try {
      final result = await ref
          .read(worktreeAgentTaskOrchestratorProvider)
          .startAndExecuteReady(request);
      state = WorktreeAgentTaskRunState(lastResult: result);
      return result;
    } catch (error) {
      state = WorktreeAgentTaskRunState(errorMessage: error.toString());
      return null;
    } finally {
      _isRunning = false;
      if (state.isRunning) {
        state = state.copyWith(isRunning: false);
      }
    }
  }
}
