import '../../domain/entities/chat_turn_owner.dart';
import 'chat_state.dart';

/// One message the user typed while a turn was already running.
///
/// The original [QueuedChatMessage] is retained rather than just its text
/// because a steer that never reaches the model is handed back to the queue,
/// and that hand-back has to be lossless.
final class TurnSteeringEntry {
  TurnSteeringEntry({required this.message, required this.receivedAt});

  final QueuedChatMessage message;
  final DateTime receivedAt;

  String get id => message.id;
  String get content => message.content;
}

/// Mid-turn user interruptions, kept per turn owner.
///
/// Owner-keyed rather than conversation-keyed for the same reason tool results
/// are: a message aimed at one turn must never surface inside a later turn of
/// the same thread.
final class TurnSteeringRegistry {
  final Map<ChatTurnOwner, _TurnSteeringState> _states =
      <ChatTurnOwner, _TurnSteeringState>{};

  bool get isEmpty => _states.isEmpty;
  int get length => _states.length;

  bool contains(ChatTurnOwner owner) => _states.containsKey(owner);

  void add(ChatTurnOwner owner, TurnSteeringEntry entry) {
    _states.putIfAbsent(owner, _TurnSteeringState.new).pending.add(entry);
  }

  /// Steers that arrived since the last claim, oldest first.
  ///
  /// Claiming marks them as carried: the caller is committing them to the
  /// turn's history, so the turn no longer owes them back to the queue.
  List<TurnSteeringEntry> claimPending(ChatTurnOwner owner) {
    final state = _states[owner];
    if (state == null || state.pending.isEmpty) {
      return const <TurnSteeringEntry>[];
    }
    final claimed = List<TurnSteeringEntry>.unmodifiable(state.pending);
    state
      ..pending.clear()
      ..carriedCount += claimed.length;
    return claimed;
  }

  /// Steers still waiting for a request to carry them, oldest first.
  List<TurnSteeringEntry> pending(ChatTurnOwner owner) =>
      List<TurnSteeringEntry>.unmodifiable(
        _states[owner]?.pending ?? const <TurnSteeringEntry>[],
      );

  int pendingCount(ChatTurnOwner owner) => _states[owner]?.pending.length ?? 0;

  /// Whether a request of this turn has already carried a steer.
  ///
  /// Drives the prompt directive, which has to stay in place for the rest of
  /// the turn rather than only for the request that first carried the message.
  bool hasCarried(ChatTurnOwner owner) => carriedCount(owner) > 0;

  int carriedCount(ChatTurnOwner owner) => _states[owner]?.carriedCount ?? 0;

  /// Drops [id] from [owner] before any request carried it.
  ///
  /// Returns whether anything was removed. A carried steer is already part of
  /// the transcript and cannot be withdrawn here.
  bool removePending(ChatTurnOwner owner, String id) {
    final state = _states[owner];
    if (state == null) return false;
    final before = state.pending.length;
    state.pending.removeWhere((entry) => entry.id == id);
    return state.pending.length != before;
  }

  /// Drops [id] from whichever owner holds it, for callers that only know the
  /// message. Returns the owner it was removed from, or null.
  ChatTurnOwner? removePendingAnywhere(String id) {
    for (final entry in _states.entries) {
      if (entry.value.pending.any((pending) => pending.id == id)) {
        entry.value.pending.removeWhere((pending) => pending.id == id);
        return entry.key;
      }
    }
    return null;
  }

  /// Every pending steer across all owners, oldest first per owner.
  List<TurnSteeringEntry> pendingForConversation(String conversationId) {
    final result = <TurnSteeringEntry>[];
    for (final entry in _states.entries) {
      if (entry.key.conversationId != conversationId) continue;
      result.addAll(entry.value.pending);
    }
    result.sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
    return List<TurnSteeringEntry>.unmodifiable(result);
  }

  /// Retires [owner] and returns the steers no request ever carried.
  List<TurnSteeringEntry> dispose(ChatTurnOwner owner) {
    final state = _states.remove(owner);
    if (state == null) return const <TurnSteeringEntry>[];
    return List<TurnSteeringEntry>.unmodifiable(state.pending);
  }

  void clear() => _states.clear();
}

final class _TurnSteeringState {
  final List<TurnSteeringEntry> pending = <TurnSteeringEntry>[];
  int carriedCount = 0;
}
