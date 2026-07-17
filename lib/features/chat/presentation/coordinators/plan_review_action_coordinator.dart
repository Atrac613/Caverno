import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_plan_artifact.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../../domain/services/conversation_plan_execution_coordinator.dart';
import '../../domain/services/conversation_plan_projection_service.dart';
import '../providers/conversations_notifier.dart';

sealed class PlanReviewApprovalOutcome {
  const PlanReviewApprovalOutcome();
}

final class PlanReviewApprovalMissingDocument
    extends PlanReviewApprovalOutcome {
  const PlanReviewApprovalMissingDocument();
}

final class PlanReviewApprovalBlocked extends PlanReviewApprovalOutcome {
  const PlanReviewApprovalBlocked(this.errorMessage);

  final String errorMessage;
}

final class PlanReviewApprovalAborted extends PlanReviewApprovalOutcome {
  const PlanReviewApprovalAborted();
}

final class PlanReviewApprovalReady extends PlanReviewApprovalOutcome {
  const PlanReviewApprovalReady({
    required this.executionConversation,
    required this.nextTask,
  });

  final Conversation executionConversation;
  final ConversationWorkflowTask? nextTask;
}

final class PlanReviewActionCoordinator {
  PlanReviewActionCoordinator({
    required ConversationsNotifier conversationsNotifier,
    required Conversation? Function() readCurrentConversation,
    required void Function() dismissPlanProposal,
    required bool Function() isPageMounted,
    required DateTime Function() now,
  }) : _conversationsNotifier = conversationsNotifier,
       _readCurrentConversation = readCurrentConversation,
       _dismissPlanProposal = dismissPlanProposal,
       _isPageMounted = isPageMounted,
       _now = now;

  final ConversationsNotifier _conversationsNotifier;
  final Conversation? Function() _readCurrentConversation;
  final void Function() _dismissPlanProposal;
  final bool Function() _isPageMounted;
  final DateTime Function() _now;

  Future<String?> prepareEdit({
    required Conversation currentConversation,
  }) async {
    if (!currentConversation.isPlanningSession) {
      await _conversationsNotifier.enterPlanningSession();
    }
    if (!_isPageMounted()) {
      return null;
    }
    return currentConversation.effectivePlanArtifact.hasApproved
        ? 'Please revise the saved plan for this thread based on the following adjustment:\n- '
        : 'Please adjust the current draft plan for this thread as follows:\n- ';
  }

  Future<bool> cancelReview({required Conversation currentConversation}) async {
    final latestConversation =
        _readCurrentConversation() ?? currentConversation;
    final planArtifact = latestConversation.effectivePlanArtifact;

    if (planArtifact.hasApproved && planArtifact.hasPendingEdits) {
      final approvedMarkdown = planArtifact.normalizedApprovedMarkdown ?? '';
      final updatedAt = _now();
      final nextArtifact = planArtifact
          .copyWith(draftMarkdown: approvedMarkdown, updatedAt: updatedAt)
          .recordRevision(
            markdown: approvedMarkdown,
            kind: ConversationPlanRevisionKind.restored,
            label: 'Cancelled draft changes and restored approved plan',
            createdAt: updatedAt,
          );
      await _conversationsNotifier.updateCurrentPlanArtifact(
        planArtifact: nextArtifact,
      );
    } else if (!planArtifact.hasApproved) {
      await _conversationsNotifier.updateCurrentPlanArtifact(
        clearPlanArtifact: true,
      );
    }

    await _conversationsNotifier.exitPlanningSession();
    _dismissPlanProposal();
    return _isPageMounted();
  }

  Future<PlanReviewApprovalOutcome> approveCurrentPlan({
    required Conversation currentConversation,
  }) async {
    final latestConversation =
        _readCurrentConversation() ?? currentConversation;
    final currentArtifact = latestConversation.effectivePlanArtifact;
    final draftMarkdown =
        currentArtifact.normalizedDraftMarkdown ??
        currentArtifact.normalizedApprovedMarkdown;
    if (draftMarkdown == null) {
      return const PlanReviewApprovalMissingDocument();
    }

    final validation = ConversationPlanProjectionService.validateDocument(
      markdown: draftMarkdown,
      requireTasks: true,
    );
    if (!validation.isValid || validation.projection == null) {
      return PlanReviewApprovalBlocked(
        validation.errorMessage ?? 'plan document could not be parsed',
      );
    }

    final approvedWorkflowStage = switch (validation.workflowStage) {
      ConversationWorkflowStage.tasks ||
      ConversationWorkflowStage.implement ||
      ConversationWorkflowStage.review => validation.workflowStage!,
      _ =>
        validation.previewTasks.isEmpty
            ? ConversationWorkflowStage.tasks
            : ConversationWorkflowStage.implement,
    };
    final approvedMarkdown =
        ConversationPlanProjectionService.replaceWorkflowStage(
          markdown: draftMarkdown,
          workflowStage: approvedWorkflowStage,
        );
    final updatedAt = _now();
    final nextArtifact = currentArtifact
        .copyWith(
          draftMarkdown: approvedMarkdown,
          approvedMarkdown: approvedMarkdown,
          updatedAt: updatedAt,
        )
        .recordRevision(
          markdown: approvedMarkdown,
          kind: ConversationPlanRevisionKind.approved,
          label: 'Approved plan from timeline review',
          createdAt: updatedAt,
        );

    await _conversationsNotifier.updateCurrentPlanArtifact(
      planArtifact: nextArtifact,
      clearPlanArtifact: !nextArtifact.hasContent,
    );
    final refreshed = await _conversationsNotifier
        .refreshCurrentWorkflowProjectionFromApprovedPlan();
    if (!_isPageMounted()) {
      return const PlanReviewApprovalAborted();
    }
    if (!refreshed && validation.workflowSpec != null) {
      await _conversationsNotifier.updateCurrentWorkflow(
        workflowStage: approvedWorkflowStage,
        workflowSpec: validation.workflowSpec!,
      );
    }

    await _conversationsNotifier.exitPlanningSession();
    _dismissPlanProposal();
    if (!_isPageMounted()) {
      return const PlanReviewApprovalAborted();
    }

    final executionConversation =
        _readCurrentConversation() ?? latestConversation;
    var nextTask = ConversationPlanExecutionCoordinator.nextTask(
      executionConversation,
    );
    if (nextTask == null && validation.workflowSpec != null) {
      await _conversationsNotifier.updateCurrentWorkflow(
        workflowStage: approvedWorkflowStage,
        workflowSpec: validation.workflowSpec!,
      );
      if (!_isPageMounted()) {
        return const PlanReviewApprovalAborted();
      }
      final refreshedExecutionConversation =
          _readCurrentConversation() ?? executionConversation;
      nextTask = ConversationPlanExecutionCoordinator.nextTask(
        refreshedExecutionConversation,
      );
    }

    return PlanReviewApprovalReady(
      executionConversation: executionConversation,
      nextTask: nextTask,
    );
  }
}
