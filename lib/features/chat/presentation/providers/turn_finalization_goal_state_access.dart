import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/services/goal_update_tool_contract.dart';
import 'turn_finalization_state_registry.dart';

/// Keeps goal-specific turn-finalization state out of the generic registry.
extension TurnFinalizationGoalStateAccess on TurnFinalizationStateRegistry {
  bool setGoalOutcome(ChatTurnOwner owner, GoalUpdateAckOutcome outcome) {
    final state = stateFor(owner);
    if (state == null) return false;
    state.shadowGoalCompletionOutcome = outcome;
    return true;
  }

  GoalUpdateAckOutcome? takeGoalOutcome(ChatTurnOwner owner) =>
      stateFor(owner)?.takeGoalOutcome();

  bool markGoalClaimed(ChatTurnOwner owner) {
    final state = stateFor(owner);
    if (state == null) return false;
    state.toolGoalCompletionClaimed = true;
    return true;
  }

  bool takeGoalClaim(ChatTurnOwner owner) =>
      stateFor(owner)?.takeGoalClaim() ?? false;

  bool recordGoalAcknowledgement(
    ChatTurnOwner owner,
    GoalUpdateCompletionAcknowledgement acknowledgement,
  ) {
    final state = stateFor(owner);
    if (state == null || acknowledgement.identity.owner != owner) return false;
    state.goalUpdateAcknowledgement = acknowledgement;
    state.shadowGoalCompletionOutcome = acknowledgement.isCompletionClaim
        ? acknowledgement.outcome
        : null;
    state.toolGoalCompletionClaimed = acknowledgement.completionAccepted;
    return true;
  }

  GoalUpdateCompletionAcknowledgement? takeGoalAcknowledgement(
    ChatTurnOwner owner,
  ) => stateFor(owner)?.takeGoalAcknowledgement();
}
