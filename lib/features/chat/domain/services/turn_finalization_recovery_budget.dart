import 'dart:convert';

import '../entities/tool_call_info.dart';
import 'coding_command_output_issue_detector.dart';
import 'command_verification_reconciliation.dart';
import 'pytest_verification_identity.dart';

/// Bounds recovery while reserving status reports for finished verification.
final class TurnFinalizationRecoveryBudget {
  final _attempts = <int, Set<String>>{};
  final _verificationResultsAtRequest = <int, Set<String>>{};

  /// A finished verification owes a status report even when it failed.
  bool needsVerificationStatus(int generation, List<ToolResultInfo> results) {
    final previous = _verificationResultsAtRequest[generation];
    return previous != null &&
        _terminalVerificationIds(results).any((id) => !previous.contains(id));
  }

  /// Failed outcomes permit only a control request whose tools the recovery
  /// plan restricts to update_goal; they never renew implementation work.
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
    final mutations = <String, String?>{};
    final verifications = <String>{};
    for (final result in CommandVerificationReconciliation.currentResults(
      results.where((result) => !_wasReused(result)).toList(),
    )) {
      for (final mutation in result.outcome?.fileMutations ?? []) {
        if (mutation.changed == true) {
          mutations[mutation.path] = mutation.contentHash;
        }
      }
      if (CommandVerificationReconciliation.isVerification(result) &&
          result.outcome?.hasSucceedingExitCode == true &&
          (result.outcome?.processState == null ||
              result.outcome!.isProcessTerminal) &&
          (result.outcome?.effectiveTestFailedCount ?? 0) == 0 &&
          (result.outcome?.diagnosticErrorCount ?? 0) == 0 &&
          const CodingCommandOutputIssueDetector().detect(result) == null) {
        final identity = PytestVerificationIdentity.parse(
          result.arguments['command']?.toString() ?? '',
          result.arguments['working_directory']?.toString() ?? '',
        );
        final tests = result.outcome?.testOutcome;
        verifications.add(
          jsonEncode([
            result.name,
            identity?.key ?? result.arguments,
            if (tests != null)
              [tests.passedCount, tests.failedCount, tests.skippedCount],
          ]),
        );
      }
    }
    var key = jsonEncode([mutations, verifications.toList()..sort()]);
    final terminalIds = _terminalVerificationIds(results);
    if (statusOnly && attempts.contains(key)) {
      key = jsonEncode([
        'verification_status',
        terminalIds
            .difference(_verificationResultsAtRequest[generation]!)
            .toList()
          ..sort(),
      ]);
    }
    if (!attempts.add(key)) return false;
    _verificationResultsAtRequest[generation] = terminalIds;
    return true;
  }

  static Set<String> _terminalVerificationIds(List<ToolResultInfo> results) => {
    for (final result in results)
      if (CommandVerificationReconciliation.isVerification(result) &&
          !_wasReused(result) &&
          result.outcome != null &&
          (result.outcome!.exitCode != null ||
              result.outcome!.testOutcome != null ||
              result.outcome!.diagnosticErrorCount != null) &&
          (result.outcome!.processState == null ||
              result.outcome!.isProcessTerminal))
        result.id,
  };

  static bool _wasReused(ToolResultInfo result) {
    try {
      final payload = jsonDecode(result.result);
      return payload is Map && payload['execution_reused'] == true;
    } on FormatException {
      return false;
    }
  }

  void remove(int generation) {
    _attempts.remove(generation);
    _verificationResultsAtRequest.remove(generation);
  }

  void clear() {
    _attempts.clear();
    _verificationResultsAtRequest.clear();
  }
}
