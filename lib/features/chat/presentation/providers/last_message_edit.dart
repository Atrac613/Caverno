import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../../domain/entities/message.dart';

/// Rewrites the last message of a turn's own message list.
///
/// F5: the append, replace and trailing-think helpers each copied this edit
/// into both an attached and a detached branch; the branch now only decides
/// where the list comes from and where it is committed.
abstract final class LastMessageEdit {
  /// [messages] with the last message's content set to [content], or null
  /// when there is no last message.
  static List<Message>? withContent(List<Message>? messages, String content) {
    if (messages == null || messages.isEmpty) return null;
    final lastIndex = messages.length - 1;
    return [...messages]
      ..[lastIndex] = messages[lastIndex].copyWith(content: content);
  }

  /// [messages] with tool-call artifacts stripped from a last assistant
  /// message, dropping that message when nothing visible or thinking remains;
  /// null when the last message is absent or not the assistant's.
  static List<Message>? withoutToolArtifacts(List<Message>? messages) {
    if (messages == null || messages.isEmpty) return null;
    final lastIndex = messages.length - 1;
    final last = messages[lastIndex];
    if (last.role != MessageRole.assistant) return null;
    final stripped = ContentParser.stripToolArtifactsPreservingThinking(
      last.content,
    );
    final updated = [...messages];
    if (stripped.trim().isEmpty) {
      updated.removeAt(lastIndex);
    } else {
      updated[lastIndex] = last.copyWith(content: stripped);
    }
    return updated;
  }
}
