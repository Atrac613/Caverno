const planModeSavedValidationConvergenceGuardPattern =
    '[Tool] Ignoring follow-up tool calls after saved validation success';

Map<String, Object> buildPlanModeToolLoopConvergenceReport(List<String> logs) {
  final guardActivations = logs
      .where(
        (line) => line.contains(planModeSavedValidationConvergenceGuardPattern),
      )
      .length;
  return <String, Object>{
    'detected': guardActivations > 0,
    'guardActivations': guardActivations,
    'guardPattern': planModeSavedValidationConvergenceGuardPattern,
  };
}
