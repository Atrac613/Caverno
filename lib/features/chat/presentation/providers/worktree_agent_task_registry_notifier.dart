import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/repositories/worktree_agent_task_repository.dart';
import '../../domain/entities/worktree_agent_task.dart';
import '../../domain/services/worktree_agent_assignment_planner.dart';

class WorktreeAgentTaskRegistryState {
  const WorktreeAgentTaskRegistryState({required this.tasks});

  final List<WorktreeAgentTask> tasks;

  factory WorktreeAgentTaskRegistryState.initial() =>
      const WorktreeAgentTaskRegistryState(tasks: <WorktreeAgentTask>[]);

  WorktreeAgentTaskRegistryState copyWith({List<WorktreeAgentTask>? tasks}) {
    return WorktreeAgentTaskRegistryState(tasks: tasks ?? this.tasks);
  }

  WorktreeAgentTask? byId(String id) {
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  List<WorktreeAgentTask> get occupyingTasks =>
      tasks.where((task) => task.occupiesWorktree).toList(growable: false);

  List<WorktreeAgentTask> get visibleTasks => tasks
      .where((task) => task.status != WorktreeAgentTaskStatus.cancelled)
      .toList(growable: false);

  List<WorktreeAgentTask> get finishedTasks => tasks
      .where(
        (task) =>
            task.status == WorktreeAgentTaskStatus.completed ||
            task.status == WorktreeAgentTaskStatus.failed ||
            task.status == WorktreeAgentTaskStatus.cancelled,
      )
      .toList(growable: false);

  List<WorktreeAgentTask> get reviewReadyTasks => tasks
      .where(
        (task) =>
            task.status == WorktreeAgentTaskStatus.completed &&
            task.verifiedGreen,
      )
      .toList(growable: false);

  List<WorktreeAgentTask> get recoverableTasks =>
      tasks.where((task) => task.isRecoverable).toList(growable: false);

  bool isWorktreeOccupied(String worktreePath, {String? excludingTaskId}) {
    final normalized = WorktreeAgentTask.normalizeWorktreePath(worktreePath);
    return occupyingTasks.any(
      (task) =>
          task.id != excludingTaskId &&
          task.normalizedWorktreePath == normalized,
    );
  }
}

final worktreeAgentTaskRegistryNotifierProvider =
    NotifierProvider<
      WorktreeAgentTaskRegistryNotifier,
      WorktreeAgentTaskRegistryState
    >(WorktreeAgentTaskRegistryNotifier.new);

class WorktreeAgentTaskRegistryNotifier
    extends Notifier<WorktreeAgentTaskRegistryState> {
  late final WorktreeAgentTaskRepository _repository;
  final _uuid = const Uuid();

  @override
  WorktreeAgentTaskRegistryState build() {
    _repository = ref.read(worktreeAgentTaskRepositoryProvider);
    final loaded = _repository.loadAll();
    final recovered = _recoverInterruptedTasks(loaded);
    return WorktreeAgentTaskRegistryState(tasks: recovered);
  }

  Future<WorktreeAgentTask> registerTask({
    required String title,
    required String prompt,
    required String branchName,
    required String worktreePath,
    String codingProjectId = '',
    String baseBranch = 'main',
    String checkpointLineageId = '',
    String endpointId = '',
    String verificationCommand = '',
  }) async {
    final normalizedWorktreePath = WorktreeAgentTask.normalizeWorktreePath(
      worktreePath,
    );
    final normalizedBranchName = branchName.trim();
    if (normalizedWorktreePath.isEmpty) {
      throw ArgumentError('Worktree path is required.');
    }
    if (normalizedBranchName.isEmpty) {
      throw ArgumentError('Branch name is required.');
    }
    _ensureWorktreeAvailable(normalizedWorktreePath);

    final now = DateTime.now();
    final task = WorktreeAgentTask(
      id: _uuid.v4(),
      title: title.trim(),
      prompt: prompt.trim(),
      codingProjectId: codingProjectId.trim(),
      baseBranch: baseBranch.trim().isEmpty ? 'main' : baseBranch.trim(),
      branchName: normalizedBranchName,
      worktreePath: normalizedWorktreePath,
      checkpointLineageId: checkpointLineageId.trim(),
      endpointId: endpointId.trim(),
      verificationCommand: verificationCommand.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await _replaceAll([task, ...state.tasks]);
    return task;
  }

  Future<WorktreeAgentTask> registerAssignment(
    WorktreeAgentAssignmentPlan plan,
  ) {
    return registerTask(
      title: plan.title,
      prompt: plan.prompt,
      branchName: plan.branchName,
      worktreePath: plan.worktreePath,
      codingProjectId: plan.codingProjectId,
      baseBranch: plan.baseBranch,
      checkpointLineageId: plan.checkpointLineageId,
      endpointId: plan.endpointId,
      verificationCommand: plan.verificationCommand,
    );
  }

  Future<void> markRunning(String id) {
    return _updateTask(
      id,
      (task, now) => task.isTerminal
          ? task
          : task.copyWith(
              status: WorktreeAgentTaskStatus.running,
              startedAt: task.startedAt ?? now,
              updatedAt: now,
            ),
    );
  }

  Future<void> markCompleted(
    String id, {
    String resultSummary = '',
    bool verifiedGreen = false,
    String verificationSummary = '',
  }) {
    return _updateTask(
      id,
      (task, now) => task.copyWith(
        status: WorktreeAgentTaskStatus.completed,
        resultSummary: resultSummary.trim(),
        verifiedGreen: verifiedGreen,
        verificationSummary: verificationSummary.trim(),
        error: '',
        finishedAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> markFailed(String id, String error) {
    return _updateTask(
      id,
      (task, now) => task.copyWith(
        status: WorktreeAgentTaskStatus.failed,
        error: error.trim(),
        finishedAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> cancel(String id) {
    return _updateTask(
      id,
      (task, now) => task.isTerminal
          ? task
          : task.copyWith(
              status: WorktreeAgentTaskStatus.cancelled,
              finishedAt: now,
              updatedAt: now,
            ),
    );
  }

  Future<void> markRecoveryQueued(String id) {
    return _updateTask(
      id,
      (task, now) => task.status == WorktreeAgentTaskStatus.needsRecovery
          ? task.copyWith(
              status: WorktreeAgentTaskStatus.queued,
              recoveryNote: '',
              updatedAt: now,
            )
          : task,
    );
  }

  Future<void> remove(String id) {
    return _replaceAll(
      state.tasks.where((task) => task.id != id).toList(growable: false),
    );
  }

  Future<void> clearFinished() {
    return _replaceAll(
      state.tasks.where((task) => !task.isTerminal).toList(growable: false),
    );
  }

  void _ensureWorktreeAvailable(String normalizedWorktreePath) {
    final occupant = state.occupyingTasks
        .where((task) => task.normalizedWorktreePath == normalizedWorktreePath)
        .cast<WorktreeAgentTask?>()
        .firstOrNull;
    if (occupant == null) return;
    throw StateError('Worktree is already assigned to task ${occupant.id}.');
  }

  List<WorktreeAgentTask> _recoverInterruptedTasks(
    List<WorktreeAgentTask> tasks,
  ) {
    var changed = false;
    final now = DateTime.now();
    final recovered = [
      for (final task in tasks)
        if (task.status == WorktreeAgentTaskStatus.queued ||
            task.status == WorktreeAgentTaskStatus.running) ...[
          task.copyWith(
            status: WorktreeAgentTaskStatus.needsRecovery,
            recoveryNote: 'Task was active when the app restarted.',
            updatedAt: now,
          ),
        ] else
          task,
    ];

    for (var i = 0; i < tasks.length; i++) {
      if (tasks[i].status != recovered[i].status) {
        changed = true;
        break;
      }
    }
    if (changed) {
      unawaited(_repository.saveAll(recovered));
    }
    return recovered;
  }

  Future<void> _updateTask(
    String id,
    WorktreeAgentTask Function(WorktreeAgentTask task, DateTime now) update,
  ) {
    final now = DateTime.now();
    return _replaceAll([
      for (final task in state.tasks)
        if (task.id == id) update(task, now) else task,
    ]);
  }

  Future<void> _replaceAll(List<WorktreeAgentTask> tasks) async {
    final sorted = [...tasks]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = state.copyWith(tasks: sorted);
    await _repository.saveAll(sorted);
  }
}
