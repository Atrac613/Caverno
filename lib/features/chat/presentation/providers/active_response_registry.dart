import '../../../../core/utils/logger.dart';
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

  /// Open registrations, for the lifecycle gate: after every turn has ended
  /// this must be zero, or some thread is stranded looking busy on a stale
  /// snapshot until the app restarts.
  int get openRegistrationCount => _conversationIdsByGeneration.length;

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

  /// The open registrations, as `gen:thread(messageCount)`, newest last.
  ///
  /// A registration is what makes a thread look busy and what a thread switch
  /// shows instead of the persisted transcript, so one that outlives its turn
  /// strands the thread on a stale snapshot under a spinner that never stops —
  /// exactly what two threads did on 2026-07-26 until the app was relaunched.
  /// The store was correct throughout, which is why a restart healed it and
  /// why the session log, written per request, showed nothing at all.
  String describeOpenRegistrations() {
    final generations = _conversationIdsByGeneration.keys.toList()..sort();
    return generations
        .map((generation) {
          final thread = _conversationIdsByGeneration[generation] ?? '?';
          final count = _messagesByGeneration[generation]?.length ?? 0;
          return 'gen-$generation:${thread.substring(0, thread.length.clamp(0, 8))}'
              '($count)';
        })
        .join(' ');
  }

  void register({
    required int generation,
    required String? targetConversationId,
    required List<Message> messages,
  }) {
    if (targetConversationId == null) return;
    // One thread, one open registration: a turn registers and releases before
    // the next one on that thread starts. A second open registration means the
    // previous turn never handed the thread back, and since lookups take the
    // newest generation the older one can no longer be reached to release it.
    final stranded = generationForConversation(targetConversationId);
    if (stranded != null && stranded != generation) {
      appLog(
        '[ActiveResponse][WARN] gen-$stranded never released '
        'thread=${targetConversationId.substring(0, targetConversationId.length.clamp(0, 8))} '
        'before gen-$generation started',
      );
    }
    _conversationIdsByGeneration[generation] = targetConversationId;
    cacheMessages(generation, messages);
    if (generation == _currentGeneration) {
      _currentConversationId = targetConversationId;
      _currentMessages = List<Message>.unmodifiable(messages);
    }
    appLog(
      '[ActiveResponse] register gen-$generation '
      'thread=${targetConversationId.substring(0, targetConversationId.length.clamp(0, 8))} '
      'messages=${messages.length} open=[${describeOpenRegistrations()}]',
    );
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
    final released = _conversationIdsByGeneration.remove(generation);
    _messagesByGeneration.remove(generation);
    if (generation == _currentGeneration) {
      _currentConversationId = null;
      _currentMessages = null;
    }
    if (released != null) {
      appLog(
        '[ActiveResponse] release gen-$generation '
        'thread=${released.substring(0, released.length.clamp(0, 8))} '
        'open=[${describeOpenRegistrations()}]',
      );
    }
  }

  void clearAll() {
    if (_conversationIdsByGeneration.isNotEmpty) {
      appLog(
        '[ActiveResponse] release all '
        'open=[${describeOpenRegistrations()}]',
      );
    }
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
