enum TaskState { queued, running, paused, done, failed, cancelled }

/// Legal transitions for a background task.
///
/// `done`, `failed` and `cancelled` are terminal: once a task reaches one, no
/// further transition is allowed, so a late event cannot resurrect it.
class TaskStateMachine {
  const TaskStateMachine();

  static const _allowed = <TaskState, Set<TaskState>>{
    TaskState.queued: {TaskState.running, TaskState.cancelled},
    TaskState.running: {
      TaskState.paused,
      TaskState.done,
      TaskState.failed,
      TaskState.cancelled,
    },
    TaskState.paused: {TaskState.running, TaskState.cancelled},
    TaskState.done: <TaskState>{},
    TaskState.failed: <TaskState>{},
    TaskState.cancelled: <TaskState>{},
  };

  bool isTerminal(TaskState state) => _allowed[state]!.isEmpty;

  bool canTransition(TaskState from, TaskState to) {
    return _allowed[from]!.contains(to);
  }

  /// Applies [to], or returns [from] unchanged when the move is illegal.
  TaskState transition(TaskState from, TaskState to) {
    return canTransition(from, to) ? to : from;
  }

  /// Replays [events] from [initial], ignoring any illegal step.
  TaskState replay(TaskState initial, List<TaskState> events) {
    var current = initial;
    for (final event in events) {
      if (!canTransition(current, event)) {
        return current;
      }
      current = transition(current, event);
    }
    return current;
  }
}
