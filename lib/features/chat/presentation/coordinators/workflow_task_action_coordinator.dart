import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_workflow.dart';
import '../providers/chat_state.dart';
import '../providers/conversations_notifier.dart';

enum WorkflowTaskMenuAction {
  markPending,
  markInProgress,
  markCompleted,
  markBlocked,
  markUnblocked,
  editBlockedReason,
  replanFromBlocker,
  edit,
  delete,
}

enum WorkflowTaskEditorAction { save, delete }

final class WorkflowTaskEditorSubmission {
  const WorkflowTaskEditorSubmission.save({required this.task})
    : action = WorkflowTaskEditorAction.save;

  const WorkflowTaskEditorSubmission.delete({required this.task})
    : action = WorkflowTaskEditorAction.delete;

  final WorkflowTaskEditorAction action;
  final ConversationWorkflowTask task;
}

enum WorkflowTaskApplyOutcome { saved, deleted, ignored }

enum WorkflowTaskMenuOutcome {
  none,
  unblocked,
  editBlockedReason,
  replanFromBlocker,
  edit,
  deleted,
}

final class WorkflowTaskActionCoordinator {
  WorkflowTaskActionCoordinator({
    required ConversationsNotifier conversationsNotifier,
    required Conversation? Function() readCurrentConversation,
    required String Function() createTaskId,
    required void Function() dismissTaskProposal,
  }) : _conversationsNotifier = conversationsNotifier,
       _readCurrentConversation = readCurrentConversation,
       _createTaskId = createTaskId,
       _dismissTaskProposal = dismissTaskProposal;

  final ConversationsNotifier _conversationsNotifier;
  final Conversation? Function() _readCurrentConversation;
  final String Function() _createTaskId;
  final void Function() _dismissTaskProposal;

  Future<void> applyTaskProposal({
    required Conversation currentConversation,
    required WorkflowTaskProposalDraft proposal,
  }) async {
    await replaceTasks(
      currentConversation: currentConversation,
      tasks: proposal.tasks,
      workflowStage: ConversationWorkflowStage.tasks,
    );
    _dismissTaskProposal();
  }

  Future<WorkflowTaskApplyOutcome> applyEditorSubmission({
    required Conversation currentConversation,
    required WorkflowTaskEditorSubmission submission,
  }) async {
    switch (submission.action) {
      case WorkflowTaskEditorAction.delete:
        if (submission.task.id.isEmpty) {
          return WorkflowTaskApplyOutcome.ignored;
        }
        await deleteTask(
          currentConversation: currentConversation,
          task: submission.task,
        );
        return WorkflowTaskApplyOutcome.deleted;
      case WorkflowTaskEditorAction.save:
        final existingTasks = currentConversation.effectiveWorkflowSpec.tasks;
        final nextTask = submission.task.id.isEmpty
            ? submission.task.copyWith(id: _createTaskId())
            : submission.task;
        final taskIndex = existingTasks.indexWhere(
          (task) => task.id == nextTask.id,
        );
        final nextTasks = [...existingTasks];
        if (taskIndex >= 0) {
          nextTasks[taskIndex] = nextTask;
        } else {
          nextTasks.add(nextTask);
        }
        await replaceTasks(
          currentConversation: currentConversation,
          tasks: nextTasks,
        );
        return WorkflowTaskApplyOutcome.saved;
    }
  }

