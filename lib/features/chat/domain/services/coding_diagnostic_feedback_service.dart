import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../entities/tool_call_info.dart';

typedef CodingDiagnosticCommandRunner =
    Future<CodingDiagnosticCommandOutput> Function(
      CodingDiagnosticCommand command,
      Duration timeout,
    );

class CodingDiagnosticCommand {
  const CodingDiagnosticCommand({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
}

class CodingDiagnosticCommandOutput {
  const CodingDiagnosticCommandOutput({
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

class CodingDiagnosticFeedbackService {
  CodingDiagnosticFeedbackService({
    CodingDiagnosticCommandRunner? commandRunner,
    this.timeout = const Duration(seconds: 20),
    this.maxDiagnosticsPerFile = 10,
    this.maxTotalDiagnostics = 30,
  }) : _commandRunner = commandRunner ?? _runAnalyzeCommand;

  static const toolName = 'dart_analyze_feedback';
  static const schemaName = 'caverno_dart_analyze_feedback';

  static final RegExp _windowsDriveLetterPath = RegExp(r'^[A-Za-z]:[\\/]');

  final CodingDiagnosticCommandRunner _commandRunner;
  final Duration timeout;
  final int maxDiagnosticsPerFile;
  final int maxTotalDiagnostics;

  Future<ToolResultInfo?> buildFeedbackToolResult({
    required String projectRoot,
    required Iterable<String> changedPaths,
    DateTime? now,
  }) async {
    if (!isDesktopPlatform) {
      return null;
    }

    final root = Directory(projectRoot).absolute.path;
    final changedDartFiles = _changedDartFiles(
      projectRoot: root,
      changedPaths: changedPaths,
    );
    if (changedDartFiles.isEmpty) {
      return null;
    }

    for (final command in _buildAnalyzeCommands(root, changedDartFiles)) {
      final output = await _commandRunner(command, timeout);
      final diagnostics = _parseDiagnostics(
        '${output.stdout}\n${output.stderr}',
        projectRoot: root,
        pathBase: command.workingDirectory,
        changedFiles: changedDartFiles,
      );
      if (diagnostics.isEmpty) {
        if (output.ran && output.exitCode == 0) {
          return null;
        }
        continue;
      }

      final limitedDiagnostics = _limitDiagnostics(diagnostics);
      final payload = {
        'schema': schemaName,
        'instruction':
            'These analyzer diagnostics were detected after the latest Dart file edits. Fix relevant errors or warnings before claiming the coding task is complete.',
        'project_root': root,
        'changed_paths': changedDartFiles
            .map((file) => file.relativePath)
            .toList(growable: false),
        'analyzer': {
          'executable': command.executable,
          'arguments': command.arguments,
          'working_directory': command.workingDirectory,
          'exit_code': output.exitCode,
        },
        'diagnostic_count': limitedDiagnostics.length,
        'diagnostics': limitedDiagnostics
            .map((diagnostic) => diagnostic.toJson(projectRoot: root))
            .toList(growable: false),
        if (limitedDiagnostics.length < diagnostics.length)
          'truncated_diagnostic_count':
              diagnostics.length - limitedDiagnostics.length,
      };

      return ToolResultInfo(
        id: '${toolName}_${(now ?? DateTime.now()).microsecondsSinceEpoch}',
        name: toolName,
        arguments: {
          'project_root': root,
          'changed_paths': changedDartFiles
              .map((file) => file.relativePath)
              .toList(growable: false),
        },
        result: jsonEncode(payload),
      );
    }

    return null;
  }

  static bool get isDesktopPlatform =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  List<CodingDiagnosticCommand> _buildAnalyzeCommands(
    String projectRoot,
    List<_ChangedDartFile> changedDartFiles,
  ) {
    final analysisRoot = _analysisRootForFiles(projectRoot, changedDartFiles);
    final analysisRelativePaths = changedDartFiles
        .map((file) => _relativePath(file.absolutePath, analysisRoot))
        .toList(growable: false);
    final analyzeArgs = [
      'analyze',
      '--format=machine',
      ...analysisRelativePaths,
    ];
    final fvmAnalyzeArgs = ['dart', ...analyzeArgs];
    final flutterAnalyzeArgs = [
      'analyze',
      '--no-pub',
      '--no-congratulate',
      ...analysisRelativePaths,
    ];
    final fvmFlutterAnalyzeArgs = ['flutter', ...flutterAnalyzeArgs];
    final hasFvmMetadata =
        File('$analysisRoot/.fvm/fvm_config.json').existsSync() ||
        File('$analysisRoot/.fvmrc').existsSync() ||
        File('$projectRoot/.fvm/fvm_config.json').existsSync() ||
        File('$projectRoot/.fvmrc').existsSync();

    final commands = <CodingDiagnosticCommand>[];
    if (hasFvmMetadata) {
      commands.add(
        CodingDiagnosticCommand(
          executable: 'fvm',
          arguments: fvmAnalyzeArgs,
          workingDirectory: analysisRoot,
        ),
      );
    }
    commands.add(
      CodingDiagnosticCommand(
        executable: 'dart',
        arguments: analyzeArgs,
        workingDirectory: analysisRoot,
      ),
    );
    if (hasFvmMetadata) {
      commands.add(
        CodingDiagnosticCommand(
          executable: 'fvm',
          arguments: fvmFlutterAnalyzeArgs,
          workingDirectory: analysisRoot,
        ),
      );
    }
    commands.add(
      CodingDiagnosticCommand(
        executable: 'flutter',
        arguments: flutterAnalyzeArgs,
        workingDirectory: analysisRoot,
      ),
    );
    if (!hasFvmMetadata) {
      commands.add(
        CodingDiagnosticCommand(
          executable: 'fvm',
          arguments: fvmAnalyzeArgs,
          workingDirectory: analysisRoot,
        ),
      );
      commands.add(
        CodingDiagnosticCommand(
          executable: 'fvm',
          arguments: fvmFlutterAnalyzeArgs,
          workingDirectory: analysisRoot,
        ),
      );
    }
    return commands;
  }

  String _analysisRootForFiles(
    String projectRoot,
    List<_ChangedDartFile> changedDartFiles,
  ) {
    final roots = changedDartFiles
        .map((file) => _nearestPackageRoot(file.absolutePath, projectRoot))
        .toSet();
    return roots.length == 1 ? roots.single : projectRoot;
  }

  String _nearestPackageRoot(String filePath, String projectRoot) {
    var directory = File(filePath).parent.absolute;
    final root = Directory(projectRoot).absolute;
    while (_isInsideRoot(directory.path, root.path)) {
      if (File.fromUri(directory.uri.resolve('pubspec.yaml')).existsSync()) {
        return directory.path;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) {
        break;
      }
      directory = parent;
    }
    return root.path;
  }

  List<_ChangedDartFile> _changedDartFiles({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) {
    final seen = <String>{};
    final files = <_ChangedDartFile>[];
    for (final rawPath in changedPaths) {
      final absolutePath = _resolvePath(rawPath, projectRoot: projectRoot);
      if (absolutePath == null) {
        continue;
      }
      if (!_isInsideRoot(absolutePath, projectRoot)) {
        continue;
      }
      if (!absolutePath.toLowerCase().endsWith('.dart')) {
        continue;
      }
      if (!File(absolutePath).existsSync()) {
        continue;
      }
      if (!seen.add(_pathKey(absolutePath))) {
        continue;
      }
      files.add(
        _ChangedDartFile(
          absolutePath: absolutePath,
          relativePath: _relativePath(absolutePath, projectRoot),
        ),
      );
    }
    files.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return files;
  }

  List<_AnalyzerDiagnostic> _parseDiagnostics(
    String output, {
    required String projectRoot,
    required String pathBase,
    required List<_ChangedDartFile> changedFiles,
  }) {
    final changedPathKeys = changedFiles
        .map((file) => _pathKey(file.absolutePath))
        .toSet();
    final diagnostics = <_AnalyzerDiagnostic>[];
    final seen = <String>{};

    for (final line in const LineSplitter().convert(output)) {
      final diagnostic =
          _parseMachineDiagnosticLine(line, pathBase: pathBase) ??
          _parseHumanDiagnosticLine(line, pathBase: pathBase) ??
          _parseFlutterDiagnosticLine(line, pathBase: pathBase);
      if (diagnostic == null) {
        continue;
      }
      if (!changedPathKeys.contains(_pathKey(diagnostic.absolutePath))) {
        continue;
      }
      final key = diagnostic.dedupeKey;
      if (!seen.add(key)) {
        continue;
      }
      diagnostics.add(diagnostic);
    }

    diagnostics.sort((a, b) {
      final severity = a.severityRank.compareTo(b.severityRank);
      if (severity != 0) return severity;
      final file = a
          .relativePath(projectRoot)
          .compareTo(b.relativePath(projectRoot));
      if (file != 0) return file;
      final line = a.line.compareTo(b.line);
      if (line != 0) return line;
      return a.column.compareTo(b.column);
    });
    return diagnostics;
  }

  _AnalyzerDiagnostic? _parseMachineDiagnosticLine(
    String line, {
    required String pathBase,
  }) {
    final parts = line.split('|');
    if (parts.length < 8) {
      return null;
    }
    final severity = _normalizeSeverity(parts[0]);
    if (severity == null) {
      return null;
    }
    final absolutePath = _resolvePath(parts[3], projectRoot: pathBase);
    final lineNumber = int.tryParse(parts[4]);
    final column = int.tryParse(parts[5]);
    if (absolutePath == null || lineNumber == null || column == null) {
      return null;
    }

    return _AnalyzerDiagnostic(
      absolutePath: absolutePath,
      severity: severity,
      code: parts[2].trim().isEmpty ? null : parts[2].trim(),
      line: lineNumber,
      column: column,
      message: parts.sublist(7).join('|').trim(),
    );
  }

  _AnalyzerDiagnostic? _parseHumanDiagnosticLine(
    String line, {
    required String pathBase,
  }) {
    final match = RegExp(
      r'^\s*(error|warning|info|hint)\s+-\s+(.+?):(\d+):(\d+)\s+-\s+(.+?)(?:\s+-\s+([A-Za-z0-9_.-]+))?\s*$',
      caseSensitive: false,
    ).firstMatch(line);
    if (match == null) {
      return null;
    }
    final severity = _normalizeSeverity(match.group(1));
    final absolutePath = _resolvePath(match.group(2), projectRoot: pathBase);
    final lineNumber = int.tryParse(match.group(3) ?? '');
    final column = int.tryParse(match.group(4) ?? '');
    if (severity == null ||
        absolutePath == null ||
        lineNumber == null ||
        column == null) {
      return null;
    }
    return _AnalyzerDiagnostic(
      absolutePath: absolutePath,
      severity: severity,
      code: match.group(6)?.trim(),
      line: lineNumber,
      column: column,
      message: match.group(5)?.trim() ?? '',
    );
  }

  _AnalyzerDiagnostic? _parseFlutterDiagnosticLine(
    String line, {
    required String pathBase,
  }) {
    final bullet = String.fromCharCode(0x2022);
    if (!line.contains(bullet)) {
      return null;
    }
    final parts = line
        .split(bullet)
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length < 4) {
      return null;
    }
    final severity = _normalizeSeverity(parts[0]);
    final location = RegExp(r'^(.+):(\d+):(\d+)$').firstMatch(parts[2]);
    if (severity == null || location == null) {
      return null;
    }
    final absolutePath = _resolvePath(location.group(1), projectRoot: pathBase);
    final lineNumber = int.tryParse(location.group(2) ?? '');
    final column = int.tryParse(location.group(3) ?? '');
    if (absolutePath == null || lineNumber == null || column == null) {
      return null;
    }
    return _AnalyzerDiagnostic(
      absolutePath: absolutePath,
      severity: severity,
      code: parts[3].trim().isEmpty ? null : parts[3].trim(),
      line: lineNumber,
      column: column,
      message: parts[1],
    );
  }

  List<_AnalyzerDiagnostic> _limitDiagnostics(
    List<_AnalyzerDiagnostic> diagnostics,
  ) {
    final perFileCounts = <String, int>{};
    final limited = <_AnalyzerDiagnostic>[];
    for (final diagnostic in diagnostics) {
      if (limited.length >= maxTotalDiagnostics) {
        break;
      }
      final fileKey = _pathKey(diagnostic.absolutePath);
      final fileCount = perFileCounts[fileKey] ?? 0;
      if (fileCount >= maxDiagnosticsPerFile) {
        continue;
      }
      perFileCounts[fileKey] = fileCount + 1;
      limited.add(diagnostic);
    }
    return limited;
  }

  static String? _normalizeSeverity(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'error':
        return 'Error';
      case 'warning':
        return 'Warning';
      case 'info':
      case 'information':
        return 'Info';
      case 'hint':
        return 'Hint';
      default:
        return null;
    }
  }

  static int _severityRank(String severity) {
    return switch (severity) {
      'Error' => 1,
      'Warning' => 2,
      'Info' => 3,
      'Hint' => 4,
      _ => 5,
    };
  }

  static String? _resolvePath(String? rawPath, {required String projectRoot}) {
    final trimmed = rawPath?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    if (_isAbsolutePath(trimmed)) {
      return File(trimmed).absolute.path;
    }
    return File.fromUri(Directory(projectRoot).uri.resolve(trimmed)).path;
  }

  static bool _isAbsolutePath(String path) {
    return path.startsWith('/') ||
        path.startsWith(r'\\') ||
        _windowsDriveLetterPath.hasMatch(path);
  }

  static bool _isInsideRoot(String candidatePath, String projectRoot) {
    final rootKey = _pathKey(projectRoot);
    final candidateKey = _pathKey(candidatePath);
    final separator = Platform.pathSeparator;
    return candidateKey == rootKey ||
        candidateKey.startsWith('$rootKey$separator');
  }

  static String _relativePath(String absolutePath, String projectRoot) {
    final root = Directory(projectRoot).absolute.path;
    final path = File(absolutePath).absolute.path;
    if (path == root) {
      return '.';
    }
    final prefix = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    if (!path.startsWith(prefix)) {
      return path;
    }
    return path.substring(prefix.length);
  }

  static String _pathKey(String path) {
    final normalized = File(path).absolute.path;
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static Future<CodingDiagnosticCommandOutput> _runAnalyzeCommand(
    CodingDiagnosticCommand command,
    Duration timeout,
  ) async {
    Process? process;
    try {
      process = await Process.start(
        command.executable,
        command.arguments,
        workingDirectory: command.workingDirectory,
      );
      final stdout = process.stdout.transform(utf8.decoder).join();
      final stderr = process.stderr.transform(utf8.decoder).join();
      final exitCode = await process.exitCode.timeout(timeout);
      return CodingDiagnosticCommandOutput(
        exitCode: exitCode,
        stdout: await stdout,
        stderr: await stderr,
      );
    } on TimeoutException {
      process?.kill();
      return const CodingDiagnosticCommandOutput(exitCode: -1, timedOut: true);
    } on ProcessException catch (error) {
      return CodingDiagnosticCommandOutput(
        exitCode: -1,
        startError: error.message,
      );
    } catch (error) {
      return CodingDiagnosticCommandOutput(
        exitCode: -1,
        startError: error.toString(),
      );
    }
  }
}

class _ChangedDartFile {
  const _ChangedDartFile({
    required this.absolutePath,
    required this.relativePath,
  });

  final String absolutePath;
  final String relativePath;
}

class _AnalyzerDiagnostic {
  const _AnalyzerDiagnostic({
    required this.absolutePath,
    required this.severity,
    required this.line,
    required this.column,
    required this.message,
    this.code,
  });

  final String absolutePath;
  final String severity;
  final int line;
  final int column;
  final String message;
  final String? code;

  int get severityRank =>
      CodingDiagnosticFeedbackService._severityRank(severity);

  String get dedupeKey {
    return [
      CodingDiagnosticFeedbackService._pathKey(absolutePath),
      severity,
      line,
      column,
      code ?? '',
      message,
    ].join('|');
  }

  String relativePath(String projectRoot) {
    return CodingDiagnosticFeedbackService._relativePath(
      absolutePath,
      projectRoot,
    );
  }

  Map<String, dynamic> toJson({required String projectRoot}) {
    return {
      'path': absolutePath,
      'relative_path': relativePath(projectRoot),
      'severity': severity,
      'line': line,
      'column': column,
      if (code != null && code!.isNotEmpty) 'code': code,
      'message': message,
    };
  }
}
