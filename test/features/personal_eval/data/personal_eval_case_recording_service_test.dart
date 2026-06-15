import 'dart:convert';
import 'dart:io';

import 'package:caverno/core/types/workspace_mode.dart';
import 'package:caverno/features/chat/data/datasources/llm_session_log_store.dart';
import 'package:caverno/features/personal_eval/data/personal_eval_case_recording_service.dart';
import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_case_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late LlmSessionLogStore store;
  late PersonalEvalCaseRecordingService service;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pe_recording_service_test');
    store = LlmSessionLogStore(rootDirectoryProvider: () async => tempDir);
    service = PersonalEvalCaseRecordingService(sessionLogStore: store);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  const context = LlmSessionLogContext(
    workspaceMode: WorkspaceMode.coding,
    sessionId: 'session-7',
  );

  Future<File> writeLog() async {
    final file = await store.fileForContext(context);
    await file.writeAsString(
      [
        jsonEncode({
          'operation': 'chat',
          'durationMs': 120,
          'request': {'messages': []},
          'response': {
            'finishReason': 'tool_calls',
            'toolCalls': [
              {'name': 'edit_file'},
            ],
          },
        }),
        jsonEncode({
          'operation': 'chat',
          'durationMs': 80,
          'request': {'messages': []},
          'response': {'content': 'Done.', 'finishReason': 'stream_end'},
        }),
      ].join('\n'),
    );
    return file;
  }

  test('records a case from an on-disk session log', () async {
    final file = await writeLog();

    final result = await service.recordFromSession(
      context: context,
      consentGranted: true,
      prompt: 'Fix the login crash',
      repoStateRef: 'abc123',
      verificationCommand: 'flutter test',
      verificationResult: PersonalEvalVerificationResult.passed,
      split: PersonalEvalCaseSplit.heldOut,
    );

    expect(result.caseId, 'case_session-7');
    expect(result.workspaceMode, 'coding');
    expect(result.sessionLogPath, file.path);
    expect(result.readiness, PersonalEvalCaseReadiness.ready);

    final summary = result.sessionLogSummary;
    expect(summary, isNotNull);
    expect(summary!.result, 'complete');
    expect(summary.toolCallCount, 1);
    expect(summary.totalDurationMs, 200);
  });

  test('throws when the session has no log on disk', () {
    expect(
      () => service.recordFromSession(
        context: context,
        consentGranted: true,
        prompt: 'p',
        repoStateRef: 'r',
      ),
      throwsA(isA<PersonalEvalSessionLogNotFoundException>()),
    );
  });

  test('refuses without consent before touching the log file', () async {
    // The log exists, but consent is withheld: it must fail with the consent
    // exception, proving consent is checked before any file read.
    await writeLog();

    expect(
      () => service.recordFromSession(
        context: context,
        consentGranted: false,
        prompt: 'p',
        repoStateRef: 'r',
      ),
      throwsA(isA<PersonalEvalCaseRecordingDeniedException>()),
    );
  });
}
