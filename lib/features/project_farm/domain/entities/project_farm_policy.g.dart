// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project_farm_policy.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ProjectFarmPolicy _$ProjectFarmPolicyFromJson(Map<String, dynamic> json) =>
    _ProjectFarmPolicy(
      projectId: json['projectId'] as String,
      allowedVerificationCommands:
          (json['allowedVerificationCommands'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      maxConcurrentTasks: (json['maxConcurrentTasks'] as num?)?.toInt() ?? 1,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$ProjectFarmPolicyToJson(_ProjectFarmPolicy instance) =>
    <String, dynamic>{
      'projectId': instance.projectId,
      'allowedVerificationCommands': instance.allowedVerificationCommands,
      'maxConcurrentTasks': instance.maxConcurrentTasks,
      'updatedAt': instance.updatedAt.toIso8601String(),
    };
