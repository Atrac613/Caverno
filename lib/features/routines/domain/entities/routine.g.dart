// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'routine.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RoutineRunRecord _$RoutineRunRecordFromJson(Map<String, dynamic> json) =>
    _RoutineRunRecord(
      id: json['id'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String),
      finishedAt: DateTime.parse(json['finishedAt'] as String),
      status:
          $enumDecodeNullable(
            _$RoutineRunStatusEnumMap,
            json['status'],
            unknownValue: RoutineRunStatus.completed,
          ) ??
          RoutineRunStatus.completed,
      trigger:
          $enumDecodeNullable(
            _$RoutineRunTriggerEnumMap,
            json['trigger'],
            unknownValue: RoutineRunTrigger.manual,
          ) ??
          RoutineRunTrigger.manual,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      usedTools: json['usedTools'] as bool? ?? false,
      toolCallCount: (json['toolCallCount'] as num?)?.toInt() ?? 0,
      toolNames:
          (json['toolNames'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      preview: json['preview'] as String? ?? '',
      output: json['output'] as String? ?? '',
      error: json['error'] as String? ?? '',
    );

Map<String, dynamic> _$RoutineRunRecordToJson(_RoutineRunRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'startedAt': instance.startedAt.toIso8601String(),
      'finishedAt': instance.finishedAt.toIso8601String(),
      'status': _$RoutineRunStatusEnumMap[instance.status]!,
      'trigger': _$RoutineRunTriggerEnumMap[instance.trigger]!,
      'durationMs': instance.durationMs,
      'usedTools': instance.usedTools,
      'toolCallCount': instance.toolCallCount,
      'toolNames': instance.toolNames,
      'preview': instance.preview,
      'output': instance.output,
      'error': instance.error,
    };

const _$RoutineRunStatusEnumMap = {
  RoutineRunStatus.completed: 'completed',
  RoutineRunStatus.failed: 'failed',
};

const _$RoutineRunTriggerEnumMap = {
  RoutineRunTrigger.manual: 'manual',
  RoutineRunTrigger.scheduled: 'scheduled',
};

_Routine _$RoutineFromJson(Map<String, dynamic> json) => _Routine(
  id: json['id'] as String,
  name: json['name'] as String,
  prompt: json['prompt'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  enabled: json['enabled'] as bool? ?? true,
  notifyOnCompletion: json['notifyOnCompletion'] as bool? ?? true,
  toolsEnabled: json['toolsEnabled'] as bool? ?? false,
  intervalValue: (json['intervalValue'] as num?)?.toInt() ?? 1,
  intervalUnit:
      $enumDecodeNullable(
        _$RoutineIntervalUnitEnumMap,
        json['intervalUnit'],
        unknownValue: RoutineIntervalUnit.hours,
      ) ??
      RoutineIntervalUnit.hours,
  nextRunAt: json['nextRunAt'] == null
      ? null
      : DateTime.parse(json['nextRunAt'] as String),
  lastRunAt: json['lastRunAt'] == null
      ? null
      : DateTime.parse(json['lastRunAt'] as String),
  runs:
      (json['runs'] as List<dynamic>?)
          ?.map((e) => RoutineRunRecord.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <RoutineRunRecord>[],
);

Map<String, dynamic> _$RoutineToJson(_Routine instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'prompt': instance.prompt,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
  'enabled': instance.enabled,
  'notifyOnCompletion': instance.notifyOnCompletion,
  'toolsEnabled': instance.toolsEnabled,
  'intervalValue': instance.intervalValue,
  'intervalUnit': _$RoutineIntervalUnitEnumMap[instance.intervalUnit]!,
  'nextRunAt': instance.nextRunAt?.toIso8601String(),
  'lastRunAt': instance.lastRunAt?.toIso8601String(),
  'runs': instance.runs,
};

const _$RoutineIntervalUnitEnumMap = {
  RoutineIntervalUnit.minutes: 'minutes',
  RoutineIntervalUnit.hours: 'hours',
  RoutineIntervalUnit.days: 'days',
};
