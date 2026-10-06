// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project_proposal.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ProjectProposal _$ProjectProposalFromJson(Map<String, dynamic> json) =>
    _ProjectProposal(
      projectId: json['projectId'] as String,
      inputHash: json['inputHash'] as String,
      proposedAt: DateTime.parse(json['proposedAt'] as String),
      taskId: json['taskId'] as String? ?? '',
      taskTitle: json['taskTitle'] as String? ?? '',
      rationale: json['rationale'] as String? ?? '',
      automatability: json['automatability'] as String? ?? '',
      automatabilityReason: json['automatabilityReason'] as String? ?? '',
      error: json['error'] as String?,
    );

Map<String, dynamic> _$ProjectProposalToJson(_ProjectProposal instance) =>
    <String, dynamic>{
      'projectId': instance.projectId,
      'inputHash': instance.inputHash,
      'proposedAt': instance.proposedAt.toIso8601String(),
      'taskId': instance.taskId,
      'taskTitle': instance.taskTitle,
      'rationale': instance.rationale,
      'automatability': instance.automatability,
      'automatabilityReason': instance.automatabilityReason,
      'error': instance.error,
    };
