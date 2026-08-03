import '../../domain/entities/chat_turn_owner.dart';
import 'turn_runtime.dart';

/// Tracks the minimal live conversation state required by an owner lease.
final class TurnRuntimeOwnerLeaseRegistry implements TurnRuntimeOwnerLeasePort {
  bool _mounted = false;
  String? _visibleConversationId;
  String? _selectedConversationId;

  void mount({
    required String? visibleConversationId,
    required String? selectedConversationId,
  }) {
    _mounted = true;
    _visibleConversationId = visibleConversationId;
    _selectedConversationId = selectedConversationId;
  }

  void updateVisibleConversation(String? conversationId) {
    _visibleConversationId = conversationId;
  }

  void updateSelectedConversation(String? conversationId) {
    _selectedConversationId = conversationId;
  }

  void retire() {
    _mounted = false;
    _visibleConversationId = null;
    _selectedConversationId = null;
  }

  @override
  bool isCurrent(ChatTurnOwner owner) =>
      isConversationCurrent(owner.conversationId);

  bool isConversationCurrent(String conversationId) =>
      _mounted &&
      _visibleConversationId == conversationId &&
      _selectedConversationId == conversationId;
}
