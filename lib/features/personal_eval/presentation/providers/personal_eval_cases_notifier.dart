import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/data/datasources/llm_session_log_store.dart';
import '../../../chat/data/datasources/session_logging_chat_datasource.dart';
import '../../data/personal_eval_case_recording_service.dart';
import '../../data/personal_eval_case_repository.dart';
import '../../domain/entities/personal_eval_case.dart';

/// Local-only personal eval case store (LL19).
final personalEvalCaseRepositoryProvider = Provider<PersonalEvalCaseRepository>(
  (ref) => PersonalEvalCaseRepository(),
);

/// Records a completed session as a personal eval case, reading the session
/// log through the shared [LlmSessionLogStore].
final personalEvalCaseRecordingServiceProvider =
    Provider<PersonalEvalCaseRecordingService>(
      (ref) => PersonalEvalCaseRecordingService(
        sessionLogStore: ref.read(llmSessionLogStoreProvider),
      ),
    );

/// Exposes the recorded personal eval cases and their held-in / held-out
/// management to the UI.
final personalEvalCasesNotifierProvider =
    AsyncNotifierProvider<PersonalEvalCasesNotifier, List<PersonalEvalCase>>(
      PersonalEvalCasesNotifier.new,
    );

class PersonalEvalCasesNotifier extends AsyncNotifier<List<PersonalEvalCase>> {
  PersonalEvalCaseRepository get _repository =>
      ref.read(personalEvalCaseRepositoryProvider);

  PersonalEvalCaseRecordingService get _recordingService =>
      ref.read(personalEvalCaseRecordingServiceProvider);

  @override
  Future<List<PersonalEvalCase>> build() => _repository.loadAll();

  List<PersonalEvalCase> _casesForSplit(
    List<PersonalEvalCase> cases,
    PersonalEvalCaseSplit split,
  ) {
    return cases.where((item) => item.split == split).toList(growable: false);
  }

  /// Cases on the given split from the current state (empty while loading).
  List<PersonalEvalCase> casesForSplit(PersonalEvalCaseSplit split) {
    return _casesForSplit(state.value ?? const [], split);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_repository.loadAll);
  }

  Future<void> setSplit(String caseId, PersonalEvalCaseSplit split) async {
    await _repository.setSplit(caseId, split);
    await refresh();
  }

  Future<void> delete(String caseId) async {
    await _repository.delete(caseId);
    await refresh();
  }

  /// Records the given session as a case, stores it locally, and refreshes the
  /// list. Requires explicit consent (the recorder throws otherwise) and a
  /// session log on disk.
  Future<PersonalEvalCase> recordFromSession({
    required LlmSessionLogContext context,
    required bool consentGranted,
    required String prompt,
    required String repoStateRef,
    String title = '',
    String? verificationCommand,
    PersonalEvalVerificationResult verificationResult =
        PersonalEvalVerificationResult.inconclusive,
    PersonalEvalCaseSplit split = PersonalEvalCaseSplit.heldIn,
  }) async {
    final evalCase = await _recordingService.recordFromSession(
      context: context,
      consentGranted: consentGranted,
      prompt: prompt,
      repoStateRef: repoStateRef,
      title: title,
      verificationCommand: verificationCommand,
      verificationResult: verificationResult,
      split: split,
    );
    await _repository.save(evalCase);
    await refresh();
    return evalCase;
  }
}
