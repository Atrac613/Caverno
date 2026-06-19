import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/login_shell_environment.dart';
import '../../../settings/presentation/providers/settings_notifier.dart';

typedef WorktreeAgentVerificationCommandRunner =
    Future<WorktreeAgentVerificationCommandOutput> Function(
      WorktreeAgentVerificationCommand command,
      Duration timeout,
    );

class WorktreeAgentVerificationCommand {
  const WorktreeAgentVerificationCommand({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
}

class WorktreeAgentVerificationCommandOutput {
  const WorktreeAgentVerificationCommandOutput({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.timedOut = false,
    this.startError,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final String? startError;

  bool get ran => !timedOut && startError == null;
}

class WorktreeAgentVerificationRun {
  const WorktreeAgentVerificationRun({
    required this.commandLine,
    required this.verifiedGreen,
    required this.summary,
    this.command,
    this.output,
  });

  final String commandLine;
  final WorktreeAgentVerificationCommand? command;
  final WorktreeAgentVerificationCommandOutput? output;
  final bool verifiedGreen;
  final String summary;
}

final worktreeAgentVerificationRunnerProvider =
    Provider<WorktreeAgentVerificationRunner>((ref) {
      final settings = ref.watch(settingsNotifierProvider);
      return WorktreeAgentVerificationRunner(
        timeout: Duration(seconds: settings.codingVerificationTimeoutSeconds),
      );
    });

class WorktreeAgentVerificationRunner {
  const WorktreeAgentVerificationRunner({
    WorktreeAgentVerificationCommandRunner? commandRunner,
    this.timeout = const Duration(seconds: 90),
  }) : _commandRunner = commandRunner ?? _runCommand;

  static const int _maxOutputChars = 12000;

  final WorktreeAgentVerificationCommandRunner _commandRunner;
  final Duration timeout;

  Future<WorktreeAgentVerificationRun> run({
    required String verificationCommand,
    required String worktreePath,
  }) async {
    final commandLine = verificationCommand.trim();
    if (commandLine.isEmpty) {
      return const WorktreeAgentVerificationRun(
        commandLine: '',
        verifiedGreen: false,
        summary:
            'Verification was not configured for this worktree-agent task.',
      );
    }

    final controlOperator = _firstShellControlOperator(commandLine);
    if (controlOperator != null) {
      return WorktreeAgentVerificationRun(
        commandLine: commandLine,
        verifiedGreen: false,
        summary:
            'Verification command was not run because shell control operator '
            '"$controlOperator" is not supported.',
      );
    }

    final args = _splitCommand(commandLine);
    if (args.isEmpty) {
      return WorktreeAgentVerificationRun(
        commandLine: commandLine,
        verifiedGreen: false,
        summary: 'Verification command was empty after parsing.',
      );
    }

    final command = WorktreeAgentVerificationCommand(
      executable: args.first,
      arguments: args.skip(1).toList(growable: false),
      workingDirectory: Directory(worktreePath).absolute.path,
    );
    final output = await _commandRunner(command, timeout);
    final verifiedGreen =
        output.ran && output.exitCode == 0 && !output.timedOut;
    return WorktreeAgentVerificationRun(
      commandLine: commandLine,
      command: command,
      output: output,
      verifiedGreen: verifiedGreen,
      summary: _buildSummary(
        commandLine: commandLine,
        output: output,
        timeout: timeout,
      ),
    );
  }

  String _buildSummary({
    required String commandLine,
    required WorktreeAgentVerificationCommandOutput output,
    required Duration timeout,
  }) {
    if (output.timedOut) {
      return 'Verification timed out after ${timeout.inSeconds}s: $commandLine.';
    }
    final startError = output.startError?.trim();
    if (startError != null && startError.isNotEmpty) {
      return [
        'Verification could not start: $commandLine.',
        'Error: ${_cap(startError)}',
      ].join('\n');
    }

    final header = output.exitCode == 0
        ? 'Verification passed: $commandLine (exit code 0).'
        : 'Verification failed: $commandLine (exit code ${output.exitCode}).';
    final stdout = output.stdout.trim();
    final stderr = output.stderr.trim();
    return [
      header,
      if (stdout.isNotEmpty) 'stdout:\n${_cap(stdout)}',
      if (stderr.isNotEmpty) 'stderr:\n${_cap(stderr)}',
    ].join('\n');
  }

  String _cap(String value) {
    if (value.length <= _maxOutputChars) {
      return value;
    }
    return '${value.substring(0, _maxOutputChars)}\n...[truncated]';
  }

  static String? _firstShellControlOperator(String command) {
    String? quoteChar;
    for (var i = 0; i < command.length; i++) {
      final c = command[i];
      if (quoteChar != null) {
        if (quoteChar == '"' && c == '\\') {
          i += 1;
          continue;
        }
        if (c == quoteChar) {
          quoteChar = null;
        }
        continue;
      }

      if (c == '"' || c == "'") {
        quoteChar = c;
        continue;
      }

      if (c == '&') {
        if (i + 1 < command.length && command[i + 1] == '&') {
          return '&&';
        }
        return '&';
      }
      if (c == '|') {
        if (i + 1 < command.length && command[i + 1] == '|') {
          return '||';
        }
        return '|';
      }
      if (c == ';' || c == '<' || c == '>' || c == '\n') {
        return c == '\n' ? 'newline' : c;
      }
    }
    return null;
  }

  static List<String> _splitCommand(String command) {
    final args = <String>[];
    final buffer = StringBuffer();
    String? quoteChar;

    for (var i = 0; i < command.length; i++) {
      final c = command[i];
      if (quoteChar != null) {
        if (quoteChar == '"' && c == '\\' && i + 1 < command.length) {
          i += 1;
          buffer.writeCharCode(command.codeUnitAt(i));
        } else if (c == quoteChar) {
          quoteChar = null;
        } else {
          buffer.writeCharCode(c.codeUnitAt(0));
        }
        continue;
      }

      if (c == '"' || c == "'") {
        quoteChar = c;
        continue;
      }
      if (c == ' ' || c == '\t') {
        if (buffer.isNotEmpty) {
          args.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }
      buffer.writeCharCode(c.codeUnitAt(0));
    }

    if (buffer.isNotEmpty) {
      args.add(buffer.toString());
    }
    return args;
  }

  static Future<WorktreeAgentVerificationCommandOutput> _runCommand(
    WorktreeAgentVerificationCommand command,
    Duration timeout,
  ) async {
    Process? process;
    try {
      process = await Process.start(
        command.executable,
        command.arguments,
        workingDirectory: command.workingDirectory,
        environment: await LoginShellEnvironment.instance.environment(),
      );
      final stdout = _BoundedTextBuffer(_maxOutputChars);
      final stderr = _BoundedTextBuffer(_maxOutputChars);
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
        return WorktreeAgentVerificationCommandOutput(
          exitCode: exitCode,
          stdout: stdout.text,
          stderr: stderr.text,
        );
      } on TimeoutException {
        process.kill();
        await stdoutSubscription.cancel();
        await stderrSubscription.cancel();
        return const WorktreeAgentVerificationCommandOutput(
          exitCode: -1,
          timedOut: true,
        );
      }
    } on ProcessException catch (error) {
      return WorktreeAgentVerificationCommandOutput(
        exitCode: -1,
        startError: error.message,
      );
    } catch (error) {
      return WorktreeAgentVerificationCommandOutput(
        exitCode: -1,
        startError: error.toString(),
      );
    }
  }
}

class _BoundedTextBuffer {
  _BoundedTextBuffer(this.maxChars);

  final int maxChars;
  final _buffer = StringBuffer();
  bool _truncated = false;

  String get text => _buffer.toString();

  void add(String chunk) {
    if (_truncated || chunk.isEmpty) {
      return;
    }
    final remaining = maxChars - _buffer.length;
    if (remaining <= 0) {
      _truncated = true;
      return;
    }
    if (chunk.length <= remaining) {
      _buffer.write(chunk);
      return;
    }
    _buffer.write(chunk.substring(0, remaining));
    _buffer.write('\n...[truncated]');
    _truncated = true;
  }
}
