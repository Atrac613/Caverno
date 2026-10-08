import '../../entities/conversation_goal.dart';
import '../goal/goal_update_ack.dart';
import '../project_task/project_task_implementation_instructions.dart';

/// Requests typed task status at an implementation boundary, never from prose.
final class StructuredCodingTaskRecoveryPolicy {
  const StructuredCodingTaskRecoveryPolicy();

  bool applies({
    required ConversationGoal? goal,
    required bool implementationTurn,
  }) => goal?.projectTaskAutoReview == true && implementationTurn;

  bool shouldRequestStatus({
    required ConversationGoal? goal,
    required bool boundarySafe,
    required GoalUpdateAckOutcome? acknowledgement,
  }) =>
      goal?.isActive == true &&
      goal!.status == ConversationGoalStatus.active &&
      !goal.budgetExceeded &&
      boundarySafe &&
      (acknowledgement == null ||
          acknowledgement == GoalUpdateAckOutcome.progressLogged ||
          acknowledgement == GoalUpdateAckOutcome.completionRejected ||
          acknowledgement == GoalUpdateAckOutcome.invalidArguments);

  String get prompt => ProjectTaskImplementationInstructions.statusPrompt;
}
