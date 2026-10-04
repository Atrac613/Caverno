import 'dart:convert';
import 'dart:io';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';
import 'package:path/path.dart' as path;

import 'bounded_command_output.dart';
import 'filesystem_tools.dart';
import 'first_party_tool_execution_result.dart';
import 'git_tools.dart';
import 'local_command_mutation_guard.dart';
import 'local_shell_grep.dart';
import 'local_shell_launch_plan.dart';
import 'local_shell_process_runner.dart';
import 'project_mutation_path_fence.dart';
import 'project_read_path_fence.dart';
import 'turn_project_root.dart';

class LocalShellTools {
  LocalShellTools._();

  static const int _maxOutputChars = 12000;
  static const Duration _timeout = Duration(seconds: 60);
  static final RegExp _modelControlTokenPattern = RegExp(r'<\|[^>]*\|>');

  static bool get isDesktopPlatform =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  static String normalizeCommand(String command) {
    return command.replaceAll(_modelControlTokenPattern, '').trim();
  }

  static String? gitWriteCommandBlockedResult({
    required String command,
    required String workingDirectory,
  }) {
    final normalizedCommand = normalizeCommand(command);
    final gitWriteCommand = _firstDirectGitWriteCommand(normalizedCommand);
    if (gitWriteCommand == null) {
      return null;
    }
    return jsonEncode({
      'ok': false,
      'code': 'local_shell_git_write_blocked',
      ...ToolResultOrigin.refusal.marker,
      'command': normalizedCommand,
      'working_directory': workingDirectory,
      'git_command': gitWriteCommand.gitCommand,
      'git_subcommand': gitWriteCommand.gitSubcommand,
      'exit_code': 2,
      'error':
          'Direct git write commands are blocked in local shell execution '
          'because they bypass repository safety preflights.',
      'required_action':
          'Use git_execute_command with the git_subcommand value and the same '
          'working_directory. For worktree completion after commits are ready, '
          'use git_finish_worktree_session instead of merging or removing the '
          'worktree manually.',
    });
  }

  static bool isReadOnly(String command) {
    final trimmed = normalizeCommand(command);
    if (trimmed.isEmpty) return false;
    return _canExecuteInternally(trimmed);
  }

  static Future<ProjectReadPathDenial?> projectReadDenial({
    required String command,
    required String workingDirectory,
    required String? projectRoot,
  }) async {
    final normalized = normalizeCommand(command);
    if (!_canExecuteInternally(normalized)) return null;
    final segments = _internalSteps(normalized)!
        .map((step) => _splitArgs(step.command))
        .where((args) => args.isNotEmpty)
        .toList(growable: false);
    if (segments.every((args) => args.first == 'echo')) return null;
    const fence = ProjectReadPathFence();
    final workingDirectoryAuthorization = await fence.authorize(
      projectRoot: projectRoot,
      rawPath: workingDirectory,
    );
    if (!workingDirectoryAuthorization.isAllowed) {
      return workingDirectoryAuthorization.denial;
    }
    for (final args in segments) {
      if (args.first == 'echo') continue;
      for (final path in _internalReadPaths(args)) {
        final authorization = await fence.authorize(
          projectRoot: projectRoot,
          rawPath: path,
          baseDirectory: workingDirectory,
        );
        if (!authorization.isAllowed) return authorization.denial;
      }
    }
    return null;
  }

  static List<String> _internalReadPaths(List<String> args) {
    final command = args.first;
    final operands = args.skip(1).toList();
    return switch (command) {
      'pwd' => const <String>[],
      'cat' || 'ls' || 'wc' => [
        for (final operand in operands)
          if (!operand.startsWith('-')) operand,
        if (command == 'ls' && operands.every((value) => value.startsWith('-')))
          '.',
      ],
      'head' || 'tail' => _parseHeadTailArgs(operands, command).filePaths,
      'find' => [
        if (operands.isNotEmpty && !operands.first.startsWith('-'))
          operands.first
        else
          '.',
      ],
      'rg' => [_rgSearchRoot(operands)],
      // Classification already proved the parse succeeds; fencing every
      // operand is the fail-closed answer if it somehow did not.
      'grep' => LocalShellGrep.parse(operands)?.readPaths ?? operands,
      _ => const <String>[],
    };
  }

  static String _rgSearchRoot(List<String> args) {
    var filesOnly = false;
    final positional = <String>[];
    for (var index = 0; index < args.length; index++) {
      final arg = args[index];
      if (arg == '--files') {
        filesOnly = true;
      } else if (arg == '-g') {
        index += 1;
      } else if (!arg.startsWith('-')) {
        positional.add(arg);
      }
    }
    if (filesOnly) return positional.isEmpty ? '.' : positional.first;
    return positional.length > 1 ? positional[1] : '.';
  }

  static Future<String> execute({
    required String command,
    required String workingDirectory,
    Duration timeout = _timeout,
  }) async => (await executeResult(
    command: command,
    workingDirectory: workingDirectory,
    timeout: timeout,
  )).result;

  static Future<FirstPartyToolExecutionResult> executeResult({
    required String command,
    required String workingDirectory,
    Duration timeout = _timeout,
    String? projectRoot,
    String? observationRoot,
    String? containmentRoot,
  }) async {
    final authorized = await _authorizeMutation(
      command: command,
      workingDirectory: workingDirectory,
      projectRoot: projectRoot,
    );
    if (authorized.denied != null) {
      return authorized.denied!;
    }
    final directory = Directory(authorized.workingDirectory);
    if (!directory.existsSync()) {
      return FirstPartyToolExecutionResult.payloadOnly(
        jsonEncode({
          'error':
              'Working directory does not exist: ${authorized.workingDirectory}',
        }),
      );
    }

    final normalizedCommand = normalizeCommand(command);
    if (normalizedCommand.isEmpty) {
      return FirstPartyToolExecutionResult.payloadOnly(
        jsonEncode({'error': 'Command is required'}),
      );
    }
    final gitWriteBlockedResult = gitWriteCommandBlockedResult(
      command: normalizedCommand,
      workingDirectory: directory.absolute.path,
    );
    if (gitWriteBlockedResult != null) {
      return FirstPartyToolExecutionResult.payloadOnly(gitWriteBlockedResult);
    }

    if (containmentRoot == null && _canExecuteInternally(normalizedCommand)) {
      return _executeInternally(
        command: normalizedCommand,
        workingDirectory: directory.absolute.path,
        projectRoot: projectRoot,
      );
    }

    final shellExecutable = Platform.isWindows ? 'cmd' : 'bash';
    final shellArgs = Platform.isWindows
        ? ['/C', normalizedCommand]
        : [
            '-o',
            'pipefail',
            if (_shouldEnableImplicitErrexit(normalizedCommand)) '-e',
            '-c',
            normalizedCommand,
          ];

    final launch = await LocalShellLaunchPlan.prepare(
      command: normalizedCommand,
      shellExecutable: shellExecutable,
      shellArgs: shellArgs,
      observationRoot: observationRoot,
      containmentRoot: containmentRoot,
    );
    if (launch == null) {
      const error = 'Command workspace containment could not be started';
      return FirstPartyToolExecutionResult(
        result: jsonEncode({'ok': false, 'error': error}),
        errorMessage: error,
      );
    }
    try {
      return await LocalShellProcessRunner.execute(
        command: normalizedCommand,
        workingDirectory: directory.absolute.path,
        maxOutputChars: _maxOutputChars,
        shellExecutable: launch.executable,
        shellArgs: launch.args,
        timeout: timeout,
        observationTag: launch.observationTag,
        scratchDirectory: launch.scratchDirectory,
      );
    } catch (e) {
      return FirstPartyToolExecutionResult.payloadOnly(
        jsonEncode({
          'command': normalizedCommand,
          'working_directory': directory.absolute.path,
          'error': e.toString(),
        }),
      );
    } finally {
      await launch.dispose();
    }
  }

