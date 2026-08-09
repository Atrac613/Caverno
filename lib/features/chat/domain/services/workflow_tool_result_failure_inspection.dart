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

abstract final class WorkflowToolResultFailureInspection {
  static WorkflowToolResultFailureDecision inspect(
    List<ToolResultInfo> toolResults,
  ) {
    var observedSource = ToolOutcomeVerdictSource.unavailable;
    for (final toolResult in toolResults) {
      final normalized = toolResult.result.trim().toLowerCase();
      if (normalized.isEmpty && toolResult.outcome?.exitCode == null) continue;
      final decoded = _decode(toolResult.result, normalized);
      if (decoded != null) {
        final exitCode = resolveToolOutcomeExitCode(
          outcome: toolResult.outcome,
          parsedExitCode: _parseExitCode(decoded['exit_code']),
        );
        if (exitCode.source != ToolOutcomeVerdictSource.unavailable) {
          observedSource = exitCode.source;
        }
        if (exitCode.exitCode != null && exitCode.exitCode != 0) {
          return _decision(true, exitCode.source);
        }
        final errorText = decoded['error']?.toString().trim() ?? '';
        final errorMessage = decoded['errorMessage']?.toString().trim() ?? '';
        if (decoded['success'] == false ||
            decoded['isSuccess'] == false ||
            errorText.isNotEmpty ||
            errorMessage.isNotEmpty ||
            CodingCommandOutputGuardrailService.commandResultReportsOutputIssue(
              toolResult.result,
            )) {
          return _decision(true, observedSource);
        }
      }
      if (_hasLexicalFailure(normalized)) {
        return _decision(true, observedSource);
      }
    }
    return _decision(false, observedSource);
  }

  static Map<String, dynamic>? _decode(String result, String normalized) {
    if (!normalized.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(result);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static bool _hasLexicalFailure(String value) =>
      value.startsWith('error:') ||
      value.contains('failed to') ||
      value.contains('no matching tool available') ||
      value.contains('"error":') ||
      value.contains('"issuccess":false') ||
      value.contains('"success":false') ||
      value.contains('"errormessage"');

  static int? _parseExitCode(Object? value) =>
      value is num ? value.toInt() : null;

  static WorkflowToolResultFailureDecision _decision(
    bool containsFailure,
    ToolOutcomeVerdictSource source,
  ) => WorkflowToolResultFailureDecision(
    containsFailure: containsFailure,
    exitCodeSource: source,
  );
}
