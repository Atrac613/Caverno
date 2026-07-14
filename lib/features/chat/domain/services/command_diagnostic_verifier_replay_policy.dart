import 'stalled_diagnostic_repair_contract.dart';

class CommandDiagnosticVerifierReplayPolicy {
  const CommandDiagnosticVerifierReplayPolicy();

  bool shouldBlock({
    required CommandDiagnosticRepairFocus? focus,
    required String attemptedCommandKey,
    required bool isVerification,
    required bool hasPrecedingMutation,
  }) {
    return focus != null &&
        focus.hasPathBackedDiagnostic &&
        isVerification &&
        !hasPrecedingMutation &&
        attemptedCommandKey == focus.commandKey;
  }
}
