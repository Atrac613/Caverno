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
      executionMode:
          $enumDecodeNullable(
            _$ConversationExecutionModeEnumMap,
            json['executionMode'],
            unknownValue: ConversationExecutionMode.normal,
          ) ??
          ConversationExecutionMode.normal,
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
      workflowSourceHash: json['workflowSourceHash'] as String? ?? '',
      workflowDerivedAt: json['workflowDerivedAt'] == null
          ? null
          : DateTime.parse(json['workflowDerivedAt'] as String),
      executionProgress: json['executionProgress'] == null
          ? const <ConversationExecutionTaskProgress>[]
          : _executionProgressFromJson(json['executionProgress'] as List?),
      openQuestionProgress: json['openQuestionProgress'] == null
          ? const <ConversationOpenQuestionProgress>[]
          : _openQuestionProgressFromJson(
              json['openQuestionProgress'] as List?,
            ),
      planArtifact: _planArtifactFromJson(
        json['planArtifact'] as Map<String, dynamic>?,
      ),
      compactionArtifact: _compactionArtifactFromJson(
        json['compactionArtifact'] as Map<String, dynamic>?,
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
  'executionMode': _$ConversationExecutionModeEnumMap[instance.executionMode]!,
  'workflowStage': _$ConversationWorkflowStageEnumMap[instance.workflowStage]!,
  'workflowSpec': _workflowSpecToJson(instance.workflowSpec),
  'workflowSourceHash': instance.workflowSourceHash,
  'workflowDerivedAt': instance.workflowDerivedAt?.toIso8601String(),
  'executionProgress': _executionProgressToJson(instance.executionProgress),
  'openQuestionProgress': _openQuestionProgressToJson(
    instance.openQuestionProgress,
  ),
  'planArtifact': _planArtifactToJson(instance.planArtifact),
  'compactionArtifact': _compactionArtifactToJson(instance.compactionArtifact),
};

const _$WorkspaceModeEnumMap = {
  WorkspaceMode.chat: 'chat',
  WorkspaceMode.coding: 'coding',
  WorkspaceMode.routines: 'routines',
};

const _$ConversationExecutionModeEnumMap = {
  ConversationExecutionMode.normal: 'normal',
  ConversationExecutionMode.planning: 'planning',
};

const _$ConversationWorkflowStageEnumMap = {
  ConversationWorkflowStage.idle: 'idle',
  ConversationWorkflowStage.clarify: 'clarify',
  ConversationWorkflowStage.plan: 'plan',
  ConversationWorkflowStage.tasks: 'tasks',
  ConversationWorkflowStage.implement: 'implement',
  ConversationWorkflowStage.review: 'review',
};
