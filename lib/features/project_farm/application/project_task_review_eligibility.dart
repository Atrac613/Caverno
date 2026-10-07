import '../../chat/domain/entities/conversation_goal.dart';

/// Requires an enabled goal with authority and remaining execution budget.
abstract final class TaskReviewGate {
  static bool canSend(ConversationGoal? goal) {
    if (goal == null ||
        !goal.enabled ||
        goal.status == ConversationGoalStatus.blocked ||
        goal.status == ConversationGoalStatus.awaitingConfirmation ||
        goal.budgetExceeded) {
      return false;
    }
    return true;
  }

  static bool isCompleted(ConversationGoal? goal) =>
      goal?.status == ConversationGoalStatus.completed;
  static bool finished(ConversationGoal? goal, bool codeReview) =>
      codeReview || isCompleted(goal);
}
