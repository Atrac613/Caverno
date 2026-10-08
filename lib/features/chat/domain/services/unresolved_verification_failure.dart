import 'dart:convert';

import '../entities/tool_call_info.dart';
import 'coding/coding_command_output_issue_detector.dart';
import 'command_verification_reconciliation.dart';
import 'local_command/shell_exit_status_report.dart';
import 'python/inline_python_verification_contract.dart';

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

  /// The most recent failed check after matching successful runs are settled.
  ToolResultInfo? latest(List<ToolResultInfo> results) {
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
      return result;
    }
    return null;
  }

  /// The gap text for the most recent failed verification, or null when no
  /// executed verification failed (for example, a guardrail feedback failure).
  String? describe(List<ToolResultInfo> results) {
    final result = latest(results);
    if (result == null) return null;
    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(result.result);
      if (decoded is Map<String, dynamic>) payload = decoded;
    } on FormatException {
      // A budgeted result may have lost its payload; keep the failure.
    }
    final outputIssue = const CodingCommandOutputIssueDetector().detect(result);
    final raw =
        (payload?['command'] ?? result.arguments['command'] ?? result.name)
            .toString()
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    final command = raw.length <= _maxCommandLength
        ? raw
        : '${raw.substring(0, _maxCommandLength)}...';
    final exit = result.outcome?.exitCode;
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
    final scope = CommandVerificationReconciliation.scopeOf(result);
    if (scope?.runtimeLaunchFailed == true) {
      return 'the verification `$command` failed$exitDetail before pytest could launch. '
          'Use capturedEvidence.unresolvedVerification.runtimeRepairCommand when available, '
          'or replace only the Python executable in the full recorded chain with the '
          'captured working runtime. Preserve all prerequisites, imports and checks; '
          'run the full chain again. A different script or a standalone test pass '
          'does not settle this failure';
    }
    if (scope?.pytestRunner case final runner?) {
      // A pytest scope is settled by the same tests passing under any
      // interpreter. "Re-run it" sent the model in session 016d4d5e to replay
      // the venv setup in front of pytest, deleting a working venv each time.
      return 'the pytest run in `$command` failed$exitDetail and has not '
          'passed since. A passing run of the same tests in '
          '${runner.directory} settles it, for example '
          '`${runner.replayCommand}` with any interpreter that has pytest; '
          'setup steps before it are not part of the check and need not be '
          'repeated. Report blocked_reason only for a concrete blocker';
    }
    final inline = InlinePythonVerificationContract.parse(
      (payload?['command'] ?? result.arguments['command'])?.toString() ?? '',
      (payload?['working_directory'] ?? result.arguments['working_directory'])
              ?.toString() ??
          '',
    );
    if (inline != null) {
      return 'the inline verification `$command` failed$exitDetail '
          '(tool call ${result.id}). Repair its fixture while preserving the '
          'interpreter, working directory, imported modules, and the entire '
          'source block from the first top-level assert onward, then run it '
          'again. Dropping or weakening checks or passing another check does '
          'not clear this failure. Report blocked_reason only for a concrete '
          'blocker';
    }
    final projectEnv = scope?.projectEnvKey == null
        ? ''
        : ' Running the same command with the project\'s own environment '
              'interpreter (for example .venv/bin/python) also settles it; '
              'never install packages into a system or externally managed '
              'interpreter to make it pass.';
    return 'the verification `$command` failed'
        '$exitDetail and has not passed since; '
        'a different command passing does not clear it. Re-run it until it '
        'passes, or report blocked_reason if it cannot pass in this '
        'environment.$projectEnv';
  }
}
