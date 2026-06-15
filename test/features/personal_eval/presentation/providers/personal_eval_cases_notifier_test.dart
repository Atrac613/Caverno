import 'dart:io';

import 'package:caverno/features/personal_eval/data/personal_eval_case_repository.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/presentation/providers/personal_eval_cases_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late PersonalEvalCaseRepository repository;
  late ProviderContainer container;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pe_cases_notifier_test');
    repository = PersonalEvalCaseRepository(
      rootDirectoryProvider: () async => tempDir,
    );
    container = ProviderContainer(
      overrides: [
        personalEvalCaseRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  PersonalEvalCase caseWith(String id, {PersonalEvalCaseSplit? split}) {
    return PersonalEvalCase(
      caseId: id,
      prompt: 'p',
      repoStateRef: 'r',
      consentGranted: true,
      split: split ?? PersonalEvalCaseSplit.heldIn,
    );
  }

  Future<List<PersonalEvalCase>> read() =>
      container.read(personalEvalCasesNotifierProvider.future);

  test('loads stored cases', () async {
    await repository.save(caseWith('a'));
    expect((await read()).map((c) => c.caseId), ['a']);
  });

  test('setSplit reassigns and reloads state', () async {
    await repository.save(caseWith('a'));
    await read();
    final notifier = container.read(personalEvalCasesNotifierProvider.notifier);

    await notifier.setSplit('a', PersonalEvalCaseSplit.heldOut);

    expect(
      notifier
          .casesForSplit(PersonalEvalCaseSplit.heldOut)
          .map((c) => c.caseId),
      ['a'],
    );
    expect(notifier.casesForSplit(PersonalEvalCaseSplit.heldIn), isEmpty);
  });

  test('delete removes a case and reloads state', () async {
    await repository.save(caseWith('a'));
    await read();
    final notifier = container.read(personalEvalCasesNotifierProvider.notifier);

    await notifier.delete('a');

    expect(container.read(personalEvalCasesNotifierProvider).value, isEmpty);
  });
}
