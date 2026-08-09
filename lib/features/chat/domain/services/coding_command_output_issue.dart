import 'dart:convert';

import 'tool_outcome_shadow_comparison.dart';

class CodingCommandOutputIssue {
  const CodingCommandOutputIssue({
    required this.toolName,
    required this.command,
    required this.workingDirectory,
    required this.exitCode,
    required this.exitCodeSource,
    required this.source,
    required this.summary,
    required this.excerpt,
  });

  final String toolName;
  final String command;
  final String workingDirectory;
  final int exitCode;
  final ToolOutcomeVerdictSource exitCodeSource;
  final String source;
  final String summary;
  final String excerpt;

  String get signature => jsonEncode({
    'tool_name': toolName,
    'command': command,
    'working_directory': workingDirectory,
    'source': source,
    'summary': summary,
    'excerpt': excerpt,
  });

  Map<String, dynamic> toJson() => {
    'tool_name': toolName,
    'command': command,
    'working_directory': workingDirectory,
    'exit_code': exitCode,
    'exit_code_source': exitCodeSource.name,
    'source': source,
    'summary': summary,
    'excerpt': excerpt,
  };
}
