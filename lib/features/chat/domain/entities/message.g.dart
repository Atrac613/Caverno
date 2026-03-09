// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Message _$MessageFromJson(Map<String, dynamic> json) => _Message(
  id: json['id'] as String,
  content: json['content'] as String,
  role: $enumDecode(_$MessageRoleEnumMap, json['role']),
  timestamp: DateTime.parse(json['timestamp'] as String),
  isStreaming: json['isStreaming'] as bool? ?? false,
  error: json['error'] as String?,
  imageBase64: json['imageBase64'] as String?,
  imageMimeType: json['imageMimeType'] as String?,
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
};

const _$MessageRoleEnumMap = {
  MessageRole.user: 'user',
  MessageRole.assistant: 'assistant',
  MessageRole.system: 'system',
};
