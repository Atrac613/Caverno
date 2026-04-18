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
      );

      expect(diagnostics.failureClass, PlanModeFailureClass.executionStall);
      expect(diagnostics.lastToolName, 'write_file');
      expect(
        diagnostics.lastAssistantSummary,
        contains('Updating the main CLI loop'),
      );
      expect(diagnostics.stallDurationMs, 45000);
      expect(diagnostics.lastWorkflowSnapshot, 'Config loader:inProgress');
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

    test('returns passed when no error is present', () {
      final diagnostics = buildPlanModeFailureDiagnostics(
        logs: const <String>['[LLM] <think>All tasks are complete.</think>'],
      );

      expect(diagnostics.failureClass, PlanModeFailureClass.passed);
    });
  });
}
