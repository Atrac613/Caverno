import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'git_tools.dart';

class LocalShellTools {
  LocalShellTools._();

  static const int _maxOutputChars = 12000;
  static const Duration _timeout = Duration(seconds: 60);

  static bool get isDesktopPlatform =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  static bool isReadOnly(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return false;
    if (_hasUnsafeShellSyntax(trimmed)) return false;

    final args = GitTools.splitArgs(trimmed);
    if (args.isEmpty) return false;

    final executable = args.first;
    return switch (executable) {
      'pwd' ||
      'ls' ||
      'cat' ||
      'head' ||
      'tail' ||
      'wc' ||
      'stat' ||
      'file' => true,
      'find' || 'rg' || 'grep' => true,
      'sed' => _isSedReadOnly(args),
      'awk' => true,
      'git' => GitTools.isReadOnly(args.skip(1).join(' ')),
      _ => false,
    };
  }

  static Future<String> execute({
    required String command,
    required String workingDirectory,
  }) async {
    final directory = Directory(workingDirectory);
    if (!directory.existsSync()) {
      return jsonEncode({
        'error': 'Working directory does not exist: $workingDirectory',
      });
    }

    final shellExecutable = Platform.isWindows ? 'cmd' : 'sh';
    final shellArgs = Platform.isWindows ? ['/C', command] : ['-lc', command];

    try {
      final result = await Process.run(
        shellExecutable,
        shellArgs,
        workingDirectory: workingDirectory,
      ).timeout(_timeout);

      final stdout = result.stdout as String;
      final stderr = result.stderr as String;
      final stdoutTruncated = stdout.length > _maxOutputChars;
      final stderrTruncated = stderr.length > _maxOutputChars;

      return jsonEncode({
        'command': command,
        'working_directory': directory.absolute.path,
        'exit_code': result.exitCode,
        'stdout': stdoutTruncated
            ? stdout.substring(0, _maxOutputChars)
            : stdout,
        'stderr': stderrTruncated
            ? stderr.substring(0, _maxOutputChars)
            : stderr,
        if (stdoutTruncated) 'stdout_truncated': true,
        if (stderrTruncated) 'stderr_truncated': true,
      });
    } on TimeoutException {
      return jsonEncode({
        'command': command,
        'working_directory': directory.absolute.path,
        'error': 'Command timed out after ${_timeout.inSeconds} seconds.',
      });
    } catch (e) {
      return jsonEncode({
        'command': command,
        'working_directory': directory.absolute.path,
        'error': e.toString(),
      });
    }
  }

  static bool _hasUnsafeShellSyntax(String command) {
    const blockedTokens = ['|', '&&', '||', ';', '>', '<', '`', r'$(', '\n'];
    return blockedTokens.any(command.contains);
  }

  static bool _isSedReadOnly(List<String> args) {
    if (!args.contains('-n')) return false;
    for (final arg in args.skip(1)) {
      if (arg == '-i' || arg.startsWith('-i')) {
        return false;
      }
    }
    return true;
  }
}
