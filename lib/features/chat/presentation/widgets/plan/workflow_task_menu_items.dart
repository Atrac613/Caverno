import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../domain/entities/conversation_workflow.dart';
import '../../coordinators/workflow_task_action_coordinator.dart';

/// The actions offered on one workflow task.
///
/// Extracted from the chat page's task card, which was at its ratchet ceiling:
/// this is a pure function of the task's status and two permissions, so it
/// belongs outside the page library and can be asserted without pumping one.
List<PopupMenuEntry<WorkflowTaskMenuAction>> workflowTaskMenuItems({
  required ConversationWorkflowTask task,
  required bool prefersPlanDocument,
  required bool canEditTask,
}) {
  final isBlocked = task.status == ConversationWorkflowTaskStatus.blocked;
  return <PopupMenuEntry<WorkflowTaskMenuAction>>[
    for (final status in ConversationWorkflowTaskStatus.values)
      if (task.status != status)
        PopupMenuItem(
          value: _markActionFor(status),
          child: Text(_markLabelKeyFor(status).tr()),
        ),
    if (prefersPlanDocument && isBlocked) ...[
      PopupMenuItem(
        value: WorkflowTaskMenuAction.markUnblocked,
        child: Text('chat.workflow_task_mark_unblocked'.tr()),
      ),
      PopupMenuItem(
        value: WorkflowTaskMenuAction.editBlockedReason,
        child: Text('chat.workflow_task_edit_blocked_reason'.tr()),
      ),
      PopupMenuItem(
        value: WorkflowTaskMenuAction.replanFromBlocker,
        child: Text('chat.workflow_task_replan_from_blocker'.tr()),
      ),
    ],
    if (canEditTask) ...[
      PopupMenuItem(
        value: WorkflowTaskMenuAction.edit,
        child: Text('chat.workflow_task_edit'.tr()),
      ),
      PopupMenuItem(
        value: WorkflowTaskMenuAction.delete,
        child: Text('chat.workflow_task_delete'.tr()),
      ),
    ],
  ];
}

WorkflowTaskMenuAction _markActionFor(ConversationWorkflowTaskStatus status) {
  return switch (status) {
    ConversationWorkflowTaskStatus.pending =>
      WorkflowTaskMenuAction.markPending,
    ConversationWorkflowTaskStatus.inProgress =>
      WorkflowTaskMenuAction.markInProgress,
    ConversationWorkflowTaskStatus.completed =>
      WorkflowTaskMenuAction.markCompleted,
    ConversationWorkflowTaskStatus.blocked =>
      WorkflowTaskMenuAction.markBlocked,
  };
}

String _markLabelKeyFor(ConversationWorkflowTaskStatus status) {
  return switch (status) {
    ConversationWorkflowTaskStatus.pending => 'chat.workflow_task_mark_pending',
    ConversationWorkflowTaskStatus.inProgress =>
      'chat.workflow_task_mark_in_progress',
    ConversationWorkflowTaskStatus.completed =>
      'chat.workflow_task_mark_completed',
    ConversationWorkflowTaskStatus.blocked => 'chat.workflow_task_mark_blocked',
  };
}
