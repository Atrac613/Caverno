import '../../chat/domain/entities/conversation.dart';
import '../../chat/domain/services/project_task/project_task_review_verdict.dart';
import 'project_task_review_messages.dart';

/// Retries only a review lacking its accepted terminal message.
abstract final class ProjectTaskReviewRetry {
  static Future<bool> send(
    String prompt, {
    required bool codeReview,
    required Future<bool> Function(String, {required bool codeReview}) sendOnce,
    required Conversation? Function() readConversation,
  }) async {
    for (var attempt = 0; attempt < (codeReview ? 2 : 1); attempt++) {
      final priorMessageCount = readConversation()?.messages.length ?? 0;
      if (!await sendOnce(prompt, codeReview: codeReview)) return false;
      if (!codeReview ||
          ProjectTaskReviewMessages.finished(
            readConversation()?.messages.skip(priorMessageCount),
          ) ||
          attempt == 1) {
        return true;
      }
      prompt = '''$prompt

The previous review did not produce an accepted terminal review result. Perform the read-only review again through inspection tools: begin by calling read_file on the changed files listed above and wait for successful results. Earlier reads are historical evidence. Reconcile the task patch with the current files and retain any unresolved findings from the previous report. Do not edit files, commit, or change Git state.
${ProjectTaskReviewVerdict.instructions}''';
    }
    return false;
  }
}
