import '../../../../core/types/goal_completion_policy.dart';
import '../../domain/entities/conversation_goal.dart';
import '../../domain/services/conversation_goal_auto_continue_policy.dart';
import '../../domain/services/goal_auto_continue_decision_coordinator.dart';
import '../../domain/services/goal_update_ack.dart';
import '../../domain/services/tool_result_prompt_builder.dart';
import 'turn_runtime.dart';

export '../../domain/services/goal_update_tool_handler.dart';

enum GoalCompletionBoundaryDisposition {
  none,
  elicitationRequested,
  confirmationRequested,
}

extension GoalCompletionBoundaryDispositionBehavior
    on GoalCompletionBoundaryDisposition {
  bool get requestedElicitation =>
      this == GoalCompletionBoundaryDisposition.elicitationRequested;
}

typedef GoalCompletionElicitationRequest = Future<void> Function();
typedef GoalCompletionConfirmationRequest =
    Future<void> Function(TurnRuntimeGoalStatusUpdate update);

/// Resolves model elicitation and user confirmation at one stopped goal edge.
final class GoalCompletionBoundaryCoordinator {
  const GoalCompletionBoundaryCoordinator();

  Future<GoalCompletionBoundaryDisposition> coordinate({
    required GoalCompletionPolicy completionPolicy,
    required GoalAutoContinueDecisionPlan plan,
    required String assistantResponse,
    required ToolResultCompletionEvidence evidence,
    required GoalCompletionElicitationRequest requestElicitation,
    required GoalCompletionConfirmationRequest requestConfirmation,
  }) async {
    final decision = plan.policyDecision;
    final stoppedAtBudget =
        decision.stopCause == GoalAutoContinueStopCause.turnBudget ||
        decision.stopCause == GoalAutoContinueStopCause.goalBudget;
    if (completionPolicy.shouldAskImmediatelyAtBoundary(
      budgetExhausted: stoppedAtBudget,
      noRemainingWork: decision.noRemainingWork,
    )) {
      await _requestConfirmation(
        requestConfirmation,
        assistantResponse,
        evidence,
        stoppedAtBudget,
      );
      return GoalCompletionBoundaryDisposition.confirmationRequested;
    }
    if (completionPolicy.allowsCompletionElicitation &&
        plan.elicitationEligibility ==
            GoalCompletionElicitationEligibility.eligible) {
      await requestElicitation();
      return GoalCompletionBoundaryDisposition.elicitationRequested;
    }
    if (completionPolicy.allowsCompletionElicitation &&
        plan.shouldMarkAwaitingConfirmation) {
      await _requestConfirmation(
        requestConfirmation,
        assistantResponse,
        evidence,
        false,
      );
      return GoalCompletionBoundaryDisposition.confirmationRequested;
    }
    return GoalCompletionBoundaryDisposition.none;
  }

  Future<void> _requestConfirmation(
    GoalCompletionConfirmationRequest request,
    String assistantResponse,
    ToolResultCompletionEvidence evidence,
    bool stoppedAtBudget,
  ) => request(
    TurnRuntimeGoalStatusUpdate(
      status: ConversationGoalStatus.awaitingConfirmation,
      completionSummary: const GoalUpdateAckResolver().buildConfirmationSummary(
        assistantResponse: assistantResponse,
        evidence: evidence,
        stoppedAtBudget: stoppedAtBudget,
      ),
    ),
  );
}
