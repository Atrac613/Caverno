import '../../domain/services/goal_update_tool_contract.dart';
import '../../domain/services/tool_loop_exit_reason.dart';

enum CompletedToolResultFinalAnswerRecoveryDecision {
  notEvaluated('not_evaluated'),
  skipRecovery('skip_recovery'),
  allowRecovery('allow_recovery');

  const CompletedToolResultFinalAnswerRecoveryDecision(this.logValue);

  final String logValue;
}

final class TurnFinalizationState {
  ToolLoopExitReason? exitReasonHint;
  final Set<String> transforms = <String>{};
  GoalUpdateAckOutcome? shadowGoalCompletionOutcome;
  bool toolGoalCompletionClaimed = false;
  GoalUpdateCompletionAcknowledgement? goalUpdateAcknowledgement;
  CompletedToolResultFinalAnswerRecoveryDecision
  completedToolResultFinalAnswerRecoveryDecision =
      CompletedToolResultFinalAnswerRecoveryDecision.notEvaluated;

  void recordFinalAnswerRecoveryDecision(bool shouldSkip) {
    completedToolResultFinalAnswerRecoveryDecision = shouldSkip
        ? CompletedToolResultFinalAnswerRecoveryDecision.skipRecovery
        : CompletedToolResultFinalAnswerRecoveryDecision.allowRecovery;
  }

  ToolLoopExitReason? takeHint() {
    final hint = exitReasonHint;
    exitReasonHint = null;
    return hint;
  }

  GoalUpdateAckOutcome? takeGoalOutcome() {
    final outcome = shadowGoalCompletionOutcome;
    shadowGoalCompletionOutcome = null;
    return outcome;
  }

  bool takeGoalClaim() {
    final claimed = toolGoalCompletionClaimed;
    toolGoalCompletionClaimed = false;
    return claimed;
  }

  GoalUpdateCompletionAcknowledgement? takeGoalAcknowledgement() {
    final acknowledgement = goalUpdateAcknowledgement;
    goalUpdateAcknowledgement = null;
    return acknowledgement;
  }
}
