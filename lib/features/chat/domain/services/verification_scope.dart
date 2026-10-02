import 'dart:convert';

import 'package:path/path.dart' as path;

import '../entities/tool_call_info.dart';
import 'coding_command_output_issue_detector.dart';
import 'pytest_verification_identity.dart';
import 'shell_exit_status_report.dart';
import 'verification_command_sequence.dart';

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
  const VerificationScope._(
    this.key,
    this.passed, {
    this.coveredKeys = const [],
  });

  final String key;
  final bool passed;
  final List<String> coveredKeys;

  static VerificationScope? of(
    ToolResultInfo result,
    Map<String, dynamic>? decoded, {
    required bool Function(ToolResultInfo) isVerification,
  }) {
    final background = const {
      'process_start',
      'process_status',
      'process_wait',
    }.contains(result.name);
    if (result.name != 'local_execute_command' && !background) return null;
    var command =
        (decoded?['command'] ?? result.arguments['command'])?.toString() ?? '';
    var directory =
        (decoded?['working_directory'] ?? result.arguments['working_directory'])
            ?.toString() ??
        '';
    // A monitor's own arguments name a job, not its execution. Missing origin
    // metadata must never reconcile unrelated jobs or another working tree.
    if (background &&
        ((decoded?['job_id']?.toString().trim() ?? '').isEmpty ||
            command.trim().isEmpty ||
            !path.isAbsolute(directory))) {
      return null;
    }
    final report = ShellExitStatusReport.parse(command);
    command = report?.command ?? command;
    final sequence = VerificationCommandSequence.parse(command, directory);
    if (sequence != null) {
      command = sequence.command;
      directory = sequence.directory;
    }
    final outcome = result.outcome;
    final stdout =
        (decoded?['stdout'] ?? decoded?['stdout_tail'])?.toString() ?? '';
    final commandOutput = report?.commandOutput(stdout) ?? stdout;
    final compoundCounts = sequence?.terminalPytest?.counts(commandOutput);
    final compoundTests = outcome?.testOutcome ?? compoundCounts;
    final ranClean =
        outcome?.hasSucceedingExitCode == true &&
        (outcome?.processState == null || outcome!.isProcessTerminal) &&
        (outcome?.diagnosticErrorCount ?? 0) == 0 &&
        (outcome?.effectiveTestFailedCount ?? 0) == 0 &&
        (sequence?.terminalPytest == null ||
            compoundTests != null &&
                compoundTests.passedCount > 0 &&
                compoundTests.failedCount == 0) &&
        decoded?['timed_out'] != true &&
        (report == null || report.exitCode(stdout) == 0) &&
        const CodingCommandOutputIssueDetector().detect(result) == null;
    final pytest = PytestVerificationIdentity.parse(command, directory);
    if (pytest != null) {
      final counts = outcome?.testOutcome ?? pytest.counts(commandOutput);
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
      sequence?.terminalPytest != null
          ? sequence!.key
          : jsonEncode([
              directory.trim(),
              command.replaceAll(RegExp(r'\s+'), ' ').trim(),
            ]),
      ranClean,
      coveredKeys: [
        if (sequence?.terminalPytest case final runner?) runner.key,
      ],
    );
  }
}
