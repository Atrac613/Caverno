import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/personal_eval/data/personal_eval_case_recording_service.dart';
import 'package:caverno/features/personal_eval/data/personal_eval_case_repository.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_case_recorder.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/presentation/providers/personal_eval_cases_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late PersonalEvalCaseRepository repository;
  late LlmSessionLogStore sessionLogStore;
  late ProviderContainer container;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pe_cases_notifier_test');
    repository = PersonalEvalCaseRepository(
      rootDirectoryProvider: () async => tempDir,
    );
    sessionLogStore = LlmSessionLogStore(
      rootDirectoryProvider: () async => tempDir,
    );
    container = ProviderContainer(
      overrides: [
        personalEvalCaseRepositoryProvider.overrideWithValue(repository),
        personalEvalCaseRecordingServiceProvider.overrideWithValue(
          PersonalEvalCaseRecordingService(sessionLogStore: sessionLogStore),
        ),
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

  test('recordFromSession stores a recorded case and reloads state', () async {
    const context = LlmSessionLogContext(
      workspaceMode: WorkspaceMode.coding,
      sessionId: 'session-7',
    );
    final logFile = await sessionLogStore.fileForContext(context);
    await logFile.writeAsString(
      jsonEncode({
        'operation': 'chat',
        'durationMs': 90,
        'request': {'messages': []},
        'response': {'content': 'Done.', 'finishReason': 'stream_end'},
      }),
    );
    await read();
    final notifier = container.read(personalEvalCasesNotifierProvider.notifier);

    final recorded = await notifier.recordFromSession(
      context: context,
      consentGranted: true,
      prompt: 'Fix the login crash',
      repoStateRef: 'abc123',
      verificationCommand: 'flutter test',
      verificationResult: PersonalEvalVerificationResult.passed,
    );

    expect(recorded.caseId, 'case_session-7');
    expect(recorded.sessionLogSummary?.result, 'complete');

    final stored = container.read(personalEvalCasesNotifierProvider).value;
    expect(stored, hasLength(1));
    expect(stored!.single.caseId, 'case_session-7');
    // Persisted to the repository, not just held in memory.
    expect(await repository.loadAll(), hasLength(1));
  });

  test('recordFromSession without consent records nothing', () async {
    const context = LlmSessionLogContext(
      workspaceMode: WorkspaceMode.coding,
      sessionId: 'session-7',
    );
    await (await sessionLogStore.fileForContext(context)).writeAsString('{}');
    await read();
    final notifier = container.read(personalEvalCasesNotifierProvider.notifier);

    await expectLater(
      notifier.recordFromSession(
        context: context,
        consentGranted: false,
        prompt: 'p',
        repoStateRef: 'r',
      ),
      throwsA(isA<PersonalEvalCaseRecordingDeniedException>()),
    );
    expect(await repository.loadAll(), isEmpty);
  });
}
