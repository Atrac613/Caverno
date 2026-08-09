import 'package:caverno/core/types/goal_completion_policy.dart';
import 'package:caverno/features/chat/application/runtime/goal_completion_boundary_coordinator.dart';
import 'package:caverno/features/chat/application/runtime/turn_runtime.dart';
import 'package:caverno/features/chat/domain/entities/conversation_goal.dart';
import 'package:caverno/features/chat/domain/services/conversation_goal_auto_continue_policy.dart';
import 'package:caverno/features/chat/domain/services/goal_auto_continue_decision_coordinator.dart';
import 'package:caverno/features/chat/domain/services/tool_result_prompt_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const coordinator = GoalCompletionBoundaryCoordinator();

  test('ask policy requests confirmation at a no-work boundary', () async {
    var elicitations = 0;
    TurnRuntimeGoalStatusUpdate? update;

    final disposition = await coordinator.coordinate(
      completionPolicy: GoalCompletionPolicy.ask,
      plan: _plan(
        decision: GoalAutoContinueDecision.skip(
          'No remaining work.',
          noRemainingWork: true,
        ),
      ),
      assistantResponse: 'Implementation and validation are complete.',
      evidence: const ToolResultCompletionEvidence(),
      requestElicitation: () async => elicitations += 1,
      requestConfirmation: (value) async => update = value,
    );

    expect(disposition.requestedElicitation, isFalse);
    expect(elicitations, 0);
    expect(update?.status, ConversationGoalStatus.awaitingConfirmation);
    expect(update?.completionSummary, contains('Latest result:'));
    expect(update?.completionSummary, contains('No mechanical gap'));
  });

  test('tool-or-ask policy elicits once before asking the user', () async {
    var elicitations = 0;
    var confirmations = 0;

    final disposition = await coordinator.coordinate(
      completionPolicy: GoalCompletionPolicy.toolOrAsk,
      plan: _plan(
        decision: GoalAutoContinueDecision.skip(
          'No remaining work.',
          noRemainingWork: true,
        ),
        eligibility: GoalCompletionElicitationEligibility.eligible,
      ),
      assistantResponse: 'Work stopped.',
      evidence: const ToolResultCompletionEvidence(),
      requestElicitation: () async => elicitations += 1,
      requestConfirmation: (_) async => confirmations += 1,
    );

    expect(disposition.requestedElicitation, isTrue);
    expect(elicitations, 1);
    expect(confirmations, 0);
  });

  test('tool policy leaves a budget boundary under tool authority', () async {
    var elicitations = 0;
    var confirmations = 0;

    final disposition = await coordinator.coordinate(
      completionPolicy: GoalCompletionPolicy.tool,
      plan: _plan(
        decision: GoalAutoContinueDecision.skip(
          'Budget exhausted.',
          stopCause: GoalAutoContinueStopCause.goalBudget,
        ),
        shouldMarkAwaitingConfirmation: true,
      ),
      assistantResponse: 'Work stopped.',
      evidence: const ToolResultCompletionEvidence(),
      requestElicitation: () async => elicitations += 1,
      requestConfirmation: (_) async => confirmations += 1,
    );

    expect(disposition, GoalCompletionBoundaryDisposition.none);
    expect(elicitations, 0);
    expect(confirmations, 0);
  });
}

GoalAutoContinueDecisionPlan _plan({
  required GoalAutoContinueDecision decision,
  GoalCompletionElicitationEligibility eligibility =
      GoalCompletionElicitationEligibility.notApplicable,
  bool shouldMarkAwaitingConfirmation = false,
}) => (
  policyDecision: decision,
  policyInput: null,
  trackerDelta: (
    consecutiveAutoContinuationsDelta: 0,
    diagnosticRepairContinuationsDelta: 0,
    diagnosticRepairExtensionUsed: null,
    noProgressStreak: null,
    consecutiveValidationMisses: null,
    failedVerificationObserved: null,
    previousEvidence: null,
    previousDiagnosticSignature: null,
    identicalDiagnosticSignatureStreak: null,
    pendingPostRepairReplayOutcome: null,
    pendingRepairContractOutcome: null,
    repairNoMutationRetryUsed: null,
    completionElicitationMutationGeneration: null,
    markBudgetNoticePresented: false,
    removeTracker: false,
  ),
  executionSnapshot: null,
  repairContract: null,
  capabilityProfile: null,
  continuationLimits: null,
  stopNotice: null,
  elicitationEligibility: eligibility,
  shouldMarkAwaitingConfirmation: shouldMarkAwaitingConfirmation,
  effectiveTurnBudget: null,
  reason: (
    code: GoalAutoContinueCoordinationReasonCode.policySkip,
    detail: decision.reason,
  ),
);
