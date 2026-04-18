// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_plan_artifact.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ConversationPlanRevision _$ConversationPlanRevisionFromJson(
  Map<String, dynamic> json,
) => _ConversationPlanRevision(
  markdown: json['markdown'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
  kind:
      $enumDecodeNullable(
        _$ConversationPlanRevisionKindEnumMap,
        json['kind'],
      ) ??
      ConversationPlanRevisionKind.draft,
  label: json['label'] as String? ?? '',
);

Map<String, dynamic> _$ConversationPlanRevisionToJson(
  _ConversationPlanRevision instance,
) => <String, dynamic>{
  'markdown': instance.markdown,
  'createdAt': instance.createdAt.toIso8601String(),
  'kind': _$ConversationPlanRevisionKindEnumMap[instance.kind]!,
  'label': instance.label,
};

const _$ConversationPlanRevisionKindEnumMap = {
  ConversationPlanRevisionKind.draft: 'draft',
  ConversationPlanRevisionKind.approved: 'approved',
  ConversationPlanRevisionKind.restored: 'restored',
};

_ConversationPlanArtifact _$ConversationPlanArtifactFromJson(
  Map<String, dynamic> json,
) => _ConversationPlanArtifact(
  draftMarkdown: json['draftMarkdown'] as String? ?? '',
  approvedMarkdown: json['approvedMarkdown'] as String? ?? '',
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
  revisions:
      (json['revisions'] as List<dynamic>?)
          ?.map(
            (e) => ConversationPlanRevision.fromJson(e as Map<String, dynamic>),
          )
          .toList() ??
      const <ConversationPlanRevision>[],
);

Map<String, dynamic> _$ConversationPlanArtifactToJson(
  _ConversationPlanArtifact instance,
) => <String, dynamic>{
  'draftMarkdown': instance.draftMarkdown,
  'approvedMarkdown': instance.approvedMarkdown,
  'updatedAt': instance.updatedAt?.toIso8601String(),
  'revisions': instance.revisions,
};
