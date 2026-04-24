import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_report_summary.dart';

void main() {
  group('plan mode report summary', () {
    test('summarizes outcome and warning counts', () {
      final results = <Map<String, Object?>>[
        <String, Object?>{
          'scenario': 'green',
          'status': 'passed',
          'warnings': const <String>['allowed warning'],
          'allowedWarnings': const <String>['allowed warning'],
          'unexpectedWarnings': const <String>[],
          'scenarioReport': '/tmp/green/report.json',
        },
        <String, Object?>{
          'scenario': 'red',
          'status': 'failed',
          'warnings': const <String>['unexpected warning'],
          'allowedWarnings': const <String>[],
          'unexpectedWarnings': const <String>['unexpected warning'],
          'scenarioLog': '/tmp/red/log.txt',
        },
      ];

      expect(buildPlanModeSuiteOutcomeSummary(results), <String, Object>{
        'total': 2,
        'passed': 1,
        'failed': 1,
      });

      expect(
        buildPlanModeSuiteWarningSummary(results),
        containsPair('warnings', 2),
      );
      expect(
        buildPlanModeSuiteWarningSummary(results),
        containsPair('allowedWarnings', 1),
      );
      expect(
        buildPlanModeSuiteWarningSummary(results),
        containsPair('unexpectedWarnings', 1),
      );
      expect(
        buildPlanModeSuiteWarningSummary(results),
        containsPair('scenariosWithUnexpectedWarnings', 1),
      );
    });

    test('summarizes approval and fallback paths', () {
      final results = <Map<String, Object?>>[
        <String, Object?>{
          'scenario': 'ui',
          'approvalPath': planModeApprovalPathUi,
          'fallbackPath': planModeFallbackPathNone,
        },
        <String, Object?>{
          'scenario': 'harness',
          'approvalPath': planModeApprovalPathLiveHarnessFallback,
          'fallbackPath': planModeFallbackPathLiveHarnessApproval,
          'scenarioReport': '/tmp/harness/report.json',
        },
        <String, Object?>{'scenario': 'unknown'},
      ];

      final summary = buildPlanModeSuiteExecutionPathSummary(results);

      expect(summary['uiApproval'], 1);
      expect(summary['liveHarnessApprovalFallback'], 1);
      expect(summary['unknown'], 1);
      final fallbackScenarios = summary['fallbackScenarios'] as List<Object?>;
      expect(fallbackScenarios, hasLength(1));
      expect(fallbackScenarios.single, containsPair('scenario', 'harness'));
    });

    test('resolves approval path from live harness logs', () {
      expect(
        resolvePlanModeApprovalPathFromLogs(const <String>[
          '[Workflow] Proposal approval UI bypassed by live harness',
        ]),
        planModeApprovalPathLiveHarnessFallback,
      );
      expect(
        resolvePlanModeApprovalPathFromLogs(const <String>[
          '[Workflow] Proposal approval UI visible',
        ]),
        planModeApprovalPathUi,
      );
      expect(
        resolvePlanModeApprovalPathFromLogs(const <String>[]),
        planModeApprovalPathUnknown,
      );
    });
  });
}