  static Future<
    ({FirstPartyToolExecutionResult? denied, String workingDirectory})
  >
  _authorizeMutation({
    required String command,
    required String workingDirectory,
    required String? projectRoot,
  }) async {
    final fenceRoot = LocalCommandMutationGuard.authorizedProjectRoot(
      projectRoot,
    );
    if (fenceRoot == null) {
      return (denied: null, workingDirectory: workingDirectory);
    }
    const toolName = 'local_execute_command';
    final cwdAuth = await LocalCommandMutationGuard.authorizeWorkingDirectory(
      toolName: toolName,
      projectRoot: fenceRoot,
      workingDirectory: workingDirectory,
    );
    if (!cwdAuth.isAllowed) {
      return (
        denied: _mutationFailure(cwdAuth),
        workingDirectory: workingDirectory,
      );
    }
    final canonicalWorkingDirectory = cwdAuth.canonicalPath!;
    final normalizedCommand = normalizeCommand(command);
    if (!isReadOnly(normalizedCommand)) {
      final writeAuth = await LocalCommandMutationGuard.authorizeWritePaths(
        toolName: toolName,
        projectRoot: fenceRoot,
        command: normalizedCommand,
        workingDirectory: canonicalWorkingDirectory,
      );
      if (writeAuth != null && !writeAuth.isAllowed) {
        return (
          denied: _mutationFailure(writeAuth),
          workingDirectory: canonicalWorkingDirectory,
        );
      }
    }
    return (denied: null, workingDirectory: canonicalWorkingDirectory);
  }

  static FirstPartyToolExecutionResult _mutationFailure(
    ProjectMutationPathAuthorization authorization,
  ) {
    final denied = authorization.deniedResult!;
    return FirstPartyToolExecutionResult(
      result: denied.result,
      errorMessage: denied.errorMessage ?? denied.result,
    );
  }

  static bool _shouldEnableImplicitErrexit(String command) {
    String? quoteChar;

    for (var index = 0; index < command.length; index++) {
      final char = command[index];

      if (quoteChar != null) {
        if (quoteChar == '"' && char == '\\') {
          index += 1;
          continue;
        }
        if (char == quoteChar) {
          quoteChar = null;
        }
        continue;
      }

      if (char == '\\') {
        index += 1;
        continue;
      }
      if (char == '"' || char == "'") {
        quoteChar = char;
        continue;
      }
      if (char == '#' && _startsShellComment(command, index)) {
        while (index + 1 < command.length && command[index + 1] != '\n') {
          index += 1;
        }
        continue;
      }
      if (char == ';') {
        return false;
      }
      // A subshell or a negated check owns its own exit status: under `-e` the
      // shell can abort inside `(...)` before `!` inverts the result, turning a
      // passing acceptance check such as `(! prog bad-id)` into a false
      // failure — and a run that cannot trust its own exit codes starts
      // explaining them away instead.
      if (char == '(') {
        return false;
      }
      if (char == '!' && _startsNegatedCommand(command, index)) {
        return false;
      }
      if (char == '|' &&
          index + 1 < command.length &&
          command[index + 1] == '|') {
        return false;
      }
      if (char == '<' &&
          index + 1 < command.length &&
          command[index + 1] == '<') {
        return false;
      }
    }

    final containsMultilineControlFlow = RegExp(
      r'(^|\n)\s*(if|then|elif|else|fi|for|while|until|case|esac|select|do|done)\b',
      multiLine: true,
    ).hasMatch(command);
    return !containsMultilineControlFlow;
  }

  /// Whether `!` at [index] negates a command rather than appearing inside a
  /// word (`foo!bar`) or a history-style token.
  static bool _startsNegatedCommand(String command, int index) {
    final next = index + 1 < command.length ? command[index + 1] : ' ';
    if (next != ' ' && next != '\t') return false;
    for (var i = index - 1; i >= 0; i--) {
      final char = command[i];
      if (char == ' ' || char == '\t') continue;
      return char == '&' || char == '|' || char == ';' || char == '\n';
    }
    return true;
  }

  static bool _startsShellComment(String command, int index) {
    if (index == 0) {
      return true;
    }
    return RegExp(r'[\s;&|()<>]').hasMatch(command[index - 1]);
  }

  /// Whether [command] carries syntax the internal executors cannot honour.
  ///
  /// Quote-aware because grep patterns routinely hold `$` and `\|`, and inside
  /// single quotes `sh` gives no character a meaning; inside double quotes
  /// only `$`, the backtick and the backslash keep one. Getting this wrong
  /// cannot run anything -- a command accepted here is executed by Caverno,
  /// never by `sh` -- it can only make the internal answer differ from the
  /// shell's, so an unterminated quote or a newline still refuses outright.
  static bool _hasUnsafeShellSyntax(String command) {
    String? quoteChar;
    for (var index = 0; index < command.length; index++) {
      final char = command[index];
      if (char == '\n') return true;
      if (quoteChar == "'") {
        if (char == "'") quoteChar = null;
        continue;
      }
      if (quoteChar == '"') {
        if (char == '"') {
          quoteChar = null;
        } else if (char == r'$' || char == '`') {
          return true;
        } else if (char == r'\') {
          index += 1;
          if (index < command.length && command[index] == '\n') return true;
        }
        continue;
      }
      if (char == r'\') {
        // An escaped operator stays refused, as it was before quotes counted:
        // `_splitArgs` keeps the backslash that `sh` would remove.
        index += 1;
        if (index < command.length &&
            '\n$_shellOperatorChars'.contains(command[index])) {
          return true;
        }
        continue;
      }
      if (char == "'" || char == '"') {
        quoteChar = char;
        continue;
      }
      if (_shellOperatorChars.contains(char)) return true;
    }
    return quoteChar != null;
  }

