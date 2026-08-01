import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/subagent_task.dart';

/// Immutable owner-filtered view of in-memory subagent tasks.
///
/// Normal callers can inspect only an exact owner. The administrative view is
/// intentionally explicit because it may contain legacy tasks without an
/// owner.
final class SubagentTaskState {
  SubagentTaskState._(Iterable<SubagentTask> tasks)
    : _tasks = List<SubagentTask>.unmodifiable(tasks);

  factory SubagentTaskState.forAdministrativeView(
    Iterable<SubagentTask> tasks,
  ) => SubagentTaskState._(tasks);

  static final SubagentTaskState empty = SubagentTaskState._(
    const <SubagentTask>[],
  );

  final List<SubagentTask> _tasks;

  List<SubagentTask> tasksFor(ChatTurnOwner owner) =>
      List<SubagentTask>.unmodifiable(
        _tasks.where((task) => task.isOwnedBy(owner)),
      );

  List<SubagentTask> activeTasksFor(ChatTurnOwner owner) =>
      List<SubagentTask>.unmodifiable(
        _tasks.where((task) => task.isOwnedBy(owner) && task.isActive),
      );

  List<SubagentTask> tasksForConversation(String conversationId) {
    final normalizedId = conversationId.trim();
    if (normalizedId.isEmpty) {
      return const <SubagentTask>[];
    }
    return List<SubagentTask>.unmodifiable(
      _tasks.where(
        (task) => !task.isLegacyUnowned && task.conversationId == normalizedId,
      ),
    );
  }

  /// Privileged cross-owner view for diagnostics and legacy inspection only.
  List<SubagentTask> get administrativeView => _tasks;
}

/// Tracks background subagent tasks so the UI can show progress and the
/// assistant can retrieve results later via `get_subagent_result`.
///
/// Kept alive (not autoDispose) so a background task survives navigation away
/// from the chat page.
final subagentTaskNotifierProvider =
    NotifierProvider<SubagentTaskNotifier, SubagentTaskState>(
      SubagentTaskNotifier.new,
    );

class SubagentTaskNotifier extends Notifier<SubagentTaskState> {
  final Set<ChatTurnOwner> _retiredOwners = <ChatTurnOwner>{};

  @override
  SubagentTaskState build() => SubagentTaskState.empty;

  bool register(ChatTurnOwner owner, SubagentTask task) {
    if (_retiredOwners.contains(owner) ||
        !task.isOwnedBy(owner) ||
        byId(owner, task.id) != null) {
      return false;
    }
    _replace([...state._tasks, task]);
    return true;
  }

  bool markRunning(ChatTurnOwner owner, String id) => _updateActive(
    owner,
    id,
    (task) => task.copyWith(status: SubagentTaskStatus.running),
  );

  bool complete(
    ChatTurnOwner owner,
    String id, {
    required String output,
    required String summary,
  }) => _updateActive(
    owner,
    id,
    (task) => task.copyWith(
      status: SubagentTaskStatus.completed,
      output: output,
      resultSummary: summary,
      finishedAt: DateTime.now(),
    ),
  );

  bool fail(ChatTurnOwner owner, String id, String error) => _updateActive(
    owner,
    id,
    (task) => task.copyWith(
      status: SubagentTaskStatus.failed,
      error: error,
      finishedAt: DateTime.now(),
    ),
  );

  /// Soft-cancel: marks the task cancelled so its eventual result is ignored.
  /// The in-flight async run cannot be force-stopped, but its output is dropped.
  bool cancel(ChatTurnOwner owner, String id) => _updateActive(
    owner,
    id,
    (task) => task.copyWith(
      status: SubagentTaskStatus.cancelled,
      finishedAt: DateTime.now(),
    ),
  );

  bool markNotified(ChatTurnOwner owner, String id) => _update(
    owner,
    id,
    (task) => task.notified ? null : task.copyWith(notified: true),
  );

  bool remove(ChatTurnOwner owner, String id) {
    if (_retiredOwners.contains(owner)) {
      return false;
    }
    final previousLength = state._tasks.length;
    _replace(
      state._tasks.where((task) => !task.isOwnedBy(owner) || task.id != id),
    );
    return state._tasks.length != previousLength;
  }

  /// Removes settled tasks for one owner, keeping all other owners unchanged.
  int clearFinished(ChatTurnOwner owner) {
    if (_retiredOwners.contains(owner)) {
      return 0;
    }
    final previousLength = state._tasks.length;
    _replace(
      state._tasks.where((task) => !task.isOwnedBy(owner) || task.isActive),
    );
    return previousLength - state._tasks.length;
  }

  /// Retires one exact owner before dropping its tasks.
  ///
  /// Later completion, registration, and notification callbacks are rejected.
  void clearOwner(ChatTurnOwner owner) {
    _retiredOwners.add(owner);
    _replace(state._tasks.where((task) => !task.isOwnedBy(owner)));
  }

  SubagentTask? byId(ChatTurnOwner owner, String id) {
    if (_retiredOwners.contains(owner)) {
      return null;
    }
    for (final task in state._tasks) {
      if (task.id == id && task.isOwnedBy(owner)) {
        return task;
      }
    }
    return null;
  }

  List<SubagentTask> tasksFor(ChatTurnOwner owner) => state.tasksFor(owner);

  List<SubagentTask> activeTasks(ChatTurnOwner owner) =>
      state.activeTasksFor(owner);

  bool _updateActive(
    ChatTurnOwner owner,
    String id,
    SubagentTask Function(SubagentTask task) transform,
  ) => _update(owner, id, (task) => task.isActive ? transform(task) : null);

  bool _update(
    ChatTurnOwner owner,
    String id,
    SubagentTask? Function(SubagentTask task) transform,
  ) {
    if (_retiredOwners.contains(owner)) {
      return false;
    }
    var changed = false;
    final updated = <SubagentTask>[];
    for (final task in state._tasks) {
      if (!changed && task.id == id && task.isOwnedBy(owner)) {
        final transformed = transform(task);
        if (transformed != null) {
          updated.add(transformed);
          changed = true;
          continue;
        }
      }
      updated.add(task);
    }
    if (changed) {
      _replace(updated);
    }
    return changed;
  }

  void _replace(Iterable<SubagentTask> tasks) {
    state = SubagentTaskState._(tasks);
  }
}
