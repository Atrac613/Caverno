import 'package:freezed_annotation/freezed_annotation.dart';

import 'personal_eval_session_log_summary.dart';

part 'personal_eval_case.freezed.dart';
part 'personal_eval_case.g.dart';

/// Verification outcome recorded for a personal eval case. Values mirror what
/// the offline `tool/personal_eval_*` pipeline consumes.
enum PersonalEvalVerificationResult { passed, failed, inconclusive }

/// Self-Harness held-in / held-out split (docs/local_llm_agent_roadmap.md,
/// LL17 / LL19). The proposer only mines failures from held-in cases; held-out
/// cases stay hidden and serve as the regression gate.
enum PersonalEvalCaseSplit { heldIn, heldOut }

/// Readiness of a recorded case, matching the CLI manifest readiness values.
enum PersonalEvalCaseReadiness { ready, reviewRecommended, blocked }

/// LL19: an in-app personal eval case (docs/local_llm_agent_roadmap.md).
///
/// Represents a recorded real task that can be replayed to score a candidate
/// model. Cases are local-only and excluded from export by design. This entity
/// is the in-app counterpart of the offline
/// `caverno_personal_eval_case_manifest` schema; the session-log summary
/// (`source`) is attached by the recorder service in a later slice.
@freezed
abstract class PersonalEvalCase with _$PersonalEvalCase {
  const PersonalEvalCase._();

  const factory PersonalEvalCase({
    required String caseId,
    required String prompt,
    required String repoStateRef,
    @Default('') String title,
    DateTime? createdAt,
    String? verificationCommand,
    @JsonKey(unknownEnumValue: PersonalEvalVerificationResult.inconclusive)
    @Default(PersonalEvalVerificationResult.inconclusive)
    PersonalEvalVerificationResult verificationResult,
    String? workspaceMode,
    @JsonKey(unknownEnumValue: PersonalEvalCaseSplit.heldIn)
    @Default(PersonalEvalCaseSplit.heldIn)
    PersonalEvalCaseSplit split,
    @Default(false) bool consentGranted,
    DateTime? consentedAt,
    @Default('') String sessionLogPath,
    PersonalEvalSessionLogSummary? sessionLogSummary,
  }) = _PersonalEvalCase;

  factory PersonalEvalCase.fromJson(Map<String, dynamic> json) =>
      _$PersonalEvalCaseFromJson(json);

  static const caseManifestSchemaName = 'caverno_personal_eval_case_manifest';
  static const caseManifestSchemaVersion = 1;

  String get normalizedPrompt => prompt.trim();

  String get normalizedRepoStateRef => repoStateRef.trim();

  bool get hasVerificationCommand =>
      verificationCommand != null && verificationCommand!.trim().isNotEmpty;

  /// Cases are local-only and excluded from any export by default.
  bool get excludedFromExport => true;

  /// Mirrors the CLI manifest readiness: a case is blocked without consent or
  /// the required task fields, review-recommended when it has no reproducible
  /// verification command, and ready otherwise.
  PersonalEvalCaseReadiness get readiness {
    if (!consentGranted ||
        normalizedPrompt.isEmpty ||
        normalizedRepoStateRef.isEmpty) {
      return PersonalEvalCaseReadiness.blocked;
    }
    if (!hasVerificationCommand) {
      return PersonalEvalCaseReadiness.reviewRecommended;
    }
    return PersonalEvalCaseReadiness.ready;
  }

  /// Builds a JSON artifact compatible with the offline
  /// `caverno_personal_eval_case_manifest` schema. The `source` session-log
  /// summary is attached by the in-app recorder service in a later slice.
  Map<String, dynamic> toCaseManifestJson() {
    final generatedAt = (createdAt ?? DateTime.now()).toUtc();
    return {
      'schemaName': caseManifestSchemaName,
      'schemaVersion': caseManifestSchemaVersion,
      'generatedAt': generatedAt.toIso8601String(),
      'caseId': caseId,
      'title': title,
      'readiness': _readinessJsonValue(readiness),
      'split': split.name,
      'task': <String, dynamic>{
        'prompt': normalizedPrompt,
        'repoStateRef': normalizedRepoStateRef,
        if (hasVerificationCommand)
          'verificationCommand': verificationCommand!.trim(),
        'verificationResult': verificationResult.name,
        if (workspaceMode != null && workspaceMode!.trim().isNotEmpty)
          'workspaceMode': workspaceMode!.trim(),
      },
      if (sessionLogSummary != null)
        'source': sessionLogSummary!.toCaseManifestSourceJson(
          sessionLogPath: sessionLogPath,
        ),
      'consent': <String, dynamic>{
        'explicitUserConsent': consentGranted,
        'recordedAt': (consentedAt ?? generatedAt).toUtc().toIso8601String(),
        'scope': 'personal_eval_case_recording',
      },
      'privacy': const <String, dynamic>{
        'localOnly': true,
        'anonymization': 'none',
        'exportPolicy': 'excluded_by_default',
      },
    };
  }

  static String _readinessJsonValue(PersonalEvalCaseReadiness readiness) {
    return switch (readiness) {
      PersonalEvalCaseReadiness.ready => 'ready',
      PersonalEvalCaseReadiness.reviewRecommended => 'review_recommended',
      PersonalEvalCaseReadiness.blocked => 'blocked',
    };
  }
}
