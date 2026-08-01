import 'dart:convert';

import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';
import 'coding_command_output_issue_detector.dart';
import 'coding_command_preflight_issue_detector.dart';

export 'coding_command_output_issue_detector.dart'
    show CodingCommandOutputIssue, CodingCommandOutputIssueDetector;
export 'coding_command_preflight_issue_detector.dart'
    show CodingCommandPreflightIssue, CodingCommandPreflightIssueDetector;

// ChatNotifier decomposition collaborator: coding-command-output-guardrail-service

/// Compatibility facade for coding command output and preflight guardrails.
class CodingCommandOutputGuardrailService {
  const CodingCommandOutputGuardrailService();

  static const toolName = 'coding_output_feedback';
  static const schemaName = 'caverno_coding_output_feedback';
  static const providerName = 'command_output_guardrail';

  static const CodingCommandOutputIssueDetector _outputIssueDetector =
      CodingCommandOutputIssueDetector();
  static const CodingCommandPreflightIssueDetector _preflightIssueDetector =
      CodingCommandPreflightIssueDetector();

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
      'diagnostics': issues
          .map(
            (issue) => {
              'severity': 'Error',
              'code': 'command_output_failure',
              'message': '${issue.summary} ${issue.excerpt}'.trim(),
            },
          )
          .toList(growable: false),
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
    return _outputIssueDetector.detect(toolResult);
  }

  static CodingCommandPreflightIssue? detectPreflightIssue({
    required String toolName,
    required String command,
    required String workingDirectory,
  }) {
    return _preflightIssueDetector.detect(
      toolName: toolName,
      command: command,
      workingDirectory: workingDirectory,
    );
  }

  static McpToolResult? buildPreflightResult({
    required String toolName,
    required String command,
    required String workingDirectory,
  }) {
    final issue = detectPreflightIssue(
      toolName: toolName,
      command: command,
      workingDirectory: workingDirectory,
    );
    if (issue == null) {
      return null;
    }
    return McpToolResult(
      toolName: toolName,
      result: jsonEncode({
        'ok': false,
        ...issue.toJson(),
        'required_action': issue.instruction,
      }),
      isSuccess: false,
      errorMessage: issue.summary,
    );
  }

  static CodingCommandOutputIssue? detectIssueFromDecodedCommandResult({
    required String toolName,
    required Map<String, dynamic> decoded,
    String? fallbackCommand,
    String? fallbackWorkingDirectory,
  }) {
    return _outputIssueDetector.detectFromDecodedCommandResult(
      toolName: toolName,
      decoded: decoded,
      fallbackCommand: fallbackCommand,
      fallbackWorkingDirectory: fallbackWorkingDirectory,
    );
  }

  static String? feedbackSignature(ToolResultInfo feedback) {
    return _outputIssueDetector.feedbackSignature(
      feedback,
      feedbackToolName: toolName,
    );
  }

  static bool commandResultReportsOutputIssue(String rawResult) {
    return _outputIssueDetector.commandResultReportsOutputIssue(rawResult);
  }

  static CodingCommandPreflightIssue? detectMaskedExitStatusIssue({
    required String command,
    String workingDirectory = '',
  }) {
    return _preflightIssueDetector.detectMaskedExitStatusIssue(
      command: command,
      workingDirectory: workingDirectory,
    );
  }
}
