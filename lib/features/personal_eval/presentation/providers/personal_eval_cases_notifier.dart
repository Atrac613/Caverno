import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../chat/data/datasources/chat_remote_datasource.dart';
import '../../../chat/data/datasources/llm_session_log_store.dart';
import '../../../chat/data/datasources/session_logging_chat_datasource.dart';
import '../../../chat/presentation/providers/chat_notifier.dart';
import '../../../chat/presentation/providers/coding_projects_notifier.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';
import '../../data/personal_eval_case_recording_service.dart';
import '../../data/personal_eval_case_repository.dart';
import '../../data/personal_eval_chat_replay_turn_driver.dart';
import '../../domain/entities/personal_eval_case.dart';
import '../../domain/entities/personal_eval_replay_run.dart';
import '../../domain/services/live_personal_eval_case_runner.dart';
import '../../domain/services/personal_eval_replay_orchestrator.dart';
import '../../domain/services/personal_eval_verification_runner.dart';

/// Local-only personal eval case store (LL19).
final personalEvalCaseRepositoryProvider = Provider<PersonalEvalCaseRepository>(
  (ref) => PersonalEvalCaseRepository(),
);

/// Drives a candidate model through a recorded case (LL19). Reuses the active
/// model/endpoint and the session-logging chat datasource so the replay log is
/// captured the same way a real turn is.
final personalEvalReplayTurnDriverProvider =
    Provider<PersonalEvalReplayTurnDriver>((ref) {
      final settings = ref.watch(settingsNotifierProvider);
      final rawDataSource = ref.watch(chatRemoteDataSourceProvider);
      final logStore = ref.watch(llmSessionLogStoreProvider);
      final loggingEnabled = LlmSessionLogStore.isEnabled(
        settingsEnabled: settings.enableLlmSessionLogs,
      );
      final dataSource =
          !loggingEnabled ||
              settings.demoMode ||
              rawDataSource is! ChatRemoteDataSource
          ? rawDataSource
          : SessionLoggingChatDataSource(
              delegate: rawDataSource,
              logStore: logStore,
            );
      final workingDirectory =
          ref.watch(codingProjectsNotifierProvider).selectedProject?.rootPath ??
          '';
      return PersonalEvalChatReplayTurnDriver(
        dataSource: dataSource,
        sessionLogStore: logStore,
        model: settings.model,
        workingDirectory: workingDirectory,
        temperature: settings.temperature,
        maxTokens: settings.maxTokens,
      );
    });

/// Runs a recorded case's verification command (LL19).
final personalEvalVerificationRunnerProvider =
    Provider<PersonalEvalVerificationRunner>(
      (ref) => ProcessPersonalEvalVerificationRunner(),
    );

/// The live [PersonalEvalCaseRunner] used by replay runs. Override in tests to
/// inject a fake runner without touching the network or the filesystem.
final personalEvalCaseRunnerProvider = Provider<PersonalEvalCaseRunner>((ref) {
  return LivePersonalEvalCaseRunner(
    turnDriver: ref.watch(personalEvalReplayTurnDriverProvider),
    verificationRunner: ref.watch(personalEvalVerificationRunnerProvider),
  );
});

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

  static const PersonalEvalReplayOrchestrator _orchestrator =
      PersonalEvalReplayOrchestrator();

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

  /// Replays a single recorded case through the candidate model and returns a
  /// one-case [PersonalEvalReplayRun]. The orchestrator never throws on a
  /// broken case, so the caller always gets a result to display.
  Future<PersonalEvalReplayRun> replayCase(String caseId) async {
    final cases = state.value ?? await _repository.loadAll();
    final evalCase = cases.firstWhere((item) => item.caseId == caseId);
    final settings = ref.read(settingsNotifierProvider);
    return _orchestrator.run(
      label: 'replay',
      model: settings.model,
      baseUrl: settings.baseUrl.trim(),
      cases: [evalCase],
      runner: ref.read(personalEvalCaseRunnerProvider),
    );
  }
}
