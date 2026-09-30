import '../entities/conversation_goal.dart';
import 'goal_update_ack.dart';

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

  String get prompt =>
      'Before ending this project implementation turn, report its state by '
      'calling update_goal, the only tool offered in this request. '
      'Use completed as a JSON boolean. Report completed: true only after '
      'the required file changes and verification have succeeded. The harness '
      'checks the captured change and execution evidence. '
      'Use completed: false with message when work remains, or blocked_reason '
      'when a concrete blocker prevents further work. Prose does not settle '
      'the task state. Preserve completed work and reuse existing tool results. '
      'Keep the visible response in the conversation language.';
}
