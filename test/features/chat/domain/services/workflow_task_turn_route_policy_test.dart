import 'package:caverno/features/chat/domain/services/workflow_task_turn_route_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WorkflowTaskTurnRoutePolicy', () {
    test('keeps the specialized recovery routes in exact precedence', () {
      expect(
        WorkflowTaskTurnRoutePolicy.recoveryRoutes(toolResultApplied: false),
        const [
          WorkflowTaskTurnRecoveryRoute.validationFirstExecution,
          WorkflowTaskTurnRecoveryRoute.toolFailureSignals,
          WorkflowTaskTurnRecoveryRoute.missingTargetValidation,
          WorkflowTaskTurnRecoveryRoute.missingPythonRuntimeDependency,
          WorkflowTaskTurnRecoveryRoute.missingPythonTestDependency,
          WorkflowTaskTurnRecoveryRoute.pythonSourceLayoutValidation,
          WorkflowTaskTurnRecoveryRoute.taskDrift,
        ],
      );
    });

    test('skips specialized recovery after tool evidence is applied', () {
      expect(
        WorkflowTaskTurnRoutePolicy.recoveryRoutes(toolResultApplied: true),
        isEmpty,
      );
    });

    test('captures assistant evidence only before terminal evidence', () {
      for (final completionPromoted in [false, true]) {
        for (final recoveryApplied in [false, true]) {
          expect(
            WorkflowTaskTurnRoutePolicy.shouldCaptureAssistantEvidence(
              completionPromoted: completionPromoted,
              recoveryApplied: recoveryApplied,
            ),
            !completionPromoted && !recoveryApplied,
            reason:
                'completionPromoted=$completionPromoted, recoveryApplied=$recoveryApplied',
          );
        }
      }
    });

    test('attempts tool-less recovery only after an unresolved empty route', () {
      for (final toolResultApplied in [false, true]) {
        for (final recoveryApplied in [false, true]) {
          expect(
            WorkflowTaskTurnRoutePolicy.shouldAttemptToolLessRecovery(
              toolResultApplied: toolResultApplied,
              recoveryApplied: recoveryApplied,
            ),
            !toolResultApplied && !recoveryApplied,
            reason:
                'toolResultApplied=$toolResultApplied, recoveryApplied=$recoveryApplied',
          );
        }
      }
    });
  });
}
