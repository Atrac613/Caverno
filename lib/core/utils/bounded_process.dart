import 'dart:convert';
import 'dart:io';

import 'logger.dart';

/// Default wall-clock budget for the short-lived inspection commands
/// (`arp`, `ndp`, `ip`, `nslookup`, ...) the network tools shell out to.
const Duration defaultBoundedProcessTimeout = Duration(seconds: 5);

/// Exit code reported when a command was killed for exceeding its budget.
const int boundedProcessTimeoutExitCode = -1;

/// Runs [executable] and kills it once [timeout] elapses.
///
/// `Process.run` has no timeout, so a command that blocks on an unreachable
/// resolver stalls the caller forever. Callers already treat a non-zero exit
/// code as "no data", so a killed command degrades to an empty result instead
/// of hanging the turn that invoked the tool.
Future<ProcessResult> runProcessBounded(
  String executable,
  List<String> arguments, {
  Duration timeout = defaultBoundedProcessTimeout,
}) async {
  final process = await Process.start(executable, arguments);
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();

  var timedOut = false;
  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
      return boundedProcessTimeoutExitCode;
    },
  );

  final stdout = await stdoutFuture;
  final stderr = await stderrFuture;

  if (timedOut) {
    appLog(
      '[BoundedProcess] Killed "$executable ${arguments.join(' ')}" after '
      '${timeout.inMilliseconds}ms',
    );
    return ProcessResult(
      process.pid,
      boundedProcessTimeoutExitCode,
      stdout,
      stderr.isEmpty
          ? 'Command timed out after ${timeout.inMilliseconds}ms'
          : stderr,
    );
  }

  return ProcessResult(process.pid, exitCode, stdout, stderr);
}
