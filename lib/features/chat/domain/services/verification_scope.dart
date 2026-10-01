import 'dart:convert';

import '../entities/tool_call_info.dart';
import 'coding_command_output_issue_detector.dart';
import 'pytest_verification_identity.dart';

/// Which verification a command result is, and whether that run passed.
///
/// A later passing run of the same scope settles an earlier failed one; a
/// different command passing never does. Pytest runs share a scope across
/// interpreter spellings and need parsed passing counts. Any other command a
/// classifier rates as verification is scoped to its exact command and
/// working directory: before, only pytest was ever reconciled, so a failed
/// `watcher.py --dry-run` or verifier script stayed failed for the rest of the
/// turn even after the very same command passed (session d0c0462c).
final class VerificationScope {
  const VerificationScope._(this.key, this.passed);

  final String key;
  final bool passed;

  static VerificationScope? of(
    ToolResultInfo result,
    Map<String, dynamic>? decoded, {
    required bool Function(ToolResultInfo) isVerification,
  }) {
    if (result.name != 'local_execute_command') return null;
    final command =
        (decoded?['command'] ?? result.arguments['command'])?.toString() ?? '';
    final directory =
        (decoded?['working_directory'] ?? result.arguments['working_directory'])
            ?.toString() ??
        '';
    final outcome = result.outcome;
    final ranClean =
        outcome?.hasSucceedingExitCode == true &&
        (outcome?.processState == null || outcome!.isProcessTerminal) &&
        (outcome?.diagnosticErrorCount ?? 0) == 0 &&
        (outcome?.effectiveTestFailedCount ?? 0) == 0 &&
        decoded?['timed_out'] != true &&
        const CodingCommandOutputIssueDetector().detect(result) == null;
    final pytest = PytestVerificationIdentity.parse(command, directory);
    if (pytest != null) {
      final counts =
          outcome?.testOutcome ??
          pytest.counts(decoded?['stdout']?.toString() ?? '');
      return VerificationScope._(
        pytest.key,
        ranClean &&
            counts != null &&
            counts.passedCount > 0 &&
            counts.failedCount == 0,
      );
    }
    if (!isVerification(result) || command.trim().isEmpty) return null;
    return VerificationScope._(
      jsonEncode([
        directory.trim(),
        command.replaceAll(RegExp(r'\s+'), ' ').trim(),
      ]),
      ranClean,
    );
  }
}
