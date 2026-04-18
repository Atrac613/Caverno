// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_compaction_artifact.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ConversationCompactionArtifact _$ConversationCompactionArtifactFromJson(
  Map<String, dynamic> json,
) => _ConversationCompactionArtifact(
  version: (json['version'] as num?)?.toInt() ?? 1,
  summary: json['summary'] as String? ?? '',
  sourceMessageCount: (json['sourceMessageCount'] as num?)?.toInt() ?? 0,
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
  'version': instance.version,
  'summary': instance.summary,
  'sourceMessageCount': instance.sourceMessageCount,
  'compactedMessageCount': instance.compactedMessageCount,
  'retainedMessageCount': instance.retainedMessageCount,
  'estimatedPromptTokens': instance.estimatedPromptTokens,
  'updatedAt': instance.updatedAt?.toIso8601String(),
};
