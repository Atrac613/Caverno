import '../../domain/entities/chat_turn_owner.dart';
import '../../domain/entities/conversation.dart';
import 'turn_runtime.dart';
import 'turn_runtime_conversation_goal_store.dart';

export 'turn_runtime_conversation_goal_store.dart';

// ChatNotifier decomposition collaborator: turn-runtime-conversation-goal-adapter
/// Adapts conversation storage to owner-bound runtime goal operations.
final class TurnRuntimeConversationGoalAdapter
    implements TurnRuntimeConversationGoalPort {
  const TurnRuntimeConversationGoalAdapter({
    required TurnRuntimeConversationGoalStore store,
    required ChatTurnOwner owner,
  }) : _store = store,
       _owner = owner;

  final TurnRuntimeConversationGoalStore _store;
  final ChatTurnOwner _owner;

  @override
  Conversation? get conversation {
    final conversation = _store.conversationForId(_owner.conversationId);
    return conversation?.id == _owner.conversationId ? conversation : null;
  }

  @override
  Future<void> markGoalStatus(TurnRuntimeGoalStatusUpdate update) async {
    if (conversation == null) {
      return;
    }
    await _store.markGoalStatus(
      conversationId: _owner.conversationId,
      status: update.status,
      blockedReason: update.blockedReason,
      completionSummary: update.completionSummary,
    );
  }
}
