import '../entities/conversation.dart';
import '../entities/conversation_workflow.dart';

/// What a saved task has actually reached, as distinct from what its status
/// enum can say.
///
/// `ConversationWorkflowTaskStatus.completed` answers three different questions
/// at once — a child produced something, a command checked it, the parent judged
/// it — and ANA3's rule is that only the last of those is `accepted`. A child
/// saying "done" means `produced`, and nothing but evidence promotes it.
enum TaskLifecycleState {
  pending,
  inProgress,
  blocked,

  /// Finished, unchecked: something exists and nothing has confirmed it.
  produced,

  /// Finished and its saved validation command passed.
  verified,

  /// The parent recorded a judgement on it.
  accepted,
}

/// Derives [TaskLifecycleState], deliberately without storing it.
///
/// **One writer per state is why this derives rather than stores.** Each of the
/// three facts already has an owner: the status enum is the mechanical
/// lifecycle, `ConversationExecutionValidationStatus` carries verification, and
/// `ConversationTaskAcceptance` carries the acceptance and has exactly one
/// writer. Adding `accepted` to the status enum would hand every existing status
/// writer the power to set it — the shape ANA3's design opens by warning about:
/// `validationStatus` reached three writers, one of them judging prose, and a
/// fourth was added and reverted.
class TaskLifecycleProjection {
  const TaskLifecycleProjection();

  TaskLifecycleState of(
    Conversation conversation,
    ConversationWorkflowTask task,
  ) {
    // Acceptance outranks everything, including a later status edit: the
    // judgement was recorded against evidence at a point in time, and a plan
    // revision that reopens the task does not unmake it.
    final accepted = conversation.taskAcceptances.any(
      (acceptance) => acceptance.taskId == task.id,
    );
    if (accepted) return TaskLifecycleState.accepted;

    final progress = conversation.executionProgressForTask(task.id);
    final status = progress?.status ?? task.status;
    switch (status) {
      case ConversationWorkflowTaskStatus.pending:
        return TaskLifecycleState.pending;
      case ConversationWorkflowTaskStatus.inProgress:
        return TaskLifecycleState.inProgress;
      case ConversationWorkflowTaskStatus.blocked:
        return TaskLifecycleState.blocked;
      case ConversationWorkflowTaskStatus.completed:
        // A task with no validation command owes nothing mechanically and has
        // proved nothing either, so it stays `produced`. Collapsing "nothing to
        // check" into "checked" is how a green light appears for work nobody
        // verified.
        final passed =
            progress?.validationStatus ==
            ConversationExecutionValidationStatus.passed;
        return passed
            ? TaskLifecycleState.verified
            : TaskLifecycleState.produced;
    }
  }

  /// The wire name, which is what a prompt and a log line read.
  String nameOf(TaskLifecycleState state) => switch (state) {
    TaskLifecycleState.pending => 'pending',
    TaskLifecycleState.inProgress => 'in_progress',
    TaskLifecycleState.blocked => 'blocked',
    TaskLifecycleState.produced => 'produced',
    TaskLifecycleState.verified => 'verified',
    TaskLifecycleState.accepted => 'accepted',
  };

  /// Every saved task's state, keyed by task id.
  Map<String, String> namesByTaskId(Conversation conversation) {
    return <String, String>{
      for (final task in conversation.effectiveWorkflowSpec.tasks)
        if (task.id.trim().isNotEmpty) task.id: nameOf(of(conversation, task)),
    };
  }
}
