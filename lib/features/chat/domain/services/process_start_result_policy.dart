import 'dart:convert';

import '../entities/mcp_tool_entity.dart';
import '../entities/tool_call_info.dart';

// ChatNotifier decomposition collaborator: process-start-result-policy

/// Rejects stale background-process start results using dispatch-time evidence.
final class ProcessStartResultPolicy {
  const ProcessStartResultPolicy();

  McpToolResult? buildStaleGuardResult(
    ToolCallInfo toolCall,
    McpToolResult result, {
    required DateTime dispatchedAt,
  }) {
    if (toolCall.name.trim().toLowerCase() != 'process_start' ||
        !result.isSuccess) {
      return null;
    }
    final decoded = _tryDecodeMap(result.result);
    if (decoded == null ||
        decoded['ok'] != true ||
        decoded['duplicate_existing'] == true) {
      return null;
    }
    final startedAtText = decoded['started_at']?.toString().trim();
    if (startedAtText == null || startedAtText.isEmpty) {
      return null;
    }
    final startedAt = DateTime.tryParse(startedAtText);
    if (startedAt == null) {
      return null;
    }
    final staleBefore = dispatchedAt.subtract(const Duration(seconds: 5));
    if (!startedAt.isBefore(staleBefore)) {
      return null;
    }

    final payload = jsonEncode({
      'ok': false,
      'code': 'background_process_start_stale_result',
      'error':
          'process_start returned a non-duplicate job result whose started_at '
          'predates this tool call. Treat the start result as stale until the '
          'process state is verified.',
      'job_id': decoded['job_id'],
      'command': decoded['command'],
      'working_directory': decoded['working_directory'],
      'started_at': startedAtText,
      'tool_dispatched_at': dispatchedAt.toIso8601String(),
      'required_action':
          'Use process_status, process_tail, or process_wait for the job_id '
          'if it should still be monitored. Do not report the command as newly '
          'started from this result.',
    });
    return McpToolResult(
      toolName: toolCall.name,
      result: payload,
      isSuccess: false,
      errorMessage: 'process_start returned a stale job result.',
    );
  }

  Map<String, dynamic>? _tryDecodeMap(String value) {
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
