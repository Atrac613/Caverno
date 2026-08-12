enum TaskState { queued, running, paused, done, failed, cancelled }

/// Legal transitions for a background task.
class TaskStateMachine {
  const TaskStateMachine();

  static const _allowed = <TaskState, Set<TaskState>>{
    TaskState.queued: <TaskState>{},
    TaskState.running: <TaskState>{},
    TaskState.paused: <TaskState>{},
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
      current = transition(current, event);
    }
    return current;
  }
}
