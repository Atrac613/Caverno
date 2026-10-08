import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/services/tool_loop/reasoning_only_stop.dart';
import 'turn_finalization_state_registry.dart';

/// Keeps continuation-recovery bookkeeping out of the generic registry.
extension TurnFinalizationRecoveryAccess on TurnFinalizationStateRegistry {
  /// Most reasoning-only stops one turn may recover.
  static const maxReasoningOnlyRecoveries = 3;

  /// Records a continuation recovery for [owner] as a transform; a
  /// reasoning-only recovery also notes how many tool results the turn had.
  void recordRecovery(
    ChatTurnOwner owner,
    String recoveryCode,
    int completedToolResults,
  ) {
    addTransform(owner, 'coding_continuation_recovery_$recoveryCode');
    final state = stateFor(owner);
    if (state == null || recoveryCode != ReasoningOnlyStop.recoveryCode) {
      return;
    }
    state.reasoningOnlyRecoveries++;
    state.toolResultsAtReasoningOnlyRecovery = completedToolResults;
  }

  /// A reasoning-only stop is recovered once per turn, and again only after
  /// the turn has made tool progress since the last recovery. Session
  /// 49103ed0 recovered one, worked six more loops, stopped in its reasoning
  /// again with an edit left to make, and ended the turn describing it.
  bool mayRecoverReasoningOnly(ChatTurnOwner owner, int completedToolResults) {
    final state = stateFor(owner);
    if (state == null) return false;
    return state.reasoningOnlyRecoveries == 0 ||
        state.reasoningOnlyRecoveries < maxReasoningOnlyRecoveries &&
            completedToolResults > state.toolResultsAtReasoningOnlyRecovery;
  }
}
