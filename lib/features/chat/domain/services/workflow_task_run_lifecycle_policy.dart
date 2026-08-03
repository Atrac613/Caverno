import '../entities/conversation.dart';
import '../entities/conversation_workflow.dart';
import 'conversation_plan_execution_coordinator.dart';

final class WorkflowTaskAutoContinuationSelection {
  const WorkflowTaskAutoContinuationSelection({
    required this.completedTask,
    required this.nextTask,
  });

  final ConversationWorkflowTask completedTask;
  final ConversationWorkflowTask nextTask;
}

abstract final class WorkflowTaskRunLifecyclePolicy {
  static const maxAutoContinuations = 8;

  static WorkflowTaskAutoContinuationSelection? selectAutoContinuation({
    required Conversation conversation,
    required String completedTaskId,
    required int continuationDepth,
  }) {
    if (continuationDepth >= maxAutoContinuations) {
      return null;
    }

    final completedTaskView = conversation.executionTaskViews
        .where((view) => view.task.id == completedTaskId)
        .firstOrNull;
    if (completedTaskView == null ||
        completedTaskView.status != ConversationWorkflowTaskStatus.completed) {
      return null;
    }
    final completedTask = completedTaskView.task.copyWith(
      status: completedTaskView.status,
    );

    final nextTask = ConversationPlanExecutionCoordinator.nextTask(
      conversation,
    );
    if (nextTask == null || nextTask.id == completedTask.id) {
      return null;
    }

    return WorkflowTaskAutoContinuationSelection(
      completedTask: completedTask,
      nextTask: nextTask,
    );
  }

  static bool isTerminalStatus(ConversationWorkflowTaskStatus? status) {
    return status == ConversationWorkflowTaskStatus.completed ||
        status == ConversationWorkflowTaskStatus.blocked;
  }
}
