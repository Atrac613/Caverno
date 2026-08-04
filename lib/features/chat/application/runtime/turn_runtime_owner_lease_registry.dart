import '../../domain/entities/chat_turn_owner.dart';
import 'turn_runtime.dart';
import 'turn_runtime_goal_continuation_ports_factory.dart';

// ChatNotifier decomposition collaborator: turn-runtime-owner-lease-registry
/// Tracks the minimal live conversation state required by an owner lease.
final class TurnRuntimeOwnerLeaseRegistry
    implements TurnRuntimeOwnerLeaseBinder {
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

  /// Binds this long-lived registry to one owner for a single turn runtime.
  @override
  TurnRuntimeOwnerLeasePort leaseFor(ChatTurnOwner owner) =>
      _TurnRuntimeOwnerLease(registry: this, owner: owner);

  bool isConversationCurrent(String conversationId) =>
      _mounted &&
      _visibleConversationId == conversationId &&
      _selectedConversationId == conversationId;
}

final class _TurnRuntimeOwnerLease implements TurnRuntimeOwnerLeasePort {
  const _TurnRuntimeOwnerLease({
    required TurnRuntimeOwnerLeaseRegistry registry,
    required ChatTurnOwner owner,
  }) : _registry = registry,
       _owner = owner;

  final TurnRuntimeOwnerLeaseRegistry _registry;
  final ChatTurnOwner _owner;

  @override
  bool get isCurrent => _registry.isConversationCurrent(_owner.conversationId);
}
