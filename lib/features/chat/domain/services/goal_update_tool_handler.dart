import '../entities/chat_turn_owner.dart';
import '../entities/conversation_goal.dart';
import '../entities/tool_call_info.dart';
import 'goal_update_ack.dart';
import 'goal_update_tool_contract.dart';
import 'tool_result_prompt_builder.dart';

export 'goal_update_ack.dart';
export 'goal_update_tool_contract.dart';

// ChatNotifier decomposition collaborator: goal-update-tool-handler
final class GoalUpdateToolHandler {
  const GoalUpdateToolHandler();

  GoalUpdateToolHandlerOutcome handleCall({
    required ChatTurnOwner owner,
    required ToolCallInfo toolCall,
    required ConversationGoal? goal,
    required List<ToolResultInfo> toolResults,
    required ToolResultCompletionEvidence completionEvidence,
  }) {
    final request = GoalUpdateToolRequest.fromToolCall(owner, toolCall);
    return handle(
      request: request,
      ownerSnapshot: GoalUpdateOwnerSnapshot(
        identity: request.identity,
        goal: goal,
        toolResults: toolResults,
        completionEvidence: completionEvidence,
      ),
    );
  }

  GoalUpdateToolHandlerOutcome handle({
    required GoalUpdateToolRequest request,
    required GoalUpdateOwnerSnapshot ownerSnapshot,
  }) {
    if (!ownerSnapshot.identity.belongsTo(request.identity)) {
      throw StateError('Goal update owner snapshot identity mismatch.');
    }
    final callTimeEvidence = ToolResultPromptBuilder.completionEvidence(
      ownerSnapshot.toolResults,
    ).carryForwardIncompleteFrom(ownerSnapshot.completionEvidence);
    final immutableEvidence = freezeGoalUpdateCompletionEvidence(
      callTimeEvidence,
    );
    final ack = const GoalUpdateAckResolver().resolveCall(
      toolCall: request.toToolCallInfo(),
      goal: ownerSnapshot.goal,
      evidence: immutableEvidence,
    );
    final acknowledgement = GoalUpdateCompletionAcknowledgement(
      identity: request.identity,
      outcome: ack.outcome,
    );
    return GoalUpdateToolHandlerOutcome(
      identity: request.identity,
      toolResult: ack.toToolResult(request.toolName),
      completionEvidence: immutableEvidence,
      acknowledgement: acknowledgement,
      shadowOutcome: ack.isCompletionClaim ? ack.outcome : null,
    );
  }
}
