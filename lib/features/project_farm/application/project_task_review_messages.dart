import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../../chat/domain/entities/message.dart';

/// Recognizes a finished review from the latest completed assistant message.
abstract final class ProjectTaskReviewMessages {
  static bool finished(Iterable<Message>? messages) {
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
}
