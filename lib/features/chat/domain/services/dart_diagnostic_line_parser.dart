import 'coding_diagnostic_feedback_service.dart' show CodeDiagnostic;
import 'dart_project_tooling.dart';

/// Turns one line of Dart or Flutter tool output into a [CodeDiagnostic].
///
/// Lifted out of `DartAnalyzerDiagnosticFeedbackProvider`, which owned these
/// three syntaxes privately and only ever applied them to output it had run
/// itself, filtered to files it had just watched change. The syntaxes are not
/// specific to that: any command that surfaces analyzer or test output prints
/// them. Keeping the per-line reading here lets a caller that has output but no
/// changed-file set use it, while the provider keeps its own filtering,
/// deduplication and ordering.
///
/// Returns null for a line that is not a diagnostic, which is most of them —
/// callers are expected to walk every line and keep what parses.
final class DartDiagnosticLineParser {
  const DartDiagnosticLineParser();

  /// The first syntax that matches wins: machine, then human, then Flutter.
  CodeDiagnostic? parse(String line, {required String pathBase}) {
    return _parseMachineDiagnosticLine(line, pathBase: pathBase) ??
        _parseHumanDiagnosticLine(line, pathBase: pathBase) ??
        _parseFlutterDiagnosticLine(line, pathBase: pathBase);
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
}
