import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../../domain/services/conversation_plan_diff_service.dart';
import '../../domain/services/task_lifecycle_state.dart';

abstract final class WorkflowStatusPresentation {
  static String workflowProjectionStatusLabelKey(
    Conversation currentConversation,
  ) {
    if (currentConversation.isWorkflowProjectionFresh) {
      return 'chat.plan_document_projection_fresh';
    }
    if (currentConversation.isWorkflowProjectionStale) {
      return 'chat.plan_document_projection_stale';
    }
    return 'chat.plan_document_projection_unavailable';
  }

  static String planDocumentEditLabelKey(
    Conversation currentConversation, {
    required bool isPlanMode,
  }) {
    final artifact = currentConversation.effectivePlanArtifact;
    if (isPlanMode || artifact.hasPendingEdits) {
      return 'chat.plan_document_edit_draft';
    }
    if (artifact.hasApproved) {
      return 'chat.plan_document_edit_approved';
    }
    return 'chat.plan_document_edit';
  }

  static String planDocumentHeaderEditTooltipKey(
    Conversation currentConversation, {
    required bool isPlanMode,
  }) {
    final artifact = currentConversation.effectivePlanArtifact;
    if (isPlanMode || artifact.hasPendingEdits) {
      return 'chat.plan_document_edit_draft';
    }
    if (artifact.hasApproved) {
      return 'chat.plan_document_edit_approved';
    }
    return 'chat.plan_document_edit';
  }

  static Color workflowProjectionStatusColor(
    BuildContext context,
    Conversation currentConversation,
  ) {
    final scheme = Theme.of(context).colorScheme;
    if (currentConversation.isWorkflowProjectionFresh) {
      return Colors.green.shade700;
    }
    if (currentConversation.isWorkflowProjectionStale) {
      return scheme.tertiary;
    }
    return scheme.error;
  }

  static String workflowStageLabel(ConversationWorkflowStage stage) {
    return switch (stage) {
      ConversationWorkflowStage.idle => 'chat.workflow_stage_idle'.tr(),
      ConversationWorkflowStage.clarify => 'chat.workflow_stage_clarify'.tr(),
      ConversationWorkflowStage.plan => 'chat.workflow_stage_plan'.tr(),
      ConversationWorkflowStage.tasks => 'chat.workflow_stage_tasks'.tr(),
      ConversationWorkflowStage.implement =>
        'chat.workflow_stage_implement'.tr(),
      ConversationWorkflowStage.review => 'chat.workflow_stage_review'.tr(),
    };
  }

  static String workflowTaskStatusLabel(ConversationWorkflowTaskStatus status) {
    return switch (status) {
      ConversationWorkflowTaskStatus.pending =>
        'chat.workflow_task_status_pending'.tr(),
      ConversationWorkflowTaskStatus.inProgress =>
        'chat.workflow_task_status_in_progress'.tr(),
      ConversationWorkflowTaskStatus.completed =>
        'chat.workflow_task_status_completed'.tr(),
      ConversationWorkflowTaskStatus.blocked =>
        'chat.workflow_task_status_blocked'.tr(),
    };
  }

  /// What a task has actually reached, as distinct from what its status enum can
  /// say: `completed` answers produced, verified and accepted at once.
  static String taskLifecycleLabel(TaskLifecycleState state) {
    return switch (state) {
      TaskLifecycleState.pending => 'chat.workflow_task_status_pending'.tr(),
      TaskLifecycleState.inProgress =>
        'chat.workflow_task_status_in_progress'.tr(),
      TaskLifecycleState.blocked => 'chat.workflow_task_status_blocked'.tr(),
      TaskLifecycleState.produced => 'chat.workflow_task_status_produced'.tr(),
      TaskLifecycleState.verified => 'chat.workflow_task_status_verified'.tr(),
      TaskLifecycleState.accepted => 'chat.workflow_task_status_accepted'.tr(),
    };
  }

