import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/coding_diagnostic_feedback_release_gate.dart';

void main() {
  test('passes complete repeat diagnostic feedback evidence', () async {
    final directory = Directory.systemTemp.createTempSync(
      'diagnostic-feedback-gate-pass-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final summary = _writeSummary(directory, _summaryJson());

    final result = await buildCodingDiagnosticFeedbackReleaseGate(
      summaryFile: summary,
      generatedAt: DateTime.utc(2026, 5, 30),
    );

    expect(result.status, 'ready_for_coding_diagnostic_feedback_release');
    expect(result.blockedGateIds, isEmpty);
    expect(result.isReady, isTrue);
    expect(
      result.toJson()['schemaName'],
      'coding_diagnostic_feedback_release_gate',
    );
    expect(
      result.toMarkdown(),
      contains('Coding Diagnostic Feedback Release Gate'),
    );
    expect(result.feedbackFiles, [
      'lib/main.dart',
      'packages/nested_app/lib/main.dart',
    ]);
  });

  test('blocks summaries that only prove one repeat', () async {
    final directory = Directory.systemTemp.createTempSync(
      'diagnostic-feedback-gate-repeat-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final summary = _writeSummary(
      directory,
      _summaryJson(repeatCount: 1, feedbackCount: 2, diagnosticCount: 3),
    );

    final result = await buildCodingDiagnosticFeedbackReleaseGate(
      summaryFile: summary,
      generatedAt: DateTime.utc(2026, 5, 30),
    );

    expect(result.status, 'blocked');
    expect(result.blockedGateIds, contains('repeat_coverage'));
  });

  test('blocks missing analyzer feedback and nested feedback files', () async {
    final directory = Directory.systemTemp.createTempSync(
      'diagnostic-feedback-gate-feedback-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final summary = _writeSummary(
      directory,
      _summaryJson(
        observed: false,
        feedbackCount: 0,
        diagnosticCount: 0,
        feedbackFiles: const ['lib/main.dart'],
      ),
    );

    final result = await buildCodingDiagnosticFeedbackReleaseGate(
      summaryFile: summary,
      generatedAt: DateTime.utc(2026, 5, 30),
    );

    expect(result.blockedGateIds, contains('analyzer_feedback_present'));
    expect(result.blockedGateIds, contains('required_feedback_files'));
  });

  test('blocks missing analyzer feedback telemetry', () async {
    final directory = Directory.systemTemp.createTempSync(
      'diagnostic-feedback-gate-telemetry-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final summary = _writeSummary(
      directory,
      _summaryJson(feedbackDurationMs: 0, commandAttemptCount: 0),
    );

    final result = await buildCodingDiagnosticFeedbackReleaseGate(
      summaryFile: summary,
      generatedAt: DateTime.utc(2026, 5, 30),
    );

    expect(
      result.blockedGateIds,
      contains('diagnostic_feedback_telemetry_present'),
    );
  });

  test('blocks transport and recovery signals', () async {
    final directory = Directory.systemTemp.createTempSync(
      'diagnostic-feedback-gate-recovery-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final summary = _writeSummary(
      directory,
      _summaryJson(
        signals: const {
          'transportDisconnectCount': 1,
          'recoveredStreamFallbackCount': 1,
          'turnFinalizationRecoveryRequestCount': 1,
        },
      ),
    );

    final result = await buildCodingDiagnosticFeedbackReleaseGate(
      summaryFile: summary,
      generatedAt: DateTime.utc(2026, 5, 30),
    );

    expect(result.blockedGateIds, contains('recovery_signals_clean'));
    expect(
      result.gates
          .singleWhere((gate) => gate.id == 'recovery_signals_clean')
          .evidence,
      contains('transportDisconnectCount=1'),
    );
    expect(
      result.gates
          .singleWhere((gate) => gate.id == 'recovery_signals_clean')
          .evidence,
      contains('turnFinalizationRecoveryRequestCount=1'),
    );
  });

  test('blocks malformed identity metadata', () async {
    final directory = Directory.systemTemp.createTempSync(
      'diagnostic-feedback-gate-identity-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final summary = _writeSummary(
      directory,
      _summaryJson(canaryName: 'chat_live_llm_canary', surface: 'chat'),
    );

    final result = await buildCodingDiagnosticFeedbackReleaseGate(
      summaryFile: summary,
      generatedAt: DateTime.utc(2026, 5, 30),
    );

    expect(result.blockedGateIds, contains('summary_identity'));
  });
}

File _writeSummary(Directory directory, Map<String, Object?> value) {
  final file = File('${directory.path}/canary_summary.json');
  file.writeAsStringSync(jsonEncode(value));
  return file;
}

Map<String, Object?> _summaryJson({
  String canaryName = 'coding_diagnostic_feedback_live_canary',
  String surface = 'coding_diagnostic_feedback',
  int repeatCount = 3,
  bool observed = true,
  int feedbackCount = 11,
  int diagnosticCount = 17,
  int feedbackDurationMs = 1200,
  int commandAttemptCount = 11,
  int fallbackCommandCount = 1,
  int timedOutCommandCount = 0,
  int startErrorCommandCount = 0,
  List<String> feedbackFiles = const [
    'lib/main.dart',
    'packages/nested_app/lib/main.dart',
  ],
  Map<String, Object?> signals = const {},
}) {
  final testCount = repeatCount * 2;
  return {
    'schemaName': 'live_llm_canary_summary',
    'schemaVersion': 1,
    'generatedAt': DateTime.utc(2026, 5, 30).toIso8601String(),
    'canaryName': canaryName,
    'surface': surface,
    'baseUrl': 'http://127.0.0.1:1234/v1',
    'model': 'qwen3.6-27b-mtp-vision',
    'command':
        'CAVERNO_CODING_DIAGNOSTIC_FEEDBACK_LIVE_REPEAT_COUNT=$repeatCount tool/run_coding_diagnostic_feedback_live_canary.sh',
    'logPath': '${Directory.systemTemp.path}/flutter_test.jsonl',
    'result': 'passed',
    'runnerSuccess': true,
    'doneSeen': true,
    'durationMs': 1000,
    'testCount': testCount,
    'passedCount': testCount,
    'failedCount': 0,
    'skippedCount': 0,
    'hiddenTestCount': repeatCount,
    'malformedJsonLineCount': 0,
    'signals': {
      'recoveredStreamFallbackCount': 0,
      'toolResultCompactionRetryCount': 0,
      'incompleteContentToolRecoveryCount': 0,
      'ignoredAssistantToolResultCount': 0,
      'assistantAuthoredToolBlockCount': 0,
      'transportDisconnectCount': 0,
      'memoryExtractionFallbackCount': 0,
      'dartAnalyzeFeedback': {
        'observed': observed,
        'feedbackCount': feedbackCount,
        'diagnosticCount': diagnosticCount,
        'files': feedbackFiles,
        'durationMs': feedbackDurationMs,
        'commandAttemptCount': commandAttemptCount,
        'fallbackCommandCount': fallbackCommandCount,
        'timedOutCommandCount': timedOutCommandCount,
        'startErrorCommandCount': startErrorCommandCount,
      },
      ...signals,
    },
    'tests': _tests(repeatCount),
  };
}

List<Map<String, Object?>> _tests(int repeatCount) {
  return [
    for (var index = 1; index <= repeatCount; index += 1)
      for (final scenario in const ['root package', 'nested package'])
        {
          'name':
              '[run_${index.toString().padLeft(2, '0')}] live LLM repairs $scenario Dart after analyzer feedback',
          'result': 'passed',
          'skipped': false,
          'hidden': false,
          'durationMs': 1000,
        },
  ];
}
