import 'package:caverno_content_protocol/caverno_content_protocol.dart';

import '../../chat/domain/entities/message.dart';
import 'watch_snapshot.dart';

class WatchTranscriptProjection {
  const WatchTranscriptProjection({
    required this.messages,
    required this.messagesTruncated,
    required this.lastAssistantText,
  });

  final List<WatchMessage> messages;
  final bool messagesTruncated;
  final String lastAssistantText;
}

/// Reduces a chat transcript to the text that is safe and useful on a wrist.
///
/// Local chat and Remote Coding use this same boundary so neither surface can
/// accidentally expose reasoning, tool traffic, or synthesized model prompts.
class WatchTranscriptProjector {
  const WatchTranscriptProjector();

  WatchTranscriptProjection project(List<Message> messages) {
    final visible = messages.where(_isVisible).toList(growable: false);
    final kept = visible.length <= watchSnapshotMaxMessages
        ? visible
        : visible.sublist(visible.length - watchSnapshotMaxMessages);
    return WatchTranscriptProjection(
      messages: kept
          .map(
            (message) => WatchMessage(
              id: message.id,
              role: message.role == MessageRole.user
                  ? WatchMessageRole.user
                  : WatchMessageRole.assistant,
              text: textFor(message),
              timestamp: message.timestamp,
              isStreaming: message.isStreaming,
            ),
          )
          .toList(growable: false),
      messagesTruncated: visible.length > watchSnapshotMaxMessages,
      lastAssistantText: _lastAssistantText(visible),
    );
  }

  /// Assistant prose with internal markup removed; user text stays verbatim.
  String textFor(Message message) => message.role == MessageRole.assistant
      ? ContentParser.parse(message.content).text.trim()
      : message.content.trim();

  bool _isVisible(Message message) =>
      message.role != MessageRole.system &&
      !message.isSynthesizedPrompt &&
      (message.isStreaming || textFor(message).isNotEmpty);

  String _lastAssistantText(List<Message> messages) {
    for (final message in messages.reversed) {
      if (message.role != MessageRole.assistant) continue;
      final text = textFor(message);
      if (text.isNotEmpty) return text;
    }
    return '';
  }
}