  /// The label for a task whose conversation may or may not be to hand.
  ///
  /// Acceptance is recorded on the conversation and nowhere else, so without one
  /// the status enum is the fallback -- the same fallback the prompt uses for an
  /// id its snapshot does not name.
  static String taskLifecycleLabelFor(
    Conversation? conversation,
    ConversationWorkflowTask task,
  ) => conversation == null
      ? workflowTaskStatusLabel(task.status)
      : taskLifecycleLabel(
          const TaskLifecycleProjection().of(conversation, task),
        );

  static String workflowValidationStatusLabel(
    ConversationExecutionValidationStatus status,
  ) {
    return switch (status) {
      ConversationExecutionValidationStatus.unknown =>
        'chat.workflow_task_validation_status_unknown'.tr(),
      ConversationExecutionValidationStatus.passed =>
        'chat.workflow_task_validation_status_passed'.tr(),
      ConversationExecutionValidationStatus.failed =>
        'chat.workflow_task_validation_status_failed'.tr(),
    };
  }

  static String workflowTaskEventLabel(
    ConversationExecutionTaskEventType type,
  ) {
    return switch (type) {
      ConversationExecutionTaskEventType.started =>
        'chat.workflow_task_event_started'.tr(),
      ConversationExecutionTaskEventType.validated =>
        'chat.workflow_task_event_validated'.tr(),
      ConversationExecutionTaskEventType.blocked =>
        'chat.workflow_task_event_blocked'.tr(),
      ConversationExecutionTaskEventType.unblocked =>
        'chat.workflow_task_event_unblocked'.tr(),
      ConversationExecutionTaskEventType.completed =>
        'chat.workflow_task_event_completed'.tr(),
      ConversationExecutionTaskEventType.replanned =>
        'chat.workflow_task_event_replanned'.tr(),
    };
  }

  static String workflowTaskEventSummary(
    BuildContext context,
    ConversationExecutionTaskEvent event,
  ) {
    final timestamp = DateFormat(
      'MM/dd HH:mm',
    ).format(event.createdAt.toLocal());
    final summary =
        event.normalizedSummary ??
        event.normalizedValidationSummary ??
        event.normalizedBlockedReason ??
        workflowTaskStatusLabel(event.status);
    return '$timestamp · ${workflowTaskEventLabel(event.type)} · $summary';
  }

  static String planDocumentDiffEntryLabel(
    BuildContext context,
    ConversationPlanTaskDiffEntry entry,
  ) {
    final prefix = switch (entry.type) {
      ConversationPlanTaskDiffType.added =>
        'chat.plan_document_diff_entry_added'.tr(),
      ConversationPlanTaskDiffType.removed =>
        'chat.plan_document_diff_entry_removed'.tr(),
      ConversationPlanTaskDiffType.changed =>
        'chat.plan_document_diff_entry_changed'.tr(),
    };
    final beforeTitle = entry.beforeTask?.title.trim();
    final afterTitle = entry.afterTask?.title.trim();

    if (entry.type == ConversationPlanTaskDiffType.changed &&
        beforeTitle != null &&
        afterTitle != null &&
        beforeTitle != afterTitle) {
      return '$prefix: $beforeTitle -> $afterTitle';
    }
    return '$prefix: ${entry.displayTitle}';
  }

  static Color workflowTaskStatusColor(
    BuildContext context,
    ConversationWorkflowTaskStatus status,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      ConversationWorkflowTaskStatus.pending => scheme.secondary,
      ConversationWorkflowTaskStatus.inProgress => scheme.primary,
      ConversationWorkflowTaskStatus.completed => Colors.green.shade700,
      ConversationWorkflowTaskStatus.blocked => scheme.error,
    };
  }

  static ConversationWorkflowStage? recommendedWorkflowStage(
    ConversationWorkflowStage stage,
  ) {
    return switch (stage) {
      ConversationWorkflowStage.idle => ConversationWorkflowStage.clarify,
      ConversationWorkflowStage.clarify => ConversationWorkflowStage.plan,
      ConversationWorkflowStage.plan => ConversationWorkflowStage.tasks,
      ConversationWorkflowStage.tasks => ConversationWorkflowStage.implement,
      ConversationWorkflowStage.implement => ConversationWorkflowStage.review,
      ConversationWorkflowStage.review => null,
    };
  }
}
