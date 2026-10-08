enum VerificationCadence { notDue, due, required }

class VerificationCadencePolicy {
  const VerificationCadencePolicy();

  VerificationCadence decide({
    required int mutationGeneration,
    required int verificationGeneration,
    required bool taskRequiresValidation,
    required bool taskCompleted,
    required bool validationFailed,
  }) {
    if (validationFailed) {
      return VerificationCadence.required;
    }
    final verificationIsStale = mutationGeneration > verificationGeneration;
    if (verificationIsStale && (mutationGeneration > 0 || taskCompleted)) {
      return VerificationCadence.required;
    }
    if (taskRequiresValidation && verificationGeneration < 0) {
      return taskCompleted
          ? VerificationCadence.required
          : VerificationCadence.due;
    }
    return VerificationCadence.notDue;
  }
}
