import '../entities/conversation_goal.dart';
import '../entities/tool_call_info.dart';
import 'finalization_recovery_request.dart';
import 'goal_update_ack.dart';
import 'turn_finalization_delegation_recovery.dart';
import 'turn_finalization_recovery_decision.dart';
import 'turn_finalization_recovery_plan.dart';
import 'unresolved_verification_failure.dart';

/// Composes protocol eligibility with the selected recovery request.
final class FinalizationRecoveryProtocol {
  FinalizationRecoveryProtocol({
    required ConversationGoal? goal,
    required bool implementationTurn,
    bool terminalStatusOnly = false,
    bool allowVerificationRepair = false,
    bool stepTurn = false,
    required bool boundarySafe,
    required GoalUpdateAckOutcome? acknowledgement,
    required bool parentTurn,
    required String response,
    required List<ToolResultInfo> completedResults,
    required bool hasSavedValidation,
    required bool hasGitLifecycle,
    required bool skipCompletedAnswer,
    required List<Map<String, dynamic>> allTools,
    required bool prefixStable,
  }) {
    final decision = TurnFinalizationRecoveryDecision.resolve(
      goal: goal,
      implementationTurn: implementationTurn,
      stepTurn: stepTurn,
      boundarySafe: boundarySafe,
      acknowledgement: acknowledgement,
      parentTurn: parentTurn,
      response: response,
      completedResults: completedResults,
      hasSavedValidation: hasSavedValidation,
      hasGitLifecycle: hasGitLifecycle,
      skipCompletedAnswer: skipCompletedAnswer,
    );
    structuredTask = decision.structuredTask;
    structuredStep = decision.structuredStep;
    skipFinalAnswer = decision.skipFinalAnswer;
    shouldRecover = decision.shouldRecover;
    selection = const TurnFinalizationDelegationRecovery().selectTools(
      allTools: allTools,
      prefixStable: prefixStable,
      pendingDelegation: decision.pendingDelegation,
    );
    verificationRepair =
        shouldRecover &&
        (structuredTask || structuredStep) &&
        allowVerificationRepair &&
        const UnresolvedVerificationFailure().latest(completedResults) !=
            null &&
        !terminalStatusOnly;
    final request = FinalizationRecoveryRequest.resolve(
      structuredTask: structuredTask,
      structuredStep: structuredStep,
      verificationRepair: verificationRepair,
      allTools: allTools,
      completedResults: completedResults,
      goal: goal,
      terminalStatusOnly: terminalStatusOnly,
      selection: selection,
      stepStatus: decision.stepStatus,
    );
    requestTools = request.tools;
    if (requestTools.isEmpty) shouldRecover = false;
    forcedCode = request.code;
    prompt = request.prompt;
  }

  late final bool structuredTask;
  late final bool structuredStep;
  late final bool verificationRepair;
  late final bool skipFinalAnswer;
  late bool shouldRecover;
  late final FinalizationRecoveryToolSelection selection;
  late final List<Map<String, dynamic>> requestTools;
  late final String? forcedCode;
  late final String? prompt;
}
