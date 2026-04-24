import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_report_summary.dart';
import '../../integration_test/test_support/plan_mode_suite_report.dart';

void main() {
  group('plan mode suite reports', () {
    final config = PlanModeSuiteReportConfig(
      generatedAt: DateTime.utc(2026, 4, 24, 8, 30),
      suiteName: 'plan_mode_live_scenarios_macos',
      modeName: 'live',
      failOnWarnings: true,
      requestedScenarioNames: const <String>[],
      requestedTags: const <String>['smoke'],
      suiteDirectoryPath: '/tmp/caverno reports/live',
      model: 'local-model',
      baseUrl: 'http://127.0.0.1:1234/v1',
    );

    final results = <Map<String, Object?>>[
      <String, Object?>{
        'scenario': 'live_cli_entrypoint_decision',
        'tags': const <String>['live', 'smoke', 'decision'],
        'status': 'passed',
        'failureClass': 'passed',
        'budgetPhase': 'completed',
        'approvalPath': planModeApprovalPathLiveHarnessFallback,
        'fallbackPath': planModeFallbackPathLiveHarnessApproval,
        'postScenarioSettled': true,
        'postScenarioCancellationUsed': false,
        'durationMs': 55052,
        'warnings': const <String>['allowed warning'],
        'allowedWarnings': const <String>['allowed warning'],
        'unexpectedWarnings': const <String>[],
        'screenshots': const <String>[],
        'scenarioReport': '/tmp/caverno reports/live/report.json',
        'scenarioLog': '/tmp/caverno reports/live/scenario_log.txt',
      },
      <String, Object?>{
        'scenario': 'broken|scenario',
        'tags': const <String>['live'],
        'status': 'failed',
        'failureClass': 'workflowBlocked',
        'budgetPhase': 'execution',
        'approvalPath': planModeApprovalPathUi,
        'fallbackPath': planModeFallbackPathNone,
        'durationMs': 1500,
        'warnings': const <String>['unexpected warning'],
        'allowedWarnings': const <String>[],
        'unexpectedWarnings': const <String>['unexpected warning'],
        'screenshots': const <String>['failure.png'],
        'scenarioReport': '/tmp/failure/report.json',
        'scenarioLog': '/tmp/failure/log.txt',
        'error': 'Bad <failure> & details',
        'stackTrace': 'line 1\nline 2',
      },
    ];

    test('builds JSON with shared outcome and warning summaries', () {
      final report = buildPlanModeSuiteJsonReport(
        config: config,
        suiteResults: results,
      );

      expect(report['generatedAt'], '2026-04-24T08:30:00.000Z');
      expect(report['passedCount'], 1);
      expect(report['failedCount'], 1);
      expect(report['warningSummary'], containsPair('unexpectedWarnings', 1));
      expect(
        report['executionPathSummary'],
        containsPair('liveHarnessApprovalFallback', 1),
      );
    });

    test('builds readable Markdown with compact artifact links', () {
      final markdown = buildPlanModeSuiteMarkdownReport(
        config: config,
        suiteResults: results,
      );

      expect(markdown, contains('- Scenario filter: all'));
      expect(markdown, contains('- Tag filter: smoke'));
      expect(
        markdown,
        contains('- Warnings: 2 total, 1 allowed, 1 unexpected'),
      );
      expect(
        markdown,
        contains('[report](</tmp/caverno reports/live/report.json>)'),
      );
      expect(
        markdown,
        contains('[log](</tmp/caverno reports/live/scenario_log.txt>)'),
      );
      expect(markdown, contains('broken\\|scenario'));
      expect(markdown, contains('## Unexpected Warnings'));
      expect(markdown, contains('## Live Harness Fallback Paths'));
    });

    test('builds JUnit XML with escaped failure and system output', () {
      final junit = buildPlanModeSuiteJUnitReport(
        config: config,
        suiteResults: results,
      );

      expect(junit, contains('<testsuites tests="2" failures="1"'));
      expect(junit, contains('message="Bad &lt;failure&gt; &amp; details"'));
      expect(junit, contains('unexpectedWarnings=1'));
      expect(junit, contains('unexpectedWarning=unexpected warning'));
      expect(junit, contains('approvalPath=liveHarnessApprovalFallback'));
    });
  });
}
