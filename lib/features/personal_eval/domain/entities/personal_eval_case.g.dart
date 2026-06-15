// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'personal_eval_case.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PersonalEvalCase _$PersonalEvalCaseFromJson(Map<String, dynamic> json) =>
    _PersonalEvalCase(
      caseId: json['caseId'] as String,
      prompt: json['prompt'] as String,
      repoStateRef: json['repoStateRef'] as String,
      title: json['title'] as String? ?? '',
      createdAt: json['createdAt'] == null
          ? null
          : DateTime.parse(json['createdAt'] as String),
      verificationCommand: json['verificationCommand'] as String?,
      verificationResult:
          $enumDecodeNullable(
            _$PersonalEvalVerificationResultEnumMap,
            json['verificationResult'],
            unknownValue: PersonalEvalVerificationResult.inconclusive,
          ) ??
          PersonalEvalVerificationResult.inconclusive,
      workspaceMode: json['workspaceMode'] as String?,
      split:
          $enumDecodeNullable(
            _$PersonalEvalCaseSplitEnumMap,
            json['split'],
            unknownValue: PersonalEvalCaseSplit.heldIn,
          ) ??
          PersonalEvalCaseSplit.heldIn,
      consentGranted: json['consentGranted'] as bool? ?? false,
      consentedAt: json['consentedAt'] == null
          ? null
          : DateTime.parse(json['consentedAt'] as String),
      sessionLogPath: json['sessionLogPath'] as String? ?? '',
      sessionLogSummary: json['sessionLogSummary'] == null
          ? null
          : PersonalEvalSessionLogSummary.fromJson(
              json['sessionLogSummary'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$PersonalEvalCaseToJson(_PersonalEvalCase instance) =>
    <String, dynamic>{
      'caseId': instance.caseId,
      'prompt': instance.prompt,
      'repoStateRef': instance.repoStateRef,
      'title': instance.title,
      'createdAt': instance.createdAt?.toIso8601String(),
      'verificationCommand': instance.verificationCommand,
      'verificationResult':
          _$PersonalEvalVerificationResultEnumMap[instance.verificationResult]!,
      'workspaceMode': instance.workspaceMode,
      'split': _$PersonalEvalCaseSplitEnumMap[instance.split]!,
      'consentGranted': instance.consentGranted,
      'consentedAt': instance.consentedAt?.toIso8601String(),
      'sessionLogPath': instance.sessionLogPath,
      'sessionLogSummary': instance.sessionLogSummary,
    };

const _$PersonalEvalVerificationResultEnumMap = {
  PersonalEvalVerificationResult.passed: 'passed',
  PersonalEvalVerificationResult.failed: 'failed',
  PersonalEvalVerificationResult.inconclusive: 'inconclusive',
};

const _$PersonalEvalCaseSplitEnumMap = {
  PersonalEvalCaseSplit.heldIn: 'heldIn',
  PersonalEvalCaseSplit.heldOut: 'heldOut',
};
