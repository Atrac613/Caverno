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

    ConversationWorkflowTask? completedTask;
    for (final task in conversation.projectedExecutionTasks) {
      if (task.id == completedTaskId) {
        completedTask = task;
        break;
      }
    }
    if (completedTask == null ||
        completedTask.status != ConversationWorkflowTaskStatus.completed) {
      return null;
    }

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
