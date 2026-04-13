import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/types/workspace_mode.dart';
import 'message.dart';

part 'conversation.freezed.dart';
part 'conversation.g.dart';

@freezed
abstract class Conversation with _$Conversation {
  const Conversation._();

  const factory Conversation({
    required String id,
    required String title,
    required List<Message> messages,
    required DateTime createdAt,
    required DateTime updatedAt,
    @JsonKey(unknownEnumValue: WorkspaceMode.chat)
    @Default(WorkspaceMode.chat)
    WorkspaceMode workspaceMode,
    @Default('') String projectId,
  }) = _Conversation;

  factory Conversation.fromJson(Map<String, dynamic> json) =>
      _$ConversationFromJson(json);

  String? get normalizedProjectId {
    final trimmed = projectId.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
