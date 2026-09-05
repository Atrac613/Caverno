import '../entities/conversation.dart';
import '../entities/conversation_workflow.dart';
import 'conversation_task_precondition_refs.dart';

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
  const ConversationTaskReadinessResolver({
    this.refs = const ConversationTaskPreconditionRefs(),
  });

  final ConversationTaskPreconditionRefs refs;

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
      ConversationTaskPreconditionKind.assumption => _isAssumptionConfirmed(
        conversation,
        ref,
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
    final spec = conversation.effectiveWorkflowSpec;
    final task = refs.taskFor(spec, ref);
    if (task == null) return false;
    final progress = conversation.executionProgressForTask(task.id);
    final status = progress?.status ?? task.status;
    if (status != ConversationWorkflowTaskStatus.completed) return false;
    if (task.validationCommand.trim().isEmpty) return true;
    return progress?.validationStatus ==
        ConversationExecutionValidationStatus.passed;
  }

  /// Whether the contract item [ref] names has been confirmed by the user.
  ///
  /// The ref arrives as the constraint's own text, so it is resolved to an id
  /// before the provenance is asked. Comparing it to `itemId` directly — which
  /// is what this did until the first real plan was measured — can never match:
  /// an id is a hash of the text, not the text.
  bool _isAssumptionConfirmed(Conversation conversation, String ref) {
    final spec = conversation.effectiveWorkflowSpec;
    final itemId = refs.itemIdFor(spec, ref);
    if (itemId == null) return false;
    return spec.provenance.any(
      (item) => item.itemId == itemId && item.confirmed,
    );
  }
}
