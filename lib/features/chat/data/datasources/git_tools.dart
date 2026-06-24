import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../../core/services/login_shell_environment.dart';

/// Local Git command execution utilities for built-in MCP tools.
///
/// Desktop only (macOS, Linux, Windows). Uses [Process.run] to invoke
/// the system `git` binary — not available on iOS or Android.
class GitTools {
  /// Maximum characters returned for stdout/stderr.
  static const int _kMaxOutputChars = 8000;
  static final RegExp _modelControlTokenPattern = RegExp(r'<\|[^>]*\|>');

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

  /// Normalizes a git command provided by an LLM or UI layer.
  ///
  /// The built-in git tool expects subcommands without the leading `git`
  /// binary name, but some models still emit `git status` or wrap segments
  /// in control tokens like `<|"|>`. Strip those artifacts so approval
  /// dialogs and execution both operate on the intended subcommand.
  static String normalizeCommand(String command) {
    var normalized = command.replaceAll(_modelControlTokenPattern, ' ').trim();

    while (true) {
      final lower = normalized.toLowerCase();
      if (lower == 'git') {
        return '';
      }
      if (!lower.startsWith('git ')) {
        break;
      }
      normalized = normalized.substring(3).trimLeft();
    }

    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  /// Returns the first shell control operator outside quotes, if present.
  static String? firstShellControlOperator(String command) {
    final normalized = normalizeCommand(command);
    String? quoteChar;

    for (var i = 0; i < normalized.length; i++) {
      final c = normalized[i];

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
        if (i + 1 < normalized.length && normalized[i + 1] == '&') {
          return '&&';
        }
        return '&';
      }
      if (c == '|') {
        if (i + 1 < normalized.length && normalized[i + 1] == '|') {
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

  /// `git branch` is read-only when listing (no create/delete/rename flags
  /// and no positional branch-name argument that would create a branch).
  static bool _isBranchReadOnly(List<String> args) {
    const writeFlags = {
      '-d',
      '-D',
      '--delete',
      '-m',
      '-M',
      '--move',
      '-c',
      '-C',
      '--copy',
      '--set-upstream-to',
      '-u',
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
    var hasListFlag = false;
    for (var i = 1; i < args.length; i++) {
      final arg = args[i];
      if (writeFlags.contains(arg)) return false;
      if (arg == '-l' || arg == '--list' || arg.startsWith('--list=')) {
        hasListFlag = true;
      }
    }
    if (hasListFlag) return true;
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
      '--get',
      '--get-all',
      '--get-regexp',
      '--list',
      '-l',
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
    final normalizedCommand = normalizeCommand(command);

    // Validate working directory.
    final dir = Directory(workingDirectory);
    if (!dir.existsSync()) {
      return jsonEncode({
        'error': 'Working directory does not exist: $workingDirectory',
      });
    }

    final args = splitArgs(normalizedCommand);
    if (args.isEmpty) {
      return jsonEncode({'error': 'Empty git command'});
    }
    final shellOperator = firstShellControlOperator(normalizedCommand);
    if (shellOperator != null) {
      return jsonEncode({
        'command': 'git $normalizedCommand',
        'working_directory': workingDirectory,
        'exit_code': 2,
        'error':
            'git_execute_command accepts one git subcommand per tool call and '
            'runs it without a shell, so the operator "$shellOperator" (pipes, '
            'redirects, &&/;) is not supported. Do not retry the same command '
            "unfiltered — filter with git's own arguments instead, e.g. "
            '`tag --list "1.3.*" --sort=-v:refname`, `log -n 5 --oneline`, or '
            '`branch --list "feature/*"`. Run separate git_execute_command '
            'calls if you need multiple steps.',
      });
    }

    final environment = await LoginShellEnvironment.instance.environment();

    // `git init` is the one write operation that must run before a repository
    // exists. All other subcommands keep the repository preflight.
    if (args.first != 'init') {
      try {
        final check = await Process.run(
          'git',
          ['rev-parse', '--git-dir'],
          workingDirectory: workingDirectory,
          environment: environment,
        );
        if (check.exitCode != 0) {
          return jsonEncode({
            'error': 'Not a git repository: $workingDirectory',
          });
        }
      } catch (e) {
        return jsonEncode({'error': 'Failed to verify git repository: $e'});
      }

      final commitPreflightError = await _commitPreflightError(
        args: args,
        normalizedCommand: normalizedCommand,
        workingDirectory: workingDirectory,
        environment: environment,
      );
      if (commitPreflightError != null) {
        return commitPreflightError;
      }

      final tagVersionPreflightError = await _tagVersionPreflightError(
        args: args,
        normalizedCommand: normalizedCommand,
        workingDirectory: workingDirectory,
        environment: environment,
      );
      if (tagVersionPreflightError != null) {
        return tagVersionPreflightError;
      }
    }

    try {
      final result = await Process.run(
        'git',
        args,
        workingDirectory: workingDirectory,
        environment: environment,
      ).timeout(_kTimeout);

      final stdout = result.stdout as String;
      final stderr = result.stderr as String;
      final stdoutTruncated = stdout.length > _kMaxOutputChars;
      final stderrTruncated = stderr.length > _kMaxOutputChars;

      return jsonEncode({
        'command': 'git $normalizedCommand',
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
        'command': 'git $normalizedCommand',
        'working_directory': workingDirectory,
        'error':
            'Command timed out after ${_kTimeout.inSeconds} seconds. '
            'Avoid interactive git commands (use -m for commit, etc.).',
      });
    } catch (e) {
      return jsonEncode({
        'command': 'git $normalizedCommand',
        'working_directory': workingDirectory,
        'error': e.toString(),
      });
    }
  }

  static Future<String?> _commitPreflightError({
    required List<String> args,
    required String normalizedCommand,
    required String workingDirectory,
    required Map<String, String> environment,
  }) async {
    if (!_commitNeedsPartialStageCheck(args)) {
      return null;
    }

    try {
      final status = await Process.run(
        'git',
        ['status', '--porcelain'],
        workingDirectory: workingDirectory,
        environment: environment,
      ).timeout(_kTimeout);
      if (status.exitCode != 0) {
        return jsonEncode({
          'command': 'git $normalizedCommand',
          'working_directory': workingDirectory,
          'exit_code': status.exitCode,
          'code': 'git_commit_preflight_failed',
          'error': 'Failed to inspect git status before commit.',
          'stdout': status.stdout as String,
          'stderr': status.stderr as String,
        });
      }

      final stdout = status.stdout as String;
      if (!_hasPartiallyStagedFiles(stdout)) {
        return null;
      }
      return jsonEncode({
        'command': 'git $normalizedCommand',
        'working_directory': workingDirectory,
        'exit_code': 2,
        'code': 'git_commit_unstaged_changes',
        'error':
            'git commit was blocked because one or more staged files still have '
            'unstaged changes in the working tree; committing now would silently '
            'omit those edits. Re-stage them with git add (or use git commit -a), '
            'then commit again. Files only modified-but-unstaged or untracked do '
            'not need staging unless you intend to commit them.',
        'status': stdout.length > _kMaxOutputChars
            ? stdout.substring(0, _kMaxOutputChars)
            : stdout,
        if (stdout.length > _kMaxOutputChars) 'status_truncated': true,
      });
    } on TimeoutException {
      return jsonEncode({
        'command': 'git $normalizedCommand',
        'working_directory': workingDirectory,
        'exit_code': 2,
        'code': 'git_commit_preflight_timeout',
        'error': 'Timed out while inspecting git status before commit.',
      });
    } catch (e) {
      return jsonEncode({
        'command': 'git $normalizedCommand',
        'working_directory': workingDirectory,
        'exit_code': 2,
        'code': 'git_commit_preflight_failed',
        'error': 'Failed to inspect git status before commit: $e',
      });
    }
  }

  /// Whether a `git commit` invocation can leave a partially-staged file's
  /// worktree edits behind. `commit -a` / `--all` re-stage every tracked file
  /// before committing, so they cannot omit edits and skip the preflight.
  static bool _commitNeedsPartialStageCheck(List<String> args) {
    if (args.isEmpty || args.first != 'commit') {
      return false;
    }
    for (final arg in args.skip(1)) {
      if (arg == '--') {
        break;
      }
      if (arg == '--all') {
        return false;
      }
      if (arg.startsWith('-') &&
          !arg.startsWith('--') &&
          arg.substring(1).contains('a')) {
        return false;
      }
    }
    return true;
  }

  /// Returns true when any file is **partially staged**: it has staged content
  /// in the index *and* further unstaged edits in the worktree. Committing such
  /// a file records the stale index snapshot and silently drops the unstaged
  /// delta — the footgun this preflight guards against.
  ///
  /// Files that are only unstaged-modified (` M`) or only untracked (`??`) are
  /// not flagged: a normal `git commit` correctly leaves them untouched, so
  /// blocking on them would break the standard "stage a subset, commit it"
  /// workflow.
  ///
  /// Porcelain v1 status lines are `XY <path>`, where X is the index column and
  /// Y the worktree column; a partially-staged file has both non-space.
  static bool _hasPartiallyStagedFiles(String statusPorcelain) {
    for (final line in const LineSplitter().convert(statusPorcelain)) {
      if (line.length < 2 || line.startsWith('!!') || line.startsWith('??')) {
        continue;
      }
      final indexStatus = line.codeUnitAt(0);
      final worktreeStatus = line.codeUnitAt(1);
      if (indexStatus != 0x20 && worktreeStatus != 0x20) {
        return true;
      }
    }
    return false;
  }

  /// Matches a version-like token: `1.2.3` or `1.2.3+45`, with an optional
  /// leading `v`. Group 1 is the `major.minor.patch` core, group 2 the optional
  /// build number.
  static final RegExp _versionLikeTokenPattern = RegExp(
    r'^v?(\d+\.\d+\.\d+)(?:\+(\d+))?$',
  );

  /// Blocks creating a version-like git tag whose value disagrees with the
  /// project's `pubspec.yaml` version, which would label the release with the
  /// wrong version or build number (e.g. tagging `1.3.8+19` while pubspec says
  /// `1.3.8+20`). Inert unless this is a tag-creation command, the repo has a
  /// pubspec, and both the tag and the pubspec version parse as version tokens —
  /// so non-Dart repos and non-version tag schemes are never affected.
  static Future<String?> _tagVersionPreflightError({
    required List<String> args,
    required String normalizedCommand,
    required String workingDirectory,
    required Map<String, String> environment,
  }) async {
    final tagName = _versionTagNameForCreation(args);
    if (tagName == null) {
      return null;
    }
    final tagMatch = _versionLikeTokenPattern.firstMatch(tagName);
    if (tagMatch == null) {
      return null;
    }

    final pubspecVersion = await _pubspecVersion(
      workingDirectory: workingDirectory,
      environment: environment,
    );
    if (pubspecVersion == null) {
      return null;
    }
    final pubspecMatch = _versionLikeTokenPattern.firstMatch(pubspecVersion);
    if (pubspecMatch == null) {
      return null;
    }

    final coreMismatch = tagMatch.group(1) != pubspecMatch.group(1);
    final tagBuild = tagMatch.group(2);
    final pubspecBuild = pubspecMatch.group(2);
    final buildMismatch =
        tagBuild != null && pubspecBuild != null && tagBuild != pubspecBuild;
    if (!coreMismatch && !buildMismatch) {
      return null;
    }

    return jsonEncode({
      'command': 'git $normalizedCommand',
      'working_directory': workingDirectory,
      'exit_code': 2,
      'code': 'git_tag_version_mismatch',
      'error':
          'git tag "$tagName" does not match the project version in '
          'pubspec.yaml ("$pubspecVersion"); creating it would label the '
          'release with the wrong version or build number. Re-read pubspec.yaml '
          'and tag the exact version it declares ("$pubspecVersion"), or update '
          'pubspec.yaml first if the intended version differs, then retry.',
      'tag': tagName,
      'pubspec_version': pubspecVersion,
    });
  }

  /// Returns the tag name from a `git tag` creation command, or null when the
  /// command is not creating exactly one tag at HEAD (listing, deletion,
  /// verification, no name, or tagging an explicit commit-ish — where the
  /// worktree pubspec may not correspond to the tagged commit).
  static String? _versionTagNameForCreation(List<String> args) {
    if (args.isEmpty || args.first != 'tag') {
      return null;
    }
    const valueFlags = {'-m', '--message', '-F', '--file', '-u', '--local-user'};
    const listingFlags = {
      '-l',
      '--list',
      '-d',
      '--delete',
      '-v',
      '--verify',
      '-n',
      '--contains',
      '--no-contains',
      '--points-at',
      '--merged',
      '--no-merged',
    };
    final positionals = <String>[];
    for (var i = 1; i < args.length; i++) {
      final arg = args[i];
      if (listingFlags.contains(arg)) {
        return null;
      }
      if (valueFlags.contains(arg)) {
        i++; // skip the flag's value
        continue;
      }
      if (arg.startsWith('-')) {
        continue; // boolean flag (-a, -s, -f, --annotate, ...)
      }
      positionals.add(arg);
    }
    // Exactly one positional is the new tag name; a second positional is a
    // commit-ish, so skip the worktree-pubspec comparison.
    return positionals.length == 1 ? positionals.first : null;
  }

  /// Reads the `version:` value from the repository's `pubspec.yaml` (resolved
  /// from the git top level, falling back to [workingDirectory]). Returns null
  /// when there is no pubspec or no version line.
  static Future<String?> _pubspecVersion({
    required String workingDirectory,
    required Map<String, String> environment,
  }) async {
    var root = workingDirectory;
    try {
      final topLevel = await Process.run(
        'git',
        ['rev-parse', '--show-toplevel'],
        workingDirectory: workingDirectory,
        environment: environment,
      ).timeout(_kTimeout);
      if (topLevel.exitCode == 0) {
        final resolved = (topLevel.stdout as String).trim();
        if (resolved.isNotEmpty) {
          root = resolved;
        }
      }
    } catch (_) {
      // Fall back to the working directory.
    }

    final pubspec = File('$root/pubspec.yaml');
    if (!pubspec.existsSync()) {
      return null;
    }
    final String content;
    try {
      content = await pubspec.readAsString();
    } catch (_) {
      return null;
    }
    for (final line in const LineSplitter().convert(content)) {
      final match = RegExp(r'^version:\s*(\S+)').firstMatch(line);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Argument splitting
  // -------------------------------------------------------------------------

  /// Splits a command string into arguments, respecting single and double
  /// quotes. Does NOT invoke a shell — this is a simple lexer.
  static List<String> splitArgs(String command) {
    command = normalizeCommand(command);
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
