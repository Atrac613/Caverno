import 'package:freezed_annotation/freezed_annotation.dart';

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
    String? originalImagePath,
    String? originalImageMimeType,

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

extension MessageVideoAttachment on Message {
  /// Whether this message carries a video the request layer must send.
  bool get hasVideoAttachment => videoPath != null || videoUrl != null;

  /// Media type to advertise, defaulting to the container we ask pickers for.
  String get effectiveVideoMimeType => videoMimeType ?? 'video/mp4';
}
