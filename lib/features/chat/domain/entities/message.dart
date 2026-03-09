import 'package:freezed_annotation/freezed_annotation.dart';

part 'message.freezed.dart';
part 'message.g.dart';

enum MessageRole { user, assistant, system }

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
  }) = _Message;

  factory Message.fromJson(Map<String, dynamic> json) =>
      _$MessageFromJson(json);
}
