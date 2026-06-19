import 'dart:io';

import 'coding_diagnostic_feedback_service.dart';
import 'dart_project_tooling.dart';
import 'language_diagnostics_bridge.dart';

abstract interface class LspDiagnosticClient {
  String get providerName;

  bool get supportsDocumentSymbols;

  bool get supportsGoToDefinition;

  Future<List<LspDiagnostic>?> collectDiagnostics({
    required String projectRoot,
    required Iterable<String> changedPaths,
  });
}

abstract interface class LspServerReadinessProbe {
  Future<LspServerReadiness> ensureReady({
    required String projectRoot,
    required Iterable<String> changedPaths,
  });
}

class LspServerReadiness {
  const LspServerReadiness({
    required this.ok,
    required this.status,
    this.languageId,
    this.code,
    this.error,
    this.metadata,
  });

  final bool ok;
  final String status;
  final String? languageId;
  final String? code;
  final String? error;
  final Map<String, dynamic>? metadata;
}

class LspDiagnostic {
  const LspDiagnostic({
    required this.uri,
    required this.startLine,
    required this.startCharacter,
    required this.message,
    this.severity,
    this.code,
    this.source,
  });

  final String uri;
  final int startLine;
  final int startCharacter;
  final String message;
  final int? severity;
  final Object? code;
  final String? source;
}

class LspDocumentSymbol {
  const LspDocumentSymbol({
    required this.uri,
    required this.name,
    required this.kind,
    required this.kindLabel,
    required this.startLine,
    required this.startCharacter,
    this.detail,
    this.containerName,
    this.children = const [],
  });

  final String uri;
  final String name;
  final int kind;
  final String kindLabel;
  final int startLine;
  final int startCharacter;
  final String? detail;
  final String? containerName;
  final List<LspDocumentSymbol> children;

  List<LspDocumentSymbol> flatten() {
    return [this, for (final child in children) ...child.flatten()];
  }
}

class LspDefinitionLocation {
  const LspDefinitionLocation({
    required this.uri,
    required this.startLine,
    required this.startCharacter,
    this.endLine,
    this.endCharacter,
  });

  final String uri;
  final int startLine;
  final int startCharacter;
  final int? endLine;
  final int? endCharacter;
}

class LspDiagnosticFeedbackProvider
    implements CodingDiagnosticFeedbackProvider {
  const LspDiagnosticFeedbackProvider({
    required this.client,
    this.readinessProbe,
  });

  final LspDiagnosticClient client;
  final LspServerReadinessProbe? readinessProbe;

  @override
  String get providerName => client.providerName;

  @override
  Future<CodingDiagnosticSnapshot?> collectSnapshot({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) async {
    final root = Directory(projectRoot).absolute.path;
    final changedFiles = _changedFiles(
      projectRoot: root,
      changedPaths: changedPaths,
    );
    if (changedFiles.isEmpty) {
      return null;
    }

    final readiness = await readinessProbe?.ensureReady(
      projectRoot: root,
      changedPaths: changedFiles.map((file) => file.absolutePath),
    );
    if (readiness != null && !readiness.ok) {
      return null;
    }

    final stopwatch = Stopwatch()..start();
    final diagnostics = await client.collectDiagnostics(
      projectRoot: root,
      changedPaths: changedFiles.map((file) => file.absolutePath),
    );
    stopwatch.stop();
    if (diagnostics == null) {
      return null;
    }

    final changedFileKeys = changedFiles
        .map((file) => DartProjectPath.pathKey(file.absolutePath))
        .toSet();
    final mappedDiagnostics =
        diagnostics
            .map(
              (diagnostic) => _toCodeDiagnostic(diagnostic, projectRoot: root),
            )
            .whereType<CodeDiagnostic>()
            .where(
              (diagnostic) => changedFileKeys.contains(
                DartProjectPath.pathKey(diagnostic.absolutePath),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) {
            final severity = a.severityRank.compareTo(b.severityRank);
            if (severity != 0) return severity;
            final file = a.relativePath(root).compareTo(b.relativePath(root));
            if (file != 0) return file;
            final line = a.line.compareTo(b.line);
            if (line != 0) return line;
            return a.column.compareTo(b.column);
          });

    return CodingDiagnosticSnapshot(
      providerName: providerName,
      projectRoot: root,
      changedPaths: changedFiles
          .map((file) => file.relativePath)
          .toList(growable: false),
      diagnostics: mappedDiagnostics,
      telemetry: CodingDiagnosticTelemetry(
        durationMs: stopwatch.elapsedMilliseconds,
        attempts: const [],
      ),
      bridge: LanguageDiagnosticsBridgeMetadata(
        providerName: providerName,
        protocol: 'lsp',
        status: 'ready',
        capabilities: LanguageDiagnosticsBridgeCapabilities(
          diagnostics: true,
          documentSymbols: client.supportsDocumentSymbols,
          goToDefinition: client.supportsGoToDefinition,
        ),
      ),
    );
  }

  List<_ChangedFile> _changedFiles({
    required String projectRoot,
    required Iterable<String> changedPaths,
  }) {
    final seen = <String>{};
    final files = <_ChangedFile>[];
    for (final rawPath in changedPaths) {
      final absolutePath = DartProjectPath.resolvePath(
        rawPath,
        projectRoot: projectRoot,
      );
      if (absolutePath == null ||
          !DartProjectPath.isInsideRoot(absolutePath, projectRoot) ||
          !File(absolutePath).existsSync()) {
        continue;
      }
      if (!seen.add(DartProjectPath.pathKey(absolutePath))) {
        continue;
      }
      files.add(
        _ChangedFile(
          absolutePath: absolutePath,
          relativePath: DartProjectPath.relativePath(absolutePath, projectRoot),
        ),
      );
    }
    files.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return files;
  }

  CodeDiagnostic? _toCodeDiagnostic(
    LspDiagnostic diagnostic, {
    required String projectRoot,
  }) {
    final absolutePath = _pathFromUri(diagnostic.uri);
    if (absolutePath == null ||
        !DartProjectPath.isInsideRoot(absolutePath, projectRoot)) {
      return null;
    }
    final message = diagnostic.message.trim();
    if (message.isEmpty) {
      return null;
    }
    return CodeDiagnostic(
      absolutePath: absolutePath,
      severity: _severityLabel(diagnostic.severity),
      line: diagnostic.startLine + 1 < 1 ? 1 : diagnostic.startLine + 1,
      column: diagnostic.startCharacter + 1 < 1
          ? 1
          : diagnostic.startCharacter + 1,
      message: message,
      code: _codeLabel(diagnostic.code),
      source: diagnostic.source?.trim().isEmpty ?? true
          ? null
          : diagnostic.source!.trim(),
    );
  }

  String? _pathFromUri(String uri) {
    final trimmed = uri.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final parsed = Uri.parse(trimmed);
      if (parsed.scheme == 'file') {
        return File.fromUri(parsed).absolute.path;
      }
    } on FormatException {
      return null;
    }
    if (DartProjectPath.isAbsolutePath(trimmed)) {
      return File(trimmed).absolute.path;
    }
    return null;
  }

  String _severityLabel(int? severity) {
    return switch (severity) {
      1 => 'Error',
      2 => 'Warning',
      3 => 'Info',
      4 => 'Hint',
      _ => 'Info',
    };
  }

  String? _codeLabel(Object? code) {
    if (code == null) {
      return null;
    }
    final value = code.toString().trim();
    return value.isEmpty ? null : value;
  }
}

class _ChangedFile {
  const _ChangedFile({required this.absolutePath, required this.relativePath});

  final String absolutePath;
  final String relativePath;
}
