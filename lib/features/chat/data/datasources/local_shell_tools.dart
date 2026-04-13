import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'filesystem_tools.dart';
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

    final chainedCommands = _splitConditionalCommands(trimmed);
    if (chainedCommands.length > 1) {
      return chainedCommands.every(_isSingleReadOnlyCommand);
    }

    return _isSingleReadOnlyCommand(trimmed);
  }

  static bool _isSingleReadOnlyCommand(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return false;
    if (_hasUnsafeShellSyntax(trimmed)) return false;

    final args = GitTools.splitArgs(trimmed);
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

    final trimmed = command.trim();
    if (_canExecuteInternally(trimmed)) {
      return _executeInternally(
        command: trimmed,
        workingDirectory: directory.absolute.path,
      );
    }

    final shellExecutable = Platform.isWindows ? 'cmd' : 'sh';
    final shellArgs = Platform.isWindows ? ['/C', command] : ['-c', command];

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
    const blockedTokens = ['|', '||', ';', '>', '<', '`', r'$(', '\n'];
    return blockedTokens.any(command.contains);
  }

  static bool _canExecuteInternally(String command) {
    final segments = _splitConditionalCommands(command);
    if (segments.isEmpty) return false;
    return segments.every(_canExecuteSingleCommandInternally);
  }

  static bool _canExecuteSingleCommandInternally(String command) {
    final args = GitTools.splitArgs(command.trim());
    if (args.isEmpty) return false;

    return switch (args.first) {
      'pwd' || 'echo' || 'cat' || 'ls' => true,
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
    final args = GitTools.splitArgs(command);
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
      _ => _LocalCommandResult(
        exitCode: 1,
        stderr: 'Unsupported internal command: ${args.first}\n',
      ),
    };
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
