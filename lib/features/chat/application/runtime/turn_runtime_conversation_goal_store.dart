import '../../domain/entities/conversation.dart';
import '../../domain/entities/conversation_goal.dart';

/// Minimal owner-addressable goal storage required by the runtime adapter.
abstract interface class TurnRuntimeConversationGoalStore {
  Conversation? conversationForId(String conversationId);

  Future<void> markGoalStatus({
    required String conversationId,
    required ConversationGoalStatus status,
    String? blockedReason,
    String? completionSummary,
  });
}
