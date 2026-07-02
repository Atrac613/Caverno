import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../entities/tool_call_info.dart';
import 'dart_project_tooling.dart';
import 'language_diagnostics_bridge.dart';

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

abstract interface class CodingDiagnosticFeedbackProvider {
  String get providerName;

  Future<CodingDiagnosticSnapshot?> collectSnapshot({
    required String projectRoot,
    required Iterable<String> changedPaths,
  });
}

class CodingDiagnosticSnapshot {
  const CodingDiagnosticSnapshot({
    required this.providerName,
    required this.projectRoot,
    required this.changedPaths,
    required this.diagnostics,
    required this.telemetry,
    required this.bridge,
    this.selectedAttempt,
  });

  final String providerName;
  final String projectRoot;
  final List<String> changedPaths;
  final List<CodeDiagnostic> diagnostics;
  final CodingDiagnosticTelemetry telemetry;
  final LanguageDiagnosticsBridgeMetadata bridge;
  final CodingDiagnosticCommandAttempt? selectedAttempt;

  CodingDiagnosticSnapshot withBridge(LanguageDiagnosticsBridgeMetadata value) {
    return CodingDiagnosticSnapshot(
      providerName: providerName,
      projectRoot: projectRoot,
      changedPaths: changedPaths,
      diagnostics: diagnostics,
      telemetry: telemetry,
      bridge: value,
      selectedAttempt: selectedAttempt,
    );
  }
}

class CodingDiagnosticFeedbackBaseline {
  const CodingDiagnosticFeedbackBaseline({
    required this.providerName,
    required this.projectRoot,
    required this.changedPaths,
    required this.diagnostics,
    required this.telemetry,
  });

  factory CodingDiagnosticFeedbackBaseline.fromSnapshot(
    CodingDiagnosticSnapshot snapshot,
  ) {
    return CodingDiagnosticFeedbackBaseline(
      providerName: snapshot.providerName,
      projectRoot: snapshot.projectRoot,
      changedPaths: snapshot.changedPaths,
      diagnostics: snapshot.diagnostics,
      telemetry: snapshot.telemetry,
    );
  }

  final String providerName;
  final String projectRoot;
  final List<String> changedPaths;
  final List<CodeDiagnostic> diagnostics;
  final CodingDiagnosticTelemetry telemetry;
}

class CodeDiagnostic {
  const CodeDiagnostic({
    required this.absolutePath,
    required this.severity,
    required this.line,
    required this.column,
    required this.message,
    this.code,
    this.source,
  });

  final String absolutePath;
  final String severity;
  final int line;
  final int column;
  final String message;
  final String? code;
  final String? source;

  int get severityRank => _severityRank(severity);

  String get dedupeKey {
    return [
      DartProjectPath.pathKey(absolutePath),
      severity,
      line,
      column,
      code ?? '',
      source ?? '',
      message,
    ].join('|');
  }

  String relativePath(String projectRoot) {
    return DartProjectPath.relativePath(absolutePath, projectRoot);
  }

  Map<String, dynamic> toJson({required String projectRoot}) {
    return {
      'path': absolutePath,
      'relative_path': relativePath(projectRoot),
      'severity': severity,
      'line': line,
      'column': column,
      if (code != null && code!.isNotEmpty) 'code': code,
      if (source != null && source!.isNotEmpty) 'source': source,
      'message': message,
    };
  }
}

class CodingDiagnosticTelemetry {
  const CodingDiagnosticTelemetry({
    required this.durationMs,
    required this.attempts,
  });

  final int durationMs;
  final List<CodingDiagnosticCommandAttempt> attempts;

  int get commandAttemptCount => attempts.length;

  int get fallbackCommandCount =>
      commandAttemptCount == 0 ? 0 : commandAttemptCount - 1;

  int get timedOutCommandCount =>
      attempts.where((attempt) => attempt.timedOut).length;

  int get startErrorCommandCount =>
      attempts.where((attempt) => attempt.startError != null).length;

