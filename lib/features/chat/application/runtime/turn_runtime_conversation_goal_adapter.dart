import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_goal.dart';
import 'turn_runtime.dart';

/// Minimal owner-addressable goal storage required by the runtime adapter.
abstract interface class TurnRuntimeConversationGoalStore {
  Conversation? conversationForId(String conversationId);

  Future<void> markGoalStatus({
    required String conversationId,
    required ConversationGoalStatus status,
    String? blockedReason,
  });
}

/// Adapts conversation storage to owner-bound runtime goal operations.
final class TurnRuntimeConversationGoalAdapter
    implements TurnRuntimeConversationGoalPort {
  const TurnRuntimeConversationGoalAdapter({
    required TurnRuntimeConversationGoalStore store,
  }) : _store = store;

  final TurnRuntimeConversationGoalStore _store;

  @override
  Conversation? conversationFor(ChatTurnOwner owner) {
    final conversation = _store.conversationForId(owner.conversationId);
    return conversation?.id == owner.conversationId ? conversation : null;
  }

  @override
  Future<void> markGoalStatus(TurnRuntimeGoalStatusUpdate update) async {
    if (conversationFor(update.owner) == null) {
      return;
    }
    await _store.markGoalStatus(
      conversationId: update.owner.conversationId,
      status: update.status,
      blockedReason: update.blockedReason,
    );
  }
}
