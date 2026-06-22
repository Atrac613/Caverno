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
  role: $enumDecode(_$MessageRoleEnumMap, json['role']),
  timestamp: DateTime.parse(json['timestamp'] as String),
  isStreaming: json['isStreaming'] as bool? ?? false,
  error: json['error'] as String?,
  imageBase64: json['imageBase64'] as String?,
  imageMimeType: json['imageMimeType'] as String?,
  originalImagePath: json['originalImagePath'] as String?,
  originalImageMimeType: json['originalImageMimeType'] as String?,
  participantId: json['participantId'] as String?,
  participantDisplayName: json['participantDisplayName'] as String?,
  participantRoleLabel: json['participantRoleLabel'] as String?,
  participantColorValue: (json['participantColorValue'] as num?)?.toInt(),
  responseMetrics: json['responseMetrics'] == null
      ? null
      : MessageResponseMetrics.fromJson(
          json['responseMetrics'] as Map<String, dynamic>,
        ),
);

Map<String, dynamic> _$MessageToJson(_Message instance) => <String, dynamic>{
  'id': instance.id,
  'content': instance.content,
  'role': _$MessageRoleEnumMap[instance.role]!,
  'timestamp': instance.timestamp.toIso8601String(),
  'isStreaming': instance.isStreaming,
  'error': instance.error,
  'imageBase64': instance.imageBase64,
  'imageMimeType': instance.imageMimeType,
  'originalImagePath': instance.originalImagePath,
  'originalImageMimeType': instance.originalImageMimeType,
  'participantId': instance.participantId,
  'participantDisplayName': instance.participantDisplayName,
  'participantRoleLabel': instance.participantRoleLabel,
  'participantColorValue': instance.participantColorValue,
  'responseMetrics': instance.responseMetrics,
};

const _$MessageRoleEnumMap = {
  MessageRole.user: 'user',
  MessageRole.assistant: 'assistant',
  MessageRole.system: 'system',
};
