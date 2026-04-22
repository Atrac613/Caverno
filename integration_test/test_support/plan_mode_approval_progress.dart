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
