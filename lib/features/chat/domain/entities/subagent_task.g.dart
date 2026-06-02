// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subagent_task.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SubagentTask _$SubagentTaskFromJson(Map<String, dynamic> json) =>
    _SubagentTask(
      id: json['id'] as String,
      status:
          $enumDecodeNullable(_$SubagentTaskStatusEnumMap, json['status']) ??
          SubagentTaskStatus.pending,
      description: json['description'] as String? ?? '',
      parentToolUseId: json['parentToolUseId'] as String?,
      prompt: json['prompt'] as String? ?? '',
      output: json['output'] as String? ?? '',
      resultSummary: json['resultSummary'] as String? ?? '',
      startedAt: json['startedAt'] == null
          ? null
          : DateTime.parse(json['startedAt'] as String),
      finishedAt: json['finishedAt'] == null
          ? null
          : DateTime.parse(json['finishedAt'] as String),
      isBackground: json['isBackground'] as bool? ?? false,
      notified: json['notified'] as bool? ?? false,
      error: json['error'] as String?,
    );

Map<String, dynamic> _$SubagentTaskToJson(_SubagentTask instance) =>
    <String, dynamic>{
      'id': instance.id,
      'status': _$SubagentTaskStatusEnumMap[instance.status]!,
      'description': instance.description,
      'parentToolUseId': instance.parentToolUseId,
      'prompt': instance.prompt,
      'output': instance.output,
      'resultSummary': instance.resultSummary,
      'startedAt': instance.startedAt?.toIso8601String(),
      'finishedAt': instance.finishedAt?.toIso8601String(),
      'isBackground': instance.isBackground,
      'notified': instance.notified,
      'error': instance.error,
    };

const _$SubagentTaskStatusEnumMap = {
  SubagentTaskStatus.pending: 'pending',
  SubagentTaskStatus.running: 'running',
  SubagentTaskStatus.completed: 'completed',
  SubagentTaskStatus.failed: 'failed',
  SubagentTaskStatus.cancelled: 'cancelled',
};
