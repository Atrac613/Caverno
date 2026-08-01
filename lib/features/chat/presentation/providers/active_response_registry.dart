import '../../../../core/types/assistant_mode.dart';
import '../../../../core/utils/logger.dart';
import '../../data/datasources/llm_session_log_store.dart';
import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/message.dart';
import 'chat_state.dart';
import 'turn_owner_snapshot_registry.dart';

class ActiveResponseRegistry {
  ActiveResponseRegistry({TurnOwnerSnapshotRegistry? ownerSnapshots})
    : _ownerSnapshots = ownerSnapshots ?? TurnOwnerSnapshotRegistry();

  int _currentGeneration = 0;
  String? _currentConversationId;
  List<Message>? _currentMessages;
  final Map<int, String> _conversationIdsByGeneration = <int, String>{};
  final Map<int, List<Message>> _messagesByGeneration = <int, List<Message>>{};
  final Map<int, LlmSessionLogContext> _sessionLogContextsByGeneration =
      <int, LlmSessionLogContext>{};
  final TurnOwnerSnapshotRegistry _ownerSnapshots;
  int get currentGeneration => _currentGeneration;
  String? get currentConversationId => _currentConversationId;
  List<Message>? get currentMessages => _currentMessages;
  bool get hasActiveResponse =>
      _currentConversationId != null || _conversationIdsByGeneration.isNotEmpty;
  int beginGeneration() {
    _currentGeneration += 1;
    return _currentGeneration;
  }

  bool isCurrentOrRegistered(int generation) =>
      generation == _currentGeneration ||
      _conversationIdsByGeneration.containsKey(generation);
  bool isDetached({required String? visibleConversationId}) {
    return _currentConversationId != null &&
        visibleConversationId != _currentConversationId;
  }

  Set<String> get activeConversationIds =>
      _conversationIdsByGeneration.values.toSet();

  /// Turn registrations that must return to zero after all turns end.
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

  String? conversationIdForGeneration(int generation) =>
      _conversationIdsByGeneration[generation] ??
      (generation == _currentGeneration ? _currentConversationId : null);

  List<Message>? messagesForGeneration(int generation) =>
      _messagesByGeneration[generation] ??
      (generation == _currentGeneration ? _currentMessages : null);

  ChatTurnOwner? ownerForGeneration(int generation) {
    final ownerConversationId = _conversationIdsByGeneration[generation];
    if (ownerConversationId == null) return null;
    return ChatTurnOwner(
      conversationId: ownerConversationId,
      interactionGeneration: generation,
    );
  }

  bool containsOwner(ChatTurnOwner owner) {
    return _conversationIdsByGeneration[owner.interactionGeneration] ==
        owner.conversationId;
  }

  bool isCurrentOwner(ChatTurnOwner owner) =>
      containsOwner(owner) &&
      generationForConversation(owner.conversationId) ==
          owner.interactionGeneration;

  ChatTurnOwner registerOwnerForTest(String conversationId) {
    final generation = beginGeneration();
    register(
      generation: generation,
      targetConversationId: conversationId,
      messages: const <Message>[],
    );
    return ownerForGeneration(generation)!;
  }

  List<Message>? messagesForOwner(ChatTurnOwner owner) {
    if (!containsOwner(owner)) return null;
    return messagesForGeneration(owner.interactionGeneration);
  }

  TurnOwnerSnapshot? snapshotForOwner(ChatTurnOwner owner) {
    if (!containsOwner(owner)) return null;
    return _ownerSnapshots.snapshotFor(owner);
  }

  TurnOwnerSnapshot? snapshotForGeneration(int generation) {
    final owner = ownerForGeneration(generation);
    return owner == null ? null : snapshotForOwner(owner);
  }

  LlmSessionLogContext? sessionLogContextForGeneration(int generation) =>
      _sessionLogContextsByGeneration[generation];

  bool isDetachedForGeneration({
    required int generation,
    required String? visibleConversationId,
  }) {
    final targetConversationId = conversationIdForGeneration(generation);
    return targetConversationId != null &&
        visibleConversationId != targetConversationId;
  }

