import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/types/workspace_mode.dart';
import 'message.dart';
import 'conversation_workflow.dart';

part 'conversation.freezed.dart';
part 'conversation.g.dart';

ConversationWorkflowSpec? _workflowSpecFromJson(Map<String, dynamic>? json) {
  if (json == null) {
    return null;
  }
  return ConversationWorkflowSpec.fromJson(json);
}

Map<String, dynamic>? _workflowSpecToJson(ConversationWorkflowSpec? spec) {
  return spec?.toJson();
}

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
    @JsonKey(unknownEnumValue: ConversationExecutionMode.normal)
    @Default(ConversationExecutionMode.normal)
    ConversationExecutionMode executionMode,
    @JsonKey(unknownEnumValue: ConversationWorkflowStage.idle)
    @Default(ConversationWorkflowStage.idle)
    ConversationWorkflowStage workflowStage,
    @JsonKey(fromJson: _workflowSpecFromJson, toJson: _workflowSpecToJson)
    ConversationWorkflowSpec? workflowSpec,
  }) = _Conversation;

  factory Conversation.fromJson(Map<String, dynamic> json) =>
      _$ConversationFromJson(json);

  String? get normalizedProjectId {
    final trimmed = projectId.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool get isPlanningSession =>
      executionMode == ConversationExecutionMode.planning;

  ConversationWorkflowSpec get effectiveWorkflowSpec =>
      workflowSpec ?? const ConversationWorkflowSpec();

  bool get hasWorkflowContext =>
      workflowStage != ConversationWorkflowStage.idle ||
      effectiveWorkflowSpec.hasContent;
}
