import '../../domain/entities/video_attachment_draft.dart';
import 'chat_state.dart' show ChatInteractionOrigin;

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
    this.codeReview = false,
    this.projectTaskImplementation = false,
  });

  final String? conversationId;
  final bool codeReview;
  final bool projectTaskImplementation;
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
            conversationId == other.conversationId &&
            codeReview == other.codeReview &&
            projectTaskImplementation == other.projectTaskImplementation;
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
    codeReview,
    projectTaskImplementation,
  );
}
