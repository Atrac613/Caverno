// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Conversation _$ConversationFromJson(Map<String, dynamic> json) =>
    _Conversation(
      id: json['id'] as String,
      title: json['title'] as String,
      messages: (json['messages'] as List<dynamic>)
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      workspaceMode:
          $enumDecodeNullable(
            _$WorkspaceModeEnumMap,
            json['workspaceMode'],
            unknownValue: WorkspaceMode.chat,
          ) ??
          WorkspaceMode.chat,
      projectId: json['projectId'] as String? ?? '',
      workflowStage:
          $enumDecodeNullable(
            _$ConversationWorkflowStageEnumMap,
            json['workflowStage'],
            unknownValue: ConversationWorkflowStage.idle,
          ) ??
          ConversationWorkflowStage.idle,
      workflowSpec: _workflowSpecFromJson(
        json['workflowSpec'] as Map<String, dynamic>?,
      ),
    );

Map<String, dynamic> _$ConversationToJson(
  _Conversation instance,
) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'messages': instance.messages,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
  'workspaceMode': _$WorkspaceModeEnumMap[instance.workspaceMode]!,
  'projectId': instance.projectId,
  'workflowStage': _$ConversationWorkflowStageEnumMap[instance.workflowStage]!,
  'workflowSpec': _workflowSpecToJson(instance.workflowSpec),
};

const _$WorkspaceModeEnumMap = {
  WorkspaceMode.chat: 'chat',
  WorkspaceMode.coding: 'coding',
};

const _$ConversationWorkflowStageEnumMap = {
  ConversationWorkflowStage.idle: 'idle',
  ConversationWorkflowStage.clarify: 'clarify',
  ConversationWorkflowStage.plan: 'plan',
  ConversationWorkflowStage.tasks: 'tasks',
  ConversationWorkflowStage.implement: 'implement',
  ConversationWorkflowStage.review: 'review',
};
