import 'package:freezed_annotation/freezed_annotation.dart';

import 'video_attachment_draft.dart';

// Re-exported because [Message.withVideoAttachment] takes one: a file holding
// messages needs the draft type to put a video on one.
export 'video_attachment_draft.dart';

part 'message.freezed.dart';
part 'message.g.dart';

enum MessageRole { user, assistant, system }

@freezed
abstract class MessageResponseMetrics with _$MessageResponseMetrics {
  const factory MessageResponseMetrics({
    @Default(0) int promptTokens,
    @Default(0) int completionTokens,
    @Default(0) int totalTokens,
    @Default(0) int elapsedMilliseconds,
    String? finishReason,
  }) = _MessageResponseMetrics;

  factory MessageResponseMetrics.fromJson(Map<String, dynamic> json) =>
      _$MessageResponseMetricsFromJson(json);
}

@freezed
abstract class Message with _$Message {
  const factory Message({
    required String id,
    required String content,

    /// Content sent to the model when it differs from [content].
    ///
    /// Attachment text can be large and useful to the model without belonging
    /// in the chat bubble. [content] remains the user-visible transcript while
    /// this field preserves the complete request across persistence and
    /// follow-up turns.
    String? modelContent,
    required MessageRole role,
    required DateTime timestamp,
    @Default(false) bool isStreaming,
    String? error,
    String? imageBase64,
    String? imageMimeType,

    /// True when Caverno composed this message rather than the person.
    ///
    /// The tool-result envelope and the in-turn recovery prompts are sent with
    /// `MessageRole.user` because that is the only role a model will act on,
    /// but they are not the human's turn. Anything reasoning about "what the
    /// user last said" has to skip them: session 3c1f6c02 dropped an attached
    /// screenshot from the final answer because the envelope had become the
    /// latest user message and carried no image.
    @Default(false) bool isSynthesizedPrompt,

    /// True when the Anabasis parent answered this turn.
    ///
    /// The transcript is the only place a reader can tell an orchestrator's
    /// reply from an ordinary one, and the two mean different things: the
    /// parent inspects, verifies and delegates but never edits, so "it did not
    /// change anything" is expected of it and would be a failure from anyone
    /// else. Stored rather than derived so reopening a conversation keeps the
    /// distinction.
    ///
    /// A separate field rather than the participant columns: ANA0's design
    /// keeps the parent's authority off surface identity, and rendering it as a
    /// participant would mix the two.
    @Default(false) bool isAnabasisParent,
    String? originalImagePath,
    String? originalImageMimeType,

    /// Durable copy of a file attachment, kept out of band.
    ///
    /// Set for a message that carried a document so the bubble can hand it to
    /// the platform viewer. Like [videoPath] the payload never rides on the
    /// message: the file stays in the attachments directory and only its path
    /// is persisted, and the directory's retention sweep may remove it, so a
    /// reader has to tolerate the file being gone.
    String? attachmentPath,

    /// Video attachment, kept out of band.
    ///
    /// Unlike [imageBase64] the payload is never stored on the message: a
    /// multi-megabyte base64 string would be rewritten into the conversation's
    /// Hive JSON on every save. The bytes stay in the attachment directory and
    /// are encoded (or served) only at send time.
    String? videoPath,

    /// Set instead of [videoPath] when the person typed a URL by hand.
    String? videoUrl,
    String? videoMimeType,
    int? videoSizeBytes,
    int? videoDurationMs,
    String? participantId,
    String? participantDisplayName,
    String? participantRoleLabel,
    int? participantColorValue,
    @Default(<String>[]) List<String> participantToolNames,
    String? handoffTargetParticipantId,
    String? handoffTargetDisplayName,
    String? handoffTargetRoleLabel,
    MessageResponseMetrics? responseMetrics,
  }) = _Message;

  factory Message.fromJson(Map<String, dynamic> json) =>
      _$MessageFromJson(json);
}

extension MessageModelContent on Message {
  /// Text to put on the wire for this message.
  String get effectiveModelContent => modelContent ?? content;
}

extension MessageVideoAttachment on Message {
  /// Whether this message carries a video the request layer must send.
  bool get hasVideoAttachment => videoPath != null || videoUrl != null;

  /// Media type to advertise, defaulting to the container we ask pickers for.
  String get effectiveVideoMimeType => videoMimeType ?? 'video/mp4';

  /// Attaches [draft], or returns this message unchanged when there is none.
  ///
  /// The draft is one object while the message stores flat fields, because the
  /// message is what gets serialized into the conversation and a nested object
  /// there would be a schema change for no gain.
  Message withVideoAttachment(VideoAttachmentDraft? draft) {
    if (draft == null) return this;
    return copyWith(
      videoPath: draft.path,
      videoUrl: draft.url,
      videoMimeType: draft.mimeType,
      videoSizeBytes: draft.sizeBytes,
      videoDurationMs: draft.durationMs,
    );
  }
}
