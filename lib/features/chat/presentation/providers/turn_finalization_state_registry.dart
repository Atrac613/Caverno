import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/services/goal_update_ack.dart';
import '../../domain/services/tool_loop_exit_reason.dart';

/// Owns finalization and goal-claim state for explicitly registered turns.
///
/// Mutations never create state. Call [begin] when the runtime turn starts and
/// [dispose] when it reaches a terminal state. Disposed owners reject late
/// writes so an asynchronous callback cannot resurrect completed-turn state.
final class TurnFinalizationStateRegistry {
  final Map<ChatTurnOwner, _TurnFinalizationState> _states =
      <ChatTurnOwner, _TurnFinalizationState>{};
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
    _states[owner] = _TurnFinalizationState();
    return true;
  }

  bool reset(ChatTurnOwner owner) {
    if (!_states.containsKey(owner)) return false;
    _states[owner] = _TurnFinalizationState();
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

  ToolLoopExitReason? takeHint(ChatTurnOwner owner) {
    final state = _states[owner];
    final hint = state?.exitReasonHint;
    if (state != null) state.exitReasonHint = null;
    return hint;
  }

  bool addTransform(ChatTurnOwner owner, String transform) {
    final state = _states[owner];
    return state != null && state.transforms.add(transform);
  }

  List<String> transforms(ChatTurnOwner owner) =>
      List<String>.unmodifiable(_states[owner]?.transforms ?? const <String>{});

  bool setGoalOutcome(ChatTurnOwner owner, GoalUpdateAckOutcome outcome) {
    final state = _states[owner];
    if (state == null) return false;
    state.shadowGoalCompletionOutcome = outcome;
    return true;
  }

  GoalUpdateAckOutcome? takeGoalOutcome(ChatTurnOwner owner) {
    final state = _states[owner];
    final outcome = state?.shadowGoalCompletionOutcome;
    if (state != null) state.shadowGoalCompletionOutcome = null;
    return outcome;
  }

  bool markGoalClaimed(ChatTurnOwner owner) {
    final state = _states[owner];
    if (state == null) return false;
    state.toolGoalCompletionClaimed = true;
    return true;
  }

  bool takeGoalClaim(ChatTurnOwner owner) {
    final state = _states[owner];
    final claimed = state?.toolGoalCompletionClaimed ?? false;
    if (state != null) state.toolGoalCompletionClaimed = false;
    return claimed;
  }

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

final class _TurnFinalizationState {
  ToolLoopExitReason? exitReasonHint;
  final Set<String> transforms = <String>{};
  GoalUpdateAckOutcome? shadowGoalCompletionOutcome;
  bool toolGoalCompletionClaimed = false;
}
