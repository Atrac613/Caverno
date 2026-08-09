import '../../../../core/types/goal_completion_policy.dart';
import '../../application/runtime/turn_runtime_conversation_goal_store.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_goal.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/goal_update_ack.dart';
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
  }) async {
    if (!evidenceRegistry.contains(owner) ||
        !finalizationState.contains(owner)) {
      return null;
    }
    final evidence = evidenceRegistry.reconcileForFinalization(
      owner,
      completedToolResults: completedToolResults,
      contentToolResults: contentToolResults,
      mutationGeneration: conversation?.mutationGeneration,
      verificationGeneration: conversation?.verificationGeneration,
    );
    final acknowledgement = finalizationState.takeGoalAcknowledgement(owner);
    final groundedCompletionClaimed = finalizationState.takeGoalClaim(owner);
    finalizationState.takeGoalOutcome(owner);
    final finalAck = acknowledgement?.isCompletionClaim == true
        ? const GoalUpdateAckResolver().resolve(
            input: acknowledgement!.input,
            goal: conversation?.goal,
            evidence: evidence,
            completionPolicy: acknowledgement.completionPolicy,
          )
        : null;
    final toolCompletionClaimed =
        finalAck?.completionAccepted ?? groundedCompletionClaimed;
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
    return evidence;
  }
}
