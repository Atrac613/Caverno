import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../../domain/services/dart_diagnostic_line_parser.dart';
import '../../domain/services/pytest_verification_identity.dart';
import 'first_party_tool_execution_result.dart';
import 'local_shell_launch_plan.dart';
import 'shell_write_observation.dart';

/// Owns bounded process output, timeout settlement, and observed outcomes.
abstract final class LocalShellProcessRunner {
  static Future<FirstPartyToolExecutionResult> execute({
    required String command,
    required String workingDirectory,
    required String shellExecutable,
    required List<String> shellArgs,
    required Duration timeout,
    required int maxOutputChars,
    String? observationTag,
    String? scratchDirectory,
  }) async {
    final process = await startLocalShellProcess(
      executable: shellExecutable,
      arguments: shellArgs,
      workingDirectory: workingDirectory,
      scratchDirectory: scratchDirectory,
    );
    final stdout = _BoundedOutputBuffer(maxOutputChars);
    final stderr = _BoundedOutputBuffer(maxOutputChars);
    final stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .listen(stdout.add);
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(stderr.add);
    final stdoutDone = stdoutSubscription.asFuture<void>();
    final stderrDone = stderrSubscription.asFuture<void>();

    try {
      final exitCode = await process.exitCode.timeout(timeout);
      await Future.wait([stdoutDone, stderrDone]);
      return _encodeProcessResult(
        command: command,
        workingDirectory: workingDirectory,
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr,
        observationTag: observationTag,
      );
    } on TimeoutException {
      final processTerminated = await _terminateTimedOutProcess(process);
      if (!processTerminated) {
        await stdoutSubscription.cancel();
        await stderrSubscription.cancel();
      } else {
        await Future.wait([
          stdoutDone,
          stderrDone,
        ]).timeout(const Duration(seconds: 1), onTimeout: () => const <void>[]);
      }
      return _encodeProcessResult(
        command: command,
        workingDirectory: workingDirectory,
        stdout: stdout,
        stderr: stderr,
        timedOut: true,
        timeout: timeout,
        processTerminated: processTerminated,
        observationTag: observationTag,
      );
    }
  }

  static Future<bool> _terminateTimedOutProcess(Process process) async {
    process.kill();
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
      return true;
    } on TimeoutException {
      if (!Platform.isWindows) {
        process.kill(ProcessSignal.sigkill);
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
          return true;
        } on TimeoutException {
          return false;
        }
      }
      return false;
    }
  }

  static FirstPartyToolExecutionResult _encodeProcessResult({
    required String command,
    required String workingDirectory,
    required _BoundedOutputBuffer stdout,
    required _BoundedOutputBuffer stderr,
    int? exitCode,
    bool timedOut = false,
    Duration? timeout,
    bool? processTerminated,
    String? observationTag,
  }) {
    final diagnostics = timedOut || exitCode == null || exitCode == 0
        ? const <Map<String, dynamic>>[]
        : _diagnosticsFromOutput(
            command: command,
            workingDirectory: workingDirectory,
            output: '${stdout.text}\n${stderr.text}',
          );
    final result = jsonEncode({
      'command': command,
      'working_directory': workingDirectory,
      'exit_code': ?exitCode,
      'stdout': stdout.text,
      'stderr': stderr.text,
      if (diagnostics.isNotEmpty) 'diagnostics': diagnostics,
      if (stdout.truncated) 'stdout_truncated': true,
      if (stderr.truncated) 'stderr_truncated': true,
      if (timedOut) ...{
        'error': 'Command timed out after ${_formatTimeout(timeout!)}.',
        'timed_out': true,
        'timeout_ms': timeout.inMilliseconds,
        'process_terminated': processTerminated ?? false,
      },
      ShellWriteObservation.payloadKey: ?observationTag,
    });
    return FirstPartyToolExecutionResult(
      result: result,
      outcome: timedOut || exitCode == null
          ? null
          : ToolOutcome(
              exitCode: exitCode,
              testOutcome: PytestVerificationIdentity.parse(
                command,
                workingDirectory,
              )?.counts(stdout.text),
            ),
    );
  }

  /// Diagnostics a failed Dart or Flutter command reported in its own output.
  ///
  /// Caverno's completion evidence counts a `diagnostics` list on a tool
  /// result, and until now only the tools that generate diagnostics themselves
  /// produced one — so a model that verified by running `dart analyze` through
  /// this tool got errors the harness could read as prose but not as evidence.
  ///
  /// Deliberately restricted to `dart` and `flutter`. The parsers recognise
  /// only those two output syntaxes, so widening the command set would add
  /// misparse risk without adding coverage, and every command that reaches
  /// here starts contributing to the unresolved-error count that goal
  /// completion gaps are built from. Keeping it to commands whose failure
  /// really does mean unresolved Dart errors keeps that claim true.
  static List<Map<String, dynamic>> _diagnosticsFromOutput({
    required String command,
    required String workingDirectory,
    required String output,
  }) {
    if (!_isDartToolingCommand(command)) {
      return const [];
    }
    const parser = DartDiagnosticLineParser();
    final diagnostics = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final line in const LineSplitter().convert(output)) {
      final diagnostic = parser.parse(line, pathBase: workingDirectory);
      if (diagnostic == null || !seen.add(diagnostic.dedupeKey)) {
        continue;
      }
      diagnostics.add({
        'severity': diagnostic.severity,
        'path': diagnostic.absolutePath,
        'relative_path': diagnostic.relativePath(workingDirectory),
        'line': diagnostic.line,
        'column': diagnostic.column,
        if (diagnostic.code != null) 'code': diagnostic.code,
        'message': diagnostic.message,
      });
    }
    return diagnostics;
  }

  /// Whether the command is run by the Dart or Flutter CLI, allowing an `fvm`
  /// prefix, which this repository uses everywhere.
  static bool _isDartToolingCommand(String command) {
    final tokens = command.trim().split(RegExp(r'\s+'));
    final executable =
        tokens.isNotEmpty && tokens.first == 'fvm' && tokens.length > 1
        ? tokens[1]
        : (tokens.isEmpty ? '' : tokens.first);
    return executable == 'dart' || executable == 'flutter';
  }

  static String _formatTimeout(Duration timeout) {
    if (timeout.inMilliseconds % Duration.millisecondsPerSecond == 0) {
      final seconds = timeout.inSeconds;
      return '$seconds ${seconds == 1 ? 'second' : 'seconds'}';
    }
    final milliseconds = timeout.inMilliseconds;
    return '$milliseconds ${milliseconds == 1 ? 'millisecond' : 'milliseconds'}';
  }
}

class _BoundedOutputBuffer {
  _BoundedOutputBuffer(this.maxLength);

  final int maxLength;
  final StringBuffer _buffer = StringBuffer();
  bool truncated = false;

  void add(String chunk) {
    final remaining = maxLength - _buffer.length;
    if (remaining <= 0) {
      truncated = true;
      return;
    }
    if (chunk.length <= remaining) {
      _buffer.write(chunk);
      return;
    }
    _buffer.write(chunk.substring(0, remaining));
    truncated = true;
  }

  String get text => _buffer.toString();
}
