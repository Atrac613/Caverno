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

  /// From the two facts a widget already holds, plus whether an acceptance was
  /// recorded.
  ///
  /// Split out because the plan task row has the task and its progress but no
  /// conversation, and only the conversation records an acceptance: this lets
  /// that row stop calling unchecked work `completed` without inventing the one
  /// fact it cannot see.
  TaskLifecycleState ofProgress({
    required ConversationWorkflowTaskStatus status,
    required ConversationExecutionValidationStatus validationStatus,
    bool accepted = false,
  }) {
    if (accepted) return TaskLifecycleState.accepted;
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
        return validationStatus == ConversationExecutionValidationStatus.passed
            ? TaskLifecycleState.verified
            : TaskLifecycleState.produced;
    }
  }

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
    return ofProgress(
      status: progress?.status ?? task.status,
      validationStatus:
          progress?.validationStatus ??
          ConversationExecutionValidationStatus.unknown,
    );
  }

  /// Saved task id -> what its acceptance rested on and why, for the tasks that
  /// have one.
  ///
  /// **ANA3's purpose statement, finally readable.** PR 2b's claim is that the
  /// judgement "stops being something the next turn has to redo from the same
  /// files" -- and until this existed the next turn saw `[accepted]` and nothing
  /// else: `rationale`, `evidence` and `premises` were written by
  /// `recordTaskAcceptance` and read by no production code at all, only by their
  /// own tests. A state name is not a reason.
  ///
  /// Evidence first, because it is the part the parent cannot reconstruct: a
  /// branch name and a command that passed are facts, where the rationale is one
  /// turn's prose about them. Premises are omitted -- an acceptance that still
  /// stands has every premise confirmed, since `acceptance_premise_lapsed` bars
  /// the rest, so listing them would spend prompt on a constant.
  Map<String, String> acceptanceSummariesByTaskId(Conversation conversation) {
    final summaries = <String, String>{};
    for (final acceptance in conversation.taskAcceptances) {
      final parts = <String>[
        if (acceptance.evidence.isNotEmpty) acceptance.evidence.join(', '),
        if (acceptance.rationale.trim().isNotEmpty)
          _clip(acceptance.rationale.trim()),
      ];
      if (parts.isEmpty) continue;
      summaries[acceptance.taskId] = parts.join(' -- ');
    }
    return Map<String, String>.unmodifiable(summaries);
  }

  /// Model-written prose, so bounded before it reaches another prompt.
  static String _clip(String text) {
    final single = text.replaceAll(RegExp(r'\s+'), ' ');
    return single.length <= 180 ? single : '${single.substring(0, 177)}...';
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