  static const String _shellOperatorChars = '|&;<>`\$#';

  static bool _canExecuteInternally(String command) {
    final steps = _internalSteps(command);
    if (steps == null || steps.isEmpty) return false;
    return steps.every(
      (step) => _canExecuteSingleCommandInternally(step.command),
    );
  }

  static bool _canExecuteSingleCommandInternally(String command) {
    if (_hasUnsafeShellSyntax(command)) return false;

    final args = _splitArgs(command.trim());
    if (args.isEmpty) return false;

    return switch (args.first) {
      'pwd' ||
      'echo' ||
      'cat' ||
      'ls' ||
      'head' ||
      'tail' ||
      'wc' ||
      'find' ||
      'rg' => true,
      'grep' =>
        !_hasUnquotedShellExpansion(command) &&
            LocalShellGrep.parse(args.skip(1).toList()) != null,
      'git' => _readOnlyGitSubcommand(command, args) != null,
      _ => false,
    };
  }

  /// The subcommand of a `git` segment that `git_execute_command` would run
  /// without approval, or null.
  ///
  /// The segment is handed to [GitTools.executeResult], the same executor,
  /// fences and flag allowlist as that tool, so running it here grants nothing
  /// that tool does not already. Two shapes it never receives are refused: a
  /// global option before the subcommand -- `-c core.fsmonitor=<program>`
  /// makes a plain `git status` run that program, and `-C` / `--git-dir`
  /// move it out of the fenced directory -- and any word `sh` would expand
  /// differently from the quote-stripping split, as for grep.
  ///
  /// Outside a turn's coding project GitTools refuses every command, so there
  /// a git segment stays on the shell path, where it can still run once
  /// approved, rather than skip approval only to be refused.
  static String? _readOnlyGitSubcommand(String command, List<String> args) {
    final projectRoot = TurnProjectRoot.current?.rootPath.trim() ?? '';
    if (projectRoot.isEmpty) return null;
    if (args.length < 2 || args[1].startsWith('-')) return null;
    final match = _gitInvocationPattern.firstMatch(command.trim());
    if (match == null || _hasUnquotedShellExpansion(command)) return null;
    final subcommand = match.group(1)!;
    return GitTools.isReadOnly(subcommand) ? subcommand : null;
  }

  static final RegExp _gitInvocationPattern = RegExp(r'^git\s+(\S.*)$');

