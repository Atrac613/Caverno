// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_MessageResponseMetrics _$MessageResponseMetricsFromJson(
  Map<String, dynamic> json,
) => _MessageResponseMetrics(
  promptTokens: (json['promptTokens'] as num?)?.toInt() ?? 0,
  completionTokens: (json['completionTokens'] as num?)?.toInt() ?? 0,
  totalTokens: (json['totalTokens'] as num?)?.toInt() ?? 0,
  elapsedMilliseconds: (json['elapsedMilliseconds'] as num?)?.toInt() ?? 0,
  finishReason: json['finishReason'] as String?,
);

Map<String, dynamic> _$MessageResponseMetricsToJson(
  _MessageResponseMetrics instance,
) => <String, dynamic>{
  'promptTokens': instance.promptTokens,
  'completionTokens': instance.completionTokens,
  'totalTokens': instance.totalTokens,
  'elapsedMilliseconds': instance.elapsedMilliseconds,
  'finishReason': instance.finishReason,
};

_Message _$MessageFromJson(Map<String, dynamic> json) => _Message(
  id: json['id'] as String,
  content: json['content'] as String,
  modelContent: json['modelContent'] as String?,
  role: $enumDecode(_$MessageRoleEnumMap, json['role']),
  timestamp: DateTime.parse(json['timestamp'] as String),
  isStreaming: json['isStreaming'] as bool? ?? false,
  error: json['error'] as String?,
  imageBase64: json['imageBase64'] as String?,
  imageMimeType: json['imageMimeType'] as String?,
  isSynthesizedPrompt: json['isSynthesizedPrompt'] as bool? ?? false,
  isAnabasisParent: json['isAnabasisParent'] as bool? ?? false,
  originalImagePath: json['originalImagePath'] as String?,
  originalImageMimeType: json['originalImageMimeType'] as String?,
  attachmentPath: json['attachmentPath'] as String?,
  videoPath: json['videoPath'] as String?,
  videoUrl: json['videoUrl'] as String?,
  videoMimeType: json['videoMimeType'] as String?,
  videoSizeBytes: (json['videoSizeBytes'] as num?)?.toInt(),
  videoDurationMs: (json['videoDurationMs'] as num?)?.toInt(),
  participantId: json['participantId'] as String?,
  participantDisplayName: json['participantDisplayName'] as String?,
  participantRoleLabel: json['participantRoleLabel'] as String?,
  participantColorValue: (json['participantColorValue'] as num?)?.toInt(),
  participantToolNames:
      (json['participantToolNames'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  handoffTargetParticipantId: json['handoffTargetParticipantId'] as String?,
  handoffTargetDisplayName: json['handoffTargetDisplayName'] as String?,
  handoffTargetRoleLabel: json['handoffTargetRoleLabel'] as String?,
  responseMetrics: json['responseMetrics'] == null
      ? null
      : MessageResponseMetrics.fromJson(
          json['responseMetrics'] as Map<String, dynamic>,
        ),
);

Map<String, dynamic> _$MessageToJson(_Message instance) => <String, dynamic>{
  'id': instance.id,
  'content': instance.content,
  'modelContent': instance.modelContent,
  'role': _$MessageRoleEnumMap[instance.role]!,
  'timestamp': instance.timestamp.toIso8601String(),
  'isStreaming': instance.isStreaming,
  'error': instance.error,
  'imageBase64': instance.imageBase64,
  'imageMimeType': instance.imageMimeType,
  'isSynthesizedPrompt': instance.isSynthesizedPrompt,
  'isAnabasisParent': instance.isAnabasisParent,
  'originalImagePath': instance.originalImagePath,
  'originalImageMimeType': instance.originalImageMimeType,
  'attachmentPath': instance.attachmentPath,
  'videoPath': instance.videoPath,
  'videoUrl': instance.videoUrl,
  'videoMimeType': instance.videoMimeType,
  'videoSizeBytes': instance.videoSizeBytes,
  'videoDurationMs': instance.videoDurationMs,
  'participantId': instance.participantId,
  'participantDisplayName': instance.participantDisplayName,
  'participantRoleLabel': instance.participantRoleLabel,
  'participantColorValue': instance.participantColorValue,
  'participantToolNames': instance.participantToolNames,
  'handoffTargetParticipantId': instance.handoffTargetParticipantId,
  'handoffTargetDisplayName': instance.handoffTargetDisplayName,
  'handoffTargetRoleLabel': instance.handoffTargetRoleLabel,
  'responseMetrics': instance.responseMetrics,
};

const _$MessageRoleEnumMap = {
  MessageRole.user: 'user',
  MessageRole.assistant: 'assistant',
  MessageRole.system: 'system',
};
