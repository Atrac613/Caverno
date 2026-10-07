import '../entities/conversation_goal.dart';
import '../entities/tool_call_info.dart';
import 'finalization_recovery_protocol.dart';
import 'goal_update_ack.dart';
import 'project_task_step_completion_policy.dart';
import 'project_verification_repair_policy.dart';
import 'status_recovery_verification.dart';

typedef FinalizationRecoveryToolSelection = ({
  List<Map<String, dynamic>> tools,
  Set<String> selectedNames,
  bool toolSearchEnabled,
  String? forcedCode,
});

/// Chooses the finalization protocol from turn metadata before lexical guards.
final class TurnFinalizationRecoveryPlan {
  TurnFinalizationRecoveryPlan({
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
  }) : _protocol = FinalizationRecoveryProtocol(
         goal: goal,
         implementationTurn: implementationTurn,
         terminalStatusOnly: terminalStatusOnly,
         allowVerificationRepair: allowVerificationRepair,
         stepTurn: stepTurn,
         boundarySafe: boundarySafe,
         acknowledgement: acknowledgement,
         parentTurn: parentTurn,
         response: response,
         completedResults: completedResults,
         hasSavedValidation: hasSavedValidation,
         hasGitLifecycle: hasGitLifecycle,
         skipCompletedAnswer: skipCompletedAnswer,
         allTools: allTools,
         prefixStable: prefixStable,
       );
  final FinalizationRecoveryProtocol _protocol;
  static const _verification = StatusRecoveryVerification();

  bool acceptsCalls(List<ToolCallInfo> calls) => verificationRepair
      ? ProjectVerificationRepairPolicy.accepts(calls, requestTools)
      : structuredStep
      ? const ProjectTaskStepCompletionPolicy().acceptsCalls(
          calls,
          requestTools,
        )
      : !structuredTask || _verification.acceptsStatus(calls, requestTools);

  bool get structuredTask => _protocol.structuredTask;
  bool get structuredStep => _protocol.structuredStep;
  bool get verificationRepair => _protocol.verificationRepair;
  bool get skipFinalAnswer => _protocol.skipFinalAnswer;
  bool get shouldRecover => _protocol.shouldRecover;
  set shouldRecover(bool value) => _protocol.shouldRecover = value;
  FinalizationRecoveryToolSelection get selection => _protocol.selection;
  List<Map<String, dynamic>> get requestTools => _protocol.requestTools;
  String? get forcedCode => _protocol.forcedCode;
  String? get prompt => _protocol.prompt;
}
