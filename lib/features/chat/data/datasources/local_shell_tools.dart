import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'filesystem_tools.dart';
import 'git_tools.dart';

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

  static bool isReadOnly(String command) {
    final trimmed = normalizeCommand(command);
    if (trimmed.isEmpty) return false;

    final chainedCommands = _splitConditionalCommands(trimmed);
    if (chainedCommands.length > 1) {
      return chainedCommands.every(_isSingleReadOnlyCommand);
    }

    return _isSingleReadOnlyCommand(trimmed);
  }

  static bool _isSingleReadOnlyCommand(String command) {
    final trimmed = normalizeCommand(command);
    if (trimmed.isEmpty) return false;
    if (_hasUnsafeShellSyntax(trimmed)) return false;

    final args = _splitArgs(trimmed);
    if (args.isEmpty) return false;

    final executable = args.first;
    return switch (executable) {
      'pwd' ||
      'echo' ||
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

    final normalizedCommand = normalizeCommand(command);
    if (normalizedCommand.isEmpty) {
      return jsonEncode({'error': 'Command is required'});
    }

    if (_canExecuteInternally(normalizedCommand)) {
      return _executeInternally(
        command: normalizedCommand,
        workingDirectory: directory.absolute.path,
      );
    }

    final shellExecutable = Platform.isWindows ? 'cmd' : 'sh';
    final shellArgs = Platform.isWindows
        ? ['/C', normalizedCommand]
        : ['-c', normalizedCommand];

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
        'command': normalizedCommand,
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
        'command': normalizedCommand,
        'working_directory': directory.absolute.path,
        'error': 'Command timed out after ${_timeout.inSeconds} seconds.',
      });
    } catch (e) {
      return jsonEncode({
        'command': normalizedCommand,
        'working_directory': directory.absolute.path,
        'error': e.toString(),
      });
    }
  }

  static bool _hasUnsafeShellSyntax(String command) {
    const blockedTokens = ['|', '||', ';', '>', '<', '`', r'$(', '\n'];
    return blockedTokens.any(command.contains);
  }

  static bool _canExecuteInternally(String command) {
    final segments = _splitConditionalCommands(command);
    if (segments.isEmpty) return false;
    return segments.every(_canExecuteSingleCommandInternally);
  }

  static bool _canExecuteSingleCommandInternally(String command) {
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
      _ => false,
    };
  }

  static List<String> _splitConditionalCommands(String command) {
    final segments = <String>[];
    final buffer = StringBuffer();
    String? quoteChar;

    for (var i = 0; i < command.length; i++) {
      final char = command[i];

      if (quoteChar != null) {
        if (char == quoteChar) {
          quoteChar = null;
        } else {
          buffer.write(char);
        }
        continue;
      }

      if (char == '"' || char == "'") {
        quoteChar = char;
        continue;
      }

      if (char == '&' && i + 1 < command.length && command[i + 1] == '&') {
        final segment = buffer.toString().trim();
        if (segment.isNotEmpty) {
          segments.add(segment);
        }
        buffer.clear();
        i += 1;
        continue;
      }

      buffer.write(char);
    }

    final trailing = buffer.toString().trim();
    if (trailing.isNotEmpty) {
      segments.add(trailing);
    }

    return segments;
  }

  static Future<String> _executeInternally({
    required String command,
    required String workingDirectory,
  }) async {
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    var exitCode = 0;

    for (final segment in _splitConditionalCommands(command)) {
      final result = await _executeInternalSegment(
        segment,
        workingDirectory: workingDirectory,
      );

      if (result.stdout.isNotEmpty) {
        stdoutBuffer.write(result.stdout);
      }
      if (result.stderr.isNotEmpty) {
        stderrBuffer.write(result.stderr);
      }

      exitCode = result.exitCode;
      if (exitCode != 0) {
        break;
      }
    }

    final stdout = stdoutBuffer.toString();
    final stderr = stderrBuffer.toString();
    final stdoutTruncated = stdout.length > _maxOutputChars;
    final stderrTruncated = stderr.length > _maxOutputChars;

    return jsonEncode({
      'command': command,
      'working_directory': workingDirectory,
      'exit_code': exitCode,
      'stdout': stdoutTruncated ? stdout.substring(0, _maxOutputChars) : stdout,
      'stderr': stderrTruncated ? stderr.substring(0, _maxOutputChars) : stderr,
      'executed_internally': true,
      if (stdoutTruncated) 'stdout_truncated': true,
      if (stderrTruncated) 'stderr_truncated': true,
    });
  }

  static Future<_LocalCommandResult> _executeInternalSegment(
    String command, {
    required String workingDirectory,
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
      _ => _LocalCommandResult(
        exitCode: 1,
        stderr: 'Unsupported internal command: ${args.first}\n',
      ),
    };
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
          stdoutBuffer.writeln(File(resolvedPath).uri.pathSegments.last);
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
      final name = entity.uri.pathSegments.isEmpty
          ? entity.path
          : entity.uri.pathSegments.last;
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
        final name = entry.uri.pathSegments.isEmpty
            ? entry.path
            : entry.uri.pathSegments.last;
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

  static bool _isSedReadOnly(List<String> args) {
    if (!args.contains('-n')) return false;
    for (final arg in args.skip(1)) {
      if (arg == '-i' || arg.startsWith('-i')) {
        return false;
      }
    }
    return true;
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
    final matches = <String>[];

    await for (final entity in Directory(
      searchRoot,
    ).list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relativePath = _relativePath(entity.path, searchRoot);
      final fileName = entity.uri.pathSegments.last;
      if (!_wildcardToRegExp(filePattern).hasMatch(relativePath) &&
          !_wildcardToRegExp(filePattern).hasMatch(fileName)) {
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