  /// Whether `sh` would build a word of [command] differently from
  /// [_splitArgs]: pathname globbing, brace or tilde expansion, backslash
  /// removal, or an empty quoted word (`''`), which [_splitArgs] drops.
  ///
  /// The internal executors take their argv from [_splitArgs], which only
  /// strips quotes. For `grep` that difference decides what is searched --
  /// `grep foo lib/*.dart` names a literal file here and a list of files in
  /// the shell, and `grep '' a b` would search for `a` -- so such a command
  /// stays on the shell path instead of silently answering a different
  /// question. Glob characters inside option words (`--include=*.dart`) are
  /// left alone: expanding those needs a file literally named like the option.
  static bool _hasUnquotedShellExpansion(String command) {
    String? quoteChar;
    var inWord = false;
    var wordHasChars = false;
    var optionWord = false;
    for (var index = 0; index < command.length; index++) {
      final char = command[index];
      if (quoteChar == "'") {
        if (char == "'") {
          quoteChar = null;
        } else {
          wordHasChars = true;
        }
        continue;
      }
      if (quoteChar == '"') {
        if (char == '"') {
          quoteChar = null;
        } else if (char == r'\' &&
            index + 1 < command.length &&
            (command[index + 1] == '"' || command[index + 1] == r'\')) {
          return true;
        } else {
          wordHasChars = true;
        }
        continue;
      }
      if (char == ' ' || char == '\t') {
        if (inWord && !wordHasChars) return true;
        inWord = false;
        continue;
      }
      if (!inWord) {
        inWord = true;
        wordHasChars = false;
        optionWord = char == '-';
        if (char == '~') return true;
      }
      if (char == "'" || char == '"') {
        quoteChar = char;
        continue;
      }
      wordHasChars = true;
      if (char == r'\') return true;
      if (!optionWord && '*?[{'.contains(char)) return true;
    }
    return inWord && !wordHasChars;
  }

  /// [command] as the chain the internal executors would run, or null when
  /// its separators cannot be mirrored without `sh`.
  ///
  /// `&&` and a newline stop the chain at the first failure; `;` does not.
  /// A newline only stops it because the shell path adds `-e` to a multi-line
  /// command -- and drops `-e` as soon as the command also holds a `;`. Rather
  /// than model that interaction, a command mixing the two stays on the shell
  /// path. A backslash keeps the character after it inside the segment, so an
  /// escaped separator such as `find ... \;` is left for
  /// [_hasUnsafeShellSyntax] to refuse instead of being split on.
  ///
  /// Each segment may end in one `| head -N` / `| tail -N`, parsed by
  /// [GitTools.parseTrailingLineLimit] so both tools accept the same clause.
  /// Any other pipe stays in the segment and makes it unsafe.
  static List<_InternalStep>? _internalSteps(String command) {
    final steps = <_InternalStep>[];
    final buffer = StringBuffer();
    String? quoteChar;
    var continuesAfterFailure = true;
    var sawSemicolon = false;
    var sawNewline = false;

    void flush() {
      final segment = buffer.toString().trim();
      buffer.clear();
      if (segment.isEmpty) return;
      final lineLimit = GitTools.parseTrailingLineLimit(segment);
      steps.add(
        _InternalStep(
          command: lineLimit?.command ?? segment,
          lineLimit: lineLimit,
          continuesAfterFailure: continuesAfterFailure,
        ),
      );
    }

    for (var i = 0; i < command.length; i++) {
      final char = command[i];

      if (quoteChar != null) {
        if (quoteChar == '"' && char == r'\' && i + 1 < command.length) {
          buffer.write(char);
          i += 1;
          buffer.write(command[i]);
          continue;
        }
        if (char == quoteChar) {
          quoteChar = null;
        }
        buffer.write(char);
        continue;
      }

      if (char == r'\' && i + 1 < command.length) {
        buffer.write(char);
        i += 1;
        buffer.write(command[i]);
        continue;
      }

      if (char == '"' || char == "'") {
        quoteChar = char;
        buffer.write(char);
        continue;
      }

      final isAndList =
          char == '&' && i + 1 < command.length && command[i + 1] == '&';
      if (isAndList || char == '\n' || char == ';') {
        flush();
        if (char == ';') sawSemicolon = true;
        if (char == '\n') sawNewline = true;
        continuesAfterFailure = char == ';';
        if (isAndList) i += 1;
        continue;
      }

      buffer.write(char);
    }
    flush();

    if (sawSemicolon && sawNewline) return null;
    return steps;
  }

  static _DirectGitWriteCommand? _firstDirectGitWriteCommand(String command) {
    for (final segment in _splitShellCommandSegments(command)) {
      final args = _splitArgs(segment);
      if (args.length < 2) {
        continue;
      }
      final executable = _basename(args.first).toLowerCase();
      if (executable != 'git') {
        continue;
      }
      final gitSubcommandArgs = _gitArgsAfterGlobalOptions(args);
      if (gitSubcommandArgs.isEmpty) {
        continue;
      }
      final gitSubcommand = gitSubcommandArgs.join(' ');
      if (GitTools.isReadOnly(gitSubcommand)) {
        continue;
      }
      return _DirectGitWriteCommand(
        gitCommand: args.join(' '),
        gitSubcommand: gitSubcommand,
      );
    }
    return null;
  }

  static List<String> _splitShellCommandSegments(String command) {
    final segments = <String>[];
    final buffer = StringBuffer();
    String? quoteChar;

    for (var i = 0; i < command.length; i++) {
      final char = command[i];

      if (quoteChar != null) {
        if (quoteChar == '"' && char == '\\') {
          buffer.write(char);
          if (i + 1 < command.length) {
            i += 1;
            buffer.write(command[i]);
          }
          continue;
        }
        if (char == quoteChar) {
          quoteChar = null;
        }
        buffer.write(char);
        continue;
      }

      if (char == '"' || char == "'") {
        quoteChar = char;
        buffer.write(char);
        continue;
      }

      if (char == '&' && i + 1 < command.length && command[i + 1] == '&') {
        _appendShellCommandSegment(segments, buffer);
        i += 1;
        continue;
      }
      if (char == '&') {
        _appendShellCommandSegment(segments, buffer);
        continue;
      }
      if (char == '|' && i + 1 < command.length && command[i + 1] == '|') {
        _appendShellCommandSegment(segments, buffer);
        i += 1;
        continue;
      }
      if (char == ';' || char == '|' || char == '\n') {
        _appendShellCommandSegment(segments, buffer);
        continue;
      }

      buffer.write(char);
    }

    _appendShellCommandSegment(segments, buffer);
    return segments;
  }

  static void _appendShellCommandSegment(
    List<String> segments,
    StringBuffer buffer,
  ) {
    final segment = buffer.toString().trim();
    if (segment.isNotEmpty) {
      segments.add(segment);
    }
    buffer.clear();
  }

  static List<String> _gitArgsAfterGlobalOptions(List<String> gitArgs) {
    var index = 1;
    while (index < gitArgs.length) {
      final arg = gitArgs[index];
      if (_gitGlobalFlags.contains(arg)) {
        index += 1;
        continue;
      }
      if (_gitGlobalOptionsWithValue.contains(arg)) {
        index += 2;
        continue;
      }
      if (_gitGlobalOptionPrefixesWithValue.any(arg.startsWith)) {
        index += 1;
        continue;
      }
      break;
    }
    return index >= gitArgs.length
        ? const <String>[]
        : gitArgs.skip(index).toList();
  }

  static const Set<String> _gitGlobalFlags = {
    '--bare',
    '--help',
    '--literal-pathspecs',
    '--no-optional-locks',
    '--no-pager',
    '--paginate',
    '--version',
  };

  static const Set<String> _gitGlobalOptionsWithValue = {
    '-C',
    '-c',
    '--config-env',
    '--exec-path',
    '--git-dir',
    '--html-path',
    '--info-path',
    '--man-path',
    '--namespace',
    '--super-prefix',
    '--work-tree',
  };

  static const Set<String> _gitGlobalOptionPrefixesWithValue = {
    '--config-env=',
    '--exec-path=',
    '--git-dir=',
    '--namespace=',
    '--super-prefix=',
    '--work-tree=',
  };

  static String _basename(String path) {
    return path.split(RegExp(r'[\\/]')).last;
  }

  static Future<FirstPartyToolExecutionResult> _executeInternally({
    required String command,
    required String workingDirectory,
    required String? projectRoot,
  }) async {
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    var exitCode = 0;
    var skipping = false;

    for (final step in _internalSteps(command)!) {
      // A failure skips the rest of its `&&` list; the next `;` resumes, as
      // `a && b; c` runs `c` in the shell whether or not `a` failed.
      if (step.continuesAfterFailure) skipping = false;
      if (skipping) continue;

      final result = await _executeInternalSegment(
        step.command,
        workingDirectory: workingDirectory,
        projectRoot: projectRoot,
        lineLimit: step.lineLimit,
      );
      final lineLimit = step.lineLimit;
      final stdout = lineLimit == null
          ? result.stdout
          : lineLimit.apply(result.stdout);

      if (stdout.isNotEmpty) {
        stdoutBuffer.write(stdout);
      }
      if (result.stderr.isNotEmpty) {
        stderrBuffer.write(result.stderr);
      }

      // Match the native pipefail route: output trimming cannot hide failure.
      exitCode = result.exitCode;
      if (exitCode != 0) {
        skipping = true;
      }
    }

    final stdout = stdoutBuffer.toString();
    final stderr = stderrBuffer.toString();
    final stdoutTruncated = stdout.length > _maxOutputChars;
    final stderrTruncated = stderr.length > _maxOutputChars;
    final boundedStdout = BoundedCommandOutput(_maxOutputChars)..add(stdout);
    final boundedStderr = BoundedCommandOutput(_maxOutputChars)..add(stderr);

    return FirstPartyToolExecutionResult(
      result: jsonEncode({
        'command': command,
        'working_directory': workingDirectory,
        'exit_code': exitCode,
        'stdout': boundedStdout.text,
        'stderr': boundedStderr.text,
        'executed_internally': true,
        if (stdoutTruncated) 'stdout_truncated': true,
        if (stderrTruncated) 'stderr_truncated': true,
      }),
      outcome: ToolOutcome(exitCode: exitCode),
    );
  }

  static Future<_LocalCommandResult> _executeInternalSegment(
    String command, {
    required String workingDirectory,
    required String? projectRoot,
    required GitOutputLineLimit? lineLimit,
  }) async {
    final args = _splitArgs(command);
    if (args.isEmpty) {
      return const _LocalCommandResult(exitCode: 1, stderr: 'Empty command\n');
    }

    return switch (args.first) {
      'pwd' => _LocalCommandResult(
        exitCode: 0,
        stdout: '${Directory(workingDirectory).absolute.path}\n',
      ),
      'echo' => _LocalCommandResult(
        exitCode: 0,
        stdout: '${args.skip(1).join(' ')}\n',
      ),
      'cat' => await _executeCat(args.skip(1).toList(), workingDirectory),
      'ls' => await _executeLs(args.skip(1).toList(), workingDirectory),
      'head' => await _executeHead(args.skip(1).toList(), workingDirectory),
      'tail' => await _executeTail(args.skip(1).toList(), workingDirectory),
      'wc' => await _executeWc(args.skip(1).toList(), workingDirectory),
      'find' => await _executeFind(args.skip(1).toList(), workingDirectory),
      'rg' => await _executeRg(args.skip(1).toList(), workingDirectory),
      'grep' => await _executeGrep(args.skip(1).toList(), workingDirectory),
      'git' => await _executeGit(
        command,
        args,
        workingDirectory: workingDirectory,
        projectRoot: projectRoot,
        lineLimit: lineLimit,
      ),
      _ => _LocalCommandResult(
        exitCode: 1,
        stderr: 'Unsupported internal command: ${args.first}\n',
      ),
    };
  }

  static Future<_LocalCommandResult> _executeGit(
    String command,
    List<String> args, {
    required String workingDirectory,
    required String? projectRoot,
    required GitOutputLineLimit? lineLimit,
  }) async {
    final subcommand = _readOnlyGitSubcommand(command, args);
    if (subcommand == null) {
      return const _LocalCommandResult(
        exitCode: 1,
        stderr: 'git: unsupported internal command\n',
      );
    }
    // GitTools caps stdout, so it must apply the line limit itself: a
    // `| tail -N` applied here would read the end of an already-cut head.
    // Applying it again afterwards leaves the lines unchanged.
    final execution = await GitTools.executeResult(
      command: lineLimit == null
          ? subcommand
          : '$subcommand | ${lineLimit.describe}',
      workingDirectory: workingDirectory,
      projectRoot: projectRoot,
    );
    final exitCode = execution.outcome?.exitCode;
    // No exit status means git never ran: a fence, the repository check or
    // the timeout refused it, and only the error explains why.
    if (exitCode == null) {
      return _LocalCommandResult(
        exitCode: 1,
        stderr: 'git: ${execution.errorMessage ?? 'command did not run'}\n',
      );
    }
    final payload = jsonDecode(execution.result) as Map<String, dynamic>;
    return _LocalCommandResult(
      exitCode: exitCode,
      stdout: payload['stdout'] as String? ?? '',
      stderr: payload['stderr'] as String? ?? '',
    );
  }

  static List<String> _splitArgs(String command) {
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

  static Future<_LocalCommandResult> _executeCat(
    List<String> args,
    String workingDirectory,
  ) async {
    if (args.isEmpty) {
      return const _LocalCommandResult(
        exitCode: 1,
        stderr: 'cat: missing file operand\n',
      );
    }

    final stdoutBuffer = StringBuffer();
    for (final pathArg in args) {
      if (pathArg.startsWith('-')) {
        return _LocalCommandResult(
          exitCode: 1,
          stderr: 'cat: unsupported option $pathArg\n',
        );
      }

      final resolvedPath = FilesystemTools.resolvePath(
        pathArg,
        defaultRoot: workingDirectory,
      );
      if (resolvedPath == null) {
        return _LocalCommandResult(
          exitCode: 1,
          stderr: 'cat: cannot resolve path $pathArg\n',
        );
      }

      try {
        final entityType = await FileSystemEntity.type(resolvedPath);
        if (entityType != FileSystemEntityType.file) {
          return _LocalCommandResult(
            exitCode: 1,
            stderr: 'cat: $pathArg: Not a file\n',
          );
        }

        final content = await File(resolvedPath).readAsString();
        stdoutBuffer.write(content);
        if (!content.endsWith('\n')) {
          stdoutBuffer.write('\n');
        }
      } on FileSystemException catch (error) {
        return _LocalCommandResult(
          exitCode: 1,
          stderr: 'cat: $pathArg: ${error.osError?.message ?? error.message}\n',
        );
      } on FormatException {
        return _LocalCommandResult(
          exitCode: 1,
          stderr: 'cat: $pathArg: Binary files are not supported\n',
        );
      }
    }

    return _LocalCommandResult(exitCode: 0, stdout: stdoutBuffer.toString());
  }

  static Future<_LocalCommandResult> _executeLs(
    List<String> args,
    String workingDirectory,
  ) async {
    var recursive = false;
    var includeHidden = false;
    final targets = <String>[];

    for (final arg in args) {
      if (arg.startsWith('-')) {
        for (final rune in arg.substring(1).runes) {
          final flag = String.fromCharCode(rune);
          switch (flag) {
            case 'R':
              recursive = true;
            case 'a':
              includeHidden = true;
            case 'l':
            case 'h':
            case '1':
            case 'F':
              // Accepted for compatibility. Output remains simplified.
              break;
            default:
              return _LocalCommandResult(
                exitCode: 1,
                stderr: 'ls: unsupported option -$flag\n',
              );
          }
        }
      } else {
        targets.add(arg);
      }
    }

    final effectiveTargets = targets.isEmpty ? ['.'] : targets;
    final stdoutBuffer = StringBuffer();

    for (var index = 0; index < effectiveTargets.length; index++) {
      final target = effectiveTargets[index];
      final resolvedPath = FilesystemTools.resolvePath(
        target,
        defaultRoot: workingDirectory,
      );
      if (resolvedPath == null) {
        return _LocalCommandResult(
          exitCode: 1,
          stderr: 'ls: cannot resolve path $target\n',
        );
      }

      final entityType = await FileSystemEntity.type(resolvedPath);
      if (entityType == FileSystemEntityType.notFound) {
        return _LocalCommandResult(
          exitCode: 1,
          stderr: 'ls: $target: No such file or directory\n',
        );
      }

      if (index > 0) {
        stdoutBuffer.write('\n');
      }

      try {
        if (entityType == FileSystemEntityType.file) {
          stdoutBuffer.writeln(path.basename(resolvedPath));
          continue;
        }

        final listing = await _renderDirectoryListing(
          Directory(resolvedPath),
          recursive: recursive,
          includeHidden: includeHidden,
        );
        stdoutBuffer.write(listing);
        if (!listing.endsWith('\n')) {
          stdoutBuffer.write('\n');
        }
      } on FileSystemException catch (error) {
        return _LocalCommandResult(
          exitCode: 1,
          stderr: 'ls: $target: ${error.osError?.message ?? error.message}\n',
        );
      }
    }

    return _LocalCommandResult(exitCode: 0, stdout: stdoutBuffer.toString());
  }

  static Future<String> _renderDirectoryListing(
    Directory directory, {
    required bool recursive,
    required bool includeHidden,
  }) async {
    final sections = <String>[];
    await _appendDirectorySection(
      directory,
      rootPath: directory.absolute.path,
      sections: sections,
      recursive: recursive,
      includeHidden: includeHidden,
    );
    return sections.join('\n');
  }

  static Future<void> _appendDirectorySection(
    Directory directory, {
    required String rootPath,
    required List<String> sections,
    required bool recursive,
    required bool includeHidden,
  }) async {
    final entries = <FileSystemEntity>[];
    await for (final entity in directory.list(followLinks: false)) {
      final name = path.basename(entity.path);
      if (!includeHidden && name.startsWith('.')) {
        continue;
      }
      entries.add(entity);
    }
    entries.sort((a, b) => a.path.compareTo(b.path));

    final relativePath = directory.absolute.path == rootPath
        ? '.'
        : _relativePath(directory.absolute.path, rootPath);

    final buffer = StringBuffer()..writeln('$relativePath:');
    if (entries.isEmpty) {
      buffer.writeln();
    } else {
      for (final entry in entries) {
        final name = path.basename(entry.path);
        final type = await FileSystemEntity.type(entry.path);
        buffer.writeln(
          type == FileSystemEntityType.directory ? '$name/' : name,
        );
      }
    }
    sections.add(buffer.toString().trimRight());

    if (!recursive) {
      return;
    }

    for (final entry in entries) {
      final type = await FileSystemEntity.type(entry.path);
      if (type == FileSystemEntityType.directory) {
        await _appendDirectorySection(
          Directory(entry.path),
          rootPath: rootPath,
          sections: sections,
          recursive: true,
          includeHidden: includeHidden,
        );
      }
    }
  }

  static Future<_LocalCommandResult> _executeHead(
    List<String> args,
    String workingDirectory,
  ) async {
    final parsed = _parseHeadTailArgs(args, 'head');
    if (parsed.error != null) {
      return _LocalCommandResult(exitCode: 1, stderr: parsed.error!);
    }
    return _readFileSlices(
      filePaths: parsed.filePaths,
      workingDirectory: workingDirectory,
      lineCount: parsed.lineCount,
      fromStart: true,
      commandName: 'head',
    );
  }

  static Future<_LocalCommandResult> _executeTail(
    List<String> args,
    String workingDirectory,
  ) async {
    final parsed = _parseHeadTailArgs(args, 'tail');
    if (parsed.error != null) {
      return _LocalCommandResult(exitCode: 1, stderr: parsed.error!);
    }
    return _readFileSlices(
      filePaths: parsed.filePaths,
      workingDirectory: workingDirectory,
      lineCount: parsed.lineCount,
      fromStart: false,
      commandName: 'tail',
    );
  }

  static _ParsedHeadTailArgs _parseHeadTailArgs(
    List<String> args,
    String commandName,
  ) {
    var lineCount = 10;
    final filePaths = <String>[];

    for (var index = 0; index < args.length; index++) {
      final arg = args[index];
      if (arg == '-n') {
        if (index + 1 >= args.length) {
          return _ParsedHeadTailArgs(
            lineCount: lineCount,
            filePaths: filePaths,
            error: '$commandName: option requires an argument -- n\n',
          );
        }
        final parsed = int.tryParse(args[index + 1]);
        if (parsed == null || parsed < 0) {
          return _ParsedHeadTailArgs(
            lineCount: lineCount,
            filePaths: filePaths,
            error:
                '$commandName: invalid number of lines: ${args[index + 1]}\n',
          );
        }
        lineCount = parsed;
        index += 1;
        continue;
      }
      if (arg.startsWith('-n')) {
        final parsed = int.tryParse(arg.substring(2));
        if (parsed == null || parsed < 0) {
          return _ParsedHeadTailArgs(
            lineCount: lineCount,
            filePaths: filePaths,
            error: '$commandName: invalid number of lines: $arg\n',
          );
        }
        lineCount = parsed;
        continue;
      }
      if (arg.startsWith('-')) {
        return _ParsedHeadTailArgs(
          lineCount: lineCount,
          filePaths: filePaths,
          error: '$commandName: unsupported option $arg\n',
        );
      }
      filePaths.add(arg);
    }

    if (filePaths.isEmpty) {
      return _ParsedHeadTailArgs(
        lineCount: lineCount,
        filePaths: filePaths,
        error: '$commandName: missing file operand\n',
      );
    }

    return _ParsedHeadTailArgs(lineCount: lineCount, filePaths: filePaths);
  }

  static Future<_LocalCommandResult> _readFileSlices({
    required List<String> filePaths,
    required String workingDirectory,
    required int lineCount,
    required bool fromStart,
    required String commandName,
  }) async {
    final stdout = StringBuffer();

    for (var index = 0; index < filePaths.length; index++) {
      final pathArg = filePaths[index];
      final resolvedPath = FilesystemTools.resolvePath(
        pathArg,
        defaultRoot: workingDirectory,
      );
      if (resolvedPath == null) {
        return _LocalCommandResult(
          exitCode: 1,
          stderr: '$commandName: cannot resolve path $pathArg\n',
        );
      }

      try {
        final file = File(resolvedPath);
        if (!file.existsSync()) {
          return _LocalCommandResult(
            exitCode: 1,
            stderr: '$commandName: cannot open $pathArg\n',
          );
        }

        final content = await file.readAsString();
        final lines = const LineSplitter().convert(content);
        final slice = fromStart
            ? lines.take(lineCount).toList()
            : lines
                  .skip((lines.length - lineCount).clamp(0, lines.length))
                  .toList();

        if (filePaths.length > 1) {
          if (index > 0) stdout.writeln();
          stdout.writeln('==> $pathArg <==');
        }
        stdout.write(slice.join('\n'));
        if (slice.isNotEmpty && !slice.last.endsWith('\n')) {
          stdout.writeln();
        }
      } on FileSystemException catch (error) {
        return _LocalCommandResult(
          exitCode: 1,
          stderr:
              '$commandName: $pathArg: ${error.osError?.message ?? error.message}\n',
        );
      } on FormatException {
        return _LocalCommandResult(
          exitCode: 1,
          stderr: '$commandName: $pathArg: Binary files are not supported\n',
        );
      }
    }

    return _LocalCommandResult(exitCode: 0, stdout: stdout.toString());
  }

  static Future<_LocalCommandResult> _executeWc(
    List<String> args,
    String workingDirectory,
  ) async {
    var countLines = false;
    var countWords = false;
    var countBytes = false;
    final filePaths = <String>[];

    for (final arg in args) {
      if (arg.startsWith('-')) {
        for (final rune in arg.substring(1).runes) {
          final flag = String.fromCharCode(rune);
          switch (flag) {
            case 'l':
              countLines = true;
            case 'w':
              countWords = true;
            case 'c':
              countBytes = true;
            default:
              return _LocalCommandResult(
                exitCode: 1,
                stderr: 'wc: unsupported option -$flag\n',
              );
          }
        }
      } else {
        filePaths.add(arg);
      }
    }

    if (!countLines && !countWords && !countBytes) {
      countLines = true;
      countWords = true;
      countBytes = true;
    }

    if (filePaths.isEmpty) {
      return const _LocalCommandResult(
        exitCode: 1,
        stderr: 'wc: missing file operand\n',
      );
    }

    final output = StringBuffer();
    var totalLines = 0;
    var totalWords = 0;
    var totalBytes = 0;

    for (final pathArg in filePaths) {
      final counts = await _countFile(
        pathArg,
        workingDirectory: workingDirectory,
      );
      if (counts.error != null) {
        return _LocalCommandResult(exitCode: 1, stderr: counts.error!);
      }

      totalLines += counts.lines;
      totalWords += counts.words;
      totalBytes += counts.bytes;
      output.writeln(
        '${_formatWcCounts(countLines, countWords, countBytes, counts.lines, counts.words, counts.bytes)} $pathArg',
      );
    }

    if (filePaths.length > 1) {
      output.writeln(
        '${_formatWcCounts(countLines, countWords, countBytes, totalLines, totalWords, totalBytes)} total',
      );
    }

    return _LocalCommandResult(exitCode: 0, stdout: output.toString());
  }

  static String _formatWcCounts(
    bool countLines,
    bool countWords,
    bool countBytes,
    int lines,
    int words,
    int bytes,
  ) {
    final values = <String>[];
    if (countLines) values.add(lines.toString().padLeft(8));
    if (countWords) values.add(words.toString().padLeft(8));
    if (countBytes) values.add(bytes.toString().padLeft(8));
    return values.join('');
  }

  static Future<_FileCounts> _countFile(
    String pathArg, {
    required String workingDirectory,
  }) async {
    final resolvedPath = FilesystemTools.resolvePath(
      pathArg,
      defaultRoot: workingDirectory,
    );
    if (resolvedPath == null) {
      return _FileCounts(error: 'wc: cannot resolve path $pathArg\n');
    }

    try {
      final file = File(resolvedPath);
      final bytes = await file.readAsBytes();
      final content = utf8.decode(bytes);
      final lines = const LineSplitter().convert(content).length;
      final words = RegExp(r'\S+').allMatches(content).length;
      return _FileCounts(lines: lines, words: words, bytes: bytes.length);
    } on FileSystemException catch (error) {
      return _FileCounts(
        error: 'wc: $pathArg: ${error.osError?.message ?? error.message}\n',
      );
    } on FormatException {
      return _FileCounts(
        error: 'wc: $pathArg: Binary files are not supported\n',
      );
    }
  }

  static Future<_LocalCommandResult> _executeFind(
    List<String> args,
    String workingDirectory,
  ) async {
    var rootPathArg = '.';
    var index = 0;
    if (args.isNotEmpty && !args.first.startsWith('-')) {
      rootPathArg = args.first;
      index = 1;
    }

    var maxDepth = -1;
    String? namePattern;
    FileSystemEntityType? requiredType;

    while (index < args.length) {
      final arg = args[index];
      switch (arg) {
        case '-maxdepth':
          if (index + 1 >= args.length) {
            return const _LocalCommandResult(
              exitCode: 1,
              stderr: 'find: missing argument to -maxdepth\n',
            );
          }
          maxDepth = int.tryParse(args[index + 1]) ?? -2;
          if (maxDepth < 0) {
            return _LocalCommandResult(
              exitCode: 1,
              stderr: 'find: invalid maxdepth ${args[index + 1]}\n',
            );
          }
          index += 2;
          continue;
        case '-name':
          if (index + 1 >= args.length) {
            return const _LocalCommandResult(
              exitCode: 1,
              stderr: 'find: missing argument to -name\n',
            );
          }
          namePattern = args[index + 1];
          index += 2;
          continue;
        case '-type':
          if (index + 1 >= args.length) {
            return const _LocalCommandResult(
              exitCode: 1,
              stderr: 'find: missing argument to -type\n',
            );
          }
          requiredType = switch (args[index + 1]) {
            'f' => FileSystemEntityType.file,
            'd' => FileSystemEntityType.directory,
            _ => null,
          };
          if (requiredType == null) {
            return _LocalCommandResult(
              exitCode: 1,
              stderr: 'find: unsupported type ${args[index + 1]}\n',
            );
          }
          index += 2;
          continue;
        default:
          return _LocalCommandResult(
            exitCode: 1,
            stderr: 'find: unsupported expression $arg\n',
          );
      }
    }

    final rootPath = FilesystemTools.resolvePath(
      rootPathArg,
      defaultRoot: workingDirectory,
    );
    if (rootPath == null) {
      return _LocalCommandResult(
        exitCode: 1,
        stderr: 'find: cannot resolve path $rootPathArg\n',
      );
    }

    final rootType = await FileSystemEntity.type(rootPath);
    if (rootType == FileSystemEntityType.notFound) {
      return _LocalCommandResult(
        exitCode: 1,
        stderr: 'find: $rootPathArg: No such file or directory\n',
      );
    }

    final matcher = namePattern == null ? null : _wildcardToRegExp(namePattern);
    final matches = <String>[];
    await _collectFindMatches(
      rootPath: rootPath,
      currentPath: rootPath,
      maxDepth: maxDepth,
      currentDepth: 0,
      requiredType: requiredType,
      matcher: matcher,
      matches: matches,
    );

    return _LocalCommandResult(
      exitCode: 0,
      stdout: matches.isEmpty ? '' : '${matches.join('\n')}\n',
    );
  }

  static Future<void> _collectFindMatches({
    required String rootPath,
    required String currentPath,
    required int maxDepth,
    required int currentDepth,
    required FileSystemEntityType? requiredType,
    required RegExp? matcher,
    required List<String> matches,
  }) async {
    final type = await FileSystemEntity.type(currentPath);
    final relativePath = _relativePath(currentPath, rootPath);
    final displayPath = relativePath == '.' ? '.' : './$relativePath';
    final name = currentPath.split(Platform.pathSeparator).last;

    final typeMatches =
        requiredType == null ||
        type == requiredType ||
        (requiredType == FileSystemEntityType.directory && relativePath == '.');
    final nameMatches = matcher == null || matcher.hasMatch(name);
    if (typeMatches && nameMatches) {
      matches.add(displayPath);
    }

    if (type != FileSystemEntityType.directory) return;
    if (maxDepth >= 0 && currentDepth >= maxDepth) return;

    await for (final entity in Directory(
      currentPath,
    ).list(followLinks: false)) {
      await _collectFindMatches(
        rootPath: rootPath,
        currentPath: entity.path,
        maxDepth: maxDepth,
        currentDepth: currentDepth + 1,
        requiredType: requiredType,
        matcher: matcher,
        matches: matches,
      );
    }
  }

  static Future<_LocalCommandResult> _executeRg(
    List<String> args,
    String workingDirectory,
  ) async {
    var ignoreCase = false;
    var filesOnly = false;
    var filePattern = '*';
    final positional = <String>[];

    for (var index = 0; index < args.length; index++) {
      final arg = args[index];
      switch (arg) {
        case '-i':
          ignoreCase = true;
        case '-n':
        case '-S':
          break;
        case '--files':
          filesOnly = true;
        case '-g':
          if (index + 1 >= args.length) {
            return const _LocalCommandResult(
              exitCode: 1,
              stderr: 'rg: missing argument to -g\n',
            );
          }
          filePattern = args[index + 1];
          index += 1;
        default:
          if (arg.startsWith('-')) {
            return _LocalCommandResult(
              exitCode: 1,
              stderr: 'rg: unsupported option $arg\n',
            );
          }
          positional.add(arg);
      }
    }

    if (filesOnly) {
      final searchRootArg = positional.isEmpty ? '.' : positional.first;
      final searchRoot = FilesystemTools.resolvePath(
        searchRootArg,
        defaultRoot: workingDirectory,
      );
      if (searchRoot == null) {
        return _LocalCommandResult(
          exitCode: 1,
          stderr: 'rg: cannot resolve path $searchRootArg\n',
        );
      }
      final result =
          jsonDecode(
                await FilesystemTools.findFiles(
                  path: searchRoot,
                  pattern: filePattern,
                  recursive: true,
                ),
              )
              as Map<String, dynamic>;
      if (result['error'] != null) {
        return _LocalCommandResult(
          exitCode: 1,
          stderr: 'rg: ${result['error']}\n',
        );
      }
      final matches = (result['matches'] as List<dynamic>).cast<String>();
      return _LocalCommandResult(
        exitCode: 0,
        stdout: matches.isEmpty ? '' : '${matches.join('\n')}\n',
      );
    }

    if (positional.isEmpty) {
      return const _LocalCommandResult(
        exitCode: 1,
        stderr: 'rg: missing search pattern\n',
      );
    }

    final pattern = positional.first;
    final searchRootArg = positional.length > 1 ? positional[1] : '.';
    final searchRoot = FilesystemTools.resolvePath(
      searchRootArg,
      defaultRoot: workingDirectory,
    );
    if (searchRoot == null) {
      return _LocalCommandResult(
        exitCode: 1,
        stderr: 'rg: cannot resolve path $searchRootArg\n',
      );
    }

    final matcher = RegExp(
      pattern,
      caseSensitive: !ignoreCase,
      multiLine: true,
    );
    final fileMatcher = _wildcardToRegExp(filePattern);
    final matches = <String>[];

    await for (final entity in Directory(
      searchRoot,
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relativePath = _relativePath(entity.path, searchRoot);
      final fileName = entity.uri.pathSegments.last;
      if (!fileMatcher.hasMatch(relativePath) &&
          !fileMatcher.hasMatch(fileName)) {
        continue;
      }
      try {
        final content = await entity.readAsString();
        final lines = const LineSplitter().convert(content);
        for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
          if (matcher.hasMatch(lines[lineIndex])) {
            matches.add('$relativePath:${lineIndex + 1}:${lines[lineIndex]}');
          }
        }
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      }
    }

    return _LocalCommandResult(
      exitCode: matches.isEmpty ? 1 : 0,
      stdout: matches.isEmpty ? '' : '${matches.join('\n')}\n',
    );
  }

  static Future<_LocalCommandResult> _executeGrep(
    List<String> args,
    String workingDirectory,
  ) async {
    final grep = LocalShellGrep.parse(args);
    if (grep == null) {
      return const _LocalCommandResult(
        exitCode: 2,
        stderr: 'grep: unsupported invocation\n',
      );
    }
    final result = await grep.execute(
      workingDirectory: workingDirectory,
      outputLimit: _maxOutputChars,
    );
    return _LocalCommandResult(
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
    );
  }

  static RegExp _wildcardToRegExp(String pattern) {
    final buffer = StringBuffer('^');
    for (final rune in pattern.runes) {
      final char = String.fromCharCode(rune);
      if (char == '*') {
        buffer.write('.*');
      } else if (char == '?') {
        buffer.write('.');
      } else {
        buffer.write(RegExp.escape(char));
      }
    }
    buffer.write(r'$');
    return RegExp(buffer.toString(), caseSensitive: false);
  }

  static String _relativePath(String candidatePath, String basePath) {
    final absoluteCandidate = File(candidatePath).absolute.path;
    final absoluteBase = Directory(basePath).absolute.path;
    if (absoluteCandidate == absoluteBase) {
      return '.';
    }

    final prefix = absoluteBase.endsWith(Platform.pathSeparator)
        ? absoluteBase
        : '$absoluteBase${Platform.pathSeparator}';
    if (!absoluteCandidate.startsWith(prefix)) {
      return absoluteCandidate;
    }

    return absoluteCandidate.substring(prefix.length);
  }
}

class _DirectGitWriteCommand {
  const _DirectGitWriteCommand({
    required this.gitCommand,
    required this.gitSubcommand,
  });

  final String gitCommand;
  final String gitSubcommand;
}

class _LocalCommandResult {
  const _LocalCommandResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

class _ParsedHeadTailArgs {
  const _ParsedHeadTailArgs({
    required this.lineCount,
    required this.filePaths,
    this.error,
  });

  final int lineCount;
  final List<String> filePaths;
  final String? error;
}

class _FileCounts {
  const _FileCounts({
    this.lines = 0,
    this.words = 0,
    this.bytes = 0,
    this.error,
  });

  final int lines;
  final int words;
  final int bytes;
  final String? error;
}

/// One command of a chain [LocalShellTools] runs without a shell.
final class _InternalStep {
  const _InternalStep({
    required this.command,
    required this.lineLimit,
    required this.continuesAfterFailure,
  });

  /// The command with any trailing `| head -N` / `| tail -N` removed.
  final String command;
  final GitOutputLineLimit? lineLimit;

  /// Whether the step runs after an earlier failure: true for the first step
  /// and for one that follows `;`, false after `&&` or a newline.
  final bool continuesAfterFailure;
}
