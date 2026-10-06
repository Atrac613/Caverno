import '../entities/conversation_goal.dart';
import '../entities/tool_call_info.dart';
import 'goal_update_ack.dart';
import 'project_task_step_completion_policy.dart';
import 'project_verification_repair_policy.dart';
import 'status_recovery_verification.dart';
import 'structured_coding_task_recovery_policy.dart';
import 'turn_finalization_delegation_recovery.dart';
import 'turn_finalization_recovery_policy.dart';
import 'unresolved_verification_failure.dart';

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
  }) {
    const taskPolicy = StructuredCodingTaskRecoveryPolicy();
    structuredTask = taskPolicy.applies(
      goal: goal,
      implementationTurn: implementationTurn,
    );
    const stepPolicy = ProjectTaskStepCompletionPolicy();
    structuredStep = stepPolicy.applies(goal: goal, stepTurn: stepTurn);
    final stepStatus = structuredStep
        ? stepPolicy.status(
            response: response,
            results: completedResults,
            goal: goal,
          )
        : null;
    final pendingDelegation =
        !structuredTask &&
        !structuredStep &&
        const TurnFinalizationDelegationRecovery().pending(
          isParentTurn: parentTurn,
          response: response,
          completedResults: completedResults,
        );
    skipFinalAnswer = !structuredTask && !structuredStep && skipCompletedAnswer;
    shouldRecover = structuredStep
        ? stepPolicy.shouldRecover(
            status: stepStatus!,
            goal: goal,
            boundarySafe: boundarySafe,
            acknowledgement: acknowledgement,
          )
        : structuredTask
        ? taskPolicy.shouldRequestStatus(
            goal: goal,
            boundarySafe: boundarySafe,
            acknowledgement: acknowledgement,
          )
        : pendingDelegation ||
              (!skipCompletedAnswer &&
                  !const TurnFinalizationRecoveryPolicy()
                      .hasTerminalGoalSuccess(
                        completedResults,
                        hasSavedValidation: hasSavedValidation,
                        hasGitLifecycle: hasGitLifecycle,
                      ));
    selection = const TurnFinalizationDelegationRecovery().selectTools(
      allTools: allTools,
      prefixStable: prefixStable,
      pendingDelegation: pendingDelegation,
    );
    verificationRepair =
        shouldRecover &&
        (structuredTask || structuredStep) &&
        allowVerificationRepair &&
        const UnresolvedVerificationFailure().latest(completedResults) !=
            null &&
        !terminalStatusOnly;
    final status = structuredTask && !verificationRepair
        ? _verification.request(
            allTools,
            completedResults,
            goal,
            taskPolicy,
            statusOnly: terminalStatusOnly,
          )
        : null;
    requestTools = verificationRepair
        ? ProjectVerificationRepairPolicy.tools(allTools)
        : status?.tools ?? selection.tools;
    if (requestTools.isEmpty) shouldRecover = false;
    forcedCode = verificationRepair
        ? ProjectVerificationRepairPolicy.recoveryCode
        : structuredStep
        ? ProjectTaskStepCompletionPolicy.recoveryCode
        : structuredTask
        ? 'structured_coding_task_status'
        : selection.forcedCode;
    prompt = verificationRepair
        ? ProjectVerificationRepairPolicy.prompt
        : stepStatus == null
        ? status?.prompt
        : stepPolicy.prompt(stepStatus);
  }

  static const _verification = StatusRecoveryVerification();

  bool acceptsCalls(List<ToolCallInfo> calls) => verificationRepair
      ? ProjectVerificationRepairPolicy.accepts(calls, requestTools)
      : structuredStep
      ? const ProjectTaskStepCompletionPolicy().acceptsCalls(
          calls,
          requestTools,
        )
      : !structuredTask || _verification.acceptsStatus(calls, requestTools);

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