  /// Lists open registrations as `gen:thread(messageCount)`, newest last.
  /// Lingering registrations strand a thread on stale busy state.
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
    TurnOwnerSnapshot Function(ChatTurnOwner owner, List<Message> messages)?
    snapshotBuilder,
  }) {
    if (targetConversationId == null) return;
    final conversationId = ChatTurnOwner(
      conversationId: targetConversationId,
      interactionGeneration: generation,
    ).conversationId;
    // A second registration means the previous turn never handed the thread
    // back; newest-generation lookup would otherwise strand the older one.
    final stranded = generationForConversation(conversationId);
    if (stranded != null && stranded != generation) {
      appLog(
        '[ActiveResponse][WARN] gen-$stranded never released '
        'thread=${conversationId.substring(0, conversationId.length.clamp(0, 8))} '
        'before gen-$generation started',
      );
    }
    _conversationIdsByGeneration[generation] = conversationId;
    cacheMessages(generation, messages);
    if (generation == _currentGeneration) {
      _currentConversationId = conversationId;
      _currentMessages = List<Message>.unmodifiable(messages);
    }
    appLog(
      '[ActiveResponse] register gen-$generation '
      'thread=${conversationId.substring(0, conversationId.length.clamp(0, 8))} '
      'messages=${messages.length} open=[${describeOpenRegistrations()}]',
    );
    final owner = ownerForGeneration(generation);
    if (owner == null || snapshotBuilder == null) return;
    final snapshot = snapshotBuilder(owner, messagesForOwner(owner)!);
    if (snapshot.owner != owner || !containsOwner(owner)) {
      clearGeneration(generation);
      return;
    }
    _ownerSnapshots.capture(snapshot);
  }

  void registerWithSnapshot({
    required int generation,
    required String? targetConversationId,
    required List<Message> messages,
    required Message? turnUserMessage,
    required String? projectRoot,
    required LlmSessionLogContext sessionLogContext,
    required Conversation? conversation,
    String? ownerRepositoryPath,
    String? ownerWorktreePath,
    Message? hiddenPrompt,
    bool persistHiddenPromptAssistantResponse = false,
    String? temporalReferenceContext,
    required AssistantMode? assistantModeOverride,
    required AssistantMode configuredAssistantMode,
  }) {
    register(
      generation: generation,
      targetConversationId: targetConversationId,
      messages: messages,
      snapshotBuilder: (owner, ownerMessages) => TurnOwnerSnapshot.capture(
        owner: owner,
        messages: ownerMessages,
        turnUserMessage: turnUserMessage,
        projectRoot: conversation?.id == owner.conversationId
            ? projectRoot
            : null,
        sessionLogContext: sessionLogContext,
        conversation: conversation?.id == owner.conversationId
            ? conversation
            : null,
        assistantModeOverride: assistantModeOverride,
        configuredAssistantMode: configuredAssistantMode,
        savedTask: TurnOwnerSnapshot.savedTaskFor(
          conversation?.id == owner.conversationId ? conversation : null,
        ),
        allowedToolNames: null,
        ownerRepositoryPath: conversation?.id == owner.conversationId
            ? ownerRepositoryPath
            : null,
        ownerWorktreePath: conversation?.id == owner.conversationId
            ? ownerWorktreePath
            : null,
        hiddenPrompt: hiddenPrompt,
        persistHiddenPromptAssistantResponse:
            persistHiddenPromptAssistantResponse,
        temporalReferenceContext: temporalReferenceContext,
      ),
    );
    final owner = ownerForGeneration(generation);
    if (owner != null && snapshotForOwner(owner) != null) {
      _sessionLogContextsByGeneration[generation] = sessionLogContext;
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
    final owner = ownerForGeneration(generation);
    if (owner != null) {
      _ownerSnapshots.updateMessages(owner, cached);
    }
  }

  bool cacheMessagesForOwner(ChatTurnOwner owner, List<Message> messages) {
    if (!containsOwner(owner)) return false;
    cacheMessages(owner.interactionGeneration, messages);
    return true;
  }

  bool updateAllowedToolNamesForOwner(
    ChatTurnOwner owner,
    Set<String>? allowedToolNames,
  ) {
    return containsOwner(owner) &&
        _ownerSnapshots.updateAllowedToolNames(owner, allowedToolNames);
  }

  bool setTools(int generation, Set<String>? allowedToolNames) {
    final owner = ownerForGeneration(generation);
    return owner != null &&
        updateAllowedToolNamesForOwner(owner, allowedToolNames);
  }

  bool denyTools(int generation) => setTools(generation, const <String>{});

  void clearGeneration(int generation) {
    final owner = ownerForGeneration(generation);
    if (owner != null) _ownerSnapshots.dispose(owner);
    _sessionLogContextsByGeneration.remove(generation);
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

  bool clearOwner(ChatTurnOwner owner) {
    if (!containsOwner(owner)) return false;
    clearGeneration(owner.interactionGeneration);
    return true;
  }

  void clearAll() {
    _ownerSnapshots.clear();
    _sessionLogContextsByGeneration.clear();
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
