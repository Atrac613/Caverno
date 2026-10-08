import 'dart:convert';

import 'package:caverno_tool_contracts/caverno_tool_contracts.dart';

import '../entities/tool_call_info.dart';
import 'coding_command_output_issue.dart';
import 'coding_command_preflight_issue_detector.dart';
import 'command_output_signal_detector.dart';
import 'local_command/exit_status_mask.dart';
import 'local_command/masked_inspection_command_policy.dart';
import 'local_command/shell_exit_status_report.dart';
import 'tool_outcome_shadow_comparison.dart';
import 'verification_metadata_query_policy.dart';

export 'coding_command_output_issue.dart' show CodingCommandOutputIssue;

/// Detects failure evidence in decoded command results.
class CodingCommandOutputIssueDetector {
  const CodingCommandOutputIssueDetector({
    CodingCommandPreflightIssueDetector preflightDetector =
        const CodingCommandPreflightIssueDetector(),
  }) : _preflightDetector = preflightDetector;

  final CodingCommandPreflightIssueDetector _preflightDetector;

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
      structuredExitCode: toolResult.outcome?.exitCode,
      structuredProcessState: toolResult.outcome?.processState,
    );
  }

  CodingCommandOutputIssue? detectFromDecodedCommandResult({
    required String toolName,
    required Map<String, dynamic> decoded,
    String? fallbackCommand,
    String? fallbackWorkingDirectory,
    int? structuredExitCode,
    ToolProcessState? structuredProcessState,
  }) {
    if (!_isCommandTool(toolName)) {
      return null;
    }
    if (const {
          'process_status',
          'process_wait',
        }.contains(toolName.trim().toLowerCase()) &&
        (structuredProcessState != null
            ? structuredProcessState != ToolProcessState.exited
            : decoded['status'] != 'exited')) {
      return null;
    }
    final exitCodeResolution = resolveToolOutcomeExitCode(
      outcome: structuredExitCode == null
          ? null
          : ToolOutcome(exitCode: structuredExitCode),
      parsedExitCode: _parseExitCode(decoded['exit_code']),
    );
    final exitCode = exitCodeResolution.exitCode;
    if (exitCode != 0) {
      return null;
    }

    final command = _normalizeText(decoded['command']) ?? fallbackCommand ?? '';
    final workingDirectory =
        _normalizeText(decoded['working_directory']) ??
        fallbackWorkingDirectory ??
        '';
    if (VerificationMetadataQueryPolicy.applies(command)) return null;
    final preflightIssue =
        _preflightDetector.detect(
          toolName: toolName,
          command: command,
          workingDirectory: workingDirectory,
        ) ??
        (MaskedInspectionCommandPolicy.applies(command)
            ? null
            : _preflightDetector.detectMaskedExitStatusIssue(
                command: command,
                workingDirectory: workingDirectory,
              ));
    if (preflightIssue != null) {
      return CodingCommandOutputIssue(
        toolName: toolName,
        command: command,
        workingDirectory: workingDirectory,
        exitCode: exitCode!,
        exitCodeSource: exitCodeResolution.source,
        source: 'command',
        summary: preflightIssue.summary,
        excerpt: preflightIssue.segment,
      );
    }
    final report = ShellExitStatusReport.parse(command);
    if (report != null) {
      final output =
          (decoded['stdout'] ?? decoded['stdout_tail'])?.toString() ?? '';
      final reportedExitCode = report.exitCode(output);
      if (reportedExitCode != 0) {
        return CodingCommandOutputIssue(
          toolName: toolName,
          command: command,
          workingDirectory: workingDirectory,
          exitCode: exitCode!,
          exitCodeSource: exitCodeResolution.source,
          source: 'stdout',
          summary: reportedExitCode == null
              ? 'The command exit status report is unavailable; the shell exit '
                    'status belongs to echo.'
              : 'Output reports a failing command exit status ($reportedExitCode).',
          excerpt: _excerpt(
            output,
            (output.length - 600).clamp(0, output.length).toInt(),
          ),
        );
      }
    }
    for (final entry in const {
      'stdout': 'stdout',
      'stdout_tail': 'stdout',
      'stderr': 'stderr',
      'stderr_tail': 'stderr',
    }.entries) {
      final output = _normalizeText(decoded[entry.key]);
      if (output == null) {
        continue;
      }
      final signal = const CommandOutputSignalDetector().detect(
        output,
        runtimeSignals:
            report == null && const ExitStatusMask().mayHide(command),
      );
      if (signal == null) {
        continue;
      }
      return CodingCommandOutputIssue(
        toolName: toolName,
        command: command,
        workingDirectory: workingDirectory,
        exitCode: exitCode!,
        exitCodeSource: exitCodeResolution.source,
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
      // Invocation provenance must not change the repeated-failure signature.
      'issues': [
        for (final issue in issues)
          if (issue is Map)
            Map<String, dynamic>.from(issue)..remove('tool_call_id')
          else
            issue,
      ],
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

  bool _isCommandTool(String toolName) {
    return switch (toolName.trim().toLowerCase()) {
      'local_execute_command' ||
      'run_tests' ||
      'git_execute_command' ||
      'ssh_execute_command' => true,
      'process_status' || 'process_wait' => true,
      _ => false,
    };
  }

  int? _parseExitCode(dynamic value) => switch (value) {
    int() => value,
    num() => value.toInt(),
    String() => int.tryParse(value.trim()),
    _ => null,
  };

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
