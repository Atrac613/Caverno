import '../entities/tool_call_info.dart';
import 'recovery_execution_signature.dart';
import 'unresolved_verification_failure.dart';

/// Reserves repair attempts and tracks the status report each repair owes.
final class VerificationRepairBudget {
  final verificationResultsAtRequest = <int, Set<String>>{};
  final attempts = <int, Set<String>>{};
  final pendingStatus = <int>{};
  static const maxVerificationRepairAttempts = 2;
  bool canRepairVerification(int generation, List<ToolResultInfo> results) {
    final failure = const UnresolvedVerificationFailure().latest(results);
    if (failure == null ||
        RecoveryExecutionSignature.wasReused(failure) ||
        !RecoveryExecutionSignature.terminalIds(results).contains(failure.id)) {
      return false;
    }
    final prior = attempts[generation] ?? const {};
    return prior.length < maxVerificationRepairAttempts &&
        !prior.contains(failure.id);
  }

  /// Fresh failed executions can request bounded repair, independently of
  /// status-only recovery. Reads, cached results and new hashes cannot renew it.
  bool claimVerificationRepair(int generation, List<ToolResultInfo> results) {
    if (!canRepairVerification(generation, results)) return false;
    final failure = const UnresolvedVerificationFailure().latest(results)!;
    attempts.putIfAbsent(generation, () => {}).add(failure.id);
    verificationResultsAtRequest[generation] =
        RecoveryExecutionSignature.terminalIds(results);
    pendingStatus.add(generation);
    return true;
  }

  /// A finished verification or declined repair still owes a status report.
  bool needsVerificationStatus(int generation, List<ToolResultInfo> results) {
    final previous = verificationResultsAtRequest[generation];
    return pendingStatus.contains(generation) ||
        (previous != null &&
            RecoveryExecutionSignature.terminalIds(
              results,
            ).any((id) => !previous.contains(id)));
  }

  void remove(int generation) {
    verificationResultsAtRequest.remove(generation);
    attempts.remove(generation);
    pendingStatus.remove(generation);
  }

  void clear() {
    verificationResultsAtRequest.clear();
    attempts.clear();
    pendingStatus.clear();
  }
}
