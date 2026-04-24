import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/services/conversation_plan_projection_service.dart';

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

bool shouldWaitForPlanningDecisionSheet({
  required bool hasPendingDecision,
  required bool confirmVisible,
}) {
  return hasPendingDecision && !confirmVisible;
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

bool planReviewArtifactHasPreviewTasks({required Conversation? conversation}) {
  if (conversation == null) {
    return false;
  }
  final artifact = conversation.effectivePlanArtifact;
  final markdown =
      artifact.displayMarkdown(isPlanning: true) ??
      artifact.displayMarkdown(isPlanning: false);
  if (markdown == null || markdown.trim().isEmpty) {
    return false;
  }
  final validation = ConversationPlanProjectionService.validateDocument(
    markdown: markdown,
    requireTasks: true,
  );
  return validation.previewTasks.isNotEmpty;
}

bool planModeExecutionIsSettled({
  required bool isLoading,
  required bool hasPendingApprovals,
}) {
  return !isLoading && !hasPendingApprovals;
}

bool shouldCancelBackgroundExecutionAfterSettleTimeout({
  required bool waitForExecutionCompletion,
  required bool settled,
}) {
  return !settled && !waitForExecutionCompletion;
}

Duration resolvePostScenarioSettleTimeout({
  required bool usesLiveLlm,
  required bool waitForExecutionCompletion,
}) {
  if (!waitForExecutionCompletion) {
    return const Duration(seconds: 5);
  }
  return usesLiveLlm ? const Duration(seconds: 60) : const Duration(seconds: 5);
}
