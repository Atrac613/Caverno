import 'dart:convert';

import '../entities/tool_call_info.dart';

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

class CodingCommandPreflightIssue {
  const CodingCommandPreflightIssue({
    required this.code,
    required this.command,
    required this.workingDirectory,
    required this.segment,
    required this.summary,
    required this.instruction,
    required this.targets,
  });

  final String code;
  final String command;
  final String workingDirectory;
  final String segment;
  final String summary;
  final String instruction;
  final List<String> targets;

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'command': command,
      'working_directory': workingDirectory,
      'segment': segment,
      'summary': summary,
      'instruction': instruction,
      'targets': targets,
    };
  }
}

class CodingCommandOutputGuardrailService {
  const CodingCommandOutputGuardrailService();

  static const toolName = 'coding_output_feedback';
  static const schemaName = 'caverno_coding_output_feedback';
  static const providerName = 'command_output_guardrail';

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
  static const Set<String> _dartCreateOptionsWithValue = {
    '-t',
    '--template',
    '--sample',
    '--description',
    '--project-name',
  };

  ToolResultInfo? buildFeedbackToolResult({
    required List<ToolResultInfo> toolResults,
    DateTime? now,
  }) {
    if (toolResults.any((result) => result.name == toolName)) {
      return null;
    }

    final issues = <CodingCommandOutputIssue>[];
    for (final toolResult in toolResults) {
      final issue = detectIssue(toolResult);
      if (issue != null) {
        issues.add(issue);
      }
      if (issues.length >= 3) {
        break;
      }
    }
    if (issues.isEmpty) {
      return null;
    }

    final payload = {
      'schema': schemaName,
      'provider': providerName,
      'success': false,
      'validation_status': 'failed',
      'error':
          'A command exited with code 0, but its command shape or output '
          'reports a failed generated artifact or missing required data.',
      'instruction':
          'Treat the coding task as incomplete. Inspect and repair the script, generated file, or data lookup, then rerun the relevant command before claiming completion.',
      'issues': issues.map((issue) => issue.toJson()).toList(growable: false),
    };

    return ToolResultInfo(
      id: '${toolName}_${(now ?? DateTime.now()).microsecondsSinceEpoch}',
      name: toolName,
      arguments: {
        'issue_count': issues.length,
        'commands': issues
            .map((issue) => issue.command)
            .where((command) => command.isNotEmpty)
            .toList(growable: false),
      },
      result: jsonEncode(payload),
    );
  }

  static CodingCommandOutputIssue? detectIssue(ToolResultInfo toolResult) {
    final decoded = _tryDecodeMap(toolResult.result);
    if (decoded == null) {
      return null;
    }
    return detectIssueFromDecodedCommandResult(
      toolName: toolResult.name,
      decoded: decoded,
      fallbackCommand: _normalizeText(toolResult.arguments['command']),
      fallbackWorkingDirectory: _normalizeText(
        toolResult.arguments['working_directory'],
      ),
    );
  }

  static CodingCommandPreflightIssue? detectPreflightIssue({
    required String toolName,
    required String command,
    required String workingDirectory,
  }) {
    final normalizedToolName = toolName.trim().toLowerCase();
    if (normalizedToolName != 'local_execute_command' &&
        normalizedToolName != 'process_start') {
      return null;
    }
    final normalizedCommand = _normalizeText(command);
    if (normalizedCommand == null) {
      return null;
    }
    return _detectMalformedDartCreateCommand(
      command: normalizedCommand,
      workingDirectory: workingDirectory,
    );
  }

