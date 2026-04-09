import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Local Git command execution utilities for built-in MCP tools.
///
/// Desktop only (macOS, Linux, Windows). Uses [Process.run] to invoke
/// the system `git` binary — not available on iOS or Android.
class GitTools {
  /// Maximum characters returned for stdout/stderr.
  static const int _kMaxOutputChars = 8000;

  /// Timeout for git command execution.
  static const Duration _kTimeout = Duration(seconds: 30);

  /// Whether the current platform supports git command execution.
  static bool get isDesktopPlatform =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  // -------------------------------------------------------------------------
  // Read-only detection
  // -------------------------------------------------------------------------

  /// Subcommands that are always read-only.
  static const Set<String> _readOnlySubcommands = {
    'status',
    'log',
    'diff',
    'show',
    'remote',
    'blame',
    'rev-parse',
    'describe',
    'shortlog',
    'ls-files',
    'ls-tree',
    'reflog',
    'cat-file',
    'for-each-ref',
    'name-rev',
    'symbolic-ref',
    'rev-list',
    'show-ref',
    'count-objects',
    'fsck',
    'verify-pack',
    'diff-tree',
    'diff-files',
    'diff-index',
    'ls-remote',
  };

  /// Subcommands that are read-only only with specific argument patterns.
  static const Set<String> _conditionalSubcommands = {
    'branch',
    'tag',
    'stash',
    'config',
  };

  /// Returns `true` when [command] is a read-only git operation that can
  /// run without user confirmation.
  static bool isReadOnly(String command) {
    final args = splitArgs(command);
    if (args.isEmpty) return false;

    final subcommand = args.first;

    if (_readOnlySubcommands.contains(subcommand)) return true;

    if (!_conditionalSubcommands.contains(subcommand)) return false;

    // Conditional checks per subcommand.
    switch (subcommand) {
      case 'branch':
        return _isBranchReadOnly(args);
      case 'tag':
        return _isTagReadOnly(args);
      case 'stash':
        return _isStashReadOnly(args);
      case 'config':
        return _isConfigReadOnly(args);
      default:
        return false;
    }
  }

  /// `git branch` is read-only when listing (no create/delete/rename flags
  /// and no positional branch-name argument that would create a branch).
  static bool _isBranchReadOnly(List<String> args) {
    const writeFlags = {
      '-d', '-D', '--delete',
      '-m', '-M', '--move',
      '-c', '-C', '--copy',
      '--set-upstream-to', '-u',
      '--unset-upstream',
      '--edit-description',
    };
    for (var i = 1; i < args.length; i++) {
      final arg = args[i];
      if (writeFlags.contains(arg)) return false;
      if (arg.startsWith('--set-upstream-to=')) return false;
      // A positional argument (not a flag) after `branch` means create.
      if (!arg.startsWith('-') && i > 1) {
        // Allow known list flags: -r, -a, -v, -vv, --list, etc.
        continue;
      }
    }
    // Check if there's a bare positional that creates a new branch.
    final positionals = args.skip(1).where((a) => !a.startsWith('-')).toList();
    if (positionals.isNotEmpty) return false;
    return true;
  }

  /// `git tag` is read-only when listing (no -a, -d, -s, -f flags and no
  /// positional tag name that would create a tag).
  static bool _isTagReadOnly(List<String> args) {
    const writeFlags = {'-a', '-d', '-s', '-f', '--delete', '--sign', '-u'};
    for (var i = 1; i < args.length; i++) {
      if (writeFlags.contains(args[i])) return false;
    }
    final positionals = args.skip(1).where((a) => !a.startsWith('-')).toList();
    if (positionals.isNotEmpty) return false;
    return true;
  }

  /// `git stash` is read-only for `list` and `show` sub-subcommands only.
  static bool _isStashReadOnly(List<String> args) {
    if (args.length < 2) return true; // bare `git stash` = stash push (write)
    const readOnlyStashActions = {'list', 'show'};
    return readOnlyStashActions.contains(args[1]);
  }

  /// `git config` is read-only for get/list operations only.
  static bool _isConfigReadOnly(List<String> args) {
    const readFlags = {
      '--get', '--get-all', '--get-regexp',
      '--list', '-l',
      '--get-urlmatch',
    };
    for (var i = 1; i < args.length; i++) {
      if (readFlags.contains(args[i])) return true;
    }
    // Bare `git config` with just a key is a read.
    // But `git config key value` (2 positionals) is a write.
    final positionals = args.skip(1).where((a) => !a.startsWith('-')).toList();
    return positionals.length <= 1;
  }

  // -------------------------------------------------------------------------
  // Execution
  // -------------------------------------------------------------------------

  /// Executes a git command in [workingDirectory] and returns a
  /// JSON-encoded result with exit code, stdout, and stderr.
  static Future<String> execute({
    required String command,
    required String workingDirectory,
  }) async {
    // Validate working directory.
    final dir = Directory(workingDirectory);
    if (!dir.existsSync()) {
      return jsonEncode({
        'error': 'Working directory does not exist: $workingDirectory',
      });
    }

    // Verify it is inside a git repository.
    try {
      final check = await Process.run(
        'git',
        ['rev-parse', '--git-dir'],
        workingDirectory: workingDirectory,
      );
      if (check.exitCode != 0) {
        return jsonEncode({
          'error': 'Not a git repository: $workingDirectory',
        });
      }
    } catch (e) {
      return jsonEncode({
        'error': 'Failed to verify git repository: $e',
      });
    }

    final args = splitArgs(command);
    if (args.isEmpty) {
      return jsonEncode({'error': 'Empty git command'});
    }

    try {
      final result = await Process.run(
        'git',
        args,
        workingDirectory: workingDirectory,
      ).timeout(_kTimeout);

      final stdout = result.stdout as String;
      final stderr = result.stderr as String;
      final stdoutTruncated = stdout.length > _kMaxOutputChars;
      final stderrTruncated = stderr.length > _kMaxOutputChars;

      return jsonEncode({
        'command': 'git $command',
        'working_directory': workingDirectory,
        'exit_code': result.exitCode,
        'stdout': stdoutTruncated
            ? stdout.substring(0, _kMaxOutputChars)
            : stdout,
        'stderr': stderrTruncated
            ? stderr.substring(0, _kMaxOutputChars)
            : stderr,
        if (stdoutTruncated) 'stdout_truncated': true,
        if (stderrTruncated) 'stderr_truncated': true,
      });
    } on TimeoutException {
      return jsonEncode({
        'command': 'git $command',
        'working_directory': workingDirectory,
        'error':
            'Command timed out after ${_kTimeout.inSeconds} seconds. '
            'Avoid interactive git commands (use -m for commit, etc.).',
      });
    } catch (e) {
      return jsonEncode({
        'command': 'git $command',
        'working_directory': workingDirectory,
        'error': e.toString(),
      });
    }
  }

  // -------------------------------------------------------------------------
  // Argument splitting
  // -------------------------------------------------------------------------

  /// Splits a command string into arguments, respecting single and double
  /// quotes. Does NOT invoke a shell — this is a simple lexer.
  static List<String> splitArgs(String command) {
    final args = <String>[];
    final buffer = StringBuffer();
    String? quoteChar;

    for (var i = 0; i < command.length; i++) {
      final c = command[i];

      if (quoteChar != null) {
        if (c == quoteChar) {
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
}
