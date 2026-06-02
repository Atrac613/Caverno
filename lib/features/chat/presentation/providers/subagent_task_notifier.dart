import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/subagent_task.dart';

/// Tracks background subagent tasks so the UI can show progress and the
/// assistant can retrieve results later via `get_subagent_result`.
///
/// Kept alive (not autoDispose) so a background task survives navigation away
/// from the chat page.
final subagentTaskNotifierProvider =
    NotifierProvider<SubagentTaskNotifier, List<SubagentTask>>(
      SubagentTaskNotifier.new,
    );

class SubagentTaskNotifier extends Notifier<List<SubagentTask>> {
  @override
  List<SubagentTask> build() => const <SubagentTask>[];

  void register(SubagentTask task) {
    state = [...state, task];
  }

  void _update(String id, SubagentTask Function(SubagentTask task) transform) {
    state = [
      for (final task in state)
        if (task.id == id) transform(task) else task,
    ];
  }

  void markRunning(String id) =>
      _update(id, (task) => task.copyWith(status: SubagentTaskStatus.running));

  void complete(String id, {required String output, required String summary}) =>
      _update(
        id,
        (task) => task.copyWith(
          status: SubagentTaskStatus.completed,
          output: output,
          resultSummary: summary,
          finishedAt: DateTime.now(),
        ),
      );

  void fail(String id, String error) => _update(
    id,
    (task) => task.copyWith(
      status: SubagentTaskStatus.failed,
      error: error,
      finishedAt: DateTime.now(),
    ),
  );

  /// Soft-cancel: marks the task cancelled so its eventual result is ignored.
  /// The in-flight async run cannot be force-stopped, but its output is dropped.
  void cancel(String id) => _update(
    id,
    (task) => task.isTerminal
        ? task
        : task.copyWith(
            status: SubagentTaskStatus.cancelled,
            finishedAt: DateTime.now(),
          ),
  );

  void markNotified(String id) =>
      _update(id, (task) => task.copyWith(notified: true));

  void remove(String id) {
    state = state.where((task) => task.id != id).toList();
  }

  /// Removes every settled task, keeping only still-running ones.
  void clearFinished() {
    state = state.where((task) => task.isActive).toList();
  }

  SubagentTask? byId(String id) {
    for (final task in state) {
      if (task.id == id) {
        return task;
      }
    }
    return null;
  }

  List<SubagentTask> get activeTasks =>
      state.where((task) => task.isActive).toList(growable: false);
}