  static CodingCommandOutputIssue? detectIssueFromDecodedCommandResult({
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
    final preflightIssue = detectPreflightIssue(
      toolName: toolName,
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

  static String? feedbackSignature(ToolResultInfo feedback) {
    if (feedback.name != toolName) {
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

  static bool commandResultReportsOutputIssue(String rawResult) {
    final decoded = _tryDecodeMap(rawResult);
    if (decoded == null) {
      return false;
    }
    return detectIssueFromDecodedCommandResult(
          toolName: 'local_execute_command',
          decoded: decoded,
        ) !=
        null;
  }

  static _OutputSignal? _detectOutputSignal(String output) {
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

  static CodingCommandPreflightIssue? _detectMalformedDartCreateCommand({
    required String command,
    required String workingDirectory,
  }) {
    for (final segment in _splitShellSegments(command)) {
      final args = _splitArgs(segment);
      final createArgs = _dartCreateArgs(args);
      if (createArgs == null) {
        continue;
      }
      final targets = _dartCreateTargets(createArgs);
      if (targets.length <= 1) {
        continue;
      }
      return CodingCommandPreflightIssue(
        code: 'dart_create_multiple_targets',
        command: command,
        workingDirectory: workingDirectory,
        segment: segment,
        summary: 'Dart create command specifies multiple target directories.',
        instruction:
            'Run dart create with exactly one target directory. Use '
            '"dart create --force prime_numbers_pkg" from the parent '
            'directory, or create the directory first and run '
            '"dart create --force ." inside it.',
        targets: targets,
      );
    }
    return null;
  }

  static List<String>? _dartCreateArgs(List<String> args) {
    if (args.length >= 2 && args[0] == 'dart' && args[1] == 'create') {
      return args.skip(2).toList(growable: false);
    }
    if (args.length >= 3 &&
        args[0] == 'fvm' &&
        args[1] == 'dart' &&
        args[2] == 'create') {
      return args.skip(3).toList(growable: false);
    }
    return null;
  }

  static List<String> _dartCreateTargets(List<String> args) {
    final targets = <String>[];
    var consumeNextAsOptionValue = false;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (consumeNextAsOptionValue) {
        consumeNextAsOptionValue = false;
        continue;
      }
      if (arg == '--') {
        targets.addAll(
          args
              .skip(i + 1)
              .map((target) => target.trim())
              .where((target) => target.isNotEmpty),
        );
        break;
      }
      if (arg.startsWith('-')) {
        consumeNextAsOptionValue = _dartCreateOptionConsumesNext(arg);
        continue;
      }
      targets.add(arg);
    }
    return targets;
  }

  static bool _dartCreateOptionConsumesNext(String arg) {
    if (arg.contains('=')) {
      return false;
    }
    return _dartCreateOptionsWithValue.contains(arg);
  }

  static List<String> _splitShellSegments(String command) {
    final segments = <String>[];
    final buffer = StringBuffer();
    String? quoteChar;

    for (var i = 0; i < command.length; i++) {
      final char = command[i];

      if (quoteChar != null) {
        if (char == '\\' && i + 1 < command.length) {
          i += 1;
          buffer.write(command[i]);
          continue;
        }
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

      if (char == '\\' && i + 1 < command.length) {
        i += 1;
        buffer.write(command[i]);
        continue;
      }

      if (char == ';' || char == '\n') {
        final segment = buffer.toString().trim();
        if (segment.isNotEmpty) {
          segments.add(segment);
        }
        buffer.clear();
        continue;
      }

      if ((char == '&' || char == '|') &&
          i + 1 < command.length &&
          command[i + 1] == char) {
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

  static List<String> _splitArgs(String command) {
    final args = <String>[];
    final buffer = StringBuffer();
    String? quoteChar;

    for (var i = 0; i < command.length; i++) {
      final char = command[i];

      if (quoteChar != null) {
        if (char == '\\' && i + 1 < command.length) {
          i += 1;
          buffer.write(command[i]);
          continue;
        }
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

      if (char == '\\' && i + 1 < command.length) {
        i += 1;
        buffer.write(command[i]);
        continue;
      }

      if (char == ' ' || char == '\t') {
        if (buffer.isNotEmpty) {
          args.add(buffer.toString());
          buffer.clear();
        }
        continue;
      }

      buffer.write(char);
    }

    if (buffer.isNotEmpty) {
      args.add(buffer.toString());
    }
    return args;
  }

  static bool _isCjkErrorHeading(String line) {
    final withoutHashes = line.replaceFirst(RegExp(r'^\s*#{1,6}\s*'), '');
    return withoutHashes.trim() == _cjkErrorLabel;
  }

  static bool _isCommandTool(String toolName) {
    return switch (toolName.trim().toLowerCase()) {
      'local_execute_command' ||
      'run_tests' ||
      'git_execute_command' ||
      'ssh_execute_command' => true,
      _ => false,
    };
  }

  static int? _parseExitCode(dynamic value) {
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

  static Map<String, dynamic>? _tryDecodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static String? _normalizeText(dynamic value) {
    if (value == null) {
      return null;
    }
    final normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  static String _excerpt(String output, int startIndex) {
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
