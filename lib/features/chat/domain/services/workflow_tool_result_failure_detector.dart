import 'dart:convert';

import '../entities/tool_call_info.dart';
import 'coding_command_output_guardrail_service.dart';

final class WorkflowToolResultFailureDetector {
  WorkflowToolResultFailureDetector._();

  static bool containsFailure(List<ToolResultInfo> toolResults) {
    for (final toolResult in toolResults) {
      final normalized = toolResult.result.trim().toLowerCase();
      if (normalized.isEmpty) {
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
        final exitCode = decoded['exit_code'];
        if (exitCode is num && exitCode != 0) {
          return true;
        }
        if (decoded['success'] == false || decoded['isSuccess'] == false) {
          return true;
        }
        final errorText = decoded['error']?.toString().trim() ?? '';
        final errorMessage = decoded['errorMessage']?.toString().trim() ?? '';
        if (errorText.isNotEmpty || errorMessage.isNotEmpty) {
          return true;
        }
        if (CodingCommandOutputGuardrailService.commandResultReportsOutputIssue(
          toolResult.result,
        )) {
          return true;
        }
      }
      if (normalized.startsWith('error:') ||
          normalized.contains('failed to') ||
          normalized.contains('no matching tool available') ||
          normalized.contains('"error":') ||
          normalized.contains('"issuccess":false') ||
          normalized.contains('"success":false') ||
          normalized.contains('"errormessage"')) {
        return true;
      }
    }
    return false;
  }
}
