import 'dart:convert';

import '../entities/tool_call_info.dart';
import 'coding_command_output_guardrail_service.dart';
import 'tool_outcome_shadow_comparison.dart';

class WorkflowToolResultFailureDecision {
  const WorkflowToolResultFailureDecision({
    required this.containsFailure,
    required this.exitCodeSource,
  });

  final bool containsFailure;
  final ToolOutcomeVerdictSource exitCodeSource;
}

final class WorkflowToolResultFailureDetector {
  WorkflowToolResultFailureDetector._();

  static bool containsFailure(List<ToolResultInfo> toolResults) =>
      inspect(toolResults).containsFailure;

  static WorkflowToolResultFailureDecision inspect(
    List<ToolResultInfo> toolResults,
  ) {
    var observedExitCodeSource = ToolOutcomeVerdictSource.unavailable;
    for (final toolResult in toolResults) {
      final normalized = toolResult.result.trim().toLowerCase();
      if (normalized.isEmpty && toolResult.outcome?.exitCode == null) {
        continue;
      }
      Object? decoded;
      if (normalized.startsWith('{')) {
        try {
          decoded = jsonDecode(toolResult.result);
        } catch (_) {
          decoded = null;
        }
      }
      if (decoded is Map<String, dynamic>) {
        final exitCode = resolveToolOutcomeExitCode(
          outcome: toolResult.outcome,
          parsedExitCode: _parseExitCode(decoded['exit_code']),
        );
        if (exitCode.source != ToolOutcomeVerdictSource.unavailable) {
          observedExitCodeSource = exitCode.source;
        }
        if (exitCode.exitCode != null && exitCode.exitCode != 0) {
          return WorkflowToolResultFailureDecision(
            containsFailure: true,
            exitCodeSource: exitCode.source,
          );
        }
        if (decoded['success'] == false || decoded['isSuccess'] == false) {
          return WorkflowToolResultFailureDecision(
            containsFailure: true,
            exitCodeSource: observedExitCodeSource,
          );
        }
        final errorText = decoded['error']?.toString().trim() ?? '';
        final errorMessage = decoded['errorMessage']?.toString().trim() ?? '';
        if (errorText.isNotEmpty || errorMessage.isNotEmpty) {
          return WorkflowToolResultFailureDecision(
            containsFailure: true,
            exitCodeSource: observedExitCodeSource,
          );
        }
        if (CodingCommandOutputGuardrailService.commandResultReportsOutputIssue(
          toolResult.result,
        )) {
          return WorkflowToolResultFailureDecision(
            containsFailure: true,
            exitCodeSource: observedExitCodeSource,
          );
        }
      }
      if (normalized.startsWith('error:') ||
          normalized.contains('failed to') ||
          normalized.contains('no matching tool available') ||
          normalized.contains('"error":') ||
          normalized.contains('"issuccess":false') ||
          normalized.contains('"success":false') ||
          normalized.contains('"errormessage"')) {
        return WorkflowToolResultFailureDecision(
          containsFailure: true,
          exitCodeSource: observedExitCodeSource,
        );
      }
    }
    return WorkflowToolResultFailureDecision(
      containsFailure: false,
      exitCodeSource: observedExitCodeSource,
    );
  }

  static int? _parseExitCode(Object? value) {
    if (value is num) return value.toInt();
    return null;
  }
}
