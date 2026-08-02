import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/services/goal_update_ack.dart';
import '../../domain/services/tool_loop_exit_reason.dart';
import 'turn_finalization_state.dart';

/// Owns explicitly registered turn-finalization state without late resurrection.
final class TurnFinalizationStateRegistry {
  final Map<ChatTurnOwner, TurnFinalizationState> _states =
      <ChatTurnOwner, TurnFinalizationState>{};
  final Map<String, int> _disposedGenerationWatermarks = <String, int>{};

  int get length => _states.length;
  bool get isEmpty => _states.isEmpty;

  bool contains(ChatTurnOwner owner) => _states.containsKey(owner);

  bool begin(ChatTurnOwner owner) {
    final disposedThrough =
        _disposedGenerationWatermarks[owner.conversationId] ?? 0;
    if (owner.interactionGeneration <= disposedThrough ||
        _states.containsKey(owner)) {
      return false;
    }
    _states[owner] = TurnFinalizationState();
    return true;
  }

  bool reset(ChatTurnOwner owner) {
    if (!_states.containsKey(owner)) return false;
    _states[owner] = TurnFinalizationState();
    return true;
  }

  bool setHint(ChatTurnOwner owner, ToolLoopExitReason hint) {
    final state = _states[owner];
    if (state == null) return false;
    state.exitReasonHint = hint;
    return true;
  }

  bool setHintIfAbsent(ChatTurnOwner owner, ToolLoopExitReason hint) {
    final state = _states[owner];
    if (state == null || state.exitReasonHint != null) return false;
    state.exitReasonHint = hint;
    return true;
  }

  ToolLoopExitReason? takeHint(ChatTurnOwner owner) =>
      _states[owner]?.takeHint();

  bool addTransform(ChatTurnOwner owner, String transform) {
    final state = _states[owner];
    return state != null && state.transforms.add(transform);
  }

  List<String> transforms(ChatTurnOwner owner) =>
      List<String>.unmodifiable(_states[owner]?.transforms ?? const <String>{});

  bool recordFinalAnswerRecoveryDecision(
    ChatTurnOwner owner, {
    required bool shouldSkip,
  }) {
    final state = _states[owner];
    if (state == null) return false;
    state.recordFinalAnswerRecoveryDecision(shouldSkip);
    return true;
  }

  String finalAnswerRecoveryDecisionLogValue(ChatTurnOwner? owner) =>
      (_states[owner]?.completedToolResultFinalAnswerRecoveryDecision ??
              CompletedToolResultFinalAnswerRecoveryDecision.notEvaluated)
          .logValue;

  bool setGoalOutcome(ChatTurnOwner owner, GoalUpdateAckOutcome outcome) {
    final state = _states[owner];
    if (state == null) return false;
    state.shadowGoalCompletionOutcome = outcome;
    return true;
  }

  GoalUpdateAckOutcome? takeGoalOutcome(ChatTurnOwner owner) =>
      _states[owner]?.takeGoalOutcome();

  bool markGoalClaimed(ChatTurnOwner owner) {
    final state = _states[owner];
    if (state == null) return false;
    state.toolGoalCompletionClaimed = true;
    return true;
  }

  bool takeGoalClaim(ChatTurnOwner owner) =>
      _states[owner]?.takeGoalClaim() ?? false;

  bool dispose(ChatTurnOwner owner) {
    final removed = _states.remove(owner) != null;
    final disposedThrough =
        _disposedGenerationWatermarks[owner.conversationId] ?? 0;
    if (owner.interactionGeneration > disposedThrough) {
      _disposedGenerationWatermarks[owner.conversationId] =
          owner.interactionGeneration;
    }
    return removed;
  }

  void clear() {
    for (final owner in _states.keys.toList(growable: false)) {
      dispose(owner);
    }
  }
}
