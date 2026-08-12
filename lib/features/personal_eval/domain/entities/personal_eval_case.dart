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

/// Where a case came from.
///
/// The two are not interchangeable evidence and must never be reported as if
/// they were. A `recorded` case is a real task this user actually ran, so it
/// carries representativeness. An `authored` case is a task written against a
/// committed fixture: reproducible and available immediately, but it measures
/// coding capability in general, not this user's work. The 2026-08-12 corpus
/// inventory found roughly two distinct recorded coding tasks against a
/// requirement of twenty, so an authored corpus carries the comparison until
/// recorded cases accumulate — which only stays honest if the origin travels
/// with the case.
enum PersonalEvalCaseOrigin { recorded, authored }

/// Prompt localization used by the authored capability corpus.
///
/// Recorded and legacy cases remain [unclassified]. The distinction is kept
/// separate from difficulty because removing file and behavior hints changed
/// turns but did not explain the observed outcome divergence.
enum PersonalEvalPromptStyle { unclassified, guided, unguided }

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
    @JsonKey(unknownEnumValue: PersonalEvalCaseOrigin.recorded)
    @Default(PersonalEvalCaseOrigin.recorded)
    PersonalEvalCaseOrigin origin,
    @Default(0) int tier,
    @JsonKey(unknownEnumValue: PersonalEvalPromptStyle.unclassified)
    @Default(PersonalEvalPromptStyle.unclassified)
    PersonalEvalPromptStyle promptStyle,

    /// Fixture directory an authored case runs in, relative to the repository
    /// root. Empty for recorded cases, which replay against [repoStateRef].
    ///
    /// Authored cases must never run in the user's working tree: LL19 has not
    /// shipped worktree isolation yet, so a replay edits whatever directory it
    /// is given.
    @Default('') String fixtureDirectory,
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

  bool get isAuthored => origin == PersonalEvalCaseOrigin.authored;

  String get normalizedFixtureDirectory => fixtureDirectory.trim();

  int? get classifiedTier => tier >= 1 && tier <= 3 ? tier : null;

  bool get hasClassifiedPromptStyle =>
      promptStyle != PersonalEvalPromptStyle.unclassified;

  /// Recorded cases are the user's own work and never leave the machine.
  /// Authored cases are committed fixture tasks with no private content, so
  /// excluding them from export would only make the corpus unshareable.
  bool get excludedFromExport => !isAuthored;

  /// Mirrors the CLI manifest readiness: a case is blocked without consent or
  /// the required task fields, review-recommended when it has no reproducible
  /// verification command, and ready otherwise.
  ///
  /// Authored cases are judged on reproducibility instead of consent. There is
  /// no user data to consent to, and their repository state is the committed
  /// fixture rather than a recorded ref — but a missing fixture directory
  /// blocks them, because a replay with nowhere to run would edit whatever
  /// working tree it was handed.
  PersonalEvalCaseReadiness get readiness {
    if (normalizedPrompt.isEmpty) {
      return PersonalEvalCaseReadiness.blocked;
    }
    if (isAuthored) {
      if (normalizedFixtureDirectory.isEmpty) {
        return PersonalEvalCaseReadiness.blocked;
      }
      return hasVerificationCommand
          ? PersonalEvalCaseReadiness.ready
          : PersonalEvalCaseReadiness.reviewRecommended;
    }
    if (!consentGranted || normalizedRepoStateRef.isEmpty) {
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
      // Origin travels with every artifact: a report that mixes authored and
      // recorded evidence without saying so would read as representative of
      // the user's work when it is not.
      'origin': origin.name,
      if (classifiedTier != null) 'tier': classifiedTier,
      if (hasClassifiedPromptStyle) 'promptStyle': promptStyle.name,
      'task': <String, dynamic>{
        'prompt': normalizedPrompt,
        'repoStateRef': normalizedRepoStateRef,
        if (normalizedFixtureDirectory.isNotEmpty)
          'fixtureDirectory': normalizedFixtureDirectory,
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
        'scope': isAuthored
            ? 'personal_eval_authored_fixture_task'
            : 'personal_eval_case_recording',
      },
      'privacy': <String, dynamic>{
        'localOnly': !isAuthored,
        'anonymization': 'none',
        'exportPolicy': isAuthored ? 'shareable' : 'excluded_by_default',
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
