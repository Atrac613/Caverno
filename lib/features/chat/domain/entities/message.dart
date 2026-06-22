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
    String? originalImagePath,
    String? originalImageMimeType,
    String? participantId,
    String? participantDisplayName,
    String? participantRoleLabel,
    int? participantColorValue,
    MessageResponseMetrics? responseMetrics,
  }) = _Message;

  factory Message.fromJson(Map<String, dynamic> json) =>
      _$MessageFromJson(json);
}
