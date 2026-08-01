// ChatNotifier decomposition collaborator: model-switch-handoff-registry

import '../entities/chat_turn_owner.dart';
import '../entities/conversation.dart';
import '../entities/message.dart';
import 'model_switch_handoff_brief_service.dart';

typedef ModelSwitchHandoffClock = DateTime Function();

final class ModelSwitchHandoffRegistry {
  ModelSwitchHandoffRegistry({required ModelSwitchHandoffClock clock})
    : _clock = clock;

  final ModelSwitchHandoffClock _clock;
  final Map<String, String> _pendingBriefsByConversation = {};
  final Set<ChatTurnOwner> _forcedCompactionOwners = {};

  /// Schedules a handoff only when an owning conversation is available.
  ///
  /// A model switch can happen before any conversation is selected. In that
  /// case there is no safe key for retaining a brief, so the registry leaves
  /// every existing owner entry unchanged and returns null.
  String? schedule({
    required Conversation? conversation,
    required List<Message> messages,
    required String previousModel,
    required String nextModel,
  }) {
    if (conversation == null) {
      return null;
    }
    final brief = ModelSwitchHandoffBriefService.build(
      conversation: conversation,
      messages: List<Message>.unmodifiable(messages),
      previousModel: previousModel,
      nextModel: nextModel,
    );
    if (brief == null) {
      _pendingBriefsByConversation.remove(conversation.id);
    } else {
      _pendingBriefsByConversation[conversation.id] = brief;
    }
    return brief;
  }

  bool hasPendingFor(String conversationId) =>
      _pendingBriefsByConversation.containsKey(conversationId);

  String? take(ChatTurnOwner owner) =>
      _pendingBriefsByConversation.remove(owner.conversationId);

  void clearPendingHandoff(String conversationId) =>
      _pendingBriefsByConversation.remove(conversationId);

  void clearPendingHandoffs() => _pendingBriefsByConversation.clear();

  void clearAll() {
    clearPendingHandoffs();
    clearPromptCompactions();
  }

  bool requestPromptCompaction(ChatTurnOwner owner) =>
      _forcedCompactionOwners.add(owner);

  bool discardPromptCompaction(ChatTurnOwner owner) =>
      _forcedCompactionOwners.remove(owner);

  void clearPromptCompactions() => _forcedCompactionOwners.clear();

  bool consumePromptCompaction({
    required ChatTurnOwner owner,
    required bool forceCompaction,
    required bool hasModelSwitchHandoff,
  }) {
    if (forceCompaction) return true;
    if (_forcedCompactionOwners.remove(owner)) return true;
    return hasModelSwitchHandoff;
  }

  Message? createPromptMessage(String? brief) {
    if (brief == null) return null;
    return Message(
      id: 'system_model_handoff',
      content: brief,
      role: MessageRole.system,
      timestamp: _clock(),
    );
  }
}
