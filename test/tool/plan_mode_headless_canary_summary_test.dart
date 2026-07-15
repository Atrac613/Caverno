import 'package:flutter_test/flutter_test.dart';

import '../../tool/plan_mode_headless_canary_summary.dart';

void main() {
  test('summarizes headless execution and report quality metrics', () {
    final summary = buildPlanModeHeadlessCanarySummary(
      suiteReport: <String, dynamic>{
        'reportQualitySummary': <String, dynamic>{
          'ready': true,
          'blockerCount': 0,
        },
        'scenarios': <Map<String, dynamic>>[
          <String, dynamic>{
            'scenario': 'live_todo_app_plan_completion',
            'status': 'passed',
            'startedAt': '2026-07-15T12:00:00.000Z',
            'finishedAt': '2026-07-15T12:01:00.000Z',
            'durationMs': 60000,
            'taskDriftDetected': false,
          },
        ],
      },
      scenarioReport: <String, dynamic>{
        'approvalPath': 'liveHarnessApprovalFallback',
        'usedHarnessApprovalFallback': true,
        'screenshots': <String>[],
        'capturedLogs': <String>[
          '[Tool] Tool loop [1/12]',
          '[Tool] Tool loop [2/12]',
          '[Workflow] Harness requested tool-less recovery for saved task',
        ],
        'toolLifecycle': <String, dynamic>{
          'toolCallCount': 2,
          'failedCount': 0,
        },
        'toolLoopConvergence': <String, dynamic>{'successfulValidations': 1},
      },
      sessionLogPaths: <String>['/tmp/z.jsonl', '/tmp/a.jsonl'],
      generatedAt: DateTime.utc(2026, 7, 15, 12, 2),
    );

    expect(summary['schemaVersion'], 1);
    expect(summary['surface'], 'plan_mode_headless');
    expect(summary['status'], 'passed');
    expect(summary['durationMs'], 60000);
    expect(summary['reportQualityReady'], isTrue);
    expect(summary['taskDriftDetected'], isFalse);
    expect(summary['toolLoopCount'], 2);
    expect(summary['toolCallCount'], 2);
    expect(summary['successfulValidationCount'], 1);
    expect(summary['recoveryCount'], 1);
    expect(summary['approvalDecisionCount'], 1);
    expect(summary['appOpenMarkerCount'], 0);
    expect(summary['sessionLogPaths'], <String>[
      '/tmp/a.jsonl',
      '/tmp/z.jsonl',
    ]);
  });

  test('rejects a multi-scenario suite', () {
    expect(
      () => buildPlanModeHeadlessCanarySummary(
        suiteReport: <String, dynamic>{
          'scenarios': <Map<String, dynamic>>[
            <String, dynamic>{'scenario': 'one'},
            <String, dynamic>{'scenario': 'two'},
          ],
        },
        scenarioReport: <String, dynamic>{},
        sessionLogPaths: <String>[],
        generatedAt: DateTime.utc(2026, 7, 15),
      ),
      throwsStateError,
    );
  });
}
