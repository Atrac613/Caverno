// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_workflow.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ConversationWorkflowTask _$ConversationWorkflowTaskFromJson(
  Map<String, dynamic> json,
) => _ConversationWorkflowTask(
  id: json['id'] as String,
  title: json['title'] as String,
  status:
      $enumDecodeNullable(
        _$ConversationWorkflowTaskStatusEnumMap,
        json['status'],
      ) ??
      ConversationWorkflowTaskStatus.pending,
  targetFiles:
      (json['targetFiles'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  validationCommand: json['validationCommand'] as String? ?? '',
  notes: json['notes'] as String? ?? '',
);

Map<String, dynamic> _$ConversationWorkflowTaskToJson(
  _ConversationWorkflowTask instance,
) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'status': _$ConversationWorkflowTaskStatusEnumMap[instance.status]!,
  'targetFiles': instance.targetFiles,
  'validationCommand': instance.validationCommand,
  'notes': instance.notes,
};

const _$ConversationWorkflowTaskStatusEnumMap = {
  ConversationWorkflowTaskStatus.pending: 'pending',
  ConversationWorkflowTaskStatus.inProgress: 'inProgress',
  ConversationWorkflowTaskStatus.completed: 'completed',
  ConversationWorkflowTaskStatus.blocked: 'blocked',
};

_ConversationWorkflowSpec _$ConversationWorkflowSpecFromJson(
  Map<String, dynamic> json,
) => _ConversationWorkflowSpec(
  goal: json['goal'] as String? ?? '',
  constraints:
      (json['constraints'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  acceptanceCriteria:
      (json['acceptanceCriteria'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  openQuestions:
      (json['openQuestions'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  tasks: json['tasks'] == null
      ? const <ConversationWorkflowTask>[]
      : _workflowTasksFromJson(json['tasks'] as List?),
);

Map<String, dynamic> _$ConversationWorkflowSpecToJson(
  _ConversationWorkflowSpec instance,
) => <String, dynamic>{
  'goal': instance.goal,
  'constraints': instance.constraints,
  'acceptanceCriteria': instance.acceptanceCriteria,
  'openQuestions': instance.openQuestions,
  'tasks': _workflowTasksToJson(instance.tasks),
};
