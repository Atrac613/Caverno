import '../entities/personal_eval_case.dart';
import '../entities/personal_eval_session_log_summary.dart';

/// Thrown when a personal eval case is recorded without explicit user consent.
///
/// Recording captures the user's real prompts and repo state, so consent is
/// mandatory, mirroring the offline tool's `--consent` gate.
class PersonalEvalCaseRecordingDeniedException implements Exception {
  const PersonalEvalCaseRecordingDeniedException();

  @override
  String toString() =>
      'PersonalEvalCaseRecordingDeniedException: explicit user consent is '
      'required to record a personal eval case.';
}

/// LL19: builds a [PersonalEvalCase] from a completed session's log
/// (docs/local_llm_agent_roadmap.md).
///
/// This is the pure, contents-based core of in-app recording: it parses the
/// `LlmSessionLogStore` JSONL into a summary, attaches it as the case `source`,
/// and produces a CLI-compatible case. File/store wiring lives in a thin data
/// layer on top so this stays unit-testable without file IO.
class PersonalEvalCaseRecorder {
  const PersonalEvalCaseRecorder();

  PersonalEvalCase record({
    required bool consentGranted,
    required String prompt,
    required String repoStateRef,
    required String sessionLogPath,
    required String sessionLogContents,
    String? caseId,
    String title = '',
    String? verificationCommand,
    PersonalEvalVerificationResult verificationResult =
        PersonalEvalVerificationResult.inconclusive,
    String? workspaceMode,
    PersonalEvalCaseSplit split = PersonalEvalCaseSplit.heldIn,
    DateTime? recordedAt,
  }) {
    if (!consentGranted) {
      throw const PersonalEvalCaseRecordingDeniedException();
    }
    final summary = PersonalEvalSessionLogSummary.parseLogContents(
      sessionLogContents,
    );
    final timestamp = recordedAt ?? DateTime.now();
    return PersonalEvalCase(
      caseId: _resolveCaseId(caseId, sessionLogPath, timestamp),
      title: title,
      prompt: prompt,
      repoStateRef: repoStateRef,
      verificationCommand: verificationCommand,
      verificationResult: verificationResult,
      workspaceMode: workspaceMode,
      split: split,
      consentGranted: true,
      consentedAt: timestamp,
      createdAt: timestamp,
      sessionLogPath: sessionLogPath,
      sessionLogSummary: summary,
    );
  }

  /// Derives a stable case id from the session log file name when the caller
  /// does not supply one, so re-recording the same session reuses the id.
  String _resolveCaseId(
    String? caseId,
    String sessionLogPath,
    DateTime timestamp,
  ) {
    final provided = caseId?.trim() ?? '';
    if (provided.isNotEmpty) {
      return provided;
    }
    final base = sessionLogPath.split(RegExp(r'[\\/]')).last.trim();
    final stem = base.endsWith('.jsonl')
        ? base.substring(0, base.length - '.jsonl'.length)
        : base;
    if (stem.isNotEmpty) {
      return 'case_$stem';
    }
    return 'case_${timestamp.toUtc().millisecondsSinceEpoch}';
  }
}
