import 'dart:convert';

import 'package:path/path.dart' as path;

import '../entities/tool_call_info.dart';
import 'coding_command_output_issue_detector.dart';
import 'local_command/literal_shell_words.dart';
import 'local_command/shell_exit_status_report.dart';
import 'python/inline_python_verification_contract.dart';
import 'python/pytest_verification_identity.dart';
import 'verification_command_sequence.dart';

/// Which verification a command result is, and whether that run passed.
///
/// A later passing run of the same scope settles an earlier failed one; a
/// different check passing never does. Pytest runs share a scope across
/// interpreter spellings and need parsed passing counts. Literal inline Python
/// checks retain their assertion block and imported modules across fixture
/// repairs. Other commands rated as verification use their exact command and
/// working directory: before, only pytest was ever reconciled, so a failed
/// `watcher.py --dry-run` or verifier script stayed failed for the rest of the
/// turn even after the very same command passed (session d0c0462c).
final class VerificationScope {
  const VerificationScope._(
    this.key,
    this.passed, {
    this.coveredKeys = const [],
    this.inlineContract,
    this.runtimeRepairKey,
    this.runtimeLaunchFailed = false,
    this.pytestRunner,
    this.projectEnvKey,
  });

  final String key;
  final bool passed;
  final List<String> coveredKeys;
  final InlinePythonVerificationContract? inlineContract;
  final String? runtimeRepairKey;
  final bool runtimeLaunchFailed;

  /// For a command run by a system Python interpreter: the key a passing run
  /// of the same command under the project's own environment covers. Session
  /// 1df8a06d was told a different command passing never settles a failed
  /// system `python3` check, so the model tried to pip install into the
  /// externally managed host interpreter although `.venv` already passed.
  final String? projectEnvKey;

  /// The pytest run [key] names, when the scope is that run's identity.
  final PytestVerificationIdentity? pytestRunner;

  static final _pytestLaunchFailure = RegExp(
    r'''^(?:.*[/\\])?python(?:\d+(?:\.\d+)*)?(?:\.exe)?:\s+No module named ['"]?pytest['"]?\s*$''',
  );

  static VerificationScope? of(
    ToolResultInfo result,
    Map<String, dynamic>? decoded, {
    required bool Function(ToolResultInfo) isVerification,
  }) {
    if (!isVerification(result)) return null;
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
    final leadingSummaries = sequence?.leadingPytest == null
        ? const []
        : const LineSplitter()
              .convert(commandOutput)
              .map(sequence!.leadingPytest!.counts)
              .where((summary) => summary != null)
              .toList();
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
        pytest.verificationKey,
        ranClean &&
            counts != null &&
            counts.passedCount > 0 &&
            counts.failedCount == 0,
        pytestRunner: pytest,
      );
    }
    if (!isVerification(result) || command.trim().isEmpty) return null;
    final inline = InlinePythonVerificationContract.parse(command, directory);
    // `&&` starts the final pytest only after every earlier step exited 0, so
    // when that pytest could not even import, the steps before it already
    // passed and the run still owed is the pytest run alone. Session 016d4d5e:
    // `... && python -c "print(sys.version)" && pytest -q` kept blocking after
    // the same tests passed, and the model rebuilt the venv to replay it.
    final terminal = sequence?.terminalPytest;
    final launchFailedRunner =
        terminal != null &&
            outcome?.hasFailingExitCode == true &&
            sequence!.steps
                    .where(
                      (step) =>
                          PytestVerificationIdentity.parse(step, directory) !=
                          null,
                    )
                    .length ==
                1 &&
            (_endsWithLaunchFailure(commandOutput) ||
                _endsWithLaunchFailure((decoded?['stderr'] ?? '').toString()))
        ? terminal
        : null;
    // `cd <root> && python3 verify.py` is still one Python step.
    final singleStep = sequence == null
        ? command
        : sequence.steps.length == 1
        ? sequence.steps.single
        : null;
    final env = singleStep != null && inline == null
        ? _projectEnvRun(singleStep, directory)
        : null;
    return VerificationScope._(
      projectEnvKey: env?.inProject == false ? env!.key : null,
      launchFailedRunner?.verificationKey ??
          (sequence != null
              ? sequence.key
              : inline?.key ?? _exactKey(command, directory)),
      ranClean,
      pytestRunner: launchFailedRunner,
      inlineContract: inline,
      runtimeRepairKey:
          sequence?.runtimeRepairKey != null &&
              (!ranClean ||
                  leadingSummaries.length == 1 &&
                      leadingSummaries.single!.passedCount > 0 &&
                      leadingSummaries.single!.failedCount == 0)
          ? sequence?.runtimeRepairKey
          : null,
      runtimeLaunchFailed:
          sequence?.runtimeRepairKey != null &&
          outcome?.hasFailingExitCode == true &&
          (outcome?.effectiveTestFailedCount ?? 0) == 0 &&
          (outcome?.diagnosticErrorCount ?? 0) == 0 &&
          stdout.trim().isEmpty &&
          _pytestLaunchFailure.hasMatch(
            (decoded?['stderr'] ?? '').toString().trim(),
          ),
      coveredKeys: [
        if (env?.inProject == true && ranClean) env!.key,
        if (sequence?.terminalPytest case final runner?) runner.verificationKey,
        // `&&` runs a step only after the previous one exited 0, so a passing
        // sequence also settles an earlier standalone run of each plain step.
        // In session 17398f84 `ruff check watcher.py && pytest -q` passed, yet
        // the earlier failing `ruff check watcher.py` kept blocking. Pytest and
        // inline Python steps keep their own, stricter identities.
        for (final step in sequence?.steps ?? const <String>[])
          if (PytestVerificationIdentity.parse(step, directory) == null &&
              InlinePythonVerificationContract.parse(step, directory) == null)
            _exactKey(step, directory),
      ],
    );
  }

  /// A single Python command keyed without its interpreter, and whether that
  /// interpreter lives in an environment inside [directory] (`.venv/bin/python`)
  /// rather than on the system (`python3`, `/opt/homebrew/bin/python3`).
  static ({String key, bool inProject})? _projectEnvRun(
    String command,
    String directory,
  ) {
    final words = LiteralShellWords.parse(command.trim());
    if (words == null || words.length < 2) return null;
    final interpreter = words.first;
    if (!RegExp(
      r'^python(?:\d+(?:\.\d+)*)?$',
    ).hasMatch(path.basename(interpreter))) {
      return null;
    }
    final resolved = path.isAbsolute(interpreter)
        ? path.normalize(interpreter)
        : path.normalize(path.join(directory, interpreter));
    final inProject =
        interpreter.contains('/') &&
        path.isWithin(directory, resolved) &&
        path.basename(path.dirname(resolved)) == 'bin';
    return (
      key: 'project-env:${_exactKey(words.skip(1).join(' '), directory)}',
      inProject: inProject,
    );
  }

  static bool _endsWithLaunchFailure(String output) {
    final lines = const LineSplitter()
        .convert(output)
        .where((line) => line.trim().isNotEmpty);
    return lines.isNotEmpty && _pytestLaunchFailure.hasMatch(lines.last.trim());
  }

  static String _exactKey(String command, String directory) => jsonEncode([
    directory.trim(),
    // Whitespace in an inline script can change its checks or its control
    // flow; unsupported forms must retain their exact text.
    command.contains('\n') || RegExp(r'\s-c\s').hasMatch(command)
        ? command.trim()
        : command.replaceAll(RegExp(r'\s+'), ' ').trim(),
  ]);
}
