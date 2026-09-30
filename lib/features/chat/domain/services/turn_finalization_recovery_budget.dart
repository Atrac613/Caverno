import 'dart:convert';

import '../entities/tool_call_info.dart';
import 'coding_command_output_issue_detector.dart';
import 'command_verification_reconciliation.dart';
import 'pytest_verification_identity.dart';

/// Bounds status requests and permits another only after mechanical progress.
final class TurnFinalizationRecoveryBudget {
  final _attempts = <int, Set<String>>{};

  bool claim(
    int generation, {
    required bool structuredTask,
    required List<ToolResultInfo> results,
  }) {
    final attempts = _attempts.putIfAbsent(generation, () => {});
    if (!structuredTask) return attempts.isEmpty && attempts.add('legacy');
    if (attempts.length >= 3) return false;
    final mutations = <String, String?>{};
    final verifications = <String>{};
    for (final result in CommandVerificationReconciliation.currentResults(
      results,
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
    return attempts.add(
      jsonEncode([mutations, verifications.toList()..sort()]),
    );
  }

  void remove(int generation) => _attempts.remove(generation);
  void clear() => _attempts.clear();
}
