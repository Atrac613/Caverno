// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_plan_artifact.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ConversationPlanArtifact _$ConversationPlanArtifactFromJson(
  Map<String, dynamic> json,
) => _ConversationPlanArtifact(
  draftMarkdown: json['draftMarkdown'] as String? ?? '',
  approvedMarkdown: json['approvedMarkdown'] as String? ?? '',
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$ConversationPlanArtifactToJson(
  _ConversationPlanArtifact instance,
) => <String, dynamic>{
  'draftMarkdown': instance.draftMarkdown,
  'approvedMarkdown': instance.approvedMarkdown,
  'updatedAt': instance.updatedAt?.toIso8601String(),
};
