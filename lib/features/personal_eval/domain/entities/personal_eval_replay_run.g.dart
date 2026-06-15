// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'personal_eval_replay_run.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PersonalEvalReplayCaseResult _$PersonalEvalReplayCaseResultFromJson(
  Map<String, dynamic> json,
) => _PersonalEvalReplayCaseResult(
  caseId: json['caseId'] as String,
  title: json['title'] as String? ?? '',
  split:
      $enumDecodeNullable(
        _$PersonalEvalCaseSplitEnumMap,
        json['split'],
        unknownValue: PersonalEvalCaseSplit.heldIn,
      ) ??
      PersonalEvalCaseSplit.heldIn,
  logPath: json['logPath'] as String? ?? '',
  verificationResult:
      $enumDecodeNullable(
        _$PersonalEvalVerificationResultEnumMap,
        json['verificationResult'],
        unknownValue: PersonalEvalVerificationResult.inconclusive,
      ) ??
      PersonalEvalVerificationResult.inconclusive,
  summary: json['summary'] == null
      ? const PersonalEvalSessionLogSummary()
      : PersonalEvalSessionLogSummary.fromJson(
          json['summary'] as Map<String, dynamic>,
        ),
  error: json['error'] as String?,
);

Map<String, dynamic> _$PersonalEvalReplayCaseResultToJson(
  _PersonalEvalReplayCaseResult instance,
) => <String, dynamic>{
  'caseId': instance.caseId,
  'title': instance.title,
  'split': _$PersonalEvalCaseSplitEnumMap[instance.split]!,
  'logPath': instance.logPath,
  'verificationResult':
      _$PersonalEvalVerificationResultEnumMap[instance.verificationResult]!,
  'summary': instance.summary,
  'error': instance.error,
};

const _$PersonalEvalCaseSplitEnumMap = {
  PersonalEvalCaseSplit.heldIn: 'heldIn',
  PersonalEvalCaseSplit.heldOut: 'heldOut',
};

const _$PersonalEvalVerificationResultEnumMap = {
  PersonalEvalVerificationResult.passed: 'passed',
  PersonalEvalVerificationResult.failed: 'failed',
  PersonalEvalVerificationResult.inconclusive: 'inconclusive',
};

_PersonalEvalReplayRun _$PersonalEvalReplayRunFromJson(
  Map<String, dynamic> json,
) => _PersonalEvalReplayRun(
  label: json['label'] as String,
  model: json['model'] as String?,
  baseUrl: json['baseUrl'] as String?,
  generatedAt: json['generatedAt'] == null
      ? null
      : DateTime.parse(json['generatedAt'] as String),
  manifestPaths:
      (json['manifestPaths'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  cases:
      (json['cases'] as List<dynamic>?)
          ?.map(
            (e) => PersonalEvalReplayCaseResult.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList() ??
      const <PersonalEvalReplayCaseResult>[],
);

Map<String, dynamic> _$PersonalEvalReplayRunToJson(
  _PersonalEvalReplayRun instance,
) => <String, dynamic>{
  'label': instance.label,
  'model': instance.model,
  'baseUrl': instance.baseUrl,
  'generatedAt': instance.generatedAt?.toIso8601String(),
  'manifestPaths': instance.manifestPaths,
  'cases': instance.cases,
};
