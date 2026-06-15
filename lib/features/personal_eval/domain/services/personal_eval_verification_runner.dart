import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../core/services/login_shell_environment.dart';
import '../entities/personal_eval_case.dart';

/// Outcome of running a case's verification command during an LL19 replay.
class PersonalEvalVerificationOutcome {
  const PersonalEvalVerificationOutcome({
    required this.result,
    this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.timedOut = false,
    this.error,
  });

  /// Convenience constructor for a command that never ran (no command, missing
  /// working directory, start error, or timeout). The mapped [result] is
  /// always [PersonalEvalVerificationResult.inconclusive].
  const PersonalEvalVerificationOutcome.inconclusive({
    this.exitCode,
    this.timedOut = false,
    this.error,
  }) : result = PersonalEvalVerificationResult.inconclusive,
       stdout = '',
       stderr = '';

  final PersonalEvalVerificationResult result;
  final int? exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final String? error;
}

/// LL19: runs a recorded case's verification command and maps the exit code to
/// a [PersonalEvalVerificationResult]. Isolated behind an interface so
/// [LivePersonalEvalCaseRunner] stays unit-testable with a fake runner while
/// the live implementation actually spawns a process.
abstract interface class PersonalEvalVerificationRunner {
  /// Runs [command] in [workingDirectory]. A blank command or directory yields
  /// an inconclusive outcome rather than throwing, so the orchestrator can keep
  /// running the rest of the suite.
  Future<PersonalEvalVerificationOutcome> run({
    required String command,
    required String workingDirectory,
  });
}

/// Live [PersonalEvalVerificationRunner] that spawns the verification command
/// through the platform shell, mirroring `local_shell_tools` and
/// `coding_verification_feedback_service` so recorded commands resolve their
/// binaries the same way an agent shell call would.
///
/// Exit code 0 maps to [PersonalEvalVerificationResult.passed], any other exit
/// code to [PersonalEvalVerificationResult.failed], and a timeout or
/// start/launch failure to [PersonalEvalVerificationResult.inconclusive] so a
/// broken environment never masquerades as a real verification failure.
class ProcessPersonalEvalVerificationRunner
    implements PersonalEvalVerificationRunner {
  ProcessPersonalEvalVerificationRunner({
    this.timeout = const Duration(minutes: 10),
    Future<Map<String, String>?> Function()? environmentProvider,
  }) : _environmentProvider =
           environmentProvider ?? _defaultEnvironmentProvider;

  final Duration timeout;
  final Future<Map<String, String>?> Function() _environmentProvider;

  static Future<Map<String, String>?> _defaultEnvironmentProvider() {
    // Reuse the login-shell PATH so `flutter`, `npm`, `dart`, etc. resolve when
    // the app was GUI-launched with launchd's minimal PATH.
    return LoginShellEnvironment.instance.environment();
  }

  @override
  Future<PersonalEvalVerificationOutcome> run({
    required String command,
    required String workingDirectory,
  }) async {
    final normalizedCommand = command.trim();
    if (normalizedCommand.isEmpty) {
      return const PersonalEvalVerificationOutcome.inconclusive(
        error: 'verification command is empty',
      );
    }
    final normalizedDir = workingDirectory.trim();
    if (normalizedDir.isEmpty) {
      return const PersonalEvalVerificationOutcome.inconclusive(
        error: 'verification working directory is empty',
      );
    }
    if (!Directory(normalizedDir).existsSync()) {
      return PersonalEvalVerificationOutcome.inconclusive(
        error: 'verification working directory not found: $normalizedDir',
      );
    }

    final shellExecutable = Platform.isWindows ? 'cmd' : 'sh';
    final shellArgs = Platform.isWindows
        ? ['/C', normalizedCommand]
        : ['-c', normalizedCommand];

    Process? process;
    try {
      process = await Process.start(
        shellExecutable,
        shellArgs,
        workingDirectory: normalizedDir,
        environment: await _environmentProvider(),
      );
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(timeout);
      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;
      return PersonalEvalVerificationOutcome(
        result: exitCode == 0
            ? PersonalEvalVerificationResult.passed
            : PersonalEvalVerificationResult.failed,
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr,
      );
    } on TimeoutException {
      process?.kill();
      return PersonalEvalVerificationOutcome.inconclusive(
        timedOut: true,
        error:
            'verification command timed out after '
            '${timeout.inSeconds}s',
      );
    } on ProcessException catch (error) {
      return PersonalEvalVerificationOutcome.inconclusive(error: error.message);
    } catch (error) {
      return PersonalEvalVerificationOutcome.inconclusive(
        error: error.toString(),
      );
    }
  }
}
