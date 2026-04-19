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

    test('returns passed when no error is present', () {
      final diagnostics = buildPlanModeFailureDiagnostics(
        logs: const <String>['[LLM] <think>All tasks are complete.</think>'],
      );

      expect(diagnostics.failureClass, PlanModeFailureClass.passed);
    });
  });
}
