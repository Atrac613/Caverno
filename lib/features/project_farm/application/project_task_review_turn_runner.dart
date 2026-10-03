import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../../chat/domain/entities/chat_turn_owner.dart';
import '../../chat/domain/entities/conversation.dart';
import '../../chat/domain/entities/conversation_goal.dart';
import '../../chat/domain/entities/message.dart';

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
    for (var attempt = 0; attempt < (codeReview ? 2 : 1); attempt++) {
      final priorMessageCount = readConversation()?.messages.length ?? 0;
      if (!await _sendOnce(prompt, codeReview: codeReview)) return false;
      if (!codeReview || _reviewFinished(priorMessageCount) || attempt == 1) {
        return true;
      }
      prompt = '''$prompt

The previous review did not produce an accepted terminal review result. Perform the read-only review again through inspection tools: begin by calling read_file on the changed files listed above and wait for successful results. Earlier responses and reads are historical evidence. Reconcile the task patch with the current files, then report findings and verification limits. End with PROJECT_TASK_REVIEW_CLEAN only for a complete review with no actionable findings, or PROJECT_TASK_REVIEW_FINDINGS for actionable findings. If inspection is unavailable or review remains incomplete, explain why and omit both markers. Do not edit files, commit, or change Git state.''';
    }
    return false;
  }

  bool _reviewFinished(int priorMessageCount) {
    final messages = readConversation()?.messages.skip(priorMessageCount);
    if (messages == null) return false;
    for (final message in messages.toList().reversed) {
      if (message.role != MessageRole.assistant ||
          message.isStreaming ||
          message.error != null) {
        continue;
      }
      final last = ContentParser.stripModelHistoryArtifacts(
        message.content,
      ).trimRight().split('\n').last.trim();
      return last == 'PROJECT_TASK_REVIEW_CLEAN' ||
          last == 'PROJECT_TASK_REVIEW_FINDINGS';
    }
    return false;
  }

  Future<bool> _sendOnce(String prompt, {required bool codeReview}) async {
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
