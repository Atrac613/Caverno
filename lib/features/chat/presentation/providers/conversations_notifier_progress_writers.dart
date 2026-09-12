// Same-library part of conversations_notifier.dart; see that file's `part`
// directive. Riverpod marks `state` for the framework and tests only, which an
// extension on the notifier cannot see without this -- the same directive
// chat_notifier's part files carry, for the same reason.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'conversations_notifier.dart';

/// Writers that record progress against a saved plan and that nothing
/// subclasses.
///
/// **Only unoverridden methods may live here, and that is a language
/// constraint rather than a preference.** A part file cannot hold part of a
/// class, so these are extension members -- and an extension member cannot be
/// reached through `super`. Moving `updateCurrentExecutionTaskProgress` or its
/// assistant-turn variant here broke two test doubles that override them with
/// "Superclass has no method named ...", so both stay in the class body.
///
/// Held apart because they are one concern and because ANA3 §10 asks for one
/// writer per state. Co-location is not ownership -- these are still members of
/// [ConversationsNotifier] -- but it gives the next progress writer a file with
/// a budget of its own instead of a 1,775-line one that was exactly full.
/// `ConversationExecutionValidationStatus` is the cautionary case: three
/// writers already, one judging prose, and a fourth added then reverted after
/// the investigation found stderr outranking a clean exit 0.
extension ConversationsNotifierProgressWriters on ConversationsNotifier {
  Future<bool> updateCurrentValidationProgressFromToolResults({
    required ConversationWorkflowTask task,
    required Iterable<ConversationValidationToolResultInput> toolResults,
  }) async {
    final conversation = state.currentConversation;
    if (conversation == null) {
      return false;
    }

    final inference = ConversationValidationToolResultInference.infer(
      task: task,
      toolResults: toolResults,
    );
    if (inference == null) {
      return false;
    }

    final previousProgress = conversation.executionProgressForTask(task.id);
    final preservesCompletedValidation =
        previousProgress?.status == ConversationWorkflowTaskStatus.completed &&
        inference.validationStatus ==
            ConversationExecutionValidationStatus.passed &&
        inference.status != ConversationWorkflowTaskStatus.blocked;

    await updateCurrentExecutionTaskProgress(
      taskId: task.id,
      status: preservesCompletedValidation
          ? ConversationWorkflowTaskStatus.completed
          : inference.status,
      allowStatusRegression: !preservesCompletedValidation,
      summary: inference.summary,
      blockedReason: inference.status == ConversationWorkflowTaskStatus.blocked
          ? inference.blockedReason ?? ''
          : '',
      validationStatus: inference.validationStatus,
      lastValidationAt: DateTime.now(),
      lastValidationCommand: inference.validationCommand,
      lastValidationSummary: inference.validationSummary,
      eventType: ConversationExecutionTaskEventType.validated,
      eventSummary: inference.summary,
    );

    if (!conversation.shouldPreferPlanDocument) {
      return true;
    }

    if (inference.status == ConversationWorkflowTaskStatus.completed) {
      await updateCurrentWorkflow(
        workflowStage: ConversationWorkflowStage.review,
        preserveWorkflowProjection: true,
      );
      return true;
    }

    await updateCurrentWorkflow(
      workflowStage: ConversationWorkflowStage.implement,
      preserveWorkflowProjection: true,
    );
    return true;
  }

  Future<void> updateCurrentOpenQuestionProgress({
    required String question,
    required ConversationOpenQuestionStatus status,
    String? note,
  }) async {
    final conversation = state.currentConversation;
    if (conversation == null) {
      return;
    }

    final normalizedQuestion = question.trim();
    if (normalizedQuestion.isEmpty) {
      return;
    }

    final questionId = Conversation.openQuestionIdFor(normalizedQuestion);
    final progress = [...conversation.effectiveOpenQuestionProgress];
    final index = progress.indexWhere(
      (entry) => entry.questionId == questionId,
    );
    final nextEntry = ConversationOpenQuestionProgress(
      questionId: questionId,
      question: normalizedQuestion,
      status: status,
      note: note?.trim() ?? (index >= 0 ? progress[index].note : ''),
      updatedAt: DateTime.now(),
    );

    if (index >= 0) {
      progress[index] = nextEntry;
    } else {
      progress.add(nextEntry);
    }

    final updatedConversation = conversation.copyWith(
      openQuestionProgress: progress,
      updatedAt: DateTime.now(),
    );
    await _persistUpdatedConversation(updatedConversation);
  }
}
