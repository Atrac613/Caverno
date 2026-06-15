import 'package:freezed_annotation/freezed_annotation.dart';

import 'personal_eval_case.dart';
import 'personal_eval_session_log_summary.dart';

part 'personal_eval_replay_run.freezed.dart';
part 'personal_eval_replay_run.g.dart';

/// LL19: the per-case outcome of replaying a candidate model through a case.
@freezed
abstract class PersonalEvalReplayCaseResult
    with _$PersonalEvalReplayCaseResult {
  const PersonalEvalReplayCaseResult._();

  const factory PersonalEvalReplayCaseResult({
    required String caseId,
    @Default('') String title,
    @JsonKey(unknownEnumValue: PersonalEvalCaseSplit.heldIn)
    @Default(PersonalEvalCaseSplit.heldIn)
    PersonalEvalCaseSplit split,
    @Default('') String logPath,
    @JsonKey(unknownEnumValue: PersonalEvalVerificationResult.inconclusive)
    @Default(PersonalEvalVerificationResult.inconclusive)
    PersonalEvalVerificationResult verificationResult,
    @Default(PersonalEvalSessionLogSummary())
    PersonalEvalSessionLogSummary summary,
    String? error,
  }) = _PersonalEvalReplayCaseResult;

  factory PersonalEvalReplayCaseResult.fromJson(Map<String, dynamic> json) =>
      _$PersonalEvalReplayCaseResultFromJson(json);

  int get durationMs => summary.totalDurationMs;
  int get toolCallCount => summary.toolCallCount;
  int get turnCount => summary.turnCount;
  String get summaryResult => summary.result;

  bool get isPassed =>
      verificationResult == PersonalEvalVerificationResult.passed;

  /// Per-case entry of the `caverno_personal_eval_replay_run` artifact.
  Map<String, dynamic> toReplayCaseJson() {
    return {
      'caseId': caseId,
      'title': title,
      'logPath': logPath,
      'verificationResult': verificationResult.name,
      'durationMs': durationMs,
      'toolCallCount': toolCallCount,
      'turnCount': turnCount,
      'summaryResult': summaryResult,
      'warningCodes': summary.warningCodes,
      if (error != null) 'error': error,
    };
  }
}

/// LL19: an in-app replay run, the domain counterpart of the offline
/// `caverno_personal_eval_replay_run` artifact (docs/local_llm_agent_roadmap.md).
@freezed
abstract class PersonalEvalReplayRun with _$PersonalEvalReplayRun {
  const PersonalEvalReplayRun._();

  const factory PersonalEvalReplayRun({
    required String label,
    String? model,
    String? baseUrl,
    DateTime? generatedAt,
    @Default(<String>[]) List<String> manifestPaths,
    @Default(<PersonalEvalReplayCaseResult>[])
    List<PersonalEvalReplayCaseResult> cases,
  }) = _PersonalEvalReplayRun;

  factory PersonalEvalReplayRun.fromJson(Map<String, dynamic> json) =>
      _$PersonalEvalReplayRunFromJson(json);

  static const replayRunSchemaName = 'caverno_personal_eval_replay_run';
  static const replayRunSchemaVersion = 1;

  int get caseCount => cases.length;

  int countWhere(PersonalEvalVerificationResult result) =>
      cases.where((entry) => entry.verificationResult == result).length;

  int get passedCount => countWhere(PersonalEvalVerificationResult.passed);

  int get failedCount => countWhere(PersonalEvalVerificationResult.failed);

  int get inconclusiveCount =>
      countWhere(PersonalEvalVerificationResult.inconclusive);

  int get totalDurationMs =>
      cases.fold(0, (total, entry) => total + entry.durationMs);

  int get totalToolCallCount =>
      cases.fold(0, (total, entry) => total + entry.toolCallCount);

  /// A run is successful only when every case verifies as passed.
  bool get isSuccessful => failedCount == 0 && inconclusiveCount == 0;

  /// Cases on the given held-in / held-out split, for the Self-Harness gate.
  List<PersonalEvalReplayCaseResult> casesForSplit(
    PersonalEvalCaseSplit split,
  ) {
    return cases.where((entry) => entry.split == split).toList(growable: false);
  }

  int passedCountForSplit(PersonalEvalCaseSplit split) =>
      casesForSplit(split).where((entry) => entry.isPassed).length;

  /// The `caverno_personal_eval_replay_run` artifact consumable by the offline
  /// suite comparison.
  Map<String, dynamic> toReplayRunJson() {
    return {
      'schemaName': replayRunSchemaName,
      'schemaVersion': replayRunSchemaVersion,
      'generatedAt': (generatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'label': label,
      if (model != null) 'model': model,
      if (baseUrl != null) 'baseUrl': baseUrl,
      'manifestPaths': manifestPaths,
      'caseCount': caseCount,
      'passedCount': passedCount,
      'failedCount': failedCount,
      'inconclusiveCount': inconclusiveCount,
      'totalDurationMs': totalDurationMs,
      'totalToolCallCount': totalToolCallCount,
      'cases': cases
          .map((entry) => entry.toReplayCaseJson())
          .toList(growable: false),
    };
  }
}
