import '../../../../core/types/goal_completion_policy.dart';
import '../../application/runtime/turn_runtime_conversation_goal_adapter.dart';
import '../../data/datasources/goal_update_tool_runtime_adapter.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/conversation_goal.dart';
import '../../domain/entities/mcp_tool_entity.dart';
import '../../domain/entities/tool_call_info.dart';
import '../../domain/services/goal_update_tool_contract.dart';
import '../../domain/services/tool_result_prompt_builder.dart';
import 'turn_finalization_state_registry.dart';

/// Bridges one exact notifier-owned turn into the owner-safe goal tool adapter.
final class GoalUpdateNotifierRuntimeCoordinator {
  const GoalUpdateNotifierRuntimeCoordinator({
    required this.finalizationState,
    required this.goalStore,
  });

  final TurnFinalizationStateRegistry finalizationState;
  final TurnRuntimeConversationGoalStore goalStore;

  Future<McpToolResult> handle({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
    required ConversationGoal? goal,
    required List<ToolResultInfo> toolResults,
    required ToolResultCompletionEvidence completionEvidence,
    required GoalCompletionPolicy completionPolicy,
    required bool Function() isOwnerCurrent,
  }) async {
    final request = GoalUpdateToolRequest.fromToolCall(owner, toolCall);
    final completion = GoalUpdateToolRuntimeAdapter(
      runtimePort: CallbackGoalUpdateRuntimePort(
        isCurrent: (identity) =>
            identity.owner == owner &&
            isOwnerCurrent() &&
            finalizationState.contains(owner),
        captureSnapshot: (identity) {
          if (identity.owner != owner || !finalizationState.contains(owner)) {
            return null;
          }
          return GoalUpdateOwnerSnapshot(
            identity: identity,
            goal: goal,
            toolResults: toolResults,
            completionEvidence: completionEvidence,
            completionPolicy: completionPolicy,
          );
        },
        persistAcknowledgement: (acknowledgement) {
          final recorded = finalizationState.recordGoalAcknowledgement(
            owner,
            acknowledgement,
          );
          return recorded
              ? GoalUpdatePersistenceReceipt.acknowledged(
                  identity: acknowledgement.identity,
                )
              : GoalUpdatePersistenceReceipt.ownerRetired(
                  identity: acknowledgement.identity,
                );
        },
      ),
    ).handle(request);
    final acknowledgement = completion.outcome?.acknowledgement;
    if (acknowledgement?.outcome == GoalUpdateAckOutcome.blockerLogged) {
      await goalStore.markGoalStatus(
        conversationId: owner.conversationId,
        status: ConversationGoalStatus.blocked,
        blockedReason: acknowledgement!.input.normalizedBlockedReason,
      );
    }
    return completion.result;
  }
}
