import '../../domain/entities/chat_turn_owner.dart';

/// Retains hidden assistant evidence independently for each assistant turn.
final class HiddenAssistantEvidenceRegistry {
  HiddenAssistantEvidenceRegistry({
    Duration retention = const Duration(minutes: 10),
    DateTime Function()? now,
  }) : assert(retention > Duration.zero),
       _retention = retention,
       _now = now ?? DateTime.now;

  final Duration _retention;
  final DateTime Function() _now;
  final Map<ChatTurnOwner, _HiddenAssistantEvidenceState> _states = {};
  final Map<String, int> _closedGenerationWatermarks = {};

  int get length {
    _purgeExpired(_now());
    return _states.length;
  }

  bool begin(ChatTurnOwner owner) {
    _purgeExpired(_now());
    final closedThrough =
        _closedGenerationWatermarks[owner.conversationId] ?? 0;
    if (owner.interactionGeneration <= closedThrough ||
        _states.containsKey(owner)) {
      return false;
    }
    _states[owner] = _HiddenAssistantEvidenceState();
    return true;
  }

  bool record(
    ChatTurnOwner owner,
    String? response, {
    required int Function(String response) evidenceScore,
  }) {
    _purgeExpired(_now());
    final state = _states[owner];
    final candidate = response?.trim() ?? '';
    if (state == null || !state.acceptingWrites || candidate.isEmpty) {
      return false;
    }
    final existing = state.response;
    if (existing == null ||
        evidenceScore(candidate) > evidenceScore(existing) ||
        (evidenceScore(candidate) == evidenceScore(existing) &&
            candidate.length >= existing.length)) {
      state.response = candidate;
    }
    return true;
  }

  String? take(ChatTurnOwner owner) {
    _purgeExpired(_now());
    final state = _states[owner];
    final response = state?.response;
    if (state != null) state.response = null;
    return response;
  }

  bool publish(ChatTurnOwner owner) {
    _purgeExpired(_now());
    final state = _states[owner];
    _markClosed(owner);
    if (state == null) return false;
    state
      ..acceptingWrites = false
      ..expiresAt = _now().add(_retention);
    return true;
  }

  bool dispose(ChatTurnOwner owner) {
    _purgeExpired(_now());
    _markClosed(owner);
    return _states.remove(owner) != null;
  }

  void clear() {
    for (final owner in _states.keys.toList(growable: false)) {
      _markClosed(owner);
    }
    _states.clear();
  }

  void _markClosed(ChatTurnOwner owner) {
    final closedThrough =
        _closedGenerationWatermarks[owner.conversationId] ?? 0;
    if (owner.interactionGeneration > closedThrough) {
      _closedGenerationWatermarks[owner.conversationId] =
          owner.interactionGeneration;
    }
  }

  void _purgeExpired(DateTime current) => _states.removeWhere(
    (_, state) => state.expiresAt?.isAfter(current) == false,
  );
}

final class _HiddenAssistantEvidenceState {
  String? response;
  DateTime? expiresAt;
  bool acceptingWrites = true;
}
