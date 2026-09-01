import '../../domain/entities/video_attachment_draft.dart';

typedef MessageInputSendHandler =
    void Function(
      String message,
      String? imageBase64,
      String? imageMimeType,
      String? originalImagePath,
      String? originalImageMimeType, {
      VideoAttachmentDraft? video,
      String? modelContent,
      String? attachmentPath,
    });
