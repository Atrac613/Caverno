import '../entities/tool_call_info.dart';
import 'recovery_execution_signature.dart';
import 'verification/verification_repair_budget.dart';

/// Bounds recovery while reserving status reports for finished verification.
final class TurnFinalizationRecoveryBudget {
  final _attempts = <int, Set<String>>{};
  final _repairs = VerificationRepairBudget();
  static const maxVerificationRepairAttempts =
      VerificationRepairBudget.maxVerificationRepairAttempts;

  bool canRepairVerification(int generation, List<ToolResultInfo> results) =>
      _repairs.canRepairVerification(generation, results);
  bool claimVerificationRepair(int generation, List<ToolResultInfo> results) =>
      _repairs.claimVerificationRepair(generation, results);
  bool needsVerificationStatus(int generation, List<ToolResultInfo> results) =>
      _repairs.needsVerificationStatus(generation, results);

  bool claim(
    int generation, {
    required bool structuredTask,
    required List<ToolResultInfo> results,
    bool statusOnly = false,
  }) {
    if (statusOnly &&
        (!structuredTask || !needsVerificationStatus(generation, results))) {
      return false;
    }
    final attempts = _attempts.putIfAbsent(generation, () => {});
    if (!structuredTask) return attempts.isEmpty && attempts.add('legacy');
    if (attempts.length >= 3) return false;
    var key = RecoveryExecutionSignature.of(results);
    final terminalIds = RecoveryExecutionSignature.terminalIds(results);
    if (statusOnly && attempts.contains(key)) {
      key = RecoveryExecutionSignature.status(
        terminalIds.difference(
          _repairs.verificationResultsAtRequest[generation]!,
        ),
      );
    }
    if (!attempts.add(key)) return false;
    _repairs.verificationResultsAtRequest[generation] = terminalIds;
    _repairs.pendingStatus.remove(generation);
    return true;
  }

  void remove(int generation) {
    _attempts.remove(generation);
    _repairs.remove(generation);
  }

  void clear() {
    _attempts.clear();
    _repairs.clear();
  }
}
