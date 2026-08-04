import '../../application/runtime/turn_runtime_conversation_goal_adapter.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_goal.dart';
import '../../domain/services/conversation_goal_status_transition.dart';
import 'conversations_notifier.dart';

/// Exposes only owner-addressable goal operations from conversation storage.
final class ConversationsNotifierGoalRuntimeStore
    implements TurnRuntimeConversationGoalStore {
  const ConversationsNotifierGoalRuntimeStore({
    required ConversationsNotifier notifier,
  }) : _notifier = notifier;

  final ConversationsNotifier _notifier;

  @override
  Conversation? conversationForId(String conversationId) =>
      _notifier.runtimeConversationForId(conversationId);

  @override
  Future<void> markGoalStatus({
    required String conversationId,
    required ConversationGoalStatus status,
    String? blockedReason,
  }) async {
    final nextGoal = const ConversationGoalStatusTransition().apply(
      goal: conversationForId(conversationId)?.goal,
      status: status,
      blockedReason: blockedReason,
    );
    if (nextGoal == null) {
      return;
    }
    await _notifier.persistRuntimeGoal(
      conversationId: conversationId,
      goal: nextGoal,
    );
  }
}
