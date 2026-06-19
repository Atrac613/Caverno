// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'worktree_agent_task.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_WorktreeAgentTask _$WorktreeAgentTaskFromJson(Map<String, dynamic> json) =>
    _WorktreeAgentTask(
      id: json['id'] as String,
      status:
          $enumDecodeNullable(
            _$WorktreeAgentTaskStatusEnumMap,
            json['status'],
            unknownValue: WorktreeAgentTaskStatus.needsRecovery,
          ) ??
          WorktreeAgentTaskStatus.queued,
      title: json['title'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      codingProjectId: json['codingProjectId'] as String? ?? '',
      baseBranch: json['baseBranch'] as String? ?? 'main',
      branchName: json['branchName'] as String,
      worktreePath: json['worktreePath'] as String,
      checkpointLineageId: json['checkpointLineageId'] as String? ?? '',
      endpointId: json['endpointId'] as String? ?? '',
      verificationCommand: json['verificationCommand'] as String? ?? '',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      startedAt: json['startedAt'] == null
          ? null
          : DateTime.parse(json['startedAt'] as String),
      finishedAt: json['finishedAt'] == null
          ? null
          : DateTime.parse(json['finishedAt'] as String),
      resultSummary: json['resultSummary'] as String? ?? '',
      verifiedGreen: json['verifiedGreen'] as bool? ?? false,
      verificationSummary: json['verificationSummary'] as String? ?? '',
      recoveryNote: json['recoveryNote'] as String? ?? '',
      error: json['error'] as String? ?? '',
    );

Map<String, dynamic> _$WorktreeAgentTaskToJson(_WorktreeAgentTask instance) =>
    <String, dynamic>{
      'id': instance.id,
      'status': _$WorktreeAgentTaskStatusEnumMap[instance.status]!,
      'title': instance.title,
      'prompt': instance.prompt,
      'codingProjectId': instance.codingProjectId,
      'baseBranch': instance.baseBranch,
      'branchName': instance.branchName,
      'worktreePath': instance.worktreePath,
      'checkpointLineageId': instance.checkpointLineageId,
      'endpointId': instance.endpointId,
      'verificationCommand': instance.verificationCommand,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'startedAt': instance.startedAt?.toIso8601String(),
      'finishedAt': instance.finishedAt?.toIso8601String(),
      'resultSummary': instance.resultSummary,
      'verifiedGreen': instance.verifiedGreen,
      'verificationSummary': instance.verificationSummary,
      'recoveryNote': instance.recoveryNote,
      'error': instance.error,
    };

const _$WorktreeAgentTaskStatusEnumMap = {
  WorktreeAgentTaskStatus.queued: 'queued',
  WorktreeAgentTaskStatus.running: 'running',
  WorktreeAgentTaskStatus.needsRecovery: 'needsRecovery',
  WorktreeAgentTaskStatus.completed: 'completed',
  WorktreeAgentTaskStatus.failed: 'failed',
  WorktreeAgentTaskStatus.cancelled: 'cancelled',
};