  Map<String, dynamic> toJson() {
    return {
      'duration_ms': durationMs,
      'command_attempt_count': commandAttemptCount,
      'fallback_command_count': fallbackCommandCount,
      'timed_out_command_count': timedOutCommandCount,
      'start_error_command_count': startErrorCommandCount,
      'attempts': attempts.map((attempt) => attempt.toJson()).toList(),
    };
  }
}

class CodingDiagnosticCommandAttempt {
  const CodingDiagnosticCommandAttempt({
    required this.command,
    required this.exitCode,
    required this.durationMs,
    required this.timedOut,
    required this.diagnosticCount,
    this.startError,
  });

  final CodingDiagnosticCommand command;
  final int exitCode;
  final int durationMs;
  final bool timedOut;
  final int diagnosticCount;
  final String? startError;

  Map<String, dynamic> toJson() {
    return {
      'executable': command.executable,
      'arguments': command.arguments,
      'working_directory': command.workingDirectory,
      'exit_code': exitCode,
      'duration_ms': durationMs,
      'timed_out': timedOut,
      'diagnostic_count': diagnosticCount,
      if (startError != null) 'start_error': startError,
    };
  }
}

class CodingDiagnosticFeedbackService {
  CodingDiagnosticFeedbackService({
    CodingDiagnosticCommandRunner? commandRunner,
    CodingDiagnosticFeedbackProvider? provider,
    this.timeout = const Duration(seconds: 20),
    this.maxDiagnosticsPerFile = 10,
    this.maxTotalDiagnostics = 30,
  }) : _provider =
           provider ??
           DartAnalyzerDiagnosticFeedbackProvider(
             commandRunner: commandRunner,
             timeout: timeout,
           );

  static const toolName = 'dart_analyze_feedback';
  static const schemaName = 'caverno_dart_analyze_feedback';

  final CodingDiagnosticFeedbackProvider _provider;
  final Duration timeout;
  final int maxDiagnosticsPerFile;
  final int maxTotalDiagnostics;

  String get providerName => _provider.providerName;

