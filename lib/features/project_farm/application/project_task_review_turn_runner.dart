import '../../chat/domain/entities/chat_turn_owner.dart';
import '../../chat/domain/entities/conversation.dart';
import 'project_task_review_eligibility.dart';
import 'project_task_review_retry.dart';

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

  Future<bool> send(String prompt, {required bool codeReview}) =>
      ProjectTaskReviewRetry.send(
        prompt,
        codeReview: codeReview,
        sendOnce: _sendOnce,
        readConversation: readConversation,
      );

  Future<bool> _sendOnce(String prompt, {required bool codeReview}) async {
    if (!isSelected() || isWaitingForUser()) return false;
    final goal = readConversation()?.goal;
    if (!TaskReviewGate.canSend(goal)) return false;
    if (!codeReview && TaskReviewGate.isCompleted(goal)) {
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
        TaskReviewGate.finished(readConversation()?.goal, codeReview);
  }
}
