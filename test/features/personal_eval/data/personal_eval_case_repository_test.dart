import 'dart:io';

import 'package:caverno/features/personal_eval/data/personal_eval_case_repository.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_session_log_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late PersonalEvalCaseRepository repository;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pe_case_repo_test');
    repository = PersonalEvalCaseRepository(
      rootDirectoryProvider: () async => tempDir,
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  PersonalEvalCase caseWith({
    required String id,
    PersonalEvalCaseSplit split = PersonalEvalCaseSplit.heldIn,
    String prompt = 'Fix the bug',
  }) {
    return PersonalEvalCase(
      caseId: id,
      prompt: prompt,
      repoStateRef: 'abc123',
      consentGranted: true,
      split: split,
    );
  }

  test('loadAll is empty when nothing is stored', () async {
    expect(await repository.loadAll(), isEmpty);
  });

  test('save upserts by case id and round-trips the summary', () async {
    final withSummary = caseWith(id: 'case-1').copyWith(
      sessionLogPath: '/logs/case-1.jsonl',
      sessionLogSummary: const PersonalEvalSessionLogSummary(
        result: 'complete',
        toolCallCount: 3,
      ),
    );
    await repository.save(withSummary);

    var all = await repository.loadAll();
    expect(all, hasLength(1));
    expect(all.single.sessionLogSummary?.result, 'complete');
    expect(all.single.sessionLogSummary?.toolCallCount, 3);

    // Saving the same id updates in place rather than appending.
    await repository.save(caseWith(id: 'case-1', prompt: 'Updated prompt'));
    all = await repository.loadAll();
    expect(all, hasLength(1));
    expect(all.single.prompt, 'Updated prompt');
  });

  test('rejects a case with an empty id', () {
    expect(
      () => repository.save(caseWith(id: '   ')),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('filters and reassigns the held-in / held-out split', () async {
    await repository.save(caseWith(id: 'in-1'));
    await repository.save(
      caseWith(id: 'out-1', split: PersonalEvalCaseSplit.heldOut),
    );

    expect(
      (await repository.casesForSplit(
        PersonalEvalCaseSplit.heldIn,
      )).map((item) => item.caseId),
      ['in-1'],
    );
    expect(
      (await repository.casesForSplit(
        PersonalEvalCaseSplit.heldOut,
      )).map((item) => item.caseId),
      ['out-1'],
    );

    await repository.setSplit('in-1', PersonalEvalCaseSplit.heldOut);
    expect(
      (await repository.casesForSplit(
        PersonalEvalCaseSplit.heldOut,
      )).map((item) => item.caseId),
      containsAll(['in-1', 'out-1']),
    );
  });

  test('delete removes a stored case', () async {
    await repository.save(caseWith(id: 'case-1'));
    await repository.delete('case-1');
    expect(await repository.loadAll(), isEmpty);
  });

  test('a corrupt store file degrades to an empty list', () async {
    await repository.save(caseWith(id: 'case-1'));
    final file = File('${tempDir.path}/personal_eval/personal_eval_cases.json');
    await file.writeAsString('{ not valid json');

    expect(await repository.loadAll(), isEmpty);
  });
}
