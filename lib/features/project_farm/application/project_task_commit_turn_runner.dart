import '../../chat/domain/entities/chat_turn_owner.dart';
import '../../chat/domain/entities/conversation.dart';
import '../../chat/domain/entities/conversation_goal.dart';

/// Sends the post-review commit turn of a project task.
///
/// It runs only on a completed goal and never reactivates it: the commit is
/// bookkeeping after the goal, and the workflow confirms it in git rather than
/// through goal status.
final class ProjectTaskCommitTurnRunner {
  const ProjectTaskCommitTurnRunner({
    required this.readConversation,
    required this.isSelected,
    required this.isWaitingForUser,
    required this.sendTurn,
    required this.waitForCompletion,
  });

  final Conversation? Function() readConversation;
  final bool Function() isSelected;
  final bool Function() isWaitingForUser;
  final Future<ChatTurnOwner?> Function(String prompt) sendTurn;
  final Future<void> Function(ChatTurnOwner) waitForCompletion;

  Future<bool> send(String prompt) async {
    if (!isSelected() || isWaitingForUser()) return false;
    if (readConversation()?.goal?.status != ConversationGoalStatus.completed) {
      return false;
    }
    final owner = await sendTurn(prompt);
    if (owner == null || owner.conversationId != readConversation()?.id) {
      return false;
    }
    await waitForCompletion(owner);
    return isSelected() && !isWaitingForUser();
  }
}
