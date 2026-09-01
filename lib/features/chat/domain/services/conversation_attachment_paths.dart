import 'package:path/path.dart' as p;

import '../entities/conversation.dart';
import '../entities/message.dart';

/// Every file on disk a conversation is the last owner of.
///
/// Deleting a conversation has to reclaim the copies its messages kept, so
/// this is the one place that knows where a message can be holding a path.
/// Structured fields are read directly; the prose pattern is only for messages
/// written before attachments carried their path out of band.
abstract final class ConversationAttachmentPaths {
  /// The large-file reference the composer used to leave in the message body.
  static final RegExp _legacyReferencePattern = RegExp(
    r'^\[Attached file: (.+) \([^)]+\)\]$',
    multiLine: true,
  );

  static Iterable<String> of(Conversation conversation) sync* {
    for (final message in conversation.messages) {
      yield* _pathsIn(message);
    }
  }

  static Iterable<String> _pathsIn(Message message) sync* {
    for (final candidate in <String?>[
      message.originalImagePath,
      message.videoPath,
      message.attachmentPath,
    ]) {
      final trimmed = candidate?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        yield p.normalize(p.absolute(trimmed));
      }
    }
    // The prose reference lives in what was sent, not in the bubble text.
    for (final match in _legacyReferencePattern.allMatches(
      message.effectiveModelContent,
    )) {
      final path = match.group(1)?.trim();
      if (path != null && path.isNotEmpty) {
        yield p.normalize(p.absolute(path));
      }
    }
  }
}
