import 'dart:convert';

import 'package:caverno/features/personal_eval/domain/entities/personal_eval_case.dart';
import 'package:caverno/features/personal_eval/domain/services/personal_eval_case_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const recorder = PersonalEvalCaseRecorder();

  String log() => [
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
      'response': {'content': 'All tests pass.', 'finishReason': 'stream_end'},
    }),
  ].join('\n');

  test('refuses to record without explicit consent', () {
    expect(
      () => recorder.record(
        consentGranted: false,
        prompt: 'Fix the bug',
        repoStateRef: 'abc123',
        sessionLogPath: '/logs/s1.jsonl',
        sessionLogContents: log(),
      ),
      throwsA(isA<PersonalEvalCaseRecordingDeniedException>()),
    );
  });

  test('records a case with the parsed session-log summary as source', () {
    final recordedAt = DateTime.utc(2026, 6, 15, 9, 0, 0);
    final result = recorder.record(
      consentGranted: true,
      prompt: 'Fix the login crash',
      repoStateRef: 'abc123',
      verificationCommand: 'flutter test',
      verificationResult: PersonalEvalVerificationResult.passed,
      workspaceMode: 'coding',
      split: PersonalEvalCaseSplit.heldOut,
      sessionLogPath: '/logs/session-7.jsonl',
      sessionLogContents: log(),
      recordedAt: recordedAt,
    );

    expect(result.consentGranted, isTrue);
    expect(result.consentedAt, recordedAt);
    expect(result.readiness, PersonalEvalCaseReadiness.ready);
    // Case id is derived from the session log file name.
    expect(result.caseId, 'case_session-7');

    final summary = result.sessionLogSummary;
    expect(summary, isNotNull);
    expect(summary!.result, 'complete');
    expect(summary.toolCallCount, 1);
    expect(summary.totalDurationMs, 200);

    // The manifest now carries a CLI-compatible source block.
    final manifest = result.toCaseManifestJson();
    final source = manifest['source'] as Map<String, dynamic>;
    expect(source['sessionLogPath'], '/logs/session-7.jsonl');
    final embedded = source['sessionLogSummary'] as Map<String, dynamic>;
    expect(embedded['result'], 'complete');
    expect(embedded['toolCallCount'], 1);
  });

  test('prefers an explicit case id over the derived one', () {
    final result = recorder.record(
      consentGranted: true,
      caseId: 'custom-case',
      prompt: 'p',
      repoStateRef: 'r',
      sessionLogPath: '/logs/session-7.jsonl',
      sessionLogContents: log(),
    );

    expect(result.caseId, 'custom-case');
  });
}
