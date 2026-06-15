// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'personal_eval_session_log_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PersonalEvalSessionLogSummary _$PersonalEvalSessionLogSummaryFromJson(
  Map<String, dynamic> json,
) => _PersonalEvalSessionLogSummary(
  result: json['result'] as String? ?? 'incomplete',
  entryCount: (json['entryCount'] as num?)?.toInt() ?? 0,
  turnCount: (json['turnCount'] as num?)?.toInt() ?? 0,
  malformedLineCount: (json['malformedLineCount'] as num?)?.toInt() ?? 0,
  toolCallCount: (json['toolCallCount'] as num?)?.toInt() ?? 0,
  totalDurationMs: (json['totalDurationMs'] as num?)?.toInt() ?? 0,
  operationCounts:
      (json['operationCounts'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, (e as num).toInt()),
      ) ??
      const <String, int>{},
  finishReasonCounts:
      (json['finishReasonCounts'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, (e as num).toInt()),
      ) ??
      const <String, int>{},
  warningCodes:
      (json['warningCodes'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const <String>[],
  finalAnswerLineNumber: (json['finalAnswerLineNumber'] as num?)?.toInt(),
);

Map<String, dynamic> _$PersonalEvalSessionLogSummaryToJson(
  _PersonalEvalSessionLogSummary instance,
) => <String, dynamic>{
  'result': instance.result,
  'entryCount': instance.entryCount,
  'turnCount': instance.turnCount,
  'malformedLineCount': instance.malformedLineCount,
  'toolCallCount': instance.toolCallCount,
  'totalDurationMs': instance.totalDurationMs,
  'operationCounts': instance.operationCounts,
  'finishReasonCounts': instance.finishReasonCounts,
  'warningCodes': instance.warningCodes,
  'finalAnswerLineNumber': ?instance.finalAnswerLineNumber,
};
