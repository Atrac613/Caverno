import '../../domain/entities/video_attachment_draft.dart';
import 'chat_state.dart' show ChatInteractionOrigin;

/// One message waiting for its thread to be free.
///
/// Lifted out of chat_state.dart: it is a hand-written value class with
/// its own equality, not part of the ChatState freezed graph, and it grows
/// a field every time the composer learns to carry something new.
class QueuedChatMessage {
  const QueuedChatMessage({
    required this.id,
    required this.content,
    this.modelContent,
    this.attachmentPath,
    required this.imageBase64,
    required this.imageMimeType,
    required this.languageCode,
    required this.isVoiceMode,
    required this.bypassPlanMode,
    this.originalImagePath,
    this.originalImageMimeType,
    this.video,
    this.origin = ChatInteractionOrigin.local,
    this.remoteDeviceId,
    this.conversationId,
  });

  /// The thread this message was typed in. A message queued behind another
  /// thread's turn must come back to its own thread, never to whichever one
  /// the user is looking at when the queue drains.
  final String? conversationId;
  final String id;
  final String content;
  final String? modelContent;
  final String? attachmentPath;
  final String? imageBase64;
  final String? imageMimeType;
  final String? originalImagePath;
  final String? originalImageMimeType;
  final VideoAttachmentDraft? video;
  final String languageCode;
  final bool isVoiceMode;
  final bool bypassPlanMode;
  final ChatInteractionOrigin origin;
  final String? remoteDeviceId;
  bool get hasImage => imageBase64 != null && imageBase64!.isNotEmpty;
  bool get hasVideo => video != null;
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is QueuedChatMessage &&
            id == other.id &&
            content == other.content &&
            modelContent == other.modelContent &&
            attachmentPath == other.attachmentPath &&
            imageBase64 == other.imageBase64 &&
            imageMimeType == other.imageMimeType &&
            originalImagePath == other.originalImagePath &&
            originalImageMimeType == other.originalImageMimeType &&
            video == other.video &&
            languageCode == other.languageCode &&
            isVoiceMode == other.isVoiceMode &&
            bypassPlanMode == other.bypassPlanMode &&
            origin == other.origin &&
            remoteDeviceId == other.remoteDeviceId &&
            conversationId == other.conversationId;
  }

  @override
  int get hashCode => Object.hash(
    id,
    content,
    modelContent,
    attachmentPath,
    imageBase64,
    imageMimeType,
    originalImagePath,
    originalImageMimeType,
    video,
    languageCode,
    isVoiceMode,
    bypassPlanMode,
    origin,
    remoteDeviceId,
    conversationId,
  );
}
