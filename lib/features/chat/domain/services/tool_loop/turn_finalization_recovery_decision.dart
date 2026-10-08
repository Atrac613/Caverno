import '../../entities/conversation_goal.dart';
import '../../entities/tool_call_info.dart';
import '../coding/structured_coding_task_recovery_policy.dart';
import '../goal/goal_update_ack.dart';
import '../project_task_step_completion_policy.dart';
import '../project_task_terminal_status.dart';
import 'turn_finalization_delegation_recovery.dart';
import 'turn_finalization_recovery_policy.dart';

typedef FinalizationRecoveryDecision = ({
  bool structuredTask,
  bool structuredStep,
  bool skipFinalAnswer,
  bool shouldRecover,
  bool pendingDelegation,
  ProjectTaskTerminalStatus? stepStatus,
});

/// Decides whether metadata requires finalization recovery before tool selection.
abstract final class TurnFinalizationRecoveryDecision {
  static FinalizationRecoveryDecision resolve({
    required ConversationGoal? goal,
    required bool implementationTurn,
    bool stepTurn = false,
    required bool boundarySafe,
    required GoalUpdateAckOutcome? acknowledgement,
    required bool parentTurn,
    required String response,
    required List<ToolResultInfo> completedResults,
    required bool hasSavedValidation,
    required bool hasGitLifecycle,
    required bool skipCompletedAnswer,
  }) {
    const taskPolicy = StructuredCodingTaskRecoveryPolicy();
    final structuredTask = taskPolicy.applies(
      goal: goal,
      implementationTurn: implementationTurn,
    );
    const stepPolicy = ProjectTaskStepCompletionPolicy();
    final structuredStep = stepPolicy.applies(goal: goal, stepTurn: stepTurn);
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
    final skipFinalAnswer =
        !structuredTask && !structuredStep && skipCompletedAnswer;
    final shouldRecover = structuredStep
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
    return (
      structuredTask: structuredTask,
      structuredStep: structuredStep,
      skipFinalAnswer: skipFinalAnswer,
      shouldRecover: shouldRecover,
      pendingDelegation: pendingDelegation,
      stepStatus: stepStatus,
    );
  }
}