  Future<WorkflowTaskMenuOutcome> handleMenuAction({
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
    required WorkflowTaskMenuAction action,
  }) async {
    switch (action) {
      case WorkflowTaskMenuAction.markPending:
        await setTaskStatus(
          currentConversation: currentConversation,
          task: task,
          status: ConversationWorkflowTaskStatus.pending,
          summary: 'Moved back to pending from the task menu.',
        );
      case WorkflowTaskMenuAction.markInProgress:
        await setTaskStatus(
          currentConversation: currentConversation,
          task: task,
          status: ConversationWorkflowTaskStatus.inProgress,
          summary: 'Marked in progress from the task menu.',
        );
      case WorkflowTaskMenuAction.markCompleted:
        await setTaskStatus(
          currentConversation: currentConversation,
          task: task,
          status: ConversationWorkflowTaskStatus.completed,
          summary: 'Marked complete from the task menu.',
          eventType: ConversationExecutionTaskEventType.completed,
        );
      case WorkflowTaskMenuAction.markBlocked:
        await setTaskStatus(
          currentConversation: currentConversation,
          task: task,
          status: ConversationWorkflowTaskStatus.blocked,
          summary: 'Marked blocked from the task menu.',
          blockedReason: 'This task is blocked and needs follow-up.',
          eventType: ConversationExecutionTaskEventType.blocked,
        );
      case WorkflowTaskMenuAction.markUnblocked:
        await setTaskStatus(
          currentConversation: currentConversation,
          task: task,
          status: ConversationWorkflowTaskStatus.pending,
          summary: 'Cleared the blocker and moved the task back to pending.',
          blockedReason: '',
          eventType: ConversationExecutionTaskEventType.unblocked,
        );
        return WorkflowTaskMenuOutcome.unblocked;
      case WorkflowTaskMenuAction.editBlockedReason:
        return WorkflowTaskMenuOutcome.editBlockedReason;
      case WorkflowTaskMenuAction.replanFromBlocker:
        return WorkflowTaskMenuOutcome.replanFromBlocker;
      case WorkflowTaskMenuAction.edit:
        return currentConversation.shouldPreferPlanDocument
            ? WorkflowTaskMenuOutcome.none
            : WorkflowTaskMenuOutcome.edit;
      case WorkflowTaskMenuAction.delete:
        if (currentConversation.shouldPreferPlanDocument) {
          return WorkflowTaskMenuOutcome.none;
        }
        await deleteTask(currentConversation: currentConversation, task: task);
        return WorkflowTaskMenuOutcome.deleted;
    }
    return WorkflowTaskMenuOutcome.none;
  }

  Future<void> deleteTask({
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
  }) async {
    await replaceTasks(
      currentConversation: currentConversation,
      tasks: currentConversation.effectiveWorkflowSpec.tasks
          .where((item) => item.id != task.id)
          .toList(growable: false),
    );
  }

  Future<void> replaceTasks({
    required Conversation currentConversation,
    required List<ConversationWorkflowTask> tasks,
    ConversationWorkflowStage? workflowStage,
  }) async {
    final latestConversation =
        _readCurrentConversation() ?? currentConversation;
    final nextSpec = latestConversation.effectiveWorkflowSpec.copyWith(
      tasks: tasks,
    );
    await _conversationsNotifier.updateCurrentWorkflow(
      workflowStage: workflowStage,
      workflowSpec: nextSpec.hasContent ? nextSpec : null,
      clearWorkflowSpec: !nextSpec.hasContent,
    );
  }

  Future<void> setTaskStatus({
    required Conversation currentConversation,
    required ConversationWorkflowTask task,
    required ConversationWorkflowTaskStatus status,
    String summary = '',
    DateTime? lastRunAt,
    DateTime? lastValidationAt,
    ConversationExecutionValidationStatus? validationStatus,
    String? blockedReason,
    String? lastValidationCommand,
    String? lastValidationSummary,
    ConversationExecutionTaskEventType? eventType,
  }) async {
    if (currentConversation.shouldPreferPlanDocument) {
      await _conversationsNotifier.updateCurrentExecutionTaskProgress(
        taskId: task.id,
        status: status,
        allowStatusRegression: true,
        lastRunAt: lastRunAt,
        lastValidationAt: lastValidationAt,
        validationStatus: validationStatus,
        summary: summary,
        blockedReason: status == ConversationWorkflowTaskStatus.blocked
            ? blockedReason
            : '',
        lastValidationCommand: lastValidationCommand,
        lastValidationSummary: lastValidationSummary,
        eventType: eventType,
        eventSummary: summary,
      );
      if (status == ConversationWorkflowTaskStatus.completed) {
        await _conversationsNotifier.updateCurrentWorkflow(
          workflowStage: ConversationWorkflowStage.review,
          preserveWorkflowProjection: true,
        );
      } else if (status == ConversationWorkflowTaskStatus.inProgress ||
          status == ConversationWorkflowTaskStatus.blocked) {
        await _conversationsNotifier.updateCurrentWorkflow(
          workflowStage: ConversationWorkflowStage.implement,
          preserveWorkflowProjection: true,
        );
      }
      return;
    }

    final tasks = currentConversation.effectiveWorkflowSpec.tasks
        .map(
          (item) => item.id == task.id ? item.copyWith(status: status) : item,
        )
        .toList(growable: false);
    await replaceTasks(
      currentConversation: currentConversation,
      tasks: tasks,
      workflowStage: status == ConversationWorkflowTaskStatus.completed
          ? ConversationWorkflowStage.review
          : ConversationWorkflowStage.implement,
    );
  }
}
