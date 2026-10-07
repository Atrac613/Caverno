// Same-library extension on [_ChatPageState]; see chat_page_empty_state_builders.dart
// for the rationale behind the `ignore_for_file` directive.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

part of 'chat_page.dart';

extension _ChatPagePlanBuilders on _ChatPageState {
  Future<void> _answerOpenQuestion(
    BuildContext context, {
    required String question,
    String? existingNote,
  }) async {
    final pending = PendingWorkflowDecision(
      id: 'open-question-${_uuid.v4()}',
      decision: WorkflowPlanningDecision(
        id: Conversation.openQuestionIdFor(question),
        question: question.trim(),
        help: 'chat.open_question_answer_subtitle'.tr(),
        allowFreeText: true,
        freeTextPlaceholder: 'chat.open_question_answer_placeholder'.tr(),
        options: const [],
      ),
      completer: Completer<WorkflowPlanningDecisionAnswer?>(),
    );
    final answer = await showModalBottomSheet<WorkflowPlanningDecisionAnswer>(
      context: context,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _WorkflowDecisionSheet(
        pending: pending,
        initialFreeText: existingNote,
        titleText: 'chat.open_question_answer_title'.tr(),
      ),
    );
    if (answer == null || !context.mounted) {
      return;
    }

    await ref
        .read(conversationsNotifierProvider.notifier)
        .updateCurrentOpenQuestionProgress(
          question: question,
          status: ConversationOpenQuestionStatus.resolved,
          note: answer.optionLabel,
        );

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('chat.open_question_answer_saved'.tr())),
    );
  }

  Future<void> _setOpenQuestionStatus(
    BuildContext context, {
    required String question,
    required ConversationOpenQuestionStatus status,
  }) async {
    await ref
        .read(conversationsNotifierProvider.notifier)
        .updateCurrentOpenQuestionProgress(question: question, status: status);

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'chat.plan_document_open_question_status_changed'.tr(
            namedArgs: {
              'status': switch (status) {
                ConversationOpenQuestionStatus.unresolved =>
                  'chat.open_question_status_unresolved'.tr(),
                ConversationOpenQuestionStatus.needsUserInput =>
                  'chat.open_question_status_needs_user_input'.tr(),
                ConversationOpenQuestionStatus.resolved =>
                  'chat.open_question_status_resolved'.tr(),
                ConversationOpenQuestionStatus.deferred =>
                  'chat.open_question_status_deferred'.tr(),
              },
            },
          ),
        ),
      ),
    );
  }

  /// The panel's one way in, wired to the three actions this page owns.
  Future<void> _openAwaitingYouSheet(
    BuildContext context, {
    required Conversation currentConversation,
  }) async {
    await showAwaitingYouSheet(
      context,
      currentConversation: currentConversation,
      watchConversation: (sheetRef) =>
          sheetRef.watch(conversationsNotifierProvider).currentConversation,
      onStatusSelected: (question, status) =>
          _setOpenQuestionStatus(context, question: question, status: status),
      onAnswerPressed: (question, existingNote) => _answerOpenQuestion(
        context,
        question: question,
        existingNote: existingNote,
      ),
      onConfirmAssumption: (conversation, confirmedSpec) =>
          _confirmMaterialAssumption(
            context,
            currentConversation: conversation,
            confirmedSpec: confirmedSpec,
          ),
    );
    if (!mounted) return;
    setState(() {});
  }


  /// Persists one material assumption the user confirmed from the sheet.
  ///
  /// `confirmMaterialAssumption`'s only other caller is the gate, which runs
  /// when a mutation is already blocked. Without this the answer could only be
  /// given to an interrupt, and a dismissed interrupt had no way back.
  Future<void> _confirmMaterialAssumption(
    BuildContext context, {
    required Conversation currentConversation,
    required ConversationWorkflowSpec confirmedSpec,
  }) async {
    await ref
        .read(conversationsNotifierProvider.notifier)
        .updateCurrentWorkflow(
          conversationId: currentConversation.id,
          preserveWorkflowProjection: true,
          workflowSpec: confirmedSpec,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('chat.contract_assumption_confirm_toast'.tr())),
    );
  }
}
