import '../entities/conversation.dart';
import '../entities/conversation_workflow.dart';

/// Why a task is not ready yet, or that it is.
///
/// Carries the unmet edges rather than a bare boolean because every consumer
/// of readiness has to explain it: a rendered decomposition says what a task
/// waits on, and a scheduler that only knew "not ready" would have nothing to
/// tell the user when nothing moves.
class ConversationTaskReadiness {
  const ConversationTaskReadiness({required this.unmet});

  final List<ConversationTaskPrecondition> unmet;

  bool get isReady => unmet.isEmpty;
}

/// Derives whether each task's preconditions hold (ANA1).
///
/// Every kind resolves against state that already exists — task status and its
/// validation evidence, `ConversationContractItemProvenance.confirmed`, and
/// `ConversationOpenQuestionStatus.resolved`. Nothing here is stored, so there
/// is no second writer to disagree with the graph.
class ConversationTaskReadinessResolver {
  const ConversationTaskReadinessResolver();

  ConversationTaskReadiness resolve(
    Conversation conversation,
    ConversationWorkflowTask task,
  ) {
    final unmet = task.preconditions
        .where((precondition) => !_isSatisfied(conversation, precondition))
        .toList(growable: false);
    return ConversationTaskReadiness(unmet: unmet);
  }

  /// Readiness for every task in the contract, keyed by task id.
  Map<String, ConversationTaskReadiness> resolveAll(Conversation conversation) {
    return <String, ConversationTaskReadiness>{
      for (final task in conversation.effectiveWorkflowSpec.tasks)
        task.id: resolve(conversation, task),
    };
  }

  bool _isSatisfied(
    Conversation conversation,
    ConversationTaskPrecondition precondition,
  ) {
    // An edge pointing nowhere is unmet. Treating it as satisfied would let a
    // malformed plan run work it said depended on something.
    if (!precondition.isValid) return false;
    final ref = precondition.ref.trim();
    return switch (precondition.kind) {
      ConversationTaskPreconditionKind.task => _isTaskDone(conversation, ref),
      ConversationTaskPreconditionKind.assumption =>
        conversation.effectiveWorkflowSpec.provenance.any(
          (item) => item.itemId == ref && item.confirmed,
        ),
      ConversationTaskPreconditionKind.question =>
        conversation.openQuestionProgress.any(
          (item) =>
              item.question.trim() == ref &&
              item.status == ConversationOpenQuestionStatus.resolved,
        ),
    };
  }

  /// Whether the task [ref] names has finished in the only sense Caverno can
  /// currently express.
  ///
  /// The lifecycle wants `accepted` here, and no status enum has it: `completed`
  /// today conflates produced, verified and accepted, which ANA3 separates. So
  /// this asks for the strongest existing evidence instead of the claim alone —
  /// a task that declares a validation command must also have passed it. That
  /// is the same distinction goal auto-continue once got wrong by reading the
  /// lenient of two notions of "verified".
  bool _isTaskDone(Conversation conversation, String ref) {
    final tasks = conversation.effectiveWorkflowSpec.tasks;
    final match = tasks.where((task) => task.id.trim() == ref);
    if (match.isEmpty) return false;
    final task = match.first;
    final progress = conversation.executionProgressForTask(task.id);
    final status = progress?.status ?? task.status;
    if (status != ConversationWorkflowTaskStatus.completed) return false;
    if (task.validationCommand.trim().isEmpty) return true;
    return progress?.validationStatus ==
        ConversationExecutionValidationStatus.passed;
  }
}
