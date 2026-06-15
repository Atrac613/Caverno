import '../../chat/data/datasources/llm_session_log_store.dart';
import '../domain/entities/personal_eval_case.dart';
import '../domain/services/personal_eval_case_recorder.dart';

/// Thrown when recording is requested for a session that has no log on disk.
class PersonalEvalSessionLogNotFoundException implements Exception {
  const PersonalEvalSessionLogNotFoundException(this.path);

  final String path;

  @override
  String toString() =>
      'PersonalEvalSessionLogNotFoundException: no session log at $path';
}

/// LL19 data layer: turns a recorded session into a [PersonalEvalCase].
///
/// Resolves the session's log file through [LlmSessionLogStore], reads it, and
/// delegates assembly to the pure [PersonalEvalCaseRecorder]. Consent is
/// checked before any file IO so a non-consented session is never read.
class PersonalEvalCaseRecordingService {
  PersonalEvalCaseRecordingService({
    required LlmSessionLogStore sessionLogStore,
    PersonalEvalCaseRecorder recorder = const PersonalEvalCaseRecorder(),
  }) : _sessionLogStore = sessionLogStore,
       _recorder = recorder;

  final LlmSessionLogStore _sessionLogStore;
  final PersonalEvalCaseRecorder _recorder;

  Future<PersonalEvalCase> recordFromSession({
    required LlmSessionLogContext context,
    required bool consentGranted,
    required String prompt,
    required String repoStateRef,
    String? caseId,
    String title = '',
    String? verificationCommand,
    PersonalEvalVerificationResult verificationResult =
        PersonalEvalVerificationResult.inconclusive,
    PersonalEvalCaseSplit split = PersonalEvalCaseSplit.heldIn,
    DateTime? recordedAt,
  }) async {
    if (!consentGranted) {
      throw const PersonalEvalCaseRecordingDeniedException();
    }
    final file = await _sessionLogStore.fileForContext(context);
    if (!file.existsSync()) {
      throw PersonalEvalSessionLogNotFoundException(file.path);
    }
    final contents = await file.readAsString();
    return _recorder.record(
      consentGranted: consentGranted,
      prompt: prompt,
      repoStateRef: repoStateRef,
      sessionLogPath: file.path,
      sessionLogContents: contents,
      caseId: caseId,
      title: title,
      verificationCommand: verificationCommand,
      verificationResult: verificationResult,
      workspaceMode: context.workspaceMode.name,
      split: split,
      recordedAt: recordedAt,
    );
  }
}
