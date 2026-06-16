import 'dart:io';

import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_replay_orchestrator.dart';
import 'package:caverno/features/personal_eval/data/personal_eval_case_repository.dart';
import 'package:caverno/features/personal_eval/presentation/providers/personal_eval_cases_notifier.dart';
import 'package:caverno/features/settings/presentation/providers/settings_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resolves each case to a fixed verification result by caseId, so a replay
/// run can be scored without a live model.
class _FakeRunner implements PersonalEvalCaseRunner {
  _FakeRunner(this.results);
  final Map<String, PersonalEvalVerificationResult> results;

  @override
  Future<PersonalEvalCaseRunOutcome> run(PersonalEvalCase evalCase) async {
    return PersonalEvalCaseRunOutcome(
      verificationResult:
          results[evalCase.caseId] ??
          PersonalEvalVerificationResult.inconclusive,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PersonalEvalCaseRepository repository;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pe_replay_all_test');
    repository = PersonalEvalCaseRepository(
      rootDirectoryProvider: () async => tempDir,
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<ProviderContainer> buildContainer(
    PersonalEvalCaseRunner runner,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        personalEvalCaseRepositoryProvider.overrideWithValue(repository),
        personalEvalCaseRunnerFactoryProvider.overrideWithValue((_) => runner),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  PersonalEvalCase caseWith(String id) => PersonalEvalCase(
    caseId: id,
    prompt: 'p',
    repoStateRef: 'r',
    consentGranted: true,
  );

  test('replays every recorded case and scores the run', () async {
    await repository.save(caseWith('a'));
    await repository.save(caseWith('b'));
    final container = await buildContainer(
      _FakeRunner({
        'a': PersonalEvalVerificationResult.passed,
        'b': PersonalEvalVerificationResult.failed,
      }),
    );
    // Ensure the notifier state is loaded with the seeded cases.
    await container.read(personalEvalCasesNotifierProvider.future);

    final run = await container
        .read(personalEvalCasesNotifierProvider.notifier)
        .replayAllCases();

    expect(run.caseCount, 2);
    expect(run.passedCount, 1);
    expect(run.failedCount, 1);
  });

  test('returns an empty run when there are no recorded cases', () async {
    final container = await buildContainer(_FakeRunner(const {}));
    await container.read(personalEvalCasesNotifierProvider.future);

    final run = await container
        .read(personalEvalCasesNotifierProvider.notifier)
        .replayAllCases();

    expect(run.caseCount, 0);
  });
}
