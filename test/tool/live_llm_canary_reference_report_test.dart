import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/live_llm_canary_reference_report.dart';

void main() {
  test('builds a passing full-surface reference report', () async {
    final directory = Directory.systemTemp.createTempSync(
      'live-llm-reference-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    final pm5Smoke = _writeJson(directory, 'pm5_smoke.json', {
      'model': 'qwen3.6-27b-mtp-vision',
      'baseUrl': 'http://127.0.0.1:1234/v1',
      'scenarioCount': 3,
      'passedCount': 3,
      'failedCount': 0,
      'warningSummary': {
        'warnings': 0,
        'allowedWarnings': 0,
        'unexpectedWarnings': 0,
      },
      'taskDriftSummary': {'detected': 0},
      'reportQualitySummary': {'blockerCount': 0},
      'toolLoopConvergenceSummary': {'guardActivations': 0, 'naturalStops': 2},
      'scenarios': [
        {
          'usedHarnessApprovalFallback': true,
          'postScenarioCancellationUsed': true,
        },
        {
          'usedHarnessApprovalFallback': true,
          'postScenarioCancellationUsed': false,
        },
        {
          'usedHarnessApprovalFallback': true,
          'postScenarioCancellationUsed': true,
        },
      ],
    });
    final pingSummary = _writeJson(directory, 'ping_summary.json', {
      'runCount': 1,
      'passedCount': 1,
      'failedCount': 0,
      'failureClassCounts': {'passed': 1},
      'runs': [
        {'reportQualityBlockerCount': 0},
      ],
    });
    final readmeReport = _writeJson(directory, 'readme_report.json', {
      'model': 'qwen3.6-27b-mtp-vision',
      'baseUrl': 'http://127.0.0.1:1234/v1',
      'scenarioCount': 1,
      'passedCount': 1,
      'failedCount': 0,
      'warningSummary': {
        'warnings': 0,
        'allowedWarnings': 0,
        'unexpectedWarnings': 0,
      },
      'taskDriftSummary': {'detected': 0},
      'reportQualitySummary': {'blockerCount': 0},
      'toolLoopConvergenceSummary': {'guardActivations': 0, 'naturalStops': 1},
      'scenarios': [
        {
          'usedHarnessApprovalFallback': true,
          'postScenarioCancellationUsed': false,
        },
      ],
    });
    final chatSummary = _writeLiveSummary(
      directory: directory,
      fileName: 'chat_summary.json',
      surface: 'chat',
      canaryName: 'chat_live_llm_canary',
      passedCount: 3,
      testCount: 3,
      signals: const {},
    );
    final budgetSummary = _writeLiveSummary(
      directory: directory,
      fileName: 'budget_summary.json',
      surface: 'chat_budget',
      canaryName: 'tool_result_budget_live_canary',
      passedCount: 1,
      testCount: 1,
      signals: const {'toolResultCompactionRetryCount': 1},
    );
    final routineSummary = _writeLiveSummary(
      directory: directory,
      fileName: 'routine_summary.json',
      surface: 'routine',
      canaryName: 'routine_live_llm_canary',
      passedCount: 4,
      testCount: 4,
      signals: const {},
    );

    final report = await buildLiveLlmCanaryReferenceReport(
      label: 'qwen post-hardening',
      pm5SmokeReport: pm5Smoke,
      pm5PingSummary: pingSummary,
      readmeReport: readmeReport,
      chatSummary: chatSummary,
      budgetSummary: budgetSummary,
      routineSummary: routineSummary,
      generatedAt: DateTime.utc(2026, 5, 23, 1, 2, 3),
    );

    expect(report.result, 'passed');
    expect(report.model, 'qwen3.6-27b-mtp-vision');
    expect(report.baseUrl, 'http://127.0.0.1:1234/v1');
    expect(report.totalPassed, 13);
    expect(report.totalCount, 13);
    expect(report.entries, hasLength(6));
    expect(report.entries.first.riskSummary, contains('approval fallback 3'));
    expect(
      report.entries.first.riskSummary,
      contains('cleanup cancellations 2'),
    );
    expect(
      report.entries
          .singleWhere((entry) => entry.surface == 'chat_budget')
          .riskSummary,
      contains('compaction retry 1'),
    );
    expect(report.toJson()['schemaName'], 'live_llm_canary_reference_report');
    expect(report.toMarkdown(), contains('Live LLM Canary Reference Report'));
    expect(report.toMarkdown(), contains('qwen post-hardening'));
  });

  test('fails when a Plan Mode report has unexpected warnings', () async {
    final directory = Directory.systemTemp.createTempSync(
      'live-llm-reference-fail-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    final pm5Smoke = _writeJson(directory, 'pm5_smoke.json', {
      'model': 'test-model',
      'baseUrl': 'http://127.0.0.1:1234/v1',
      'scenarioCount': 1,
      'passedCount': 1,
      'failedCount': 0,
      'warningSummary': {
        'warnings': 1,
        'allowedWarnings': 0,
        'unexpectedWarnings': 1,
      },
      'taskDriftSummary': {'detected': 0},
      'reportQualitySummary': {'blockerCount': 0},
      'toolLoopConvergenceSummary': {'guardActivations': 0, 'naturalStops': 1},
      'scenarios': const [],
    });

    final report = await buildLiveLlmCanaryReferenceReport(
      label: 'warning case',
      pm5SmokeReport: pm5Smoke,
      generatedAt: DateTime.utc(2026, 5, 23),
    );

    expect(report.result, 'failed');
    expect(report.isSuccessful, isFalse);
    expect(
      report.entries.single.riskSummary,
      contains('unexpected warnings 1'),
    );
  });
}

File _writeLiveSummary({
  required Directory directory,
  required String fileName,
  required String surface,
  required String canaryName,
  required int passedCount,
  required int testCount,
  required Map<String, int> signals,
}) {
  return _writeJson(directory, fileName, {
    'schemaName': 'live_llm_canary_summary',
    'surface': surface,
    'canaryName': canaryName,
    'result': 'passed',
    'model': 'qwen3.6-27b-mtp-vision',
    'baseUrl': 'http://127.0.0.1:1234/v1',
    'passedCount': passedCount,
    'testCount': testCount,
    'failedCount': 0,
    'signals': {
      'recoveredStreamFallbackCount': 0,
      'toolResultCompactionRetryCount': 0,
      'transportDisconnectCount': 0,
      'memoryExtractionFallbackCount': 0,
      ...signals,
    },
  });
}

File _writeJson(Directory directory, String fileName, Object value) {
  final file = File('${directory.path}/$fileName');
  file.writeAsStringSync(jsonEncode(value));
  return file;
}
