import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';

bool planApprovalTransitionObserved({
  required Conversation? conversation,
  required bool isLoading,
}) {
  if (isLoading) {
    return true;
  }
  if (conversation == null) {
    return false;
  }
  if (conversation.projectedExecutionTasks.isNotEmpty) {
    return true;
  }
  return switch (conversation.workflowStage) {
    ConversationWorkflowStage.implement ||
    ConversationWorkflowStage.review => true,
    _ => false,
  };
}

bool shouldRetryPlanApprovalTap({
  required Conversation? conversation,
  required bool isLoading,
  required bool approvalVisible,
}) {
  if (!approvalVisible) {
    return false;
  }
  return !planApprovalTransitionObserved(
    conversation: conversation,
    isLoading: isLoading,
  );
}

bool shouldRecoverPlanApprovalFromExecutionDocument({
  required Conversation? conversation,
  required bool isLoading,
}) {
  if (isLoading || conversation == null) {
    return false;
  }
  if (conversation.projectedExecutionTasks.isNotEmpty) {
    return false;
  }
  return conversation.shouldPreferPlanDocument &&
      (conversation.effectiveExecutionDocument?.trim().isNotEmpty ?? false);
}

bool shouldHandlePlanningDecision({
  required bool hasPendingDecision,
  required bool confirmVisible,
}) {
  if (!confirmVisible) {
    return false;
  }
  return hasPendingDecision;
}

bool shouldWaitForPlanApprovalToSettle({
  required DateTime? approvalTappedAt,
  required DateTime now,
  Duration settleDelay = const Duration(seconds: 2),
}) {
  if (approvalTappedAt == null) {
    return false;
  }
  return now.difference(approvalTappedAt) < settleDelay;
}
