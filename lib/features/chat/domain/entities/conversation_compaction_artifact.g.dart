// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_compaction_artifact.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ConversationCompactionArtifact _$ConversationCompactionArtifactFromJson(
  Map<String, dynamic> json,
) => _ConversationCompactionArtifact(
  summary: json['summary'] as String? ?? '',
  compactedMessageCount: (json['compactedMessageCount'] as num?)?.toInt() ?? 0,
  retainedMessageCount: (json['retainedMessageCount'] as num?)?.toInt() ?? 0,
  estimatedPromptTokens: (json['estimatedPromptTokens'] as num?)?.toInt() ?? 0,
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$ConversationCompactionArtifactToJson(
  _ConversationCompactionArtifact instance,
) => <String, dynamic>{
  'summary': instance.summary,
  'compactedMessageCount': instance.compactedMessageCount,
  'retainedMessageCount': instance.retainedMessageCount,
  'estimatedPromptTokens': instance.estimatedPromptTokens,
  'updatedAt': instance.updatedAt?.toIso8601String(),
};
