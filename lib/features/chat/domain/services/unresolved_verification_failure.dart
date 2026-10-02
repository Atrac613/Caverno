import 'dart:convert';

import '../entities/tool_call_info.dart';
import 'coding_command_output_issue_detector.dart';
import 'command_verification_reconciliation.dart';
import 'shell_exit_status_report.dart';

/// Names the verification command whose failure still blocks completion.
///
/// Verification is reconciled per command, so a different command passing
/// later does not clear a failure. The gap used to read "the last
/// verification command failed", which was untrue once a later command had
/// passed: in session d0c0462c a network-dependent
/// `watcher.py --dry-run | head` failed with exit 120, and the model re-ran
/// its passing test suite three times without learning which check it owed.
final class UnresolvedVerificationFailure {
  const UnresolvedVerificationFailure();

  static const _maxCommandLength = 160;

  /// The gap text for the most recent failed verification, or null when no
  /// executed verification failed (for example, a guardrail feedback failure).
  String? describe(List<ToolResultInfo> results) {
    final current = CommandVerificationReconciliation.currentResults(results);
    for (final result in current.reversed) {
      if (!CommandVerificationReconciliation.isVerification(result)) continue;
      final outcome = result.outcome;
      final outputIssue = const CodingCommandOutputIssueDetector().detect(
        result,
      );
      final failed =
          outputIssue != null ||
          (outcome?.effectiveTestFailedCount ?? 0) > 0 ||
          (CommandVerificationReconciliation.testOutcome(result)?.failedCount ??
                  0) >
              0 ||
          (outcome?.diagnosticErrorCount ?? 0) > 0 ||
          (outcome?.hasFailingExitCode ?? false);
      if (!failed) continue;
      Map<String, dynamic>? payload;
      try {
        final decoded = jsonDecode(result.result);
        if (decoded is Map<String, dynamic>) payload = decoded;
      } on FormatException {
        // A budgeted result may have lost its payload; keep the failure.
      }
      final raw =
          (payload?['command'] ?? result.arguments['command'] ?? result.name)
              .toString()
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
      final command = raw.length <= _maxCommandLength
          ? raw
          : '${raw.substring(0, _maxCommandLength)}...';
      final exit = outcome?.exitCode;
      final reportedExit =
          ShellExitStatusReport.parse(
            (payload?['command'] ?? result.arguments['command'])?.toString() ??
                '',
          )?.exitCode(
            (payload?['stdout'] ?? payload?['stdout_tail'])?.toString() ?? '',
          );
      final exitDetail = reportedExit != null && reportedExit != 0
          ? ' (reported exit $reportedExit${exit == null ? '' : '; shell exit $exit'})'
          : outputIssue != null
          ? ' (${outputIssue.summary})'
          : exit == null
          ? ''
          : ' (exit $exit)';
      return 'the verification `$command` failed'
          '$exitDetail and has not passed since; '
          'a different command passing does not clear it. Re-run it until it '
          'passes, or report blocked_reason if it cannot pass in this '
          'environment';
    }
    return null;
  }
}
