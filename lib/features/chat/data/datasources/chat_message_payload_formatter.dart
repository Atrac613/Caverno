import 'package:openai_dart/openai_dart.dart' hide MessageRole;

import '../../domain/entities/message.dart';
import '../../domain/entities/video_attachment_part.dart';

/// Turns Caverno's messages into the wire shape an OpenAI-compatible endpoint
/// expects, deciding what each one is allowed to carry.
///
/// Pure and stateless: every input it reasons about arrives as an argument, so
/// what a request will look like can be checked without a client, a socket, or
/// a turn in flight.
class ChatMessagePayloadFormatter {
  const ChatMessagePayloadFormatter();

  static const String imageOmittedNotice =
      '[image attachment omitted from this request]';

  /// Whether images should be left out of this request.
  ///
  /// They ride along only while the latest user message still carries one, so
  /// a conversation can continue against a non-vision endpoint once the
  /// attachment is behind it.
  ///
  /// The tool-result paths hardcoded this to true, on the theory that images
  /// had "already been processed at tool call time". They had not: a follow-up
  /// carries the newest assistant text, not the first-pass reading, so any
  /// vision turn that touched a tool answered blind -- session cad9b37c said
  /// "No sessions yet" about a screenshot it had just read as holding 106.
  /// Re-sending costs ~1k prompt tokens and sits in the cached prefix.
  bool shouldStripImages(List<Message> messages) =>
      latestUserMessage(messages).imageBase64 == null;

  /// The person's most recent turn, skipping prompts Caverno composed itself.
  ///
  /// Caverno's own prompts are not the person's turn. Treating the tool-result
  /// envelope as the latest user message stripped the screenshot from the
  /// answer the reader sees (session 3c1f6c02).
  Message latestUserMessage(List<Message> messages) => messages.lastWhere(
    (m) => m.role == MessageRole.user && !m.isSynthesizedPrompt,
    orElse: () => messages.last,
  );

  List<ChatMessage> format(
    List<Message> messages, {
    bool stripImages = false,
    Map<String, String> videoUrls = const <String, String>{},
  }) {
    return messages.map<ChatMessage>((m) {
      switch (m.role) {
        case MessageRole.user:
          return _formatUserMessage(
            m,
            stripImages: stripImages,
            videoUrls: videoUrls,
          );
        case MessageRole.assistant:
          return ChatMessage.assistant(content: m.content);
        case MessageRole.system:
          return ChatMessage.system(m.content);
      }
    }).toList();
  }

  ChatMessage _formatUserMessage(
    Message message, {
    required bool stripImages,
    required Map<String, String> videoUrls,
  }) {
    final content = message.effectiveModelContent;
    final carriesImage = message.imageBase64 != null && !stripImages;
    final videoUrl = message.hasVideoAttachment ? videoUrls[message.id] : null;

    if (carriesImage || videoUrl != null) {
      final parts = <ContentPart>[
        if (content.isNotEmpty) ContentPart.text(content),
        if (carriesImage)
          ContentPart.imageBase64(
            data: message.imageBase64!,
            mediaType: message.imageMimeType ?? 'image/jpeg',
          ),
        // Placeholder only: VideoContentPartClient turns this into the
        // `video_url` part once the body is JSON, because the typed request
        // has no video content part to build here.
        if (videoUrl != null)
          ContentPart.text(VideoAttachmentPart.encode(videoUrl)),
      ];
      return ChatMessage.user(parts);
    }

    // Name every removal. Saying nothing is what let a model answer a
    // screenshot question from an empty context and invent the screen.
    final notices = <String>[
      if (message.imageBase64 != null) imageOmittedNotice,
      if (message.hasVideoAttachment) VideoAttachmentPart.omittedNotice,
    ];
    if (notices.isEmpty) return ChatMessage.user(content);
    final omitted = notices.join('\n');
    return ChatMessage.user(content.isEmpty ? omitted : '$content\n\n$omitted');
  }
}
