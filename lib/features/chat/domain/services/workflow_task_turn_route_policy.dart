enum WorkflowTaskTurnRecoveryRoute {
  validationFirstExecution,
  toolFailureSignals,
  missingTargetValidation,
  missingPythonRuntimeDependency,
  missingPythonTestDependency,
  pythonSourceLayoutValidation,
  taskDrift,
}

abstract final class WorkflowTaskTurnRoutePolicy {
  static const _orderedRecoveryRoutes = <WorkflowTaskTurnRecoveryRoute>[
    WorkflowTaskTurnRecoveryRoute.validationFirstExecution,
    WorkflowTaskTurnRecoveryRoute.toolFailureSignals,
    WorkflowTaskTurnRecoveryRoute.missingTargetValidation,
    WorkflowTaskTurnRecoveryRoute.missingPythonRuntimeDependency,
    WorkflowTaskTurnRecoveryRoute.missingPythonTestDependency,
    WorkflowTaskTurnRecoveryRoute.pythonSourceLayoutValidation,
    WorkflowTaskTurnRecoveryRoute.taskDrift,
  ];

  static List<WorkflowTaskTurnRecoveryRoute> recoveryRoutes({
    required bool toolResultApplied,
  }) {
    return toolResultApplied
        ? const <WorkflowTaskTurnRecoveryRoute>[]
        : _orderedRecoveryRoutes;
  }

  static bool shouldCaptureAssistantEvidence({
    required bool completionPromoted,
    required bool recoveryApplied,
  }) {
    return !completionPromoted && !recoveryApplied;
  }

  static bool shouldAttemptToolLessRecovery({
    required bool toolResultApplied,
    required bool recoveryApplied,
  }) {
    return !toolResultApplied && !recoveryApplied;
  }
}
