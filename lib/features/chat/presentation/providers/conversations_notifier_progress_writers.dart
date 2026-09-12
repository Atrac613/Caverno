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

  /// Records the parent's semantic acceptance of a saved task.
  ///
  /// **The only writer of [Conversation.taskAcceptances], by design.** §10 asks
  /// for one writer per state, and this state exists precisely because
  /// `ConversationExecutionValidationStatus` has three -- one of which judges
  /// prose -- and a fourth was added and reverted. Nothing else may write here.
  ///
  /// Judges nothing. Whether the parent *may* accept is
  /// `TaskAcceptanceAudit.mayParentAccept`, decided before this is called; an
  /// acceptance that reached this method has already cleared the derivable
  /// levels. The rationale is recorded as the parent's words, never read.
  ///
  /// [premises] is what makes the acceptance revisitable: ANA2's contradiction
  /// policy can only bar a result whose premise has lapsed if the premises in
  /// force at acceptance time were written down.
  Future<bool> recordTaskAcceptance({
    required String taskId,
    String rationale = '',
    List<String> evidence = const <String>[],
    List<String> premises = const <String>[],
    String? conversationId,
  }) async {
    final conversation = conversationId == null
        ? state.currentConversation
        : state.conversations
              .where((candidate) => candidate.id == conversationId)
              .firstOrNull;
    if (conversation == null) {
      return false;
    }
    final normalizedTaskId = taskId.trim();
    if (normalizedTaskId.isEmpty) {
      return false;
    }

    final entry = ConversationTaskAcceptance(
      taskId: normalizedTaskId,
      acceptedAt: DateTime.now(),
      rationale: rationale.trim(),
      evidence: evidence
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      premises: premises
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );

    // Replaced rather than appended: a task accepted twice has one acceptance,
    // the current one. Keeping both would leave two answers to "was this
    // accepted, and on what", which is the ambiguity the single-writer rule
    // exists to prevent.
    final acceptances = [...conversation.taskAcceptances];
    final index = acceptances.indexWhere(
      (candidate) => candidate.taskId == normalizedTaskId,
    );
    if (index >= 0) {
      acceptances[index] = entry;
    } else {
      acceptances.add(entry);
    }

    await _persistUpdatedConversation(
      conversation.copyWith(
        taskAcceptances: List<ConversationTaskAcceptance>.unmodifiable(
          acceptances,
        ),
        updatedAt: DateTime.now(),
      ),
    );
    return true;
  }
}
