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
