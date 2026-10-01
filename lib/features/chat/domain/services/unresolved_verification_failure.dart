import '../entities/tool_call_info.dart';
import 'command_verification_reconciliation.dart';

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
      final failed =
          (outcome?.effectiveTestFailedCount ?? 0) > 0 ||
          (outcome?.diagnosticErrorCount ?? 0) > 0 ||
          (outcome?.hasFailingExitCode ?? false);
      if (!failed) continue;
      final raw = (result.arguments['command'] ?? result.name)
          .toString()
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      final command = raw.length <= _maxCommandLength
          ? raw
          : '${raw.substring(0, _maxCommandLength)}...';
      final exit = outcome?.exitCode;
      return 'the verification `$command` failed'
          '${exit == null ? '' : ' (exit $exit)'} and has not passed since; '
          'a different command passing does not clear it. Re-run it until it '
          'passes, or report blocked_reason if it cannot pass in this '
          'environment';
    }
    return null;
  }
}
