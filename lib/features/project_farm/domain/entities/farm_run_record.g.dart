// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'farm_run_record.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_FarmRunRecord _$FarmRunRecordFromJson(Map<String, dynamic> json) =>
    _FarmRunRecord(
      id: json['id'] as String,
      projectId: json['projectId'] as String,
      trigger: json['trigger'] as String,
      at: DateTime.parse(json['at'] as String),
      outcome: json['outcome'] as String,
      taskId: json['taskId'] as String? ?? '',
      command: json['command'] as String? ?? '',
      branch: json['branch'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
    );

Map<String, dynamic> _$FarmRunRecordToJson(_FarmRunRecord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'projectId': instance.projectId,
      'trigger': instance.trigger,
      'at': instance.at.toIso8601String(),
      'outcome': instance.outcome,
      'taskId': instance.taskId,
      'command': instance.command,
      'branch': instance.branch,
      'detail': instance.detail,
    };
