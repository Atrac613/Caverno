import '../../domain/entities/message.dart';
import 'chat_state.dart';

class ActiveResponseRegistry {
  int _currentGeneration = 0;
  String? _currentConversationId;
  List<Message>? _currentMessages;
  final Map<int, String> _conversationIdsByGeneration = <int, String>{};
  final Map<int, List<Message>> _messagesByGeneration = <int, List<Message>>{};

  int get currentGeneration => _currentGeneration;

  String? get currentConversationId => _currentConversationId;

  List<Message>? get currentMessages => _currentMessages;

  bool get hasActiveResponse =>
      _currentConversationId != null || _conversationIdsByGeneration.isNotEmpty;

  int beginGeneration() {
    _currentGeneration += 1;
    return _currentGeneration;
  }

  bool isCurrentOrRegistered(int generation) {
    return generation == _currentGeneration ||
        _conversationIdsByGeneration.containsKey(generation);
  }

  bool isDetached({required String? visibleConversationId}) {
    return _currentConversationId != null &&
        visibleConversationId != _currentConversationId;
  }

  /// Conversations that currently have a running response, for surfacing the
  /// busy state in the UI. Mirrored into [ChatState] by the notifier: the
  /// registry itself is not observable, so a listener that rebuilt before the
  /// last entry was cleared would otherwise keep rendering "busy" forever.
  Set<String> get activeConversationIds =>
      _conversationIdsByGeneration.values.toSet();

  int? generationForConversation(String? targetConversationId) {
    if (targetConversationId == null) return null;
    int? matchedGeneration;
    for (final entry in _conversationIdsByGeneration.entries) {
      if (entry.value == targetConversationId &&
          (matchedGeneration == null || entry.key > matchedGeneration)) {
        matchedGeneration = entry.key;
      }
    }
    return matchedGeneration;
  }

  String? conversationIdForGeneration(int generation) {
    return _conversationIdsByGeneration[generation] ??
        (generation == _currentGeneration ? _currentConversationId : null);
  }

  List<Message>? messagesForGeneration(int generation) {
    return _messagesByGeneration[generation] ??
        (generation == _currentGeneration ? _currentMessages : null);
  }

  bool isDetachedForGeneration({
    required int generation,
    required String? visibleConversationId,
  }) {
    final targetConversationId = conversationIdForGeneration(generation);
    return targetConversationId != null &&
        visibleConversationId != targetConversationId;
  }

  void register({
    required int generation,
    required String? targetConversationId,
    required List<Message> messages,
  }) {
    if (targetConversationId == null) return;
    _conversationIdsByGeneration[generation] = targetConversationId;
    cacheMessages(generation, messages);
    if (generation == _currentGeneration) {
      _currentConversationId = targetConversationId;
      _currentMessages = List<Message>.unmodifiable(messages);
    }
  }

  void cacheMessages(int generation, List<Message> messages) {
    if (!_conversationIdsByGeneration.containsKey(generation)) {
      return;
    }
    final cached = List<Message>.unmodifiable(messages);
    _messagesByGeneration[generation] = cached;
    if (generation == _currentGeneration) {
      _currentMessages = cached;
    }
  }

  void clearGeneration(int generation) {
    _conversationIdsByGeneration.remove(generation);
    _messagesByGeneration.remove(generation);
    if (generation == _currentGeneration) {
      _currentConversationId = null;
      _currentMessages = null;
    }
  }

  void clearAll() {
    _conversationIdsByGeneration.clear();
    _messagesByGeneration.clear();
    _currentConversationId = null;
    _currentMessages = null;
  }
}

/// Whether the thread list should show [targetConversationId] as working.
///
/// Reads only the state so the answer changes observably: background threads
/// come from [ChatState.busyConversationIds], while the visible thread is also
/// busy during plan drafting, which runs without registering a response.
bool chatStateReportsConversationBusy({
  required ChatState state,
  required String targetConversationId,
  required String? visibleConversationId,
}) {
  final normalized = targetConversationId.trim();
  if (normalized.isEmpty) return false;
  if (state.busyConversationIds.contains(normalized)) return true;
  if (visibleConversationId != normalized) return false;
  return state.isLoading ||
      state.isGeneratingWorkflowProposal ||
      state.isGeneratingTaskProposal;
}
