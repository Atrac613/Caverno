import 'dart:convert';

import '../entities/tool_call_info.dart';
import 'coding_command_preflight_issue_detector.dart';

class CodingCommandOutputIssue {
  const CodingCommandOutputIssue({
    required this.toolName,
    required this.command,
    required this.workingDirectory,
    required this.exitCode,
    required this.source,
    required this.summary,
    required this.excerpt,
  });

  final String toolName;
  final String command;
  final String workingDirectory;
  final int exitCode;
  final String source;
  final String summary;
  final String excerpt;

  String get signature {
    return jsonEncode({
      'tool_name': toolName,
      'command': command,
      'working_directory': workingDirectory,
      'source': source,
      'summary': summary,
      'excerpt': excerpt,
    });
  }

  Map<String, dynamic> toJson() {
    return {
      'tool_name': toolName,
      'command': command,
      'working_directory': workingDirectory,
      'exit_code': exitCode,
      'source': source,
      'summary': summary,
      'excerpt': excerpt,
    };
  }
}

/// Detects failure evidence in decoded command results.
class CodingCommandOutputIssueDetector {
  const CodingCommandOutputIssueDetector({
    CodingCommandPreflightIssueDetector preflightDetector =
        const CodingCommandPreflightIssueDetector(),
  }) : _preflightDetector = preflightDetector;

  final CodingCommandPreflightIssueDetector _preflightDetector;

  static final RegExp _markdownErrorHeadingPattern = RegExp(
    r'^\s*#{1,6}\s+error\b',
    caseSensitive: false,
  );
  static final RegExp _tracebackPattern = RegExp(
    r'traceback\s+\(most recent call last\)',
    caseSensitive: false,
  );
  static final RegExp _runtimeFailurePattern = RegExp(
    r'\b(?:uncaught exception|unhandled exception|fatal exception|assertionerror:)\b',
    caseSensitive: false,
  );
  static final String _cjkErrorLabel = String.fromCharCodes([
    0x30a8,
    0x30e9,
    0x30fc,
  ]);
  static final String _cjkDataMissing = String.fromCharCodes([
    0x30c7,
    0x30fc,
    0x30bf,
    0x304c,
    0x898b,
    0x3064,
    0x304b,
    0x308a,
    0x307e,
    0x305b,
    0x3093,
  ]);

  CodingCommandOutputIssue? detect(ToolResultInfo toolResult) {
    final decoded = _tryDecodeMap(toolResult.result);
    if (decoded == null) {
      return null;
    }
    return detectFromDecodedCommandResult(
      toolName: toolResult.name,
      decoded: decoded,
      fallbackCommand: _normalizeText(toolResult.arguments['command']),
      fallbackWorkingDirectory: _normalizeText(
        toolResult.arguments['working_directory'],
      ),
    );
  }

  CodingCommandOutputIssue? detectFromDecodedCommandResult({
    required String toolName,
    required Map<String, dynamic> decoded,
    String? fallbackCommand,
    String? fallbackWorkingDirectory,
  }) {
    if (!_isCommandTool(toolName)) {
      return null;
    }
    final exitCode = _parseExitCode(decoded['exit_code']);
    if (exitCode != 0) {
      return null;
    }

    final command = _normalizeText(decoded['command']) ?? fallbackCommand ?? '';
    final workingDirectory =
        _normalizeText(decoded['working_directory']) ??
        fallbackWorkingDirectory ??
        '';
    final preflightIssue =
        _preflightDetector.detect(
          toolName: toolName,
          command: command,
          workingDirectory: workingDirectory,
        ) ??
        _preflightDetector.detectMaskedExitStatusIssue(
          command: command,
          workingDirectory: workingDirectory,
        );
    if (preflightIssue != null) {
      return CodingCommandOutputIssue(
        toolName: toolName,
        command: command,
        workingDirectory: workingDirectory,
        exitCode: exitCode!,
        source: 'command',
        summary: preflightIssue.summary,
        excerpt: preflightIssue.segment,
      );
    }
    for (final entry in const {
      'stdout': 'stdout',
      'stderr': 'stderr',
    }.entries) {
      final output = _normalizeText(decoded[entry.key]);
      if (output == null) {
        continue;
      }
      final signal = _detectOutputSignal(output);
      if (signal == null) {
        continue;
      }
      return CodingCommandOutputIssue(
        toolName: toolName,
        command: command,
        workingDirectory: workingDirectory,
        exitCode: exitCode!,
        source: entry.value,
        summary: signal.summary,
        excerpt: _excerpt(output, signal.startIndex),
      );
    }
    return null;
  }

  String? feedbackSignature(
    ToolResultInfo feedback, {
    required String feedbackToolName,
  }) {
    if (feedback.name != feedbackToolName) {
      return null;
    }
    final decoded = _tryDecodeMap(feedback.result);
    final issues = decoded?['issues'];
    if (issues is! List || issues.isEmpty) {
      return null;
    }
    return jsonEncode({
      'provider': decoded?['provider'],
      'validation_status': decoded?['validation_status'],
      'issues': issues,
    });
  }

  bool commandResultReportsOutputIssue(String rawResult) {
    final decoded = _tryDecodeMap(rawResult);
    if (decoded == null) {
      return false;
    }
    return detectFromDecodedCommandResult(
          toolName: 'local_execute_command',
          decoded: decoded,
        ) !=
        null;
  }

  _OutputSignal? _detectOutputSignal(String output) {
    final lines = output.split(RegExp(r'\r?\n'));
    var offset = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        if (_markdownErrorHeadingPattern.hasMatch(trimmed) ||
            _isCjkErrorHeading(trimmed)) {
          return _OutputSignal(
            summary: 'Output contains a Markdown error heading.',
            startIndex: offset,
          );
        }

        final normalized = trimmed.toLowerCase();
        if (normalized.contains('no data found') ||
            normalized.contains('data not found') ||
            normalized.contains('could not find data') ||
            normalized.contains('required data was not found') ||
            trimmed.contains(_cjkDataMissing)) {
          return _OutputSignal(
            summary: 'Output reports that required data was not found.',
            startIndex: offset,
          );
        }
        if (_tracebackPattern.hasMatch(trimmed) ||
            _runtimeFailurePattern.hasMatch(trimmed)) {
          return _OutputSignal(
            summary: 'Output contains a runtime failure signal.',
            startIndex: offset,
          );
        }
      }
      offset += line.length + 1;
    }
    return null;
  }

  bool _isCjkErrorHeading(String line) {
    final withoutHashes = line.replaceFirst(RegExp(r'^\s*#{1,6}\s*'), '');
    return withoutHashes.trim() == _cjkErrorLabel;
  }

  bool _isCommandTool(String toolName) {
    return switch (toolName.trim().toLowerCase()) {
      'local_execute_command' ||
      'run_tests' ||
      'git_execute_command' ||
      'ssh_execute_command' => true,
      _ => false,
    };
  }

  int? _parseExitCode(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  Map<String, dynamic>? _tryDecodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _normalizeText(dynamic value) {
    if (value == null) {
      return null;
    }
    final normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  String _excerpt(String output, int startIndex) {
    final clampedStart = startIndex.clamp(0, output.length).toInt();
    final excerpt = output.substring(clampedStart);
    if (excerpt.length <= 600) {
      return excerpt.trim();
    }
    return '${excerpt.substring(0, 597).trimRight()}...';
  }
}

class _OutputSignal {
  const _OutputSignal({required this.summary, required this.startIndex});

  final String summary;
  final int startIndex;
}
