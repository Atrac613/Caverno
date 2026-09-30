import '../../chat/domain/entities/chat_turn_owner.dart';
import '../../chat/domain/entities/conversation.dart';
import '../../chat/domain/entities/conversation_goal.dart';

/// Requires accepted implementation completion before starting task review.
final class ProjectTaskReviewTurnRunner {
  const ProjectTaskReviewTurnRunner({
    required this.readConversation,
    required this.isSelected,
    required this.isWaitingForUser,
    required this.reactivate,
    required this.sendTurn,
    required this.waitForCompletion,
  });

  final Conversation? Function() readConversation;
  final bool Function() isSelected;
  final bool Function() isWaitingForUser;
  final Future<void> Function() reactivate;
  final Future<ChatTurnOwner?> Function(String, {required bool codeReview})
  sendTurn;
  final Future<void> Function(ChatTurnOwner) waitForCompletion;

  Future<bool> send(String prompt, {required bool codeReview}) async {
    if (!isSelected() || isWaitingForUser()) return false;
    final goal = readConversation()?.goal;
    if (goal == null ||
        !goal.enabled ||
        goal.status == ConversationGoalStatus.blocked ||
        goal.status == ConversationGoalStatus.awaitingConfirmation ||
        goal.budgetExceeded) {
      return false;
    }
    if (!codeReview && goal.status == ConversationGoalStatus.completed) {
      await reactivate();
      if (!isSelected() || isWaitingForUser()) return false;
    }
    final owner = await sendTurn(prompt, codeReview: codeReview);
    if (owner == null || owner.conversationId != readConversation()?.id) {
      return false;
    }
    await waitForCompletion(owner);
    return isSelected() &&
        !isWaitingForUser() &&
        (codeReview ||
            readConversation()?.goal?.status ==
                ConversationGoalStatus.completed);
  }
}
