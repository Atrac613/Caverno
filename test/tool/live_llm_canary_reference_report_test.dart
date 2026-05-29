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
    final codingGoalSummary = _writeLiveSummary(
      directory: directory,
      fileName: 'coding_goal_summary.json',
      surface: 'coding_goal',
      canaryName: 'coding_goal_live_llm_canary',
      passedCount: 1,
      testCount: 1,
      signals: const {},
    );
    final codingGoalEditSummary = _writeLiveSummary(
      directory: directory,
      fileName: 'coding_goal_edit_summary.json',
      surface: 'coding_goal_edit',
      canaryName: 'coding_goal_live_edit_canary',
      passedCount: 4,
      testCount: 4,
      signals: const {},
    );
    final codingDiagnosticFeedbackSummary = _writeLiveSummary(
      directory: directory,
      fileName: 'coding_diagnostic_feedback_summary.json',
      surface: 'coding_diagnostic_feedback',
      canaryName: 'coding_diagnostic_feedback_live_canary',
      passedCount: 6,
      testCount: 6,
      tests: _diagnosticFeedbackTests(repeatCount: 3),
      signals: const {
        'dartAnalyzeFeedback': {
          'observed': true,
          'feedbackCount': 11,
          'diagnosticCount': 17,
          'files': ['lib/main.dart', 'packages/nested_app/lib/main.dart'],
        },
      },
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
      codingGoalSummary: codingGoalSummary,
      codingGoalEditSummary: codingGoalEditSummary,
      codingDiagnosticFeedbackSummary: codingDiagnosticFeedbackSummary,
      chatSummary: chatSummary,
      budgetSummary: budgetSummary,
      routineSummary: routineSummary,
      generatedAt: DateTime.utc(2026, 5, 23, 1, 2, 3),
    );

    expect(report.result, 'passed');
    expect(report.model, 'qwen3.6-27b-mtp-vision');
    expect(report.baseUrl, 'http://127.0.0.1:1234/v1');
    expect(report.totalPassed, 24);
    expect(report.totalCount, 24);
    expect(report.validationErrors, isEmpty);
    expect(report.entries, hasLength(9));
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
    final diagnosticEntry = report.entries.singleWhere(
      (entry) => entry.surface == 'coding_diagnostic_feedback',
    );
    expect(
      diagnosticEntry.riskSummary,
      contains('analyzer feedback 11, diagnostics 17'),
    );
    expect(
      diagnosticEntry.signals.toJson(),
      containsPair('dartAnalyzeDiagnosticCount', 17),
    );
    expect(report.toJson()['schemaName'], 'live_llm_canary_reference_report');
    expect(report.toJson()['schemaVersion'], 2);
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

  test('fails when live canary evidence has assistant tool blocks', () async {
    final directory = Directory.systemTemp.createTempSync(
      'live-llm-reference-tool-block-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    final codingGoalEditSummary = _writeLiveSummary(
      directory: directory,
      fileName: 'coding_goal_edit_summary.json',
      surface: 'coding_goal_edit',
      canaryName: 'coding_goal_live_edit_canary',
      passedCount: 1,
      testCount: 1,
      signals: const {'assistantAuthoredToolBlockCount': 1},
    );

    final report = await buildLiveLlmCanaryReferenceReport(
      label: 'tool block case',
      codingGoalEditSummary: codingGoalEditSummary,
      generatedAt: DateTime.utc(2026, 5, 26),
    );

    expect(report.result, 'failed');
    expect(report.isSuccessful, isFalse);
    expect(
      report.entries.single.riskSummary,
      contains('assistant tool blocks 1'),
    );
  });

  test(
    'fails when diagnostic feedback evidence misses release gate coverage',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'live-llm-reference-diagnostic-gate-test-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));

      final codingDiagnosticFeedbackSummary = _writeLiveSummary(
        directory: directory,
        fileName: 'coding_diagnostic_feedback_summary.json',
        surface: 'coding_diagnostic_feedback',
        canaryName: 'coding_diagnostic_feedback_live_canary',
        passedCount: 2,
        testCount: 2,
        tests: _diagnosticFeedbackTests(repeatCount: 1),
        signals: const {
          'dartAnalyzeFeedback': {
            'observed': true,
            'feedbackCount': 2,
            'diagnosticCount': 3,
            'files': ['lib/main.dart'],
          },
        },
      );

      final report = await buildLiveLlmCanaryReferenceReport(
        label: 'diagnostic gate case',
        codingDiagnosticFeedbackSummary: codingDiagnosticFeedbackSummary,
        generatedAt: DateTime.utc(2026, 5, 30),
      );

      expect(report.result, 'failed');
      expect(report.isSuccessful, isFalse);
      expect(report.entries.single.riskSummary, contains('repeat_coverage 1'));
      expect(
        report.entries.single.riskSummary,
        contains('required_feedback_files 1'),
      );
    },
  );

  test('fails when evidence mixes models or base URLs', () async {
    final directory = Directory.systemTemp.createTempSync(
      'live-llm-reference-metadata-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    final pm5Smoke = _writeJson(
      directory,
      'pm5_smoke.json',
      _planSuiteJson(
        model: 'model-a',
        baseUrl: 'http://127.0.0.1:1234/v1/',
        scenarioCount: 1,
        passedCount: 1,
        scenarioNames: const ['live_host_health_scaffold'],
      ),
    );
    final chatSummary = _writeLiveSummary(
      directory: directory,
      fileName: 'chat_summary.json',
      surface: 'chat',
      canaryName: 'chat_live_llm_canary',
      passedCount: 1,
      testCount: 1,
      model: 'model-b',
      baseUrl: 'http://localhost:1234/v1',
      signals: const {},
    );

    final report = await buildLiveLlmCanaryReferenceReport(
      label: 'mixed metadata',
      pm5SmokeReport: pm5Smoke,
      chatSummary: chatSummary,
      generatedAt: DateTime.utc(2026, 5, 23),
    );

    expect(report.result, 'failed');
    expect(report.isSuccessful, isFalse);
    expect(report.hasValidationErrors, isTrue);
    expect(
      report.validationErrors,
      contains('Mixed model evidence: model-a, model-b'),
    );
    expect(
      report.validationErrors,
      contains(
        'Mixed base URL evidence: http://127.0.0.1:1234/v1, http://localhost:1234/v1',
      ),
    );
    expect(report.toJson()['validationErrors'], hasLength(2));
    expect(report.toMarkdown(), contains('Validation errors'));
  });

  test('discovers latest artifacts from a report root', () async {
    final directory = Directory.systemTemp.createTempSync(
      'live-llm-reference-discovery-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));

    _writeJsonPath(
      directory,
      'plan_mode_live_suite_macos_100/plan_mode_live_suite_macos_report.json',
      _planSuiteJson(
        model: 'old-model',
        scenarioCount: 3,
        passedCount: 3,
        scenarioNames: const [
          'live_host_health_scaffold',
          'live_cli_entrypoint_decision',
          'live_clarify_recovery',
        ],
      ),
    );
    _writeJsonPath(
      directory,
      'plan_mode_live_suite_macos_200/plan_mode_live_suite_macos_report.json',
      _planSuiteJson(
        model: 'new-model',
        scenarioCount: 3,
        passedCount: 3,
        scenarioNames: const [
          'live_host_health_scaffold',
          'live_cli_entrypoint_decision',
          'live_clarify_recovery',
        ],
      ),
    );
    _writeJsonPath(
      directory,
      'plan_mode_live_suite_macos_300/plan_mode_live_suite_macos_report.json',
      _planSuiteJson(
        model: 'new-model',
        scenarioCount: 1,
        passedCount: 1,
        requestedScenarioNames: const ['live_readme_first_canary'],
        scenarioNames: const ['live_readme_first_canary'],
      ),
    );
    _writeJsonPath(
      directory,
      'plan_mode_ping_cli_canary_400/canary_summary.json',
      {
        'runCount': 1,
        'passedCount': 1,
        'failedCount': 0,
        'failureClassCounts': {'passed': 1},
        'runs': [
          {'reportQualityBlockerCount': 0},
        ],
      },
    );
    _writeJsonPath(
      directory,
      'chat_live_llm_canary_500/canary_summary.json',
      _liveSummaryJson(surface: 'chat', canaryName: 'chat_live_llm_canary'),
    );
    _writeJsonPath(
      directory,
      'coding_goal_live_llm_canary_550/canary_summary.json',
      _liveSummaryJson(
        surface: 'coding_goal',
        canaryName: 'coding_goal_live_llm_canary',
        testCount: 1,
        passedCount: 1,
      ),
    );
    _writeJsonPath(
      directory,
      'coding_goal_live_edit_canary_575/canary_summary.json',
      _liveSummaryJson(
        surface: 'coding_goal_edit',
        canaryName: 'coding_goal_live_edit_canary',
        testCount: 4,
        passedCount: 4,
      ),
    );
    _writeJsonPath(
      directory,
      'coding_diagnostic_feedback_live_canary_585/canary_summary.json',
      _liveSummaryJson(
        surface: 'coding_diagnostic_feedback',
        canaryName: 'coding_diagnostic_feedback_live_canary',
        testCount: 6,
        passedCount: 6,
        tests: _diagnosticFeedbackTests(repeatCount: 3),
        signals: const {
          'dartAnalyzeFeedback': {
            'observed': true,
            'feedbackCount': 11,
            'diagnosticCount': 17,
            'files': ['lib/main.dart', 'packages/nested_app/lib/main.dart'],
          },
        },
      ),
    );
    _writeJsonPath(
      directory,
      'tool_result_budget_live_canary_600/canary_summary.json',
      _liveSummaryJson(
        surface: 'chat_budget',
        canaryName: 'tool_result_budget_live_canary',
        testCount: 1,
        passedCount: 1,
        signals: const {'toolResultCompactionRetryCount': 1},
      ),
    );
    _writeJsonPath(
      directory,
      'routine_live_llm_canary_700/canary_summary.json',
      _liveSummaryJson(
        surface: 'routine',
        canaryName: 'routine_live_llm_canary',
        testCount: 4,
        passedCount: 4,
      ),
    );

    final report = await buildLiveLlmCanaryReferenceReportFromArtifacts(
      label: 'discovered',
      reportRoot: directory,
      generatedAt: DateTime.utc(2026, 5, 23),
    );

    expect(report.result, 'passed');
    expect(report.entries, hasLength(9));
    expect(report.model, 'new-model');
    expect(
      report.entries
          .singleWhere((entry) => entry.surface == 'coding_pm5')
          .evidencePath,
      endsWith(
        'plan_mode_live_suite_macos_200/plan_mode_live_suite_macos_report.json',
      ),
    );
    expect(
      report.entries
          .singleWhere((entry) => entry.surface == 'coding_artifact')
          .evidencePath,
      endsWith(
        'plan_mode_live_suite_macos_300/plan_mode_live_suite_macos_report.json',
      ),
    );
    expect(
      report.entries
          .singleWhere((entry) => entry.surface == 'coding_goal')
          .evidencePath,
      endsWith('coding_goal_live_llm_canary_550/canary_summary.json'),
    );
    expect(
      report.entries
          .singleWhere((entry) => entry.surface == 'coding_goal_edit')
          .evidencePath,
      endsWith('coding_goal_live_edit_canary_575/canary_summary.json'),
    );
    final diagnosticEntry = report.entries.singleWhere(
      (entry) => entry.surface == 'coding_diagnostic_feedback',
    );
    expect(
      diagnosticEntry.evidencePath,
      endsWith(
        'coding_diagnostic_feedback_live_canary_585/canary_summary.json',
      ),
    );
    expect(
      diagnosticEntry.riskSummary,
      contains('analyzer feedback 11, diagnostics 17'),
    );
    expect(
      report.entries
          .singleWhere((entry) => entry.surface == 'chat_budget')
          .riskSummary,
      contains('compaction retry 1'),
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
  required Map<String, Object?> signals,
  List<Map<String, Object?>> tests = const [],
  String model = 'qwen3.6-27b-mtp-vision',
  String baseUrl = 'http://127.0.0.1:1234/v1',
}) {
  return _writeJson(directory, fileName, {
    'schemaName': 'live_llm_canary_summary',
    'surface': surface,
    'canaryName': canaryName,
    'result': 'passed',
    'runnerSuccess': true,
    'doneSeen': true,
    'model': model,
    'baseUrl': baseUrl,
    'command': 'tool/run_$canaryName.sh',
    'logPath': '${directory.path}/flutter_test.jsonl',
    'passedCount': passedCount,
    'testCount': testCount,
    'failedCount': 0,
    'skippedCount': 0,
    'malformedJsonLineCount': 0,
    'signals': {
      'recoveredStreamFallbackCount': 0,
      'toolResultCompactionRetryCount': 0,
      'incompleteContentToolRecoveryCount': 0,
      'ignoredAssistantToolResultCount': 0,
      'assistantAuthoredToolBlockCount': 0,
      'transportDisconnectCount': 0,
      'memoryExtractionFallbackCount': 0,
      ...signals,
    },
    'tests': tests,
  });
}

File _writeJson(Directory directory, String fileName, Object value) {
  final file = File('${directory.path}/$fileName');
  file.writeAsStringSync(jsonEncode(value));
  return file;
}

File _writeJsonPath(Directory directory, String relativePath, Object value) {
  final file = File('${directory.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(value));
  return file;
}

Map<String, Object?> _planSuiteJson({
  required String model,
  required int scenarioCount,
  required int passedCount,
  String baseUrl = 'http://127.0.0.1:1234/v1',
  List<String> requestedScenarioNames = const [],
  List<String> scenarioNames = const [],
}) {
  return {
    'model': model,
    'baseUrl': baseUrl,
    'scenarioCount': scenarioCount,
    'passedCount': passedCount,
    'failedCount': scenarioCount - passedCount,
    'requestedScenarioNames': requestedScenarioNames,
    'warningSummary': {
      'warnings': 0,
      'allowedWarnings': 0,
      'unexpectedWarnings': 0,
    },
    'taskDriftSummary': {'detected': 0},
    'reportQualitySummary': {'blockerCount': 0},
    'toolLoopConvergenceSummary': {
      'guardActivations': 0,
      'naturalStops': passedCount,
    },
    'scenarios': [
      for (final scenario in scenarioNames)
        {
          'scenario': scenario,
          'usedHarnessApprovalFallback': true,
          'postScenarioCancellationUsed': false,
        },
    ],
  };
}

Map<String, Object?> _liveSummaryJson({
  required String surface,
  required String canaryName,
  int testCount = 3,
  int passedCount = 3,
  String model = 'new-model',
  String baseUrl = 'http://127.0.0.1:1234/v1',
  Map<String, Object?> signals = const {},
  List<Map<String, Object?>> tests = const [],
}) {
  return {
    'schemaName': 'live_llm_canary_summary',
    'surface': surface,
    'canaryName': canaryName,
    'result': passedCount == testCount ? 'passed' : 'failed',
    'runnerSuccess': passedCount == testCount,
    'doneSeen': true,
    'model': model,
    'baseUrl': baseUrl,
    'command': 'tool/run_$canaryName.sh',
    'logPath': '/tmp/flutter_test.jsonl',
    'passedCount': passedCount,
    'testCount': testCount,
    'failedCount': testCount - passedCount,
    'skippedCount': 0,
    'malformedJsonLineCount': 0,
    'signals': {
      'recoveredStreamFallbackCount': 0,
      'toolResultCompactionRetryCount': 0,
      'incompleteContentToolRecoveryCount': 0,
      'ignoredAssistantToolResultCount': 0,
      'assistantAuthoredToolBlockCount': 0,
      'transportDisconnectCount': 0,
      'memoryExtractionFallbackCount': 0,
      ...signals,
    },
    'tests': tests,
  };
}

List<Map<String, Object?>> _diagnosticFeedbackTests({
  required int repeatCount,
}) {
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
