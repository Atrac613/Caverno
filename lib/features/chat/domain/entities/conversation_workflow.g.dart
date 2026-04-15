// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_workflow.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

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
);

Map<String, dynamic> _$ConversationWorkflowSpecToJson(
  _ConversationWorkflowSpec instance,
) => <String, dynamic>{
  'goal': instance.goal,
  'constraints': instance.constraints,
  'acceptanceCriteria': instance.acceptanceCriteria,
  'openQuestions': instance.openQuestions,
};
