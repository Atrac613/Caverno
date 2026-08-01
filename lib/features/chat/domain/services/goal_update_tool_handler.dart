import '../entities/chat_turn_owner.dart';
import '../entities/mcp_tool_entity.dart';
import 'goal_update_ack.dart';
import 'goal_update_tool_contract.dart';
import 'tool_result_prompt_builder.dart';

export 'goal_update_tool_contract.dart';

// ChatNotifier decomposition collaborator: goal-update-tool-handler
final class GoalUpdateToolHandlerOutcome {
  const GoalUpdateToolHandlerOutcome({
    required this.identity,
    required this.toolResult,
    required this.completionEvidence,
    required this.acknowledgement,
    required this.shadowOutcome,
  });

  final GoalUpdateOperationIdentity identity;
  final McpToolResult toolResult;
  final ToolResultCompletionEvidence completionEvidence;
  final GoalUpdateCompletionAcknowledgement acknowledgement;
  final GoalUpdateAckOutcome? shadowOutcome;

  ChatTurnOwner get owner => identity.owner;
  GoalUpdateAckOutcome get ackOutcome => acknowledgement.outcome;
  bool get isCompletionClaim => acknowledgement.isCompletionClaim;
  bool get completionAccepted => acknowledgement.completionAccepted;
}

final class GoalUpdateToolHandler {
  const GoalUpdateToolHandler();

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
