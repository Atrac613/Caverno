import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_failure_artifacts.dart';
import '../../integration_test/test_support/plan_mode_heartbeat.dart';
import '../../integration_test/test_support/plan_mode_report_summary.dart';
import '../../integration_test/test_support/plan_mode_scenario_spec.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'plan_mode_failure_artifacts_',
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('copies nested scenario directories', () async {
    final source = Directory('${tempDir.path}/source')..createSync();
    final nested = Directory('${source.path}/nested')..createSync();
    File('${source.path}/README.md').writeAsStringSync('# Project\n');
    File('${nested.path}/main.py').writeAsStringSync('print("ok")\n');
    final destination = Directory('${tempDir.path}/destination');

    await copyPlanModeDirectoryContents(
      source: source,
      destination: destination,
    );

    expect(
      File('${destination.path}/README.md').readAsStringSync(),
      '# Project\n',
    );
    expect(
      File('${destination.path}/nested/main.py').readAsStringSync(),
      'print("ok")\n',
    );
  });

  test('filters captured logs to failure-triage lines', () {
    expect(
      filterPlanModeFailureCapturedLogs(const <String>[
        '[Workflow] Proposal ready',
        '[Tool] Executing tool',
        'plain debug noise',
        '[Screenshot] Saved image',
      ]),
      const <String>[
        '[Workflow] Proposal ready',
        '[Tool] Executing tool',
        '[Screenshot] Saved image',
      ],
    );
  });

  test('resolves saved task target files from failure logs', () {
    expect(
      resolvePlanModeFailureSavedTaskTargetFiles(
        logs: const <String>[
          '[LLM]   [3] user: Use the approved saved task now: Create README.md\n'
              'Target files: README.md\n'
              'Validation: ls README.md',
        ],
      ),
      const <String>['README.md'],
    );
    expect(
      resolvePlanModeFailureSavedTaskTargetFiles(
        logs: const <String>[
          '[LLM] user: Target files: requirements.txt, `README.md`',
        ],
      ),
      const <String>['requirements.txt', 'README.md'],
    );
  });

  test('writes failure report and full scenario log', () async {
    final scenarioDir = Directory('${tempDir.path}/scenario')..createSync();
    File('${scenarioDir.path}/README.md').writeAsStringSync('# Project\n');
    File('${scenarioDir.path}/requirements.txt').writeAsStringSync('ping3\n');
    File('${scenarioDir.path}/failure.png').writeAsBytesSync(const <int>[0]);
    final heartbeatPath = '${tempDir.path}/heartbeat.json';
    File(heartbeatPath).writeAsStringSync(
      jsonEncode(<String, Object?>{
        'activeTaskTitle': 'Create README',
        'toolResultCount': 2,
        'fileWriteCount': 1,
      }),
    );
    final phaseTrace = PlanModePhaseTrace()
      ..proposalReadyAt = DateTime(2026, 5, 12, 12)
      ..taskProposalReadyAt = DateTime(2026, 5, 12, 12, 1);
    const budgets = PlanModeTimeoutBudgets(
      planningTimeout: Duration(seconds: 5),
      executionTimeout: Duration(seconds: 20),
      executionStallTimeout: Duration(seconds: 45),
      overallTimeout: Duration(seconds: 70),
    );
    const logs = <String>[
      '[Workflow] Proposal approval UI bypassed by live harness',
      '[Tool] Executing tool: write_file',
      'plain debug noise',
    ];

    await writePlanModeFailureScenarioArtifacts(
      scenario: _scenario(),
      scenarioDir: scenarioDir,
      logs: logs,
      error: StateError('boom'),
      stackTrace: StackTrace.current,
      phaseTrace: phaseTrace,
      budgets: budgets,
      heartbeatPath: heartbeatPath,
    );

    expect(
      File('${scenarioDir.path}/scenario_log.txt').readAsStringSync(),
      '${logs.join('\n')}\n',
    );
    final report =
        jsonDecode(
              File(
                '${scenarioDir.path}/scenario_report.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    expect(report['scenario'], 'failure_artifacts');
    expect(report['status'], 'failed');
    expect(report['approvalPath'], planModeApprovalPathLiveHarnessFallback);
    expect(report['fallbackPath'], planModeFallbackPathLiveHarnessApproval);
    expect(report['usedHarnessApprovalFallback'], isTrue);
    expect(report['capturedLogs'], const <String>[
      '[Workflow] Proposal approval UI bypassed by live harness',
      '[Tool] Executing tool: write_file',
    ]);
    expect(
      report['lastHeartbeat'],
      containsPair('activeTaskTitle', 'Create README'),
    );
    expect(report['taskDriftDetected'], isTrue);
    expect(
      (report['taskDrift'] as Map<String, dynamic>)['unexpectedChangedFiles'],
      const <String>['requirements.txt'],
    );
    expect(report['screenshots'], isNotEmpty);
    expect(report['diagnostics'], isA<Map<String, dynamic>>());
  });

  test('uses logged target files for failure task drift', () async {
    final scenarioDir = Directory('${tempDir.path}/scenario')..createSync();
    File('${scenarioDir.path}/README.md').writeAsStringSync('# Project\n');
    final phaseTrace = PlanModePhaseTrace()
      ..proposalReadyAt = DateTime(2026, 5, 12, 12)
      ..taskProposalReadyAt = DateTime(2026, 5, 12, 12, 1);
    const budgets = PlanModeTimeoutBudgets(
      planningTimeout: Duration(seconds: 5),
      executionTimeout: Duration(seconds: 20),
      executionStallTimeout: Duration(seconds: 45),
      overallTimeout: Duration(seconds: 70),
    );
    const logs = <String>[
      '[LLM]   [3] user: Use the approved saved task now: Create README.md\n'
          'Target files: README.md\n'
          'Validation: ls README.md',
    ];

    await writePlanModeFailureScenarioArtifacts(
      scenario: _scenario(),
      scenarioDir: scenarioDir,
      logs: logs,
      error: StateError('boom'),
      stackTrace: StackTrace.current,
      phaseTrace: phaseTrace,
      budgets: budgets,
    );

    final report =
        jsonDecode(
              File(
                '${scenarioDir.path}/scenario_report.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final taskDrift = report['taskDrift'] as Map<String, dynamic>;

    expect(taskDrift['savedTaskTargetFiles'], const <String>['readme.md']);
    expect(taskDrift['missingExpectedSavedTaskTargetFiles'], isEmpty);
    expect(report['taskDriftDetected'], isFalse);
  });

  test('skips task drift when failure happens before task planning', () async {
    final scenarioDir = Directory('${tempDir.path}/scenario')..createSync();
    const budgets = PlanModeTimeoutBudgets(
      planningTimeout: Duration(seconds: 5),
      executionTimeout: Duration(seconds: 20),
      executionStallTimeout: Duration(seconds: 45),
      overallTimeout: Duration(seconds: 70),
    );

    await writePlanModeFailureScenarioArtifacts(
      scenario: _scenario(),
      scenarioDir: scenarioDir,
      logs: const <String>[],
      error: TimeoutException('Scenario run timed out after 70s.'),
      stackTrace: StackTrace.current,
      phaseTrace: PlanModePhaseTrace(),
      budgets: budgets,
    );

    final report =
        jsonDecode(
              File(
                '${scenarioDir.path}/scenario_report.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    expect(report['taskDriftDetected'], isFalse);
    expect(
      (report['taskDrift'] as Map<String, dynamic>)['expectedTargetFiles'],
      isEmpty,
    );
  });
}

PlanModeScenarioSpec _scenario() {
  return const PlanModeScenarioSpec(
    name: 'failure_artifacts',
    userPrompt: 'Create a README.',
    projectName: 'plan-mode-failure-artifacts',
    workflowResponses: <PlanModeWorkflowResponseSpec>[],
    taskProposal: <PlanModeScenarioTaskSpec>[
      PlanModeScenarioTaskSpec(
        title: 'Create README',
        targetFiles: <String>['README.md'],
        validationCommand: 'test -f README.md',
        notes: 'Keep the fixture minimal.',
      ),
    ],
    toolWrites: <PlanModeScenarioToolWriteSpec>[],
    continuationStreams: <String>[],
    savedWorkflowExpectation: PlanModeSavedWorkflowExpectation(
      firstTaskTargetFilesContain: <String>['README.md'],
    ),
  );
}
