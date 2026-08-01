import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/conversation_participant.dart';
import '../../domain/services/participant_turn_coordinator.dart';

/// Immutable continuation data retained while one participant turn is paused.
final class ParticipantTurnPauseSnapshot {
  ParticipantTurnPauseSnapshot({
    required this.cursor,
    required List<ConversationParticipant> participants,
    required this.config,
    this.preferredParticipantId,
    this.lastSpeakerParticipantId,
  }) : participants = List<ConversationParticipant>.unmodifiable(participants);

  final ParticipantTurnCursor cursor;
  final List<ConversationParticipant> participants;
  final ParticipantTurnConfig config;
  final String? preferredParticipantId;
  final String? lastSpeakerParticipantId;
}

/// Owns stop and pause control state for explicitly registered turns.
///
/// A paused owner may be claimed once for resumption. [clear] releases that
/// claim after a failed resume attempt, while [dispose] permanently retires the
/// owner so late callbacks cannot recreate its state.
final class ParticipantTurnControlRegistry {
  final Map<ChatTurnOwner, _ParticipantTurnControlState> _states =
      <ChatTurnOwner, _ParticipantTurnControlState>{};
  final Map<String, int> _disposedGenerationWatermarks = <String, int>{};

  int get length => _states.length;
  bool get isEmpty => _states.isEmpty;
  Set<ChatTurnOwner> get owners =>
      Set<ChatTurnOwner>.unmodifiable(_states.keys);

  bool contains(ChatTurnOwner owner) => _states.containsKey(owner);

  bool begin(ChatTurnOwner owner) {
    final disposedThrough =
        _disposedGenerationWatermarks[owner.conversationId] ?? 0;
    if (owner.interactionGeneration <= disposedThrough ||
        _states.containsKey(owner)) {
      return false;
    }
    _states[owner] = _ParticipantTurnControlState();
    return true;
  }

  bool requestStop(ChatTurnOwner owner) {
    final state = _states[owner];
    if (state == null || state.pause != null) return false;
    state.stopRequested = true;
    return true;
  }

  bool stopRequested(ChatTurnOwner owner) =>
      _states[owner]?.stopRequested ?? false;

  bool pause(ChatTurnOwner owner, ParticipantTurnPauseSnapshot snapshot) {
    final state = _states[owner];
    if (state == null) return false;
    state
      ..stopRequested = false
      ..pause = snapshot
      ..resumeClaimed = false;
    return true;
  }

  bool isPaused(ChatTurnOwner owner) => _states[owner]?.pause != null;

  ChatTurnOwner? pausedOwnerForConversation(String conversationId) {
    ChatTurnOwner? match;
    for (final entry in _states.entries) {
      if (entry.key.conversationId != conversationId ||
          entry.value.pause == null) {
        continue;
      }
      if (match == null ||
          entry.key.interactionGeneration > match.interactionGeneration) {
        match = entry.key;
      }
    }
    return match;
  }

  ParticipantTurnPauseSnapshot? resume(ChatTurnOwner owner) {
    final state = _states[owner];
    if (state == null || state.pause == null || state.resumeClaimed) {
      return null;
    }
    state.resumeClaimed = true;
    return state.pause;
  }

  ParticipantTurnCursor? consumeCursor(ChatTurnOwner owner) {
    final state = _states[owner];
    final pause = state?.pause;
    if (state == null || pause == null || !state.resumeClaimed) return null;
    state.pause = null;
    return pause.cursor;
  }

  bool clear(ChatTurnOwner owner) {
    final state = _states[owner];
    if (state == null) return false;
    state
      ..stopRequested = false
      ..resumeClaimed = false;
    return true;
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
}

final class _ParticipantTurnControlState {
  bool stopRequested = false;
  ParticipantTurnPauseSnapshot? pause;
  bool resumeClaimed = false;
}