  Future<CodingDiagnosticFeedbackBaseline?> captureBaseline({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    if (!isDesktopPlatform) {
      return null;
    }

    final snapshot = await _provider.collectSnapshot(
      projectRoot: projectRoot,
      changedPaths: changedPaths,
    );
    if (snapshot == null) {
      return null;
    }
    return CodingDiagnosticFeedbackBaseline.fromSnapshot(snapshot);
  }

  Future<ToolResultInfo?> buildFeedbackToolResult({
    required String projectRoot,
    required Iterable<String> changedPaths,
    CodingDiagnosticFeedbackBaseline? baseline,
    DateTime? now,
  }) async {
    if (!isDesktopPlatform) {
      return null;
    }

    final snapshot = await _provider.collectSnapshot(
      projectRoot: projectRoot,
      changedPaths: changedPaths,
    );
    if (snapshot == null || snapshot.diagnostics.isEmpty) {
      return null;
    }

    final newDiagnostics = _newDiagnostics(snapshot, baseline);
    if (newDiagnostics.isEmpty) {
      return null;
    }

    final limitedDiagnostics = _limitDiagnostics(newDiagnostics);
    final selectedAttempt = snapshot.selectedAttempt;
    final payload = {
      'schema': schemaName,
      'provider': snapshot.providerName,
      'instruction':
          'These new code diagnostics were detected after the latest file edits. Fix relevant errors or warnings before claiming the coding task is complete.',
      'project_root': snapshot.projectRoot,
      'changed_paths': snapshot.changedPaths,
      'baseline_applied': baseline != null,
      'baseline_diagnostic_count': baseline?.diagnostics.length ?? 0,
      'current_diagnostic_count': snapshot.diagnostics.length,
      'existing_diagnostic_count': baseline == null
          ? 0
          : snapshot.diagnostics.length - newDiagnostics.length,
      'diagnostic_count': limitedDiagnostics.length,
      'new_diagnostic_count': limitedDiagnostics.length,
      'language_diagnostics_bridge': snapshot.bridge.toJson(),
      'telemetry': snapshot.telemetry.toJson(),
      if (selectedAttempt != null)
        'analyzer': {
          'executable': selectedAttempt.command.executable,
          'arguments': selectedAttempt.command.arguments,
          'working_directory': selectedAttempt.command.workingDirectory,
          'exit_code': selectedAttempt.exitCode,
          'duration_ms': selectedAttempt.durationMs,
          'timed_out': selectedAttempt.timedOut,
        },
      'diagnostics': limitedDiagnostics
          .map(
            (diagnostic) =>
                diagnostic.toJson(projectRoot: snapshot.projectRoot),
          )
          .toList(growable: false),
      if (limitedDiagnostics.length < newDiagnostics.length)
        'truncated_diagnostic_count':
            newDiagnostics.length - limitedDiagnostics.length,
    };

    return ToolResultInfo(
      id: '${toolName}_${(now ?? DateTime.now()).microsecondsSinceEpoch}',
      name: toolName,
      arguments: {
        'project_root': snapshot.projectRoot,
        'changed_paths': snapshot.changedPaths,
      },
      result: jsonEncode(payload),
    );
  }

  static bool get isDesktopPlatform =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  List<CodeDiagnostic> _newDiagnostics(
    CodingDiagnosticSnapshot snapshot,
    CodingDiagnosticFeedbackBaseline? baseline,
  ) {
    if (baseline == null ||
        baseline.providerName != snapshot.providerName ||
        DartProjectPath.pathKey(baseline.projectRoot) !=
            DartProjectPath.pathKey(snapshot.projectRoot)) {
      return snapshot.diagnostics;
    }

    final baselineKeys = baseline.diagnostics
        .map((diagnostic) => diagnostic.dedupeKey)
        .toSet();
    return snapshot.diagnostics
        .where((diagnostic) => !baselineKeys.contains(diagnostic.dedupeKey))
        .toList(growable: false);
  }

  List<CodeDiagnostic> _limitDiagnostics(List<CodeDiagnostic> diagnostics) {
    final perFileCounts = <String, int>{};
    final limited = <CodeDiagnostic>[];
    for (final diagnostic in diagnostics) {
      if (limited.length >= maxTotalDiagnostics) {
        break;
      }
      final fileKey = DartProjectPath.pathKey(diagnostic.absolutePath);
      final fileCount = perFileCounts[fileKey] ?? 0;
      if (fileCount >= maxDiagnosticsPerFile) {
        continue;
      }
      perFileCounts[fileKey] = fileCount + 1;
      limited.add(diagnostic);
    }
    return limited;
  }
}

class LanguageDiagnosticsBridgeFallbackProvider
    implements CodingDiagnosticFeedbackProvider {
  const LanguageDiagnosticsBridgeFallbackProvider({
    required this.primary,
    required this.fallback,
  });

  final CodingDiagnosticFeedbackProvider primary;
  final CodingDiagnosticFeedbackProvider fallback;

  @override
  String get providerName => primary.providerName;

  @override
  Future<CodingDiagnosticSnapshot?> collectSnapshot({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    try {
      final primarySnapshot = await primary.collectSnapshot(
        projectRoot: projectRoot,
        changedPaths: changedPaths,
      );
      if (primarySnapshot != null) {
        if (primarySnapshot.diagnostics.isNotEmpty) {
          return primarySnapshot;
        }
        return await _collectFallback(
              projectRoot: projectRoot,
              changedPaths: changedPaths,
              reason: 'primary_empty',
            ) ??
            primarySnapshot;
      }
      return _collectFallback(
        projectRoot: projectRoot,
        changedPaths: changedPaths,
        reason: 'primary_unavailable',
      );
    } catch (_) {
      return _collectFallback(
        projectRoot: projectRoot,
        changedPaths: changedPaths,
        reason: 'primary_failed',
      );
    }
  }

  Future<CodingDiagnosticSnapshot?> _collectFallback({
    required String projectRoot,
    required Iterable<String> changedPaths,
    required String reason,
  }) async {
    final fallbackSnapshot = await fallback.collectSnapshot(
      projectRoot: projectRoot,
      changedPaths: changedPaths,
    );
    if (fallbackSnapshot == null) {
      return null;
    }
    return fallbackSnapshot.withBridge(
      fallbackSnapshot.bridge.degradedFrom(
        attemptedProviderName: primary.providerName,
        reason: reason,
      ),
    );
  }
}

class DartAnalyzerDiagnosticFeedbackProvider
    implements CodingDiagnosticFeedbackProvider {
  DartAnalyzerDiagnosticFeedbackProvider({
    CodingDiagnosticCommandRunner? commandRunner,
    this.timeout = const Duration(seconds: 20),
  }) : _commandRunner = commandRunner ?? _runAnalyzeCommand;

  @override
  String get providerName => 'dart_analyzer';

  final CodingDiagnosticCommandRunner _commandRunner;
  final Duration timeout;

  @override
  Future<CodingDiagnosticSnapshot?> collectSnapshot({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    final root = Directory(projectRoot).absolute.path;
    final changedDartFiles = DartProjectTooling.changedDartFiles(
      projectRoot: root,
      changedPaths: changedPaths,
    );
    if (changedDartFiles.isEmpty) {
      return null;
    }

    final stopwatch = Stopwatch()..start();
    final attempts = <CodingDiagnosticCommandAttempt>[];
    for (final command in _buildAnalyzeCommands(root, changedDartFiles)) {
      final attemptStopwatch = Stopwatch()..start();
      final output = await _commandRunner(command, timeout);
      attemptStopwatch.stop();

      final diagnostics = _parseDiagnostics(
        '${output.stdout}\n${output.stderr}',
        projectRoot: root,
        pathBase: command.workingDirectory,
        changedFiles: changedDartFiles,
      );
      final attempt = CodingDiagnosticCommandAttempt(
        command: command,
        exitCode: output.exitCode,
        durationMs: attemptStopwatch.elapsedMilliseconds,
        timedOut: output.timedOut,
        startError: output.startError,
        diagnosticCount: diagnostics.length,
      );
      attempts.add(attempt);

      if (diagnostics.isEmpty) {
        if (output.ran && output.exitCode == 0) {
          stopwatch.stop();
          return _snapshot(
            projectRoot: root,
            changedDartFiles: changedDartFiles,
            diagnostics: const [],
            attempts: attempts,
            durationMs: stopwatch.elapsedMilliseconds,
            selectedAttempt: attempt,
          );
        }
        continue;
      }

      stopwatch.stop();
      return _snapshot(
        projectRoot: root,
        changedDartFiles: changedDartFiles,
        diagnostics: diagnostics,
        attempts: attempts,
        durationMs: stopwatch.elapsedMilliseconds,
        selectedAttempt: attempt,
      );
    }

    stopwatch.stop();
    return null;
  }

  CodingDiagnosticSnapshot _snapshot({
    required String projectRoot,
    required List<DartChangedFile> changedDartFiles,
    required List<CodeDiagnostic> diagnostics,
    required List<CodingDiagnosticCommandAttempt> attempts,
    required int durationMs,
    required CodingDiagnosticCommandAttempt selectedAttempt,
  }) {
    return CodingDiagnosticSnapshot(
      providerName: providerName,
      projectRoot: projectRoot,
      changedPaths: changedDartFiles
          .map((file) => file.relativePath)
          .toList(growable: false),
      diagnostics: diagnostics,
      telemetry: CodingDiagnosticTelemetry(
        durationMs: durationMs,
        attempts: List<CodingDiagnosticCommandAttempt>.unmodifiable(attempts),
      ),
      bridge: LanguageDiagnosticsBridgeMetadata.dartAnalyzerCli(),
      selectedAttempt: selectedAttempt,
    );
  }

  List<CodingDiagnosticCommand> _buildAnalyzeCommands(
    String projectRoot,
    List<DartChangedFile> changedDartFiles,
  ) {
    final analysisRoot = _analysisRootForFiles(projectRoot, changedDartFiles);
    final analysisRelativePaths = changedDartFiles
        .map(
          (file) =>
              DartProjectPath.relativePath(file.absolutePath, analysisRoot),
        )
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
    final hasFvmMetadata = DartProjectTooling.hasFvmMetadata(
      packageRoot: analysisRoot,
      projectRoot: projectRoot,
    );

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
    List<DartChangedFile> changedDartFiles,
  ) {
    return DartProjectTooling.rootForFiles(projectRoot, changedDartFiles);
  }

  List<CodeDiagnostic> _parseDiagnostics(
    String output, {
    required String projectRoot,
    required String pathBase,
    required List<DartChangedFile> changedFiles,
  }) {
    final changedPathKeys = changedFiles
        .map((file) => DartProjectPath.pathKey(file.absolutePath))
        .toSet();
    final diagnostics = <CodeDiagnostic>[];
    final seen = <String>{};

    for (final line in const LineSplitter().convert(output)) {
      final diagnostic =
          _parseMachineDiagnosticLine(line, pathBase: pathBase) ??
          _parseHumanDiagnosticLine(line, pathBase: pathBase) ??
          _parseFlutterDiagnosticLine(line, pathBase: pathBase);
      if (diagnostic == null) {
        continue;
      }
      if (!changedPathKeys.contains(
        DartProjectPath.pathKey(diagnostic.absolutePath),
      )) {
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

  CodeDiagnostic? _parseMachineDiagnosticLine(
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
    final absolutePath = DartProjectPath.resolvePath(
      parts[3],
      projectRoot: pathBase,
    );
    final lineNumber = int.tryParse(parts[4]);
    final column = int.tryParse(parts[5]);
    if (absolutePath == null || lineNumber == null || column == null) {
      return null;
    }

    return CodeDiagnostic(
      absolutePath: absolutePath,
      severity: severity,
      source: parts[1].trim().isEmpty ? null : parts[1].trim(),
      code: parts[2].trim().isEmpty ? null : parts[2].trim(),
      line: lineNumber,
      column: column,
      message: parts.sublist(7).join('|').trim(),
    );
  }

  CodeDiagnostic? _parseHumanDiagnosticLine(
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
    final absolutePath = DartProjectPath.resolvePath(
      match.group(2),
      projectRoot: pathBase,
    );
    final lineNumber = int.tryParse(match.group(3) ?? '');
    final column = int.tryParse(match.group(4) ?? '');
    if (severity == null ||
        absolutePath == null ||
        lineNumber == null ||
        column == null) {
      return null;
    }
    return CodeDiagnostic(
      absolutePath: absolutePath,
      severity: severity,
      code: match.group(6)?.trim(),
      line: lineNumber,
      column: column,
      message: match.group(5)?.trim() ?? '',
    );
  }

  CodeDiagnostic? _parseFlutterDiagnosticLine(
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
    final absolutePath = DartProjectPath.resolvePath(
      location.group(1),
      projectRoot: pathBase,
    );
    final lineNumber = int.tryParse(location.group(2) ?? '');
    final column = int.tryParse(location.group(3) ?? '');
    if (absolutePath == null || lineNumber == null || column == null) {
      return null;
    }
    return CodeDiagnostic(
      absolutePath: absolutePath,
      severity: severity,
      code: parts[3].trim().isEmpty ? null : parts[3].trim(),
      line: lineNumber,
      column: column,
      message: parts[1],
    );
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

int _severityRank(String severity) {
  return switch (severity) {
    'Error' => 1,
    'Warning' => 2,
    'Info' => 3,
    'Hint' => 4,
    _ => 5,
  };
}
