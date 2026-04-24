const planModeSavedValidationConvergenceGuardPattern =
    '[Tool] Ignoring follow-up tool calls after saved validation success';

const planModeSavedValidationSuccessPattern =
    '[Tool] Saved validation command succeeded';

Map<String, Object> buildPlanModeToolLoopConvergenceReport(List<String> logs) {
  final successfulValidations = logs
      .where((line) => line.contains(planModeSavedValidationSuccessPattern))
      .length;
  final guardActivations = logs
      .where(
        (line) => line.contains(planModeSavedValidationConvergenceGuardPattern),
      )
      .length;
  final naturalStops = successfulValidations > guardActivations
      ? successfulValidations - guardActivations
      : 0;
  var status = 'not_observed';
  if (guardActivations > 0) {
    status = 'guarded';
  } else if (successfulValidations > 0) {
    status = 'natural_stop';
  }
  return <String, Object>{
    'detected': guardActivations > 0,
    'status': status,
    'successfulValidations': successfulValidations,
    'guardActivations': guardActivations,
    'naturalStops': naturalStops,
    'successPattern': planModeSavedValidationSuccessPattern,
    'guardPattern': planModeSavedValidationConvergenceGuardPattern,
  };
}
