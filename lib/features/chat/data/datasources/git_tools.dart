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
    String? reason,
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

      final mergePreflightError = await _mergePreflightError(
        args: args,
        normalizedCommand: normalizedCommand,
        workingDirectory: workingDirectory,
        environment: environment,
        reason: reason,
      );
      if (mergePreflightError != null) {
        return mergePreflightError;
      }

      final worktreeRemovePreflightError = _worktreeRemovePreflightError(
        args: args,
        normalizedCommand: normalizedCommand,
        workingDirectory: workingDirectory,
      );
      if (worktreeRemovePreflightError != null) {
        return worktreeRemovePreflightError;
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

  static Future<String> finishWorktreeSession({
    required String worktreePath,
    String baseBranch = 'main',
    bool removeWorktree = true,
    String? mergeMessage,
  }) async {
    final normalizedWorktreePath = worktreePath.trim();
    final normalizedBaseBranch = _normalizeBranchName(baseBranch.trim());
    if (normalizedWorktreePath.isEmpty || normalizedBaseBranch.isEmpty) {
      return jsonEncode({
        'ok': false,
        'code': 'git_finish_worktree_invalid_arguments',
        'error': 'worktree_path and base_branch are required.',
      });
    }

    final worktreeDir = Directory(normalizedWorktreePath);
    if (!worktreeDir.existsSync()) {
      return jsonEncode({
        'ok': false,
        'code': 'git_finish_worktree_path_not_found',
        'worktree_path': normalizedWorktreePath,
        'error': 'Worktree path does not exist: $normalizedWorktreePath',
      });
    }

    final environment = await LoginShellEnvironment.instance.environment();
    final currentBranchResult = await _runGitCommand(
      const ['branch', '--show-current'],
      workingDirectory: worktreeDir.absolute.path,
      environment: environment,
    );
    if (currentBranchResult.exitCode != 0) {
      return _finishWorktreeErrorResult(
        code: 'git_finish_worktree_branch_failed',
        error: 'Could not determine the current worktree branch.',
        worktreePath: worktreeDir.absolute.path,
        commandResult: currentBranchResult,
      );
    }
    final currentBranch = currentBranchResult.stdout.trim();
    if (currentBranch.isEmpty) {
      return jsonEncode({
        'ok': false,
        'code': 'git_finish_worktree_detached_head',
        'worktree_path': worktreeDir.absolute.path,
        'error': 'The selected worktree is detached and cannot be finished.',
      });
    }
    if (_normalizeBranchName(currentBranch) == normalizedBaseBranch) {
      return jsonEncode({
        'ok': false,
        'code': 'git_finish_worktree_base_branch_selected',
        'worktree_path': worktreeDir.absolute.path,
        'base_branch': normalizedBaseBranch,
        'current_branch': currentBranch,
        'error':
            'The selected worktree is already on the base branch; there is no '
            'feature branch to merge.',
      });
    }

    final worktreeStatus = await _runGitCommand(
      const ['status', '--porcelain'],
      workingDirectory: worktreeDir.absolute.path,
      environment: environment,
    );
    if (worktreeStatus.exitCode != 0) {
      return _finishWorktreeErrorResult(
        code: 'git_finish_worktree_status_failed',
        error: 'Could not inspect worktree status before merge.',
        worktreePath: worktreeDir.absolute.path,
        baseBranch: normalizedBaseBranch,
        currentBranch: currentBranch,
        commandResult: worktreeStatus,
      );
    }
    if (worktreeStatus.stdout.trim().isNotEmpty) {
      return jsonEncode({
        'ok': false,
        'code': 'git_finish_worktree_dirty',
        'worktree_path': worktreeDir.absolute.path,
        'base_branch': normalizedBaseBranch,
        'current_branch': currentBranch,
        'status': worktreeStatus.stdout,
        'error':
            'The worktree has uncommitted changes. Commit, stash, or discard '
            'them before finishing the worktree session.',
      });
    }

    final worktreeListResult = await _runGitCommand(
      const ['worktree', 'list', '--porcelain'],
      workingDirectory: worktreeDir.absolute.path,
      environment: environment,
    );
    if (worktreeListResult.exitCode != 0) {
      return _finishWorktreeErrorResult(
        code: 'git_finish_worktree_list_failed',
        error: 'Could not read git worktree list.',
        worktreePath: worktreeDir.absolute.path,
        baseBranch: normalizedBaseBranch,
        currentBranch: currentBranch,
        commandResult: worktreeListResult,
      );
    }

    final entries = _parseWorktreeListPorcelain(worktreeListResult.stdout);
    final normalizedCurrentPath = _normalizeFilesystemPath(
      worktreeDir.absolute.path,
    );
    final currentEntry = entries
        .where((entry) => entry.normalizedPath == normalizedCurrentPath)
        .firstOrNull;
    if (currentEntry == null) {
      return jsonEncode({
        'ok': false,
        'code': 'git_finish_worktree_not_registered',
        'worktree_path': worktreeDir.absolute.path,
        'base_branch': normalizedBaseBranch,
        'current_branch': currentBranch,
        'worktrees': entries.map((entry) => entry.toJson()).toList(),
        'error': 'The selected path is not registered in git worktree list.',
      });
    }

    final baseEntry = entries
        .where(
          (entry) => _normalizeBranchName(entry.branch) == normalizedBaseBranch,
        )
        .firstOrNull;
    if (baseEntry == null) {
      return jsonEncode({
        'ok': false,
        'code': 'git_finish_worktree_base_not_found',
        'worktree_path': worktreeDir.absolute.path,
        'base_branch': normalizedBaseBranch,
        'current_branch': currentBranch,
        'worktrees': entries.map((entry) => entry.toJson()).toList(),
        'error':
            'No git worktree is currently checked out on the base branch '
            '"$normalizedBaseBranch".',
      });
    }

    final baseStatus = await _runGitCommand(
      const ['status', '--porcelain'],
      workingDirectory: baseEntry.path,
      environment: environment,
    );
    if (baseStatus.exitCode != 0) {
      return _finishWorktreeErrorResult(
        code: 'git_finish_worktree_base_status_failed',
        error: 'Could not inspect base worktree status before merge.',
        worktreePath: worktreeDir.absolute.path,
        basePath: baseEntry.path,
        baseBranch: normalizedBaseBranch,
        currentBranch: currentBranch,
        commandResult: baseStatus,
      );
    }
    if (baseStatus.stdout.trim().isNotEmpty) {
      return jsonEncode({
        'ok': false,
        'code': 'git_finish_worktree_base_dirty',
        'worktree_path': worktreeDir.absolute.path,
        'base_worktree_path': baseEntry.path,
        'base_branch': normalizedBaseBranch,
        'current_branch': currentBranch,
        'status': baseStatus.stdout,
        'error':
            'The base worktree has uncommitted changes. Clean it before '
            'merging the worktree branch.',
      });
    }

    final mergeArgs = <String>['merge', '--no-edit'];
    final trimmedMessage = mergeMessage?.trim();
    if (trimmedMessage != null && trimmedMessage.isNotEmpty) {
      mergeArgs.addAll(['-m', trimmedMessage]);
    }
    mergeArgs.add(currentBranch);
    final mergeResult = await _runGitCommand(
      mergeArgs,
      workingDirectory: baseEntry.path,
      environment: environment,
    );
    if (mergeResult.exitCode != 0) {
      return jsonEncode({
        'ok': false,
        'code': 'git_finish_worktree_merge_failed',
        'worktree_path': worktreeDir.absolute.path,
        'base_worktree_path': baseEntry.path,
        'base_branch': normalizedBaseBranch,
        'current_branch': currentBranch,
        'merge': mergeResult.toJson(),
        'error': 'Failed to merge the worktree branch into the base worktree.',
      });
    }

    _GitCommandRun? unlockResult;
    _GitCommandRun? removeResult;
    if (removeWorktree) {
      unlockResult = await _runGitCommand(
        ['worktree', 'unlock', worktreeDir.absolute.path],
        workingDirectory: baseEntry.path,
        environment: environment,
      );
      removeResult = await _runGitCommand(
        ['worktree', 'remove', worktreeDir.absolute.path],
        workingDirectory: baseEntry.path,
        environment: environment,
      );
      if (removeResult.exitCode != 0) {
        return jsonEncode({
          'ok': false,
          'code': 'git_finish_worktree_remove_failed',
          'worktree_path': worktreeDir.absolute.path,
          'base_worktree_path': baseEntry.path,
          'base_branch': normalizedBaseBranch,
          'current_branch': currentBranch,
          'merge': mergeResult.toJson(),
          'unlock': unlockResult.toJson(),
          'remove': removeResult.toJson(),
          'error': 'Merged the branch, but failed to remove the worktree path.',
        });
      }
    }

    return jsonEncode({
      'ok': true,
      'code': 'git_finish_worktree_completed',
      'worktree_path': worktreeDir.absolute.path,
      'base_worktree_path': baseEntry.path,
      'base_branch': normalizedBaseBranch,
      'current_branch': currentBranch,
      'worktree_branch': currentEntry.branch,
      'removed_worktree': removeWorktree,
      'merge': mergeResult.toJson(),
      if (unlockResult != null && unlockResult.exitCode == 0)
        'unlock': unlockResult.toJson(),
      if (removeResult != null) 'remove': removeResult.toJson(),
    });
  }

  static String? _worktreeRemovePreflightError({
    required List<String> args,
    required String normalizedCommand,
    required String workingDirectory,
  }) {
    if (args.length < 3 || args[0] != 'worktree' || args[1] != 'remove') {
      return null;
    }
    final forceCount = args
        .skip(2)
        .fold<int>(0, (count, arg) => count + _worktreeRemoveForceCount(arg));
    if (forceCount < 2) {
      return null;
    }
    return jsonEncode({
      'command': 'git $normalizedCommand',
      'working_directory': workingDirectory,
      'exit_code': 2,
      'code': 'git_worktree_force_remove_blocked',
      'error':
          'git worktree remove was blocked because double-force removal can '
          'discard a locked Caverno worktree without merging it through the '
          'base worktree.',
      'required_action':
          'Use git_finish_worktree_session for worktree completion after all '
          'intended changes are committed. Only remove a worktree manually '
          'outside Caverno when you intentionally want to discard it.',
    });
  }

  static int _worktreeRemoveForceCount(String arg) {
    if (arg == '--force' || arg == '-f') {
      return 1;
    }
    if (arg.length > 2 && arg.startsWith('-') && !arg.startsWith('--')) {
      final shortFlags = arg.substring(1);
      if (RegExp(r'^f+$').hasMatch(shortFlags)) {
        return shortFlags.length;
      }
    }
    return 0;
  }

  static Future<String?> _mergePreflightError({
    required List<String> args,
    required String normalizedCommand,
    required String workingDirectory,
    required Map<String, String> environment,
    required String? reason,
  }) async {
    final mergeTargets = _mergeTargets(args);
    if (mergeTargets.isEmpty) {
      return null;
    }

    try {
      final branchResult = await Process.run(
        'git',
        ['branch', '--show-current'],
        workingDirectory: workingDirectory,
        environment: environment,
      ).timeout(_kTimeout);
      if (branchResult.exitCode != 0) {
        return null;
      }
      final currentBranch = (branchResult.stdout as String).trim();
      if (currentBranch.isEmpty) {
        return null;
      }
      final normalizedCurrent = _normalizeBranchName(currentBranch);
      for (final target in mergeTargets) {
        if (_normalizeBranchName(target) != normalizedCurrent) {
          continue;
        }
        return jsonEncode({
          'command': 'git $normalizedCommand',
          'working_directory': workingDirectory,
          'exit_code': 2,
          'code': 'git_merge_current_branch',
          'error':
              'git merge was blocked because the command would merge the '
              'current branch "$currentBranch" into itself, which only reports '
              'Already up to date and does not merge it into another branch. '
              'If the intent is to merge this branch into main, inspect '
              'git worktree list and run the merge from the worktree where '
              'main is checked out.',
          'current_branch': currentBranch,
          'merge_target': target,
        });
      }
      final intendedTargetBranch = _intendedMergeDestinationBranch(
        args: args,
        normalizedCommand: normalizedCommand,
        reason: reason,
      );
      if (intendedTargetBranch != null &&
          _normalizeBranchName(intendedTargetBranch) != normalizedCurrent) {
        return jsonEncode({
          'command': 'git $normalizedCommand',
          'working_directory': workingDirectory,
          'exit_code': 2,
          'code': 'git_merge_wrong_target_worktree',
          'error':
              'git merge was blocked because the command context indicates '
              'that the merge should land on "$intendedTargetBranch", but the '
              'working directory is currently on "$currentBranch". Inspect '
              'git worktree list and run the merge from the worktree where '
              '"$intendedTargetBranch" is checked out.',
          'current_branch': currentBranch,
          'intended_target_branch': intendedTargetBranch,
          'merge_targets': mergeTargets,
        });
      }
      return null;
    } on TimeoutException {
      return jsonEncode({
        'command': 'git $normalizedCommand',
        'working_directory': workingDirectory,
        'exit_code': 2,
        'code': 'git_merge_preflight_timeout',
        'error': 'Timed out while checking the current branch before merge.',
      });
    } catch (e) {
      return jsonEncode({
        'command': 'git $normalizedCommand',
        'working_directory': workingDirectory,
        'exit_code': 2,
        'code': 'git_merge_preflight_failed',
        'error': 'Failed to check the current branch before merge: $e',
      });
    }
  }

  static String? _intendedMergeDestinationBranch({
    required List<String> args,
    required String normalizedCommand,
    required String? reason,
  }) {
    if (args.isEmpty || args.first != 'merge') {
      return null;
    }
    if (_mergeTargets(
      args,
    ).any((target) => _normalizeBranchName(target) == 'main')) {
      return null;
    }
    final context = [
      normalizedCommand,
      reason?.trim() ?? '',
    ].where((value) => value.isNotEmpty).join(' ').toLowerCase();
    if (context.isEmpty || !RegExp(r'\bmain\b').hasMatch(context)) {
      return null;
    }
    return 'main';
  }

  static List<String> _mergeTargets(List<String> args) {
    if (args.isEmpty || args.first != 'merge') {
      return const <String>[];
    }
    const actionFlags = {'--abort', '--continue', '--quit', '--skip'};
    const flagPrefixesWithValues = {
      '--message=',
      '--gpg-sign=',
      '--strategy=',
      '--strategy-option=',
      '--into-name=',
      '--cleanup=',
      '--file=',
      '--log=',
    };
    const valueFlags = {
      '-m',
      '--message',
      '--strategy',
      '-s',
      '--strategy-option',
      '-X',
      '--into-name',
      '--cleanup',
      '-F',
      '--file',
    };
    final targets = <String>[];
    for (var index = 1; index < args.length; index++) {
      final arg = args[index];
      if (arg == '--') {
        targets.addAll(args.skip(index + 1));
        break;
      }
      if (actionFlags.contains(arg)) {
        return const <String>[];
      }
      if (valueFlags.contains(arg)) {
        index += 1;
        continue;
      }
      if (flagPrefixesWithValues.any(arg.startsWith)) {
        continue;
      }
      if (arg.startsWith('-')) {
        continue;
      }
      targets.add(arg);
    }
    return targets;
  }

  static String _normalizeBranchName(String branchName) {
    var normalized = branchName.trim();
    if (normalized.startsWith('refs/heads/')) {
      normalized = normalized.substring('refs/heads/'.length);
    }
    return normalized;
  }

  static String _normalizeFilesystemPath(String path) {
    var normalized = Directory(path).absolute.path;
    try {
      normalized = Directory(normalized).resolveSymbolicLinksSync();
    } catch (_) {
      // Fall back to the absolute path when the entry no longer exists.
    }
    while (normalized.length > 1 &&
        (normalized.endsWith('/') || normalized.endsWith('\\'))) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static Future<_GitCommandRun> _runGitCommand(
    List<String> args, {
    required String workingDirectory,
    required Map<String, String> environment,
  }) async {
    final command = 'git ${args.join(' ')}';
    try {
      final result = await Process.run(
        'git',
        args,
        workingDirectory: workingDirectory,
        environment: environment,
      ).timeout(_kTimeout);
      return _GitCommandRun(
        command: command,
        workingDirectory: workingDirectory,
        exitCode: result.exitCode,
        stdout: result.stdout is String ? result.stdout as String : '',
        stderr: result.stderr is String ? result.stderr as String : '',
      );
    } on TimeoutException {
      return _GitCommandRun(
        command: command,
        workingDirectory: workingDirectory,
        exitCode: 124,
        stdout: '',
        stderr:
            'Command timed out after ${_kTimeout.inSeconds} seconds. Avoid '
            'interactive git commands.',
      );
    } catch (error) {
      return _GitCommandRun(
        command: command,
        workingDirectory: workingDirectory,
        exitCode: 1,
        stdout: '',
        stderr: error.toString(),
      );
    }
  }

  static String _finishWorktreeErrorResult({
    required String code,
    required String error,
    required String worktreePath,
    required _GitCommandRun commandResult,
    String? basePath,
    String? baseBranch,
    String? currentBranch,
  }) {
    final payload = <String, dynamic>{
      'ok': false,
      'code': code,
      'worktree_path': worktreePath,
      'command_result': commandResult.toJson(),
      'error': error,
    };
    if (basePath != null) {
      payload['base_worktree_path'] = basePath;
    }
    if (baseBranch != null) {
      payload['base_branch'] = baseBranch;
    }
    if (currentBranch != null) {
      payload['current_branch'] = currentBranch;
    }
    return jsonEncode(payload);
  }

  static List<_GitWorktreeEntry> _parseWorktreeListPorcelain(String output) {
    final entries = <_GitWorktreeEntry>[];
    String? path;
    var branch = '';

    void flush() {
      final currentPath = path?.trim();
      if (currentPath != null && currentPath.isNotEmpty) {
        entries.add(_GitWorktreeEntry(path: currentPath, branch: branch));
      }
      path = null;
      branch = '';
    }

    for (final line in const LineSplitter().convert(output)) {
      if (line.startsWith('worktree ')) {
        flush();
        path = line.substring('worktree '.length).trim();
        continue;
      }
      if (line.startsWith('branch ')) {
        branch = line.substring('branch '.length).trim();
      }
    }
    flush();

    return entries;
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
    const valueFlags = {
      '-m',
      '--message',
      '-F',
      '--file',
      '-u',
      '--local-user',
    };
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

class _GitCommandRun {
  const _GitCommandRun({
    required this.command,
    required this.workingDirectory,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final String command;
  final String workingDirectory;
  final int exitCode;
  final String stdout;
  final String stderr;

  Map<String, dynamic> toJson() {
    final stdoutTruncated = stdout.length > GitTools._kMaxOutputChars;
    final stderrTruncated = stderr.length > GitTools._kMaxOutputChars;
    return {
      'command': command,
      'working_directory': workingDirectory,
      'exit_code': exitCode,
      'stdout': stdoutTruncated
          ? stdout.substring(0, GitTools._kMaxOutputChars)
          : stdout,
      'stderr': stderrTruncated
          ? stderr.substring(0, GitTools._kMaxOutputChars)
          : stderr,
      if (stdoutTruncated) 'stdout_truncated': true,
      if (stderrTruncated) 'stderr_truncated': true,
    };
  }
}

class _GitWorktreeEntry {
  const _GitWorktreeEntry({required this.path, required this.branch});

  final String path;
  final String branch;

  String get normalizedPath => GitTools._normalizeFilesystemPath(path);

  Map<String, dynamic> toJson() {
    return {'path': path, if (branch.isNotEmpty) 'branch': branch};
  }
}
