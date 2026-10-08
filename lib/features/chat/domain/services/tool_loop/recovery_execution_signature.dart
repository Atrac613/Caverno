import 'dart:convert';

import '../../entities/tool_call_info.dart';
import '../coding/coding_command_output_issue_detector.dart';
import '../verification/command_verification_reconciliation.dart';

/// Stable fresh-execution identity for bounded finalization recovery.
abstract final class RecoveryExecutionSignature {
  static String of(List<ToolResultInfo> results) {
    final mutations = <String, String?>{};
    final verifications = <String>{};
    for (final result in CommandVerificationReconciliation.currentResults(
      results.where((result) => !wasReused(result)).toList(),
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
        final scope = CommandVerificationReconciliation.scopeOf(result);
        final tests = result.outcome?.testOutcome;
        verifications.add(
          jsonEncode([
            result.name,
            scope?.key ?? result.arguments,
            if (tests != null)
              [tests.passedCount, tests.failedCount, tests.skippedCount],
          ]),
        );
      }
    }
    return jsonEncode([mutations, verifications.toList()..sort()]);
  }

  static String status(Set<String> ids) =>
      jsonEncode(['verification_status', ids.toList()..sort()]);

  static Set<String> terminalIds(List<ToolResultInfo> results) => {
    for (final result in results)
      if (CommandVerificationReconciliation.isVerification(result) &&
          !wasReused(result) &&
          result.outcome != null &&
          (result.outcome!.exitCode != null ||
              result.outcome!.testOutcome != null ||
              result.outcome!.diagnosticErrorCount != null) &&
          (result.outcome!.processState == null ||
              result.outcome!.isProcessTerminal))
        result.id,
  };

  static bool wasReused(ToolResultInfo result) {
    try {
      final payload = jsonDecode(result.result);
      return payload is Map && payload['execution_reused'] == true;
    } on FormatException {
      return false;
    }
  }
}
