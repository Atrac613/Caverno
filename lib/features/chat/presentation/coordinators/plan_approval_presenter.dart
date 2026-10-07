import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../providers/chat_notifier.dart';
import 'plan_review_action_coordinator.dart';

/// Presents plan approval outcomes and dispatches the approved next action.
abstract final class PlanApprovalPresenter {
  static Future<void> show({
    required BuildContext context,
    required PlanReviewApprovalOutcome outcome,
    required String languageCode,
    required ScaffoldMessengerState messenger,
    required ChatNotifier chatNotifier,
    required VoidCallback clearComposer,
    required Future<void> Function(
      BuildContext, {
      required Conversation currentConversation,
      required ConversationWorkflowTask task,
    })
    runTask,
  }) async {
    switch (outcome) {
      case PlanReviewApprovalMissingDocument() || PlanReviewApprovalAborted():
        return;
      case PlanReviewApprovalBlocked(:final errorMessage):
        if (!context.mounted) {
          return;
        }
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'chat.plan_document_approval_blocked'.tr(
                namedArgs: {'error': errorMessage},
              ),
            ),
          ),
        );
        return;
      case PlanReviewApprovalReady(
        :final executionConversation,
        :final nextTask,
      ):
        clearComposer();
        messenger.showSnackBar(
          SnackBar(content: Text('chat.plan_proposal_started'.tr())),
        );
        if (nextTask == null) {
          await chatNotifier.sendMessage(
            'chat.plan_proposal_execute_prompt'.tr(),
            languageCode: languageCode,
            bypassPlanMode: true,
          );
          return;
        }
        if (!context.mounted) {
          return;
        }
        await runTask(
          context,
          currentConversation: executionConversation,
          task: nextTask,
        );
    }
  }
}
