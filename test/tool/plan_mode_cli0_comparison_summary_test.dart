import 'package:flutter_test/flutter_test.dart';

import '../../tool/plan_mode_cli0_comparison_summary.dart';

void main() {
  test('summarizes three headless runs and one macOS run', () {
    final summary = buildPlanModeCli0ComparisonSummary(
      headlessSummaries: <Map<String, dynamic>>[
        _headlessSummary(index: 3, durationMs: 300, toolLoopCount: 3),
        _headlessSummary(index: 1, durationMs: 100, toolLoopCount: 1),
        _headlessSummary(index: 2, durationMs: 200, toolLoopCount: 2),
      ],
      macosSuiteReport: _macosSuiteReport(),
      macosScenarioReport: <String, dynamic>{
        'approvalPath': 'liveHarnessApprovalFallback',
        'usedHarnessApprovalFallback': true,
        'screenshots': <String>['/tmp/completed.png'],
        'capturedLogs': <String>[
          '[Tool] Tool loop [1/12]',
          '[Tool] Tool loop [2/12]',
          '[Workflow] Harness requested tool-less recovery',
        ],
        'toolLifecycle': <String, dynamic>{
          'toolCallCount': 4,
          'failedCount': 0,
        },
        'toolLoopConvergence': <String, dynamic>{'successfulValidations': 2},
      },
      macosSessionLogPaths: <String>['/tmp/macos.jsonl'],
      expectedHeadlessCount: 3,
      macosSuiteReportPath: '/tmp/macos_suite.json',
      generatedAt: DateTime.utc(2026, 7, 15, 14),
    );

    expect(summary['schemaVersion'], 1);
    expect(summary['status'], 'passed');
    expect(summary['failureReasons'], isEmpty);
    expect(summary['scenario'], 'live_todo_app_plan_completion');
    expect(summary['model'], 'test-model');

    final headless = summary['headless']! as Map<String, Object?>;
    expect(headless['runCount'], 3);
    expect(headless['passedCount'], 3);
    expect(headless['passRate'], 1.0);
    expect(headless['toolLoopCount'], 6);
    expect(headless['toolCallCount'], 9);
    expect(headless['recoveryCount'], 0);
    expect(headless['approvalDecisionCount'], 3);
    expect(headless['approvalPathCounts'], <String, int>{
      'liveHarnessApprovalFallback': 3,
    });
    expect(headless['sessionLogPaths'], <String>[
      '/tmp/headless_1.jsonl',
      '/tmp/headless_2.jsonl',
      '/tmp/headless_3.jsonl',
    ]);
    expect(headless['durationMs'], <String, Object?>{
      'values': <int>[100, 200, 300],
      'minimum': 100,
      'maximum': 300,
      'average': 200,
    });

    final macos = summary['macos']! as Map<String, Object?>;
    expect(macos['status'], 'passed');
    expect(macos['toolLoopCount'], 2);
    expect(macos['toolCallCount'], 4);
    expect(macos['successfulValidationCount'], 2);
    expect(macos['recoveryCount'], 1);
    expect(macos['screenshotCount'], 1);
    expect(macos['sessionLogPaths'], <String>['/tmp/macos.jsonl']);
  });

  test('reports parity failures with stable reason codes', () {
    final mismatched = _headlessSummary(
      index: 1,
      durationMs: 100,
      toolLoopCount: 1,
    )..['model'] = 'different-model';

    final summary = buildPlanModeCli0ComparisonSummary(
      headlessSummaries: <Map<String, dynamic>>[mismatched],
      macosSuiteReport: _macosSuiteReport(),
      macosScenarioReport: <String, dynamic>{
        'capturedLogs': <String>[],
        'toolLifecycle': <String, dynamic>{},
        'toolLoopConvergence': <String, dynamic>{},
      },
      macosSessionLogPaths: <String>[],
      expectedHeadlessCount: 3,
      macosSuiteReportPath: '/tmp/macos_suite.json',
      generatedAt: DateTime.utc(2026, 7, 15, 14),
    );

    expect(summary['status'], 'failed');
    expect(
      summary['failureReasons'],
      containsAll(<String>[
        'headless_run_count_mismatch',
        'model_mismatch',
        'macos_session_log_missing',
      ]),
    );
  });

  test('rejects a non-positive expected headless count', () {
    expect(
      () => buildPlanModeCli0ComparisonSummary(
        headlessSummaries: <Map<String, dynamic>>[],
        macosSuiteReport: _macosSuiteReport(),
        macosScenarioReport: <String, dynamic>{},
        macosSessionLogPaths: <String>[],
        expectedHeadlessCount: 0,
        macosSuiteReportPath: '/tmp/macos_suite.json',
        generatedAt: DateTime.utc(2026, 7, 15),
      ),
      throwsArgumentError,
    );
  });
}

Map<String, dynamic> _headlessSummary({
  required int index,
  required int durationMs,
  required int toolLoopCount,
}) {
  return <String, dynamic>{
    'summaryPath': '/tmp/headless_$index.json',
    'surface': 'plan_mode_headless',
    'baseUrl': 'http://127.0.0.1:1234/v1',
    'model': 'test-model',
    'scenario': 'live_todo_app_plan_completion',
    'status': 'passed',
    'startedAt': '2026-07-15T14:00:0$index.000Z',
    'finishedAt': '2026-07-15T14:00:1$index.000Z',
    'durationMs': durationMs,
    'reportQualityReady': true,
    'reportQualityBlockerCount': 0,
    'taskDriftDetected': false,
    'toolLoopCount': toolLoopCount,
    'toolCallCount': 3,
    'toolFailureCount': 0,
    'successfulValidationCount': 1,
    'recoveryCount': 0,
    'approvalDecisionCount': 1,
    'approvalPath': 'liveHarnessApprovalFallback',
    'screenshotCount': 0,
    'appOpenMarkerCount': 0,
    'sessionLogPaths': <String>['/tmp/headless_$index.jsonl'],
  };
}

Map<String, dynamic> _macosSuiteReport() {
  return <String, dynamic>{
    'baseUrl': 'http://127.0.0.1:1234/v1',
    'model': 'test-model',
    'reportQualitySummary': <String, dynamic>{'ready': true, 'blockerCount': 0},
    'scenarios': <Map<String, dynamic>>[
      <String, dynamic>{
        'scenario': 'live_todo_app_plan_completion',
        'status': 'passed',
        'startedAt': '2026-07-15T15:00:00.000Z',
        'finishedAt': '2026-07-15T15:01:00.000Z',
        'durationMs': 60000,
        'taskDriftDetected': false,
        'scenarioReport': '/tmp/macos_scenario.json',
      },
    ],
  };
}
