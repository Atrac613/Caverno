import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:caverno/features/chat/domain/entities/conversation.dart';
import 'package:caverno/features/chat/domain/entities/conversation_workflow.dart';
import 'package:caverno/features/chat/domain/entities/message.dart';

import '../../integration_test/test_support/plan_mode_heartbeat.dart';
import '../../integration_test/test_support/plan_mode_post_scenario_settle.dart';
import '../../integration_test/test_support/plan_mode_report_summary.dart';
import '../../integration_test/test_support/plan_mode_scenario_reporting.dart';
import '../../integration_test/test_support/plan_mode_scenario_spec.dart';
import '../../integration_test/test_support/plan_mode_task_drift.dart';
import '../../integration_test/test_support/plan_mode_warning_policy.dart';

void main() {
  group('plan mode scenario reporting', () {
    test('writes passed scenario report and log artifacts', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'plan_mode_scenario_reporting_test_',
      );
      try {
        await File(
          '${tempDir.path}/README.md',
        ).writeAsString('# Host Health Check\n');
        final scenario = _scenario();
        final savedWorkflow = _workflowSpec();
        final conversation = _conversation(savedWorkflow);
        final heartbeatPath = '${tempDir.path}/heartbeat.json';
        File(heartbeatPath).writeAsStringSync(
          jsonEncode(<String, Object?>{
            'scenario': 'report_case',
            'phase': 'completed',
            'subphase': 'scenarioCompleted',
          }),
        );
        final logs = <String>[
          '[Workflow] Task proposal ready',
          '[Tool] Executing tool: write_file',
          '[Tool] Lifecycle {"toolCallId":"tool-write","toolName":"write_file","lifecycleState":"completed","loopIndex":1,"schedulerClass":"serial","resultStatus":"success","durationMs":7}',
          '[Screenshot] Saved completed screenshot',
        ];

        final result = await writePlanModePassedScenarioReport(
          scenario: scenario,
          scenarioDir: tempDir,
          executionModeName: 'fake',
          approvalPath: planModeApprovalPathUi,
          conversation: conversation,
          savedWorkflow: savedWorkflow,
          logs: logs,
          warnings: const <String>[],
          warningSummary: const PlanModeWarningSummary(
            allowedWarnings: <String>[],
            unexpectedWarnings: <String>[],
            details: <PlanModeWarningDetail>[],
          ),
          postScenarioSettle: const PlanModePostScenarioSettleResult(
            initiallySettled: true,
            settled: true,
            cancellationUsed: false,
          ),
          phaseTrace: PlanModePhaseTrace(),
          budgets: _budgets(),
          heartbeatPath: heartbeatPath,
        );

        final report =
            jsonDecode(File(result.reportPath).readAsStringSync())
                as Map<String, dynamic>;
        expect(report['scenario'], 'report_case');
        expect(report['status'], 'passed');
        expect(report['approvalPath'], planModeApprovalPathUi);
        expect(
          report['artifacts'],
          containsPair('README.md', '# Host Health Check\n'),
        );
        expect(report['taskDriftDetected'], isFalse);
        expect(report['diagnostics'], containsPair('budgetPhase', 'completed'));
        expect(
          report['lastHeartbeat'],
          containsPair('subphase', 'scenarioCompleted'),
        );
        expect(
          report['toolLifecycle'],
          allOf(
            containsPair('eventCount', 1),
            containsPair('completedCount', 1),
            containsPair('maxDurationMs', 7),
          ),
        );
        expect(
          report['capturedLogs'],
          isNot(contains('[Workflow] Task proposal ready')),
        );
        expect(
          report['capturedLogs'],
          contains('[Tool] Executing tool: write_file'),
        );
        expect(File(result.logPath).readAsStringSync(), contains('[Workflow]'));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('builds archived suite result from scenario report fields', () {
      final startedAt = DateTime(2026, 5, 12, 12);
      final finishedAt = startedAt.add(const Duration(seconds: 2));
      final result = buildPlanModeArchivedSuiteResult(
        scenario: _scenario(),
        modeName: 'fake',
        startedAt: startedAt,
        finishedAt: finishedAt,
        tempOutputDirectoryPath: '/tmp/source',
        archivedOutputDirectoryPath: '/tmp/archive/report_case',
        archivedReportPath: '/tmp/archive/report_case/scenario_report.json',
        archivedLogPath: '/tmp/archive/report_case/scenario_log.txt',
        archivedScreenshotPaths: const <String>['completed.png'],
        archivedReport: const <String, Object?>{
          'failureClass': 'passed',
          'diagnostics': <String, Object?>{'budgetPhase': 'completed'},
          'lastHeartbeat': <String, Object?>{
            'phase': 'completed',
            'activeTaskTitle': 'Write README',
            'updatedAt': '2026-05-12T12:00:02.000',
          },
          'taskDrift': <String, Object?>{'driftDetected': true},
          'toolLoopConvergence': <String, Object?>{'status': 'natural_stop'},
          'toolLifecycle': <String, Object?>{
            'eventCount': 1,
            'toolCallCount': 1,
          },
          'warnings': <String>['warning'],
          'allowedWarnings': <String>[],
          'unexpectedWarnings': <String>['warning'],
          'warningSummary': <String, Object?>{
            'details': <Map<String, String>>[
              <String, String>{
                'warning': 'warning',
                'disposition': 'unexpected',
                'reason': 'requiresInvestigation',
              },
            ],
          },
          'approvalPath': planModeApprovalPathLiveHarnessFallback,
          'postScenarioSettled': true,
          'postScenarioCancellationUsed': false,
        },
        failure: null,
        failureStackTrace: null,
      );

      expect(result['scenario'], 'report_case');
      expect(result['status'], 'passed');
      expect(result['durationMs'], 2000);
      expect(result['budgetPhase'], 'completed');
      expect(result['lastKnownPhase'], 'completed');
      expect(result['activeTaskTitle'], 'Write README');
      expect(result['taskDriftDetected'], isTrue);
      expect(result['toolLifecycle'], containsPair('toolCallCount', 1));
      expect(result['usedHarnessApprovalFallback'], isTrue);
      expect(result['unexpectedWarnings'], <Object?>['warning']);
      expect(result['warningDetails'], hasLength(1));
      expect(
        result['warningDetails'],
        contains(containsPair('reason', 'requiresInvestigation')),
      );
    });

    test(
      'uses projected task targets when saved workflow targets are empty',
      () {
        final conversation = _conversation(
          const ConversationWorkflowSpec(
            goal: 'Create a host health README.',
            tasks: <ConversationWorkflowTask>[
              ConversationWorkflowTask(
                id: 'task-1',
                title: 'Write README',
                targetFiles: <String>['README.md'],
              ),
            ],
          ),
        );

        expect(
          resolvePlanModeScenarioSavedTaskTargetFiles(
            conversation: conversation,
            savedWorkflow: const ConversationWorkflowSpec(
              goal: 'Create a host health README.',
              tasks: <ConversationWorkflowTask>[],
            ),
          ),
          <String>['README.md'],
        );
      },
    );

    test('collects only present artifacts in any required mode', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'plan_mode_scenario_reporting_test_',
      );
      try {
        File('${tempDir.path}/requirements.txt').writeAsStringSync('ping3\n');

        expect(
          collectPlanModeScenarioArtifactContents(
            scenarioDir: tempDir,
            expectations: const <PlanModeArtifactExpectation>[
              PlanModeArtifactExpectation(path: 'requirements.txt'),
              PlanModeArtifactExpectation(path: 'README.md'),
            ],
            mode: PlanModeArtifactExpectationMode.anyRequired,
          ),
          const <String, String>{'requirements.txt': 'ping3\n'},
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('uses started task targets for auto-continued execution', () {
      final savedWorkflow = const ConversationWorkflowSpec(
        goal: 'Create a host health CLI.',
        tasks: <ConversationWorkflowTask>[
          ConversationWorkflowTask(
            id: 'task-1',
            title: 'Initialize project structure',
            targetFiles: <String>['requirements.txt', 'README.md'],
          ),
          ConversationWorkflowTask(
            id: 'task-2',
            title: 'Implement CLI entry point',
            targetFiles: <String>['main.py'],
          ),
        ],
      );
      final conversation = _conversation(
        const ConversationWorkflowSpec(
          goal: 'Create a host health CLI.',
          tasks: <ConversationWorkflowTask>[
            ConversationWorkflowTask(
              id: 'task-1',
              title: 'Initialize project structure',
              status: ConversationWorkflowTaskStatus.completed,
              targetFiles: <String>['requirements.txt', 'README.md'],
            ),
            ConversationWorkflowTask(
              id: 'task-2',
              title: 'Implement CLI entry point',
              status: ConversationWorkflowTaskStatus.inProgress,
              targetFiles: <String>['main.py'],
            ),
            ConversationWorkflowTask(
              id: 'task-3',
              title: 'Add JSON report output',
              targetFiles: <String>['report.py'],
            ),
          ],
        ),
      );

      expect(
        resolvePlanModeScenarioSavedTaskTargetFiles(
          conversation: conversation,
          savedWorkflow: savedWorkflow,
        ),
        <String>['README.md', 'main.py', 'requirements.txt'],
      );
    });

    test(
      'infers projected task targets from task text when explicit targets are empty',
      () {
        final conversation = _conversation(
          const ConversationWorkflowSpec(
            goal: 'Create a ping CLI.',
            tasks: <ConversationWorkflowTask>[
              ConversationWorkflowTask(
                id: 'task-1',
                title: 'Implement ping_cli.py',
                validationCommand: 'python3 ping_cli.py --help',
              ),
              ConversationWorkflowTask(
                id: 'task-2',
                title: 'Verify ping execution',
              ),
            ],
          ),
        );

        expect(
          resolvePlanModeScenarioSavedTaskTargetFiles(
            conversation: conversation,
            savedWorkflow: const ConversationWorkflowSpec(
              goal: 'Create a ping CLI.',
              tasks: <ConversationWorkflowTask>[],
            ),
          ),
          <String>['ping_cli.py'],
        );
      },
    );

    test('uses started targets for limited harness task drift', () {
      final scenario = PlanModeScenarioSpec(
        name: 'limited_live',
        userPrompt: 'Create requirements.txt and README.md.',
        projectName: 'Host Health',
        workflowResponses: const <PlanModeWorkflowResponseSpec>[],
        taskProposal: const <PlanModeScenarioTaskSpec>[],
        toolWrites: const <PlanModeScenarioToolWriteSpec>[],
        continuationStreams: const <String>[],
        harnessTaskExecutionLimit: 1,
        savedWorkflowExpectation: const PlanModeSavedWorkflowExpectation(
          targetFilesContain: <String>['requirements.txt', 'README.md'],
        ),
      );

      expect(
        resolvePlanModeScenarioExpectedTaskDriftTargetFiles(
          scenario: scenario,
          savedTaskTargetFiles: const <String>['requirements.txt'],
        ),
        const <String>['requirements.txt'],
      );
    });
  });
}

PlanModeScenarioSpec _scenario() {
  return const PlanModeScenarioSpec(
    name: 'report_case',
    userPrompt: 'Create a host health README.',
    projectName: 'Host Health',
    workflowResponses: <PlanModeWorkflowResponseSpec>[],
    taskProposal: <PlanModeScenarioTaskSpec>[],
    toolWrites: <PlanModeScenarioToolWriteSpec>[],
    continuationStreams: <String>[],
    artifactExpectations: <PlanModeArtifactExpectation>[
      PlanModeArtifactExpectation(path: 'README.md'),
    ],
    logExpectations: <PlanModeLogExpectation>[
      PlanModeLogExpectation(pattern: '[Tool]', minCount: 1),
    ],
    savedWorkflowExpectation: PlanModeSavedWorkflowExpectation(
      firstTaskTargetFilesContain: <String>['README.md'],
    ),
    decisionSelections: <PlanModeScenarioDecisionSelection>[
      PlanModeScenarioDecisionSelection(
        question: 'Which file should be updated?',
        optionLabel: 'README.md',
      ),
    ],
    tags: <String>['smoke'],
  );
}

ConversationWorkflowSpec _workflowSpec() {
  return const ConversationWorkflowSpec(
    goal: 'Create a host health README.',
    openQuestions: <String>[],
    tasks: <ConversationWorkflowTask>[
      ConversationWorkflowTask(
        id: 'task-1',
        title: 'Write README',
        status: ConversationWorkflowTaskStatus.completed,
        targetFiles: <String>['README.md'],
      ),
    ],
  );
}

Conversation _conversation(ConversationWorkflowSpec workflowSpec) {
  final now = DateTime(2026, 5, 12, 12);
  return Conversation(
    id: 'conversation-1',
    title: 'Plan mode report case',
    messages: const <Message>[],
    createdAt: now,
    updatedAt: now,
    workflowStage: ConversationWorkflowStage.review,
    workflowSpec: workflowSpec,
  );
}

PlanModeTimeoutBudgets _budgets() {
  return const PlanModeTimeoutBudgets(
    planningTimeout: Duration(seconds: 5),
    executionTimeout: Duration(seconds: 20),
    executionStallTimeout: Duration(seconds: 45),
    overallTimeout: Duration(seconds: 60),
  );
}
