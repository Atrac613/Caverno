// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'roadmap_snapshot.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RoadmapItemSnapshot _$RoadmapItemSnapshotFromJson(Map<String, dynamic> json) =>
    _RoadmapItemSnapshot(
      id: json['id'] as String,
      title: json['title'] as String,
      quote: json['quote'] as String,
      line: (json['line'] as num?)?.toInt(),
      verified: json['verified'] as bool? ?? true,
    );

Map<String, dynamic> _$RoadmapItemSnapshotToJson(
  _RoadmapItemSnapshot instance,
) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'quote': instance.quote,
  'line': instance.line,
  'verified': instance.verified,
};

_RoadmapSnapshot _$RoadmapSnapshotFromJson(
  Map<String, dynamic> json,
) => _RoadmapSnapshot(
  projectId: json['projectId'] as String,
  roadmapPath: json['roadmapPath'] as String,
  contentSha256: json['contentSha256'] as String,
  extractorVersion: (json['extractorVersion'] as num).toInt(),
  model: json['model'] as String,
  extractedAt: DateTime.parse(json['extractedAt'] as String),
  status: $enumDecode(_$RoadmapSnapshotStatusEnumMap, json['status']),
  recommended: json['recommended'] == null
      ? null
      : RoadmapItemSnapshot.fromJson(
          json['recommended'] as Map<String, dynamic>,
        ),
  recommendationSource:
      $enumDecodeNullable(
        _$RoadmapRecommendationSourceEnumMap,
        json['recommendationSource'],
      ) ??
      RoadmapRecommendationSource.explicit,
  current:
      (json['current'] as List<dynamic>?)
          ?.map((e) => RoadmapItemSnapshot.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <RoadmapItemSnapshot>[],
  blocked:
      (json['blocked'] as List<dynamic>?)
          ?.map((e) => RoadmapItemSnapshot.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <RoadmapItemSnapshot>[],
  upcoming:
      (json['upcoming'] as List<dynamic>?)
          ?.map((e) => RoadmapItemSnapshot.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <RoadmapItemSnapshot>[],
  droppedCount: (json['droppedCount'] as num?)?.toInt() ?? 0,
  error: json['error'] as String?,
  pinned: json['pinned'] as bool? ?? false,
);

Map<String, dynamic> _$RoadmapSnapshotToJson(_RoadmapSnapshot instance) =>
    <String, dynamic>{
      'projectId': instance.projectId,
      'roadmapPath': instance.roadmapPath,
      'contentSha256': instance.contentSha256,
      'extractorVersion': instance.extractorVersion,
      'model': instance.model,
      'extractedAt': instance.extractedAt.toIso8601String(),
      'status': _$RoadmapSnapshotStatusEnumMap[instance.status]!,
      'recommended': instance.recommended,
      'recommendationSource':
          _$RoadmapRecommendationSourceEnumMap[instance.recommendationSource]!,
      'current': instance.current,
      'blocked': instance.blocked,
      'upcoming': instance.upcoming,
      'droppedCount': instance.droppedCount,
      'error': instance.error,
      'pinned': instance.pinned,
    };

const _$RoadmapSnapshotStatusEnumMap = {
  RoadmapSnapshotStatus.verified: 'verified',
  RoadmapSnapshotStatus.unverified: 'unverified',
  RoadmapSnapshotStatus.none: 'none',
  RoadmapSnapshotStatus.failed: 'failed',
};

const _$RoadmapRecommendationSourceEnumMap = {
  RoadmapRecommendationSource.explicit: 'explicit',
  RoadmapRecommendationSource.priority: 'priority',
};
