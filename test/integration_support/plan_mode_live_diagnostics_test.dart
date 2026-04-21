import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/test_support/plan_mode_live_diagnostics.dart';

void main() {
  group('buildPlanModeFailureDiagnostics', () {
    test('classifies execution stalls and extracts recent context', () {
      final diagnostics = buildPlanModeFailureDiagnostics(
        logs: const <String>[
          '[ContentTool]   - write_file: {path: src/main.py}',
          '[LLM] <think>Updating the main CLI loop to use YAML config.</think>',
        ],
        errorText:
            'Workflow execution stalled after 45s. tasks=Config loader:inProgress',
        stallDurationMs: 45000,
        budgetPhase: 'execution',
        activeTaskTitle: 'Config loader',
        toolResultCount: 2,
        fileWriteCount: 1,
        phaseTimings: const <String, String?>{
          'proposalReadyAt': '2026-04-18T14:00:00.000Z',
          'lastTaskProgressAt': '2026-04-18T14:00:45.000Z',
        },
        budgets: const <String, int?>{
          'planningTimeoutMs': 180000,
          'executionTimeoutMs': 180000,
        },
      );

      expect(diagnostics.failureClass, PlanModeFailureClass.executionStall);
      expect(diagnostics.lastToolName, 'write_file');
      expect(
        diagnostics.lastAssistantSummary,
        contains('Updating the main CLI loop'),
      );
      expect(diagnostics.stallDurationMs, 45000);
      expect(diagnostics.lastWorkflowSnapshot, 'Config loader:inProgress');
      expect(diagnostics.budgetPhase, 'execution');
      expect(diagnostics.activeTaskTitle, 'Config loader');
      expect(diagnostics.toolResultCount, 2);
      expect(diagnostics.fileWriteCount, 1);
      expect(diagnostics.phaseTimings['proposalReadyAt'], isNotNull);
      expect(diagnostics.budgets['executionTimeoutMs'], 180000);
    });

    test('classifies verification stalls from the latest ping CLI replay', () {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/plan_mode_ping_cli_verification_stall_replay.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;

      final diagnostics = buildPlanModeFailureDiagnostics(
        logs: (fixture['logs'] as List<dynamic>).cast<String>(),
        errorText: fixture['errorText'] as String,
      );

      expect(
        diagnostics.failureClass.name,
        fixture['expectedFailureClass'],
      );
      expect(
        diagnostics.activeTaskTitle,
        'Verify ping functionality with a real host',
      );
    });

    test('classifies unknown tool failures from logs', () {
      final diagnostics = buildPlanModeFailureDiagnostics(
        logs: const <String>[
          '[ContentTool]   - google: {}',
          '[ContentTool] Execution failed: No matching tool available: google',
        ],
        errorText: 'Scenario failed',
      );

      expect(diagnostics.failureClass, PlanModeFailureClass.unknownTool);
      expect(
        diagnostics.lastToolFailure,
        contains('No matching tool available'),
      );
    });

    test('classifies planning timeouts from explicit errors', () {
      final diagnostics = buildPlanModeFailureDiagnostics(
        logs: const <String>[],
        errorText:
            'Planning phase timed out after 180s while waiting for the plan proposal.',
      );

      expect(diagnostics.failureClass, PlanModeFailureClass.planningTimeout);
      expect(diagnostics.budgetPhase, 'planning');
    });

    test('classifies app foreground failures from startup logs', () {
      final diagnostics = buildPlanModeFailureDiagnostics(
        logs: const <String>[
          'Failed to foreground app; open returned 1',
          '[CanaryRunner] stage=foregroundFailed at=2026-04-19T12:00:00Z detail=open returned 1',
        ],
        errorText: 'Overall live run timed out after 240s.',
      );

      expect(
        diagnostics.failureClass,
        PlanModeFailureClass.appForegroundFailure,
      );
      expect(diagnostics.budgetPhase, 'startup');
    });

    test(
      'does not classify recovered foreground failures as startup failures',
      () {
        final diagnostics = buildPlanModeFailureDiagnostics(
          logs: const <String>[
            'Failed to foreground app; open returned 1',
            '[CanaryRunner] stage=foregroundFailed at=2026-04-19T12:00:00Z detail=open returned 1',
            '[CanaryRunner] stage=firstHeartbeatSeen at=2026-04-19T12:00:08Z',
            '[CanaryRunner] stage=foregroundRecovered at=2026-04-19T12:00:08Z',
          ],
          errorText: '',
        );

        expect(diagnostics.failureClass, PlanModeFailureClass.passed);
      },
    );

    test('classifies first-heartbeat startup timeouts separately', () {
      final diagnostics = buildPlanModeFailureDiagnostics(
        logs: const <String>[
          '[CanaryRunner] stage=buildFinished at=2026-04-19T12:00:00Z',
          '[CanaryRunner] stage=firstHeartbeatTimeout at=2026-04-19T12:00:45Z',
        ],
        errorText: 'App launch timed out before the first live heartbeat.',
      );

      expect(diagnostics.failureClass, PlanModeFailureClass.appLaunchTimeout);
      expect(diagnostics.budgetPhase, 'startup');
    });

    test('classifies planning decision waits separately from generic timeouts', () {
      final diagnostics = buildPlanModeFailureDiagnostics(
        logs: const <String>[
          '[ScenarioLive] Auto-accepted the default planning option.',
        ],
        errorText:
            'Planning phase timed out after 60s while waiting for the plan proposal. '
            'workflowDraft=false, taskDraft=false, isGeneratingWorkflow=false, '
            'isGeneratingTask=false, pendingDecision=true, workflowError=null, taskError=null',
      );

      expect(
        diagnostics.failureClass,
        PlanModeFailureClass.planningDecisionWait,
      );
      expect(diagnostics.budgetPhase, 'planning');
    });

    test('classifies short task proposals as planning quality failures', () {
      final diagnostics = buildPlanModeFailureDiagnostics(
        logs: const <String>[],
        errorText:
            'Saved workflow task proposal was too short. expectedMinTaskCount=2 actualTaskCount=1 tasks=Implement basic ping functionality in main.py',
      );

      expect(
        diagnostics.failureClass,
        PlanModeFailureClass.taskProposalQuality,
      );
      expect(diagnostics.budgetPhase, 'planning');
    });

    test('classifies blocked executions from explicit errors', () {
      final diagnostics = buildPlanModeFailureDiagnostics(
        logs: const <String>[
          '[LLM] <think>The current saved task is blocked until the file list is corrected.</think>',
        ],
        errorText:
            'Execution phase timed out after 120s. isLoading=true, pendingApprovals=false, activeTask=Scaffold task, toolResults=3, fileWrites=2, tasks=Scaffold task:blocked',
      );

      expect(diagnostics.failureClass, PlanModeFailureClass.blockedExecution);
      expect(diagnostics.lastWorkflowSnapshot, 'Scaffold task:blocked');
    });

    test('classifies blocked Python import failures separately', () {
      final diagnostics = buildPlanModeFailureDiagnostics(
        logs: const <String>[
          '[LLM] <think>The validation failed with ModuleNotFoundError: No module named \'ping_cli\'.</think>',
        ],
        errorText:
            'Bad state: Workflow execution remained blocked after 15s. activeTask=Implement core ping logic using subprocess toolResults=0 fileWrites=5 tasks=Implement core ping logic using subprocess:blocked lastAssistant=ModuleNotFoundError: No module named \'ping_cli\'',
      );

      expect(
        diagnostics.failureClass,
        PlanModeFailureClass.validationImportBlocked,
      );
      expect(
        diagnostics.activeTaskTitle,
        'Implement core ping logic using subprocess',
      );
    });

    test('classifies execution hangs from in-flight timeouts', () {
      final diagnostics = buildPlanModeFailureDiagnostics(
        logs: const <String>[
          '[LLM] <think>Continuing with the saved task.</think>',
        ],
        errorText:
            'Execution phase timed out after 120s. isLoading=true, pendingApprovals=false, activeTask=Implement CLI parsing, toolResults=0, fileWrites=0, tasks=Implement CLI parsing:inProgress',
      );

      expect(diagnostics.failureClass, PlanModeFailureClass.executionHang);
      expect(diagnostics.budgetPhase, 'execution');
    });

    test('classifies overall timeout with active execution as overrun', () {
      final diagnostics = buildPlanModeFailureDiagnostics(
        logs: const <String>[],
        errorText: 'Overall live run timed out after 240s.',
        lastKnownPhase: 'execution',
        lastWorkflowSnapshot:
            'Implement core ping logic and CLI arguments:blocked',
        activeTaskTitle: 'Implement core ping logic and CLI arguments',
      );

      expect(diagnostics.failureClass, PlanModeFailureClass.executionOverrun);
      expect(diagnostics.budgetPhase, 'execution');
    });

    test('classifies overall timeout in planning as planning timeout', () {
      final diagnostics = buildPlanModeFailureDiagnostics(
        logs: const <String>[],
        errorText: 'Overall live run timed out after 420s.',
        lastKnownPhase: 'planning',
      );

      expect(diagnostics.failureClass, PlanModeFailureClass.planningTimeout);
      expect(diagnostics.budgetPhase, 'planning');
    });

    test('classifies execution state loss when no active task remains', () {
      final diagnostics = buildPlanModeFailureDiagnostics(
        logs: const <String>[],
        errorText:
            'Execution phase timed out after 120s. isLoading=false, pendingApprovals=false, activeTask=none, toolResults=0, fileWrites=0, tasks=none',
      );

      expect(
        diagnostics.failureClass,
        PlanModeFailureClass.executionStateLost,
      );
      expect(diagnostics.budgetPhase, 'execution');
    });

    test('classifies execution drift from low-signal write timeouts', () {
      final diagnostics = buildPlanModeFailureDiagnostics(
        logs: const <String>[
          '[LLM] <think>The previous write_file for README.py succeeded.</think>',
        ],
        errorText:
            'Execution phase timed out after 120s. isLoading=false, pendingApprovals=false, activeTask=Implement monitor loop, toolResults=1, fileWrites=5, tasks=Implement monitor loop:inProgress',
      );

      expect(diagnostics.failureClass, PlanModeFailureClass.executionDrift);
      expect(diagnostics.activeTaskTitle, 'Implement monitor loop');
    });

    test('classifies replay cases from the latest ping CLI canary samples', () {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/plan_mode_ping_cli_execution_timeout_replay.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final cases = (fixture['cases'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      for (final entry in cases) {
        final diagnostics = buildPlanModeFailureDiagnostics(
          logs: (entry['logs'] as List<dynamic>).cast<String>(),
          errorText: entry['errorText'] as String,
        );

        expect(
          diagnostics.failureClass.name,
          entry['expectedFailureClass'],
          reason: 'Replay case "${entry['name']}" classified unexpectedly.',
        );
      }
    });

    test('returns passed when no error is present', () {
      final diagnostics = buildPlanModeFailureDiagnostics(
        logs: const <String>['[LLM] <think>All tasks are complete.</think>'],
      );

      expect(diagnostics.failureClass, PlanModeFailureClass.passed);
    });
  });
}
