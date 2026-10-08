import '../../../../core/types/goal_completion_policy.dart';
import '../../application/runtime/turn_runtime_conversation_goal_store.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_goal.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/goal/goal_update_tool_contract.dart';
import '../../domain/services/project_task_terminal_status.dart';
import '../../domain/services/tool_result_prompt_builder.dart';
import 'turn_finalization_state_registry.dart';
import 'turn_goal_completion_evidence_registry.dart';

typedef GoalTurnRecorder =
    Future<void> Function({
      required String assistantResponse,
      required int tokenUsageDelta,
      required ToolResultCompletionEvidence completionEvidence,
      required bool toolCompletionClaimed,
      required String conversationId,
    });

/// Reconciles and records one owner's goal state before terminal disposal.
final class TurnGoalCompletionFinalizer {
  TurnGoalCompletionFinalizer({
    required GoalTurnRecorder recordGoalTurn,
    required TurnRuntimeConversationGoalStore goalStore,
  }) : _recordGoalTurn = recordGoalTurn,
       _goalStore = goalStore;

  final GoalTurnRecorder _recordGoalTurn;
  final TurnRuntimeConversationGoalStore _goalStore;

  Future<ToolResultCompletionEvidence?> finalize({
    required ChatTurnOwner owner,
    required TurnGoalCompletionEvidenceRegistry evidenceRegistry,
    required TurnFinalizationStateRegistry finalizationState,
    required List<ToolResultInfo> completedToolResults,
    required List<ToolResultInfo> contentToolResults,
    required Conversation? conversation,
    required String assistantResponse,
    required int tokenUsageDelta,
    bool projectTaskImplementation = false,
    void Function(ProjectTaskTerminalStatus status)? onProjectTaskStatus,
  }) async {
    if (!evidenceRegistry.contains(owner) ||
        !finalizationState.contains(owner)) {
      return null;
    }
    var evidence = evidenceRegistry.reconcileForFinalization(
      owner,
      completedToolResults: completedToolResults,
      contentToolResults: contentToolResults,
      mutationGeneration: conversation?.mutationGeneration,
      verificationGeneration: conversation?.verificationGeneration,
    );
    final acknowledgement = finalizationState.takeGoalAcknowledgement(owner);
    final groundedCompletionClaimed = finalizationState.takeGoalClaim(owner);
    finalizationState.takeGoalOutcome(owner);
    if (projectTaskImplementation &&
        conversation?.goal?.projectTaskAutoReview == true &&
        acknowledgement?.isCompletionClaim == true) {
      evidence = freezeGoalUpdateCompletionEvidence(
        evidence,
        clearReportedRemainingWork: true,
      );
    }
    var finalAck = acknowledgement?.isCompletionClaim == true
        ? const GoalUpdateAckResolver().resolve(
            input: acknowledgement!.input,
            goal: conversation?.goal,
            evidence: evidence,
            completionPolicy: acknowledgement.completionPolicy,
            taskToolResults: [...completedToolResults, ...contentToolResults],
          )
        : null;
    if (acknowledgement?.outcome == GoalUpdateAckOutcome.completionRejected &&
        (finalAck?.completionAccepted == true ||
            finalAck?.confirmationRequired == true)) {
      // Re-evaluation may revoke acceptance, but cannot accept a rejected
      // invocation that the model was explicitly told to report again.
      finalAck = const GoalUpdateAck(
        outcome: GoalUpdateAckOutcome.completionRejected,
        modelMessage: 'Completion still requires a new update_goal call.',
        gaps: [
          'Report completion again with update_goal after successful verification.',
        ],
      );
    }
    if (projectTaskImplementation &&
        conversation?.goal?.projectTaskAutoReview == true) {
      final status = finalAck?.outcome ?? acknowledgement?.outcome;
      finalizationState.addTransform(
        owner,
        'coding_task_status_${status?.name ?? 'missing'}',
      );
    }
    final toolCompletionClaimed = projectTaskImplementation
        ? finalAck?.completionAccepted == true
        : finalAck?.completionAccepted ?? groundedCompletionClaimed;
    await _recordGoalTurn(
      assistantResponse: assistantResponse,
      tokenUsageDelta: tokenUsageDelta,
      completionEvidence: evidence,
      toolCompletionClaimed: toolCompletionClaimed,
      conversationId: owner.conversationId,
    );
    final shouldAskForCompletion = finalAck?.confirmationRequired == true;
    final pausedAtCap =
        acknowledgement?.outcome == GoalUpdateAckOutcome.pausedAtCap &&
        acknowledgement!.completionPolicy.asksAtBoundary;
    if (shouldAskForCompletion || pausedAtCap) {
      await _goalStore.markGoalStatus(
        conversationId: owner.conversationId,
        status: ConversationGoalStatus.awaitingConfirmation,
        completionSummary: shouldAskForCompletion
            ? 'The model reported completion and no mechanical gap was found. '
                  'Confirm completion or reactivate the goal.'
            : 'The goal reached its configured budget cap. Review the work and '
                  'confirm completion or reactivate it with a larger budget.',
      );
    }
    if (projectTaskImplementation &&
        conversation?.goal?.projectTaskAutoReview == true) {
      onProjectTaskStatus?.call(
        ProjectTaskTerminalStatus(
          outcome: finalAck?.outcome ?? acknowledgement?.outcome,
          gaps:
              finalAck?.gaps ??
              [
                ...const GoalUpdateAckResolver().completionGaps(evidence),
                if (acknowledgement?.input.normalizedBlockedReason
                    case final String reason)
                  reason,
              ],
        ),
      );
    }
    return evidence;
  }
}
