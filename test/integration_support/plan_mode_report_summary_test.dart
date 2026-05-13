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
          'warningDetails': const <Map<String, String>>[
            <String, String>{
              'warning': 'allowed warning',
              'disposition': 'allowed',
              'reason': 'allowedPattern',
            },
          ],
          'scenarioReport': '/tmp/green/report.json',
        },
        <String, Object?>{
          'scenario': 'red',
          'status': 'failed',
          'warnings': const <String>['unexpected warning'],
          'allowedWarnings': const <String>[],
          'unexpectedWarnings': const <String>['unexpected warning'],
          'warningDetails': const <Map<String, String>>[
            <String, String>{
              'warning': 'unexpected warning',
              'disposition': 'unexpected',
              'reason': 'requiresInvestigation',
            },
          ],
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

      final detailSummary = buildPlanModeSuiteWarningDetailSummary(results);
      expect(detailSummary['totalDetails'], 2);
      expect(detailSummary['unexpectedDetails'], 1);
      expect(
        detailSummary['unexpectedByReason'],
        containsPair('requiresInvestigation', 1),
      );
    });

    test('summarizes report quality blockers with scenario reasons', () {
      final results = <Map<String, Object?>>[
        <String, Object?>{
          'scenario': 'green',
          'status': 'passed',
          'approvalPath': planModeApprovalPathUi,
          'postScenarioSettled': true,
          'warnings': const <String>['allowed warning'],
          'allowedWarnings': const <String>['allowed warning'],
          'unexpectedWarnings': const <String>[],
          'warningDetails': const <Map<String, String>>[
            <String, String>{
              'warning': 'allowed warning',
              'disposition': 'allowed',
              'reason': 'allowedPattern',
            },
          ],
        },
        <String, Object?>{
          'scenario': 'red',
          'status': 'failed',
          'failureClass': 'workflowBlocked',
          'approvalPath': planModeApprovalPathUnknown,
          'lastKnownPhase': 'execution',
          'postScenarioSettled': false,
          'error': 'No final answer',
          'warnings': const <String>['unexpected warning'],
          'allowedWarnings': const <String>[],
          'unexpectedWarnings': const <String>['unexpected warning'],
          'warningSummary': const <String, Object>{
            'details': <Map<String, String>>[
              <String, String>{
                'warning': 'unexpected warning',
                'disposition': 'unexpected',
                'reason': 'requiresInvestigation',
              },
            ],
          },
          'taskDrift': const <String, Object?>{
            'driftDetected': true,
            'driftReason': 'unexpectedChangedFiles',
          },
          'scenarioReport': '/tmp/red/report.json',
          'scenarioLog': '/tmp/red/log.txt',
        },
      ];

      final summary = buildPlanModeSuiteReportQualitySummary(results);

      expect(summary['ready'], isFalse);
      expect(summary['blockerCount'], 5);
      expect(summary['blockedScenarioCount'], 1);
      expect(summary['byReason'], containsPair('workflowBlocked', 1));
      expect(summary['byReason'], containsPair('requiresInvestigation', 1));
      expect(summary['byReason'], containsPair('unexpectedChangedFiles', 1));
      expect(summary['byReason'], containsPair('approvalPathUnknown', 1));
      expect(summary['byReason'], containsPair('postScenarioDidNotSettle', 1));

      final blockers = summary['blockers'] as List<Object?>;
      expect(
        blockers,
        contains(
          allOf(
            containsPair('scenario', 'red'),
            containsPair('kind', 'unexpectedWarning'),
            containsPair('reason', 'requiresInvestigation'),
            containsPair('warning', 'unexpected warning'),
          ),
        ),
      );
    });

    test('does not require approval path for pre-approval failures', () {
      final summary = buildPlanModeSuiteReportQualitySummary(const [
        <String, Object?>{
          'scenario': 'early_timeout',
          'status': 'failed',
          'failureClass': 'overallTimeout',
          'approvalPath': planModeApprovalPathUnknown,
          'error': 'Scenario run timed out after 500s.',
          'phaseTimings': <String, Object?>{},
        },
      ]);

      expect(summary['ready'], isFalse);
      expect(summary['blockerCount'], 1);
      expect(summary['byReason'], containsPair('overallTimeout', 1));
      expect(
        summary['byReason'] as Map<String, Object?>,
        isNot(containsPair('approvalPathUnknown', 1)),
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

    test('summarizes task drift scenarios', () {
      final results = <Map<String, Object?>>[
        <String, Object?>{
          'scenario': 'readme_canary',
          'scenarioReport': '/tmp/readme/report.json',
          'taskDrift': const <String, Object?>{
            'driftDetected': true,
            'driftReason': 'unexpectedChangedFiles',
            'fallbackSource': 'actualChangedFiles',
            'expectedTargetFiles': <String>['README.md'],
            'savedTaskTargetFiles': <String>['README.md'],
            'actualChangedFiles': <String>['README.md', 'requirements.txt'],
          },
        },
        <String, Object?>{
          'scenario': 'green',
          'taskDrift': const <String, Object?>{'driftDetected': false},
        },
      ];

      final summary = buildPlanModeSuiteTaskDriftSummary(results);

      expect(summary['detected'], 1);
      final scenarios = summary['scenarios'] as List<Object?>;
      expect(scenarios, hasLength(1));
      expect(scenarios.single, containsPair('scenario', 'readme_canary'));
      expect(
        scenarios.single,
        containsPair('actualChangedFiles', ['README.md', 'requirements.txt']),
      );
    });

    test('summarizes tool loop convergence guard activations', () {
      final results = <Map<String, Object?>>[
        <String, Object?>{
          'scenario': 'readme_canary',
          'scenarioReport': '/tmp/readme/report.json',
          'scenarioLog': '/tmp/readme/log.txt',
          'toolLoopConvergence': const <String, Object?>{
            'detected': true,
            'status': 'guarded',
            'successfulValidations': 2,
            'guardActivations': 2,
            'naturalStops': 0,
            'guardPattern':
                '[Tool] Ignoring follow-up tool calls after saved validation success',
          },
        },
        <String, Object?>{
          'scenario': 'natural_stop',
          'scenarioReport': '/tmp/natural/report.json',
          'scenarioLog': '/tmp/natural/log.txt',
          'toolLoopConvergence': const <String, Object?>{
            'detected': false,
            'status': 'natural_stop',
            'successfulValidations': 1,
            'guardActivations': 0,
            'naturalStops': 1,
          },
        },
        <String, Object?>{
          'scenario': 'green',
          'toolLoopConvergence': const <String, Object?>{
            'detected': false,
            'guardActivations': 0,
          },
        },
      ];

      final summary = buildPlanModeSuiteToolLoopConvergenceSummary(results);

      expect(summary['detected'], 2);
      expect(summary['successfulValidations'], 3);
      expect(summary['guardActivations'], 2);
      expect(summary['naturalStops'], 1);
      final scenarios = summary['scenarios'] as List<Object?>;
      expect(scenarios, hasLength(2));
      expect(scenarios.first, containsPair('scenario', 'readme_canary'));
      expect(scenarios.first, containsPair('guardActivations', 2));
      expect(scenarios.last, containsPair('scenario', 'natural_stop'));
      expect(scenarios.last, containsPair('naturalStops', 1));
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
